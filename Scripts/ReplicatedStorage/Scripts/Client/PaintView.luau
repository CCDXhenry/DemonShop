-- 统一视觉线段视图：本地逐帧生成、稳定 ID 增量和所有客户端同几何重建
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Surface = require(ReplicatedStorage.Scripts.Shared.PaintSurface)
local Path = require(ReplicatedStorage.Scripts.Shared.StrokePath)
local Curve = require(ReplicatedStorage.Scripts.Shared.CurvedSurface)
local CurvedView = require(script.Parent.CurvedPaintView)
local View = {}
View.__index = View
export type View = typeof(setmetatable({} :: {
 faces: {[string]: SurfaceGui}, models: {[string]: Model},
 segments: {[string]: {[string]: Types.VisualSegment}}, frames: {[string]: Frame},
 tips: {[string]: {path: Path.Tip,key: string}}, dirty: {[string]: {[string]: Types.VisualSegment}},
 counts: {[string]: number}, pool: {Frame}, budgetReached: boolean,
 curved: CurvedView.View?, curvedTips: {[string]: Types.Sample}?,
},View))
function View.new(): View
 return setmetatable({faces={},models={},segments={},frames={},tips={},dirty={},counts={},pool={},budgetReached=false},View)
end
function View.Release(self: View, frame: Frame): ()
 frame.Parent=nil
 if #self.pool<Config.PaintPreviewPoolBudget then table.insert(self.pool,frame) else frame:Destroy() end
end
function View.Render(self: View,id: string,segment: Types.VisualSegment): ()
 local model=self.models[id]
 local part=model and model:FindFirstChild(segment.part)
 if not part or not part:IsA("BasePart") then return end
 if Curve.IsPart(part) then
  local curved: CurvedView.View=self.curved or CurvedView.new()
  self.curved=curved
  curved:Bind(id,model :: Model,self.segments[id] or {})
  curved:Apply(id,segment)
  return
 end
 local dimensions=Surface.Dimensions(part.Size,segment.face)
 local faceKey=id..":"..segment.part..":"..tostring(segment.face)
 local gui=self.faces[faceKey]
 if not gui then
  local cloned=(ReplicatedStorage.UI:WaitForChild("PaintFaceGui") :: SurfaceGui):Clone()
  cloned.Name,cloned.Adornee,cloned.Face="RuneStroke",part,Surface.Faces[segment.face]
  cloned.CanvasSize=dimensions*Config.PaintSurfacePixels
  cloned.Parent=Players.LocalPlayer:WaitForChild("PlayerGui")
  self.faces[faceKey],gui=cloned,cloned
 end
 local key=id..":"..segment.key
 local frame=self.frames[key]
 if not frame then
  local cloned=table.remove(self.pool) or (ReplicatedStorage.UI:WaitForChild("PaintCellFrame") :: Frame):Clone()
  cloned.Name="StrokeSegment"
  cloned:SetAttribute("VisualKey",segment.key)
  self.frames[key],frame=cloned,cloned
 end
 local from=Vector2.new(segment.u0*dimensions.X,segment.v0*dimensions.Y)
 local point=Vector2.new(segment.u1*dimensions.X,segment.v1*dimensions.Y)
 local delta=point-from
 local width=Config.PaintVisualWidth*Config.PaintSurfacePixels
 frame.Position=UDim2.fromOffset((point.X+from.X)*.5*Config.PaintSurfacePixels,(point.Y+from.Y)*.5*Config.PaintSurfacePixels)
 frame.Size=UDim2.fromOffset(delta.Magnitude*Config.PaintSurfacePixels+width,width)
 frame.Rotation=math.deg(math.atan2(delta.Y,delta.X))
 frame:SetAttribute("VisualVersion",segment.version)
 frame.Parent=gui
end
function View.Apply(self: View,id: string,segments: {Types.VisualSegment}): ()
 local records=self.segments[id] or {}
 self.segments[id]=records
 for _,segment in segments do
  local old=records[segment.key]
  if old and old.version>=segment.version then continue end
  if not old then self.counts[id]=(self.counts[id] or 0)+1 end
  records[segment.key]=table.clone(segment)
  self:Render(id,segment)
 end
end
function View.DrawLocal(self: View,id: string,session: string,gesture: number,samples: {Types.Sample}): ()
 local model=self.models[id]
 if not model then return end
 if model:GetAttribute("SurfaceVersion")==Curve.Version then
  local pathKey=id..":"..session..":"..tostring(gesture)
  local tips=self.curvedTips or {}
  self.curvedTips=tips
  local previous=tips[pathKey]
  local changed=self.dirty[id] or {}
  self.dirty[id]=changed
  for _,sample in samples do
   local part=model:FindFirstChild(sample.part)
   if not part or not part:IsA("BasePart") or not Curve.Valid(part,sample) then previous=nil;continue end
   if (self.counts[id] or 0)>=Config.PaintLocalSegmentBudget then self.budgetReached=true;break end
   local from=sample
   if previous and previous.part==sample.part and not sample.breakBefore and (Curve.Point(part,previous)-Curve.Point(part,sample)).Magnitude<Config.BrushRadius*3 then from=previous end
   if previous and previous.part==sample.part and (Curve.Point(part,previous)-Curve.Point(part,sample)).Magnitude<.003 then continue end
   -- 路径缓存按身体隔离；上传标识必须沿用服务端的会话前缀契约。
   local key=session..":"..tostring(gesture)..":"..tostring((self.counts[id] or 0)+1)
   local segment: Types.VisualSegment={key=key,version=1,gesture=gesture,part=sample.part,face=1,u0=from.u,v0=from.v,u1=sample.u,v1=sample.v,triangle0=from.triangle,triangle1=sample.triangle,surfaceVersion=sample.surfaceVersion}
   self:Apply(id,{segment})
   changed[key]=segment
   previous=sample
  end
  tips[pathKey]=previous
  return
 end
 local pathKey=id..":"..session..":"..tostring(gesture)
 local previous: {path: Path.Tip,key: string}?=self.tips[pathKey]
 local records=self.segments[id] or {}
 local changed=self.dirty[id] or {}
 self.segments[id],self.dirty[id]=records,changed
 for _,sample in samples do
  local part=model:FindFirstChild(sample.part)
  if not part or not part:IsA("BasePart") then previous=nil;continue end
  local dimensions=Surface.Dimensions(part.Size,sample.face)
  local nextSegment=Path.Next(if previous then previous.path else nil,sample,dimensions)
  if nextSegment.skip then continue end
  local key: string
  if nextSegment.reuse and previous then key=previous.key else
   if (self.counts[id] or 0)>=Config.PaintLocalSegmentBudget then self.budgetReached=true;break end
   key=session..":"..tostring(gesture)..":"..tostring((self.counts[id] or 0)+1)
  end
  local old=records[key]
  local segment: Types.VisualSegment={key=key,version=if old then old.version+1 else 1,gesture=gesture,part=sample.part,face=sample.face,
   u0=math.clamp(nextSegment.tip.from.X/dimensions.X,0,1),v0=math.clamp(nextSegment.tip.from.Y/dimensions.Y,0,1),
   u1=math.clamp(nextSegment.tip.point.X/dimensions.X,0,1),v1=math.clamp(nextSegment.tip.point.Y/dimensions.Y,0,1)}
  self:Apply(id,{segment})
  changed[key]=segment
  previous={path=nextSegment.tip,key=key}
 end
 if previous then self.tips[pathKey]=previous else self.tips[pathKey]=nil end
end
function View.Drain(self: View,id: string): {[string]: Types.VisualSegment}
 local changed=self.dirty[id] or {}
 self.dirty[id]=nil
 return changed
end
function View.Bind(self: View,id: string,model: Model): ()
 if self.models[id]==model then return end
 self.models[id]=model
 if model:GetAttribute("SurfaceVersion")==Curve.Version then
  local curved: CurvedView.View=self.curved or CurvedView.new()
  self.curved=curved
  curved:Bind(id,model,self.segments[id] or {})
  return
 end
 for _,segment in pairs(self.segments[id] or {}) do self:Render(id,segment) end
end
function View.Remove(self: View,id: string): ()
 if self.curved then self.curved:Remove(id) end
 local prefix=id..":"
 for key,frame in self.frames do if string.sub(key,1,#prefix)==prefix then self:Release(frame);self.frames[key]=nil end end
 for key,gui in self.faces do if string.sub(key,1,#prefix)==prefix then gui:Destroy();self.faces[key]=nil end end
 for key in self.tips do if string.sub(key,1,#prefix)==prefix then self.tips[key]=nil end end
 self.models[id],self.segments[id],self.dirty[id],self.counts[id]=nil,nil,nil,nil
 for key in pairs(self.curvedTips or {}) do if string.sub(key,1,#prefix)==prefix then (self.curvedTips :: {[string]: Types.Sample})[key]=nil end end
end
function View.Update(self: View,active: string?): () if self.curved then self.curved:Update(active) end end
function View.IsReady(self: View,id: string): boolean
 local model: Model?=self.models[id]
 return not self.curved or not model or model:GetAttribute("SurfaceVersion")~=Curve.Version or self.curved:IsReady(id)
end
function View.Destroy(self: View): ()
 if self.curved then self.curved:Destroy() end
 for id in self.models do self:Remove(id) end
 for id in self.segments do self:Remove(id) end
 for _,frame in self.pool do frame:Destroy() end
 table.clear(self.pool)
end
return View
