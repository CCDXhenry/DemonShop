-- 视觉线段上传队列：按 ID 合并、可靠批次确认重发与退出前排空
--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Types=require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Net=require(ReplicatedStorage.Scripts.Shared.ProcessingNet)
local BodyPose=require(ReplicatedStorage.Scripts.Shared.PaintBodyPose)
local Upload={}
Upload.__index=Upload
export type Upload=typeof(setmetatable({} :: {
 session: string?,sequence: number,acked: number,pending: {[string]: Types.VisualSegment},
 flight: {[number]: {request: Types.Request,sent: number}},lastSend: number,
 closing: boolean,finished: boolean,blocked: boolean,wasForced: boolean,
 bodyPose: Types.BodyPose?,
},Upload))
function Upload.new(): Upload
 return setmetatable({session=nil,sequence=0,acked=0,pending={},flight={},lastSend=0,closing=false,finished=false,blocked=false,wasForced=false},Upload)
end
function Upload.Begin(self: Upload,session: string): ()
 self.session=session;self.sequence=0;self.acked=0;self.lastSend=0
 self.closing=false;self.finished=false;self.blocked=false;self.wasForced=false;table.clear(self.pending);table.clear(self.flight)
 self.bodyPose=nil
end
function Upload.Clear(self: Upload): ()
 self.session=nil;table.clear(self.pending);table.clear(self.flight)
end
function Upload.Ack(self: Upload,sequence: number): ()
 if sequence>self.sequence then return end
 self.acked=math.max(self.acked,sequence)
 for seq in self.flight do if seq<=self.acked then self.flight[seq]=nil end end
end
function Upload.Update(self: Upload,changed: {[string]: Types.VisualSegment},now: number,started: number,force: boolean,bodyPose: Types.BodyPose?,rasterReady: boolean?): ()
 for key,segment in changed do self.pending[key]=segment end
 if not self.session or self.blocked then return end
 local timedOut: {number} = {}
 for seq, batch in self.flight do
  if now - batch.sent >= Config.PaintVisualRetrySeconds then
   table.insert(timedOut, seq)
  end
 end
 if #timedOut > 1 then
  table.sort(timedOut)
 end
 for _, seq in timedOut do
  local batch = self.flight[seq]
  if batch then
   Net.FireRequest(batch.request)
   batch.sent = now
  end
 end
 local immediate=force and not self.wasForced
 self.wasForced=force
 if not immediate and now-self.lastSend<Config.PaintBatchInterval then return end
 local moved=not self.closing and BodyPose.Changed(self.bodyPose,bodyPose)
 for packet=1,Config.PaintVisualPacketsPerTick do
  if not next(self.pending) and (not moved or packet>1) then break end
  local segments: {Types.VisualSegment}={}
  local keys: {string}={}
  for key in self.pending do table.insert(keys,key) end
  table.sort(keys)
  for index=1,math.min(#keys,Config.PaintVisualBatchSize) do
   local key=keys[index];table.insert(segments,self.pending[key]);self.pending[key]=nil
  end
  self.sequence+=1
  local request: Types.Request={action="PaintVisual",session=self.session,sequence=self.sequence,segments=segments,started=started}
  request.bodyPose=if bodyPose then table.clone(bodyPose) else nil
  self.flight[self.sequence]={request=request,sent=now}
  Net.FireRequest(request)
  self.lastSend=now
  self.bodyPose=request.bodyPose
 end
 if self.closing and rasterReady~=false and not self.finished and not next(self.pending) and self.acked==self.sequence then
  self.finished=true
  Net.FireRequest({action="EndPaint",session=self.session,sequence=self.sequence})
 end
end
return Upload
