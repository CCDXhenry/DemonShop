-- 曲面笔迹渲染：重心坐标投影至共享 UV 图集、限量纹理缓存和单帧提交
--!strict
local AssetService=game:GetService("AssetService")
local Curve=require(script.Parent.Parent.Shared.CurvedSurface)
local Data=require(script.Parent.Parent.Shared.BodySurfaceData)
local Config=require(script.Parent.Parent.Shared.GameConfig)
local Types=require(script.Parent.Parent.Shared.GameTypes)
local View={}
View.__index=View
type Texture={image: EditableImage,pixels: buffer,size: number,model: Model,dirty: boolean,used: number,rebuilding: boolean,minX: number,minY: number,maxX: number,maxY: number}
local PixelsPerSlice=64
export type View=typeof(setmetatable({} :: {textures: {[string]: Texture},models: {[string]: Model},records: {[string]: {[string]: Types.VisualSegment}},queue: {[string]: {Types.VisualSegment}},heads: {[string]: number},tasks: {[string]: thread},retryAfter: {[string]: number},active: string?,failed: boolean},View))
function View.new(): View return setmetatable({textures={},models={},records={},queue={},heads={},tasks={},retryAfter={},active=nil,failed=false},View) end
local function Attach(texture: Texture): ()
	for _,part in texture.model:GetChildren() do if part:IsA("MeshPart") and Curve.IsPart(part) then part.TextureContent=Content.fromObject(texture.image) end end
end
function View.RemoveTexture(self: View,id: string): ()
	local task=self.tasks[id]
	if task then coroutine.close(task);self.tasks[id]=nil end
	local texture: Texture?=self.textures[id]
	if not texture then return end
	for _,part in texture.model:GetChildren() do if part:IsA("MeshPart") then part.TextureContent=Content.none end end
	texture.image:Destroy()
	self.textures[id]=nil
end
function View.Ensure(self: View,id: string): Texture?
	if os.clock()<(self.retryAfter[id] or 0) then return nil end
	local model=self.models[id]
	if not model or not model.Parent then return nil end
	local size=if self.active==id then Config.PaintActiveTextureSize else Config.PaintObserverTextureSize
	local texture: Texture?=self.textures[id]
	-- 已有高分辨率图集退出后继续驻留，避免整张历史降采样重画。
	if texture and texture.size<size then self:RemoveTexture(id);texture=nil end
	if not texture then
		local count=0
		local oldest: string?=nil
		for key,entry in self.textures do
			count+=1
			if key~=self.active and (not oldest or entry.used<(self.textures[oldest] :: Texture).used) then oldest=key end
		end
		if count>=Config.PaintTextureResidentLimit and oldest then self:RemoveTexture(oldest) end
		local ok,image=pcall(function(): EditableImage? return AssetService:CreateEditableImage({Size=Vector2.new(size,size)}) end)
		if not ok or not image then
			if not self.failed then warn("[Paint] EditableImage unavailable; curved painting requires Mesh / Image APIs and client memory.") end
			self.failed=true
			self.retryAfter[id]=os.clock()+3
			return nil
		end
		local pixels=buffer.create(size*size*4)
		buffer.fill(pixels,0,255)
		texture={image=image,pixels=pixels,size=size,model=model,dirty=true,used=os.clock(),rebuilding=true,minX=0,minY=0,maxX=size-1,maxY=size-1}
		self.textures[id]=texture
		self.failed=false
		self.queue[id]={}
		self.heads[id]=1
		for _,segment in pairs(self.records[id] or {}) do table.insert(self.queue[id],table.clone(segment)) end
	end
	if not texture then return nil end
	texture.model,texture.used=model,os.clock()
	if not texture.rebuilding then Attach(texture) end
	return texture
end
function View.Bind(self: View,id: string,model: Model,records: {[string]: Types.VisualSegment}): ()
	if self.models[id]==model then self.records[id]=records;return end
	self.models[id],self.records[id]=model,records
	local texture=self.textures[id]
	if texture then
		texture.model=model
		if not texture.rebuilding then Attach(texture) end
	end
end
function View.Apply(self: View,id: string,segment: Types.VisualSegment): ()
	local queue=self.queue[id] or {}
	self.queue[id]=queue
	table.insert(queue,table.clone(segment))
end
local function Stamp(texture: Texture,part: BasePart,sample: Types.Sample): ()
	if not Curve.Valid(part,sample) then return end
	local geometry=Curve.Geometry(part)
	local center=Curve.Point(part,sample)
	local normal=geometry.triangles[sample.triangle :: number].normal
	local radius=Config.PaintVisualWidth*.5
	for _,index in Curve.Candidates(part,center,radius+.04) do
		coroutine.yield()
		local triangle=geometry.triangles[index]
		if not triangle.allowed or triangle.normal:Dot(normal)<.2 then continue end
		local source=Data.Parts[part.Name]
		local face=source.triangles[index]
		local a,b,c=source.uvs[face[1]],source.uvs[face[2]],source.uvs[face[3]]
		-- FBX UV origin is bottom-left; EditableImage origin is top-left.
		a,b,c=Vector2.new(a.X,1-a.Y)*texture.size,Vector2.new(b.X,1-b.Y)*texture.size,Vector2.new(c.X,1-c.Y)*texture.size
		local low,high=a:Min(b):Min(c),a:Max(b):Max(c)
		local ab,ac=b-a,c-a
		local determinant=ab.X*ac.Y-ab.Y*ac.X
		if math.abs(determinant)<1e-8 then continue end
		-- 世界空间球投影到三角面 UV 的保守包围框，最终仍按原球半径判定。
		local edgeB,edgeC=triangle.b-triangle.a,triangle.c-triangle.a
		local bb,bc,cc=edgeB:Dot(edgeB),edgeB:Dot(edgeC),edgeC:Dot(edgeC)
		local gram=bb*cc-bc*bc
		if gram<=0 then continue end
		local gradientU,gradientV=(edgeB*cc-edgeC*bc)/gram,(edgeC*bb-edgeB*bc)/gram
		local gradientX,gradientY=gradientU*ab.X+gradientV*ac.X,gradientU*ab.Y+gradientV*ac.Y
		local delta=center-triangle.a
		local pixelCenter=a+Vector2.new(gradientX:Dot(delta),gradientY:Dot(delta))
		local extent=Vector2.new(gradientX.Magnitude,gradientY.Magnitude)*radius
		low,high=low:Max(pixelCenter-extent-Vector2.one),high:Min(pixelCenter+extent+Vector2.one)
		local scanned=0
		for y=math.max(0,math.floor(low.Y)),math.min(texture.size-1,math.ceil(high.Y)) do
			for x=math.max(0,math.floor(low.X)),math.min(texture.size-1,math.ceil(high.X)) do
				scanned+=1
				if scanned%PixelsPerSlice==0 then coroutine.yield() end
				local p=Vector2.new(x+.5,y+.5)-a
				local u,v=(p.X*ac.Y-p.Y*ac.X)/determinant,(ab.X*p.Y-ab.Y*p.X)/determinant
				if u<-.005 or v<-.005 or u+v>1.005 then continue end
				local localPoint=triangle.a+(triangle.b-triangle.a)*u+(triangle.c-triangle.a)*v
				if (localPoint-center).Magnitude>radius then continue end
				local offset=(y*texture.size+x)*4
				buffer.writeu8(texture.pixels,offset,176);buffer.writeu8(texture.pixels,offset+1,63);buffer.writeu8(texture.pixels,offset+2,255)
				texture.dirty=true
				texture.minX,texture.minY=math.min(texture.minX,x),math.min(texture.minY,y)
				texture.maxX,texture.maxY=math.max(texture.maxX,x),math.max(texture.maxY,y)
			end
		end
	end
end
local function Draw(texture: Texture,segment: Types.VisualSegment): ()
	local part=texture.model:FindFirstChild(segment.part)
	if not part or not part:IsA("BasePart") then return end
	local start: Types.Sample={part=part.Name,face=1,u=segment.u0,v=segment.v0,triangle=segment.triangle0,surfaceVersion=segment.surfaceVersion}
	local finish: Types.Sample={part=part.Name,face=1,u=segment.u1,v=segment.v1,triangle=segment.triangle1,surfaceVersion=segment.surfaceVersion}
	if not Curve.Valid(part,start) or not Curve.Valid(part,finish) then return end
	local a,b=Curve.Point(part,start),Curve.Point(part,finish)
	local distance=(b-a).Magnitude
	if distance>Config.BrushRadius*3 then Stamp(texture,part,finish);return end
	local steps=math.max(1,math.ceil(distance/(Config.PaintVisualWidth*.3)))
	for index=0,steps do Stamp(texture,part,Curve.ProjectLocal(part,a:Lerp(b,index/steps))) end
end
function View.IsReady(self: View,id: string): boolean
	local texture=self.textures[id]
	-- 图像 API 失败由客户端提示并退出，不能永久等待无法创建的图集。
	if not texture then return self.failed end
	return not texture.rebuilding and not texture.dirty and self.tasks[id]==nil and (self.heads[id] or 1)>#(self.queue[id] or {})
end
local function Commit(texture: Texture): ()
	local width,height=texture.maxX-texture.minX+1,texture.maxY-texture.minY+1
	local pixels=buffer.create(width*height*4)
	for row=0,height-1 do buffer.copy(pixels,row*width*4,texture.pixels,((texture.minY+row)*texture.size+texture.minX)*4,width*4) end
	texture.image:WritePixelsBuffer(Vector2.new(texture.minX,texture.minY),Vector2.new(width,height),pixels)
	texture.dirty=false
	texture.minX,texture.minY,texture.maxX,texture.maxY=texture.size,texture.size,-1,-1
end
function View.Update(self: View,active: string?): ()
	self.active=active
	local camera=workspace.CurrentCamera
	local selected: string?=nil
	local selectedDistance=math.huge
	local visible: {{id: string,distance: number}}={}
	for id,records in self.records do
		local model=self.models[id]
		if not model or not model.Parent or (next(records)==nil and id~=active) then continue end
		local distance=if camera then (model:GetPivot().Position-camera.CFrame.Position).Magnitude else 0
		if distance>Config.PaintTextureViewDistance and id~=active then self:RemoveTexture(id);continue end
		table.insert(visible,{id=id,distance=if id==active then -1 else distance})
	end
	table.sort(visible,function(a,b) return a.distance<b.distance end)
	local resident: {[string]: boolean}={}
	for index,entry in visible do if index<=Config.PaintTextureResidentLimit then resident[entry.id]=true end end
	for id in self.textures do if not resident[id] then self:RemoveTexture(id) end end
	for index,entry in visible do
		if index>Config.PaintTextureResidentLimit then break end
		local id,distance=entry.id,entry.distance
		local texture=self.textures[id]
		local queued=self.queue[id]
		local needs=not texture or self.tasks[id]~=nil or (queued and (self.heads[id] or 1)<=#queued) or (texture and (texture.dirty or (id==active and texture.size<Config.PaintActiveTextureSize)))
		if needs and (not selected or id==active or (selected~=active and distance<selectedDistance)) then selected,selectedDistance=id,distance end
	end
	if not selected then return end
	local texture=self:Ensure(selected)
	if not texture then return end
	local queue=self.queue[selected] or {}
	local deadline=os.clock()+Config.PaintRasterBudgetSeconds
	local head=self.heads[selected] or 1
	while self.tasks[selected] or head<=#queue do
		local task=self.tasks[selected]
		if not task then
			local segment=queue[head]
			head+=1
			task=coroutine.create(function(): () Draw(texture,segment) end)
			self.tasks[selected]=task
		end
		local ok,reason=coroutine.resume(task)
		if not ok then
			warn("[Paint] Raster failed: "..tostring(reason))
			self:RemoveTexture(selected);self.failed=true;self.retryAfter[selected]=os.clock()+3
			return
		end
		if coroutine.status(task)=="dead" then self.tasks[selected]=nil end
		if os.clock()>=deadline then break end
	end
	self.heads[selected]=head
	local complete=not self.tasks[selected] and head>#queue
	if complete then self.queue[selected]={};self.heads[selected]=1 end
	-- 历史恢复只在完整重建后显示；正常输入仍逐帧提交变化区域。
	if texture.dirty and (not texture.rebuilding or complete) then Commit(texture) end
	if texture.rebuilding and complete then texture.rebuilding=false;Attach(texture) end
end
function View.Remove(self: View,id: string): () self:RemoveTexture(id);self.models[id],self.records[id],self.queue[id],self.retryAfter[id],self.heads[id]=nil,nil,nil,nil,nil end
function View.Destroy(self: View): () for id in self.models do self:Remove(id) end end
return View
