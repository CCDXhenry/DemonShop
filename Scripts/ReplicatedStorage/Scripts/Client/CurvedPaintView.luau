-- 曲面笔迹渲染：连续轨迹分块栅格化、限量纹理缓存和单帧提交
--!strict
local AssetService=game:GetService("AssetService")
local Curve=require(script.Parent.Parent.Shared.CurvedSurface)
local Data=require(script.Parent.Parent.Shared.BodySurfaceData)
local Config=require(script.Parent.Parent.Shared.GameConfig)
local Types=require(script.Parent.Parent.Shared.GameTypes)
local View={}
View.__index=View
type Mapping={tileBase: number,ax: number,ay: number,abx: number,aby: number,acx: number,acy: number,det: number,
 ox: number,oy: number,oz: number,dxX: number,dxY: number,dxZ: number,dyX: number,dyY: number,dyZ: number,
 gxX: number,gxY: number,gxZ: number,gyX: number,gyY: number,gyZ: number,extentX: number,extentY: number,
 nx: number,ny: number,nz: number,allowed: boolean,lowX: number,lowY: number,highX: number,highY: number,
 bx: number,by: number,bz: number,cx: number,cy: number,cz: number,
 minX: number,minY: number,minZ: number,maxX: number,maxY: number,maxZ: number}
type RasterPart={part: BasePart,key: string,sx: number,sy: number,sz: number,bins: {[string]: {number}},triangleCount: number,candidateCount: number,candidates: {[number]: {Mapping}}}
type Span={x: number,y: number,z: number,dx: number,dy: number,dz: number,inverse: number,nx: number,ny: number,nz: number,ex: number,ey: number,ez: number}
type Tile={mapping: Mapping,x: number,y: number,spans: {Span}}
type Diagnostics={submitted: number,completed: number,scanned: number,commits: number,commitSeconds: number}
type Texture={image: EditableImage,pixels: buffer,size: number,model: Model,dirty: boolean,used: number,rebuilding: boolean,minX: number,minY: number,maxX: number,maxY: number,mappings: {[string]: {[number]: Mapping}},parts: {[string]: RasterPart},mappingCount: number,tinted: buffer?}
local TileSize=8
local StrokeRed,StrokeGreen,StrokeBlue=176,63,255
local SacrificeSteps=20
local SegmentsPerBatch=256
local CandidateCacheLimit=256
local BinCount=Curve.BinCount
local BinKeyBase=BinCount+2
export type View=typeof(setmetatable({} :: {textures: {[string]: Texture},models: {[string]: Model},records: {[string]: {[string]: Types.VisualSegment}},queue: {[string]: {Types.VisualSegment}},heads: {[string]: number},tasks: {[string]: thread},retryAfter: {[string]: number},active: string?,failed: boolean,diagnostics: Diagnostics?,sacrifice: {[string]: number?},sacrificeStep: {[string]: number}},View))
function View.new(): View return setmetatable({textures={},models={},records={},queue={},heads={},tasks={},retryAfter={},active=nil,failed=false,sacrifice={},sacrificeStep={}},View) end
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
		texture={image=image,pixels=pixels,size=size,model=model,dirty=true,used=os.clock(),rebuilding=true,minX=0,minY=0,maxX=size-1,maxY=size-1,mappings={},parts={},mappingCount=0}
		self.textures[id]=texture
		self.failed=false
		self.queue[id]={}
		self.heads[id]=1
		for _,segment in pairs(self.records[id] or {}) do table.insert(self.queue[id],table.clone(segment)) end
	end
	if not texture then return nil end
	texture.model,texture.used=model,os.clock()
	return texture
end
function View.Bind(self: View,id: string,model: Model,records: {[string]: Types.VisualSegment}): ()
	if self.models[id]==model then self.records[id]=records;return end
	self.models[id],self.records[id]=model,records
	local texture=self.textures[id]
	if texture then
		texture.model=model
		texture.parts={}
		if not texture.rebuilding then Attach(texture) end
	end
end
function View.Apply(self: View,id: string,segment: Types.VisualSegment): ()
	local queue=self.queue[id] or {}
	self.queue[id]=queue
	table.insert(queue,table.clone(segment))
	if self.diagnostics then self.diagnostics.submitted+=1 end
end
-- 转换矩阵按纹理尺寸/部件几何缓存；更换展示模型不改变相同尺寸的局部坐标。
local function MappingFor(texture: Texture,part: BasePart,index: number,key: string): Mapping?
 local mappings=texture.mappings[key]
 if not mappings then mappings={};texture.mappings[key]=mappings end
 if mappings[index] then return mappings[index] end
 local source=Data.Parts[part.Name]
 local face=source.triangles[index]
 local a,b,c=source.uvs[face[1]],source.uvs[face[2]],source.uvs[face[3]]
 local ax,ay=a.X*texture.size,(1-a.Y)*texture.size
 local bx,by=b.X*texture.size,(1-b.Y)*texture.size
 local cx,cy=c.X*texture.size,(1-c.Y)*texture.size
 local abx,aby,acx,acy=bx-ax,by-ay,cx-ax,cy-ay
 local determinant=abx*acy-aby*acx
 if math.abs(determinant)<1e-8 then return nil end
 local triangle=Curve.Geometry(part).triangles[index]
 local edgeB,edgeC=triangle.b-triangle.a,triangle.c-triangle.a
 local bb,bc,cc=edgeB:Dot(edgeB),edgeB:Dot(edgeC),edgeC:Dot(edgeC)
 local gram=bb*cc-bc*bc
 if gram<=0 then return nil end
 local gradientU,gradientV=(edgeB*cc-edgeC*bc)/gram,(edgeC*bb-edgeB*bc)/gram
 local dx,dy=(edgeB*acy-edgeC*aby)/determinant,(edgeC*abx-edgeB*acx)/determinant
 local gx,gy=gradientU*abx+gradientV*acx,gradientU*aby+gradientV*acy
 texture.mappingCount+=1
 local tileGrid=math.ceil(texture.size/TileSize)
 local mapping: Mapping={tileBase=texture.mappingCount*tileGrid*tileGrid,ax=ax,ay=ay,abx=abx,aby=aby,acx=acx,acy=acy,det=determinant,
  ox=triangle.a.X,oy=triangle.a.Y,oz=triangle.a.Z,
  dxX=dx.X,dxY=dx.Y,dxZ=dx.Z,dyX=dy.X,dyY=dy.Y,dyZ=dy.Z,
  gxX=gx.X,gxY=gx.Y,gxZ=gx.Z,gyX=gy.X,gyY=gy.Y,gyZ=gy.Z,extentX=gx.Magnitude*Config.PaintVisualWidth*.5+1,extentY=gy.Magnitude*Config.PaintVisualWidth*.5+1,
  nx=triangle.normal.X,ny=triangle.normal.Y,nz=triangle.normal.Z,allowed=triangle.allowed,
  lowX=math.min(ax,bx,cx),lowY=math.min(ay,by,cy),highX=math.max(ax,bx,cx),highY=math.max(ay,by,cy),
  bx=edgeB.X,by=edgeB.Y,bz=edgeB.Z,cx=edgeC.X,cy=edgeC.Y,cz=edgeC.Z,
  minX=math.min(triangle.a.X,triangle.b.X,triangle.c.X),minY=math.min(triangle.a.Y,triangle.b.Y,triangle.c.Y),minZ=math.min(triangle.a.Z,triangle.b.Z,triangle.c.Z),
  maxX=math.max(triangle.a.X,triangle.b.X,triangle.c.X),maxY=math.max(triangle.a.Y,triangle.b.Y,triangle.c.Y),maxZ=math.max(triangle.a.Z,triangle.b.Z,triangle.c.Z)}
 mappings[index]=mapping
 return mapping
end
local function AddSpan(texture: Texture,tiles: {[number]: Tile},body: RasterPart,ax: number,ay: number,az: number,bx: number,by: number,bz: number,nx: number,ny: number,nz: number,endX: number?,endY: number?,endZ: number?): ()
 local radius=Config.PaintVisualWidth*.5
 local dx,dy,dz=bx-ax,by-ay,bz-az
 local lengthSquared=dx*dx+dy*dy+dz*dz
 local ex,ey,ez=endX or nx,endY or ny,endZ or nz
 local span: Span={x=ax,y=ay,z=az,dx=dx,dy=dy,dz=dz,inverse=if lengthSquared>0 then 1/lengthSquared else 0,nx=nx,ny=ny,nz=nz,ex=ex,ey=ey,ez=ez}
 local part=body.part
 local sx,sy,sz=body.sx,body.sy,body.sz
 local padding=radius+.04
 local mappingKey=body.key
 local lowBinX,highBinX=math.max(-1,math.floor((math.min(ax,bx)-padding)/sx*BinCount+BinCount*.5)),math.min(BinCount,math.floor((math.max(ax,bx)+padding)/sx*BinCount+BinCount*.5))
 local lowBinY,highBinY=math.max(-1,math.floor((math.min(ay,by)-padding)/sy*BinCount+BinCount*.5)),math.min(BinCount,math.floor((math.max(ay,by)+padding)/sy*BinCount+BinCount*.5))
 local lowBinZ,highBinZ=math.max(-1,math.floor((math.min(az,bz)-padding)/sz*BinCount+BinCount*.5)),math.min(BinCount,math.floor((math.max(az,bz)+padding)/sz*BinCount+BinCount*.5))
 -- 每个网格边界编码为一位，复用候选集合时不再创建字符串或去重表。
 local queryKey=(((((lowBinX+1)*BinKeyBase+highBinX+1)*BinKeyBase+lowBinY+1)*BinKeyBase+highBinY+1)*BinKeyBase+lowBinZ+1)*BinKeyBase+highBinZ+1
 local candidates=body.candidates[queryKey]
 if not candidates then
  local built: {Mapping}={}
  local seen: {[number]: boolean}={}
  for ix=lowBinX,highBinX do for iy=lowBinY,highBinY do for iz=lowBinZ,highBinZ do
   for _,index in ipairs(body.bins[tostring(ix)..":"..tostring(iy)..":"..tostring(iz)] or {}) do
    if seen[index] then continue end
    seen[index]=true
    local m=MappingFor(texture,part,index,mappingKey)
    if m and m.allowed then table.insert(built,m) end
    coroutine.yield()
   end
  end end end
  candidates=built
  if body.candidateCount<CandidateCacheLimit then
   body.candidates[queryKey]=built;body.candidateCount+=1
  end
 end
 local minX,minY,minZ=math.min(ax,bx)-radius,math.min(ay,by)-radius,math.min(az,bz)-radius
 local maxX,maxY,maxZ=math.max(ax,bx)+radius,math.max(ay,by)+radius,math.max(az,bz)+radius
 for _,m in candidates do
   if m.maxX<minX or m.minX>maxX or m.maxY<minY or m.minY>maxY or m.maxZ<minZ or m.minZ>maxZ or math.max(m.nx*nx+m.ny*ny+m.nz*nz,m.nx*ex+m.ny*ey+m.nz*ez)<.2 then continue end
   local paX,paY=m.ax+m.gxX*(ax-m.ox)+m.gxY*(ay-m.oy)+m.gxZ*(az-m.oz),m.ay+m.gyX*(ax-m.ox)+m.gyY*(ay-m.oy)+m.gyZ*(az-m.oz)
   local pbX,pbY=m.ax+m.gxX*(bx-m.ox)+m.gxY*(by-m.oy)+m.gxZ*(bz-m.oz),m.ay+m.gyX*(bx-m.ox)+m.gyY*(by-m.oy)+m.gyZ*(bz-m.oz)
   local extentX,extentY=m.extentX,m.extentY
   local lowX,lowY=math.max(m.lowX,math.min(paX,pbX)-extentX,0),math.max(m.lowY,math.min(paY,pbY)-extentY,0)
   local highX,highY=math.min(m.highX,math.max(paX,pbX)+extentX,texture.size-1),math.min(m.highY,math.max(paY,pbY)+extentY,texture.size-1)
   if lowX>highX or lowY>highY then continue end
   for y=math.floor(lowY/TileSize),math.floor(highY/TileSize) do
    for x=math.floor(lowX/TileSize),math.floor(highX/TileSize) do
     local key=m.tileBase+y*math.ceil(texture.size/TileSize)+x
     local tile=tiles[key]
     if not tile then tile={mapping=m,x=x*TileSize,y=y*TileSize,spans={}};tiles[key]=tile end
     table.insert(tile.spans,span)
    end
   end
 end
end
local function Prepare(texture: Texture,tiles: {[number]: Tile},segment: Types.VisualSegment): ()
 local body=texture.parts[segment.part]
 if not body then
  local part=texture.model:FindFirstChild(segment.part)
  if not part or not part:IsA("BasePart") or not Curve.IsPart(part) then return end
  local geometry=Curve.Geometry(part)
  local size=part.Size
  body={part=part,key=part.Name..":"..tostring(size),sx=size.X,sy=size.Y,sz=size.Z,bins=geometry.bins,triangleCount=#geometry.triangles,candidateCount=0,candidates={}}
  texture.parts[segment.part]=body
 end
 local firstIndex,lastIndex=segment.triangle0,segment.triangle1
 if segment.surfaceVersion~=Curve.Version or not firstIndex or not lastIndex then return end
 if firstIndex<1 or firstIndex%1~=0 or firstIndex>body.triangleCount or lastIndex<1 or lastIndex%1~=0 or lastIndex>body.triangleCount then return end
 if not (segment.u0>=0 and segment.v0>=0 and segment.u0+segment.v0<=1.00001 and segment.u1>=0 and segment.v1>=0 and segment.u1+segment.v1<=1.00001) then return end
 local first,last=MappingFor(texture,body.part,firstIndex,body.key),MappingFor(texture,body.part,lastIndex,body.key)
 if not first or not last then return end
 local ax,ay,az=first.ox+first.bx*segment.u0+first.cx*segment.v0,first.oy+first.by*segment.u0+first.cy*segment.v0,first.oz+first.bz*segment.u0+first.cz*segment.v0
 local bx,by,bz=last.ox+last.bx*segment.u1+last.cx*segment.v1,last.oy+last.by*segment.u1+last.cy*segment.v1,last.oz+last.bz*segment.u1+last.cz*segment.v1
 local dx,dy,dz=bx-ax,by-ay,bz-az
 local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
 if distance>Config.BrushRadius*3 then
  AddSpan(texture,tiles,body,bx,by,bz,bx,by,bz,last.nx,last.ny,last.nz)
 elseif firstIndex==lastIndex then
  -- 同一平面三角面内已有精确重心坐标，无需反复搜索最近三角面。
  AddSpan(texture,tiles,body,ax,ay,az,bx,by,bz,first.nx,first.ny,first.nz)
 else
  local steps=math.max(1,math.ceil(distance/(Config.PaintVisualWidth*.3)))
  local px,py,pz,nx,ny,nz=ax,ay,az,first.nx,first.ny,first.nz
  for index=1,steps do
   coroutine.yield()
   local x,y,z,nextNormalX,nextNormalY,nextNormalZ=bx,by,bz,last.nx,last.ny,last.nz
   if index<steps then
    local t=index/steps
    local sample=Curve.ProjectLocal(body.part,Vector3.new(ax+dx*t,ay+dy*t,az+dz*t))
    local m=MappingFor(texture,body.part,sample.triangle :: number,body.key)
    if not m then continue end
    x,y,z=m.ox+m.bx*sample.u+m.cx*sample.v,m.oy+m.by*sample.u+m.cy*sample.v,m.oz+m.bz*sample.u+m.cz*sample.v
    nextNormalX,nextNormalY,nextNormalZ=m.nx,m.ny,m.nz
   end
   -- 法线发生突变时只画端点，不能用连续胶囊跨过折面背侧。
   if nx*nextNormalX+ny*nextNormalY+nz*nextNormalZ>=.2 then
    AddSpan(texture,tiles,body,px,py,pz,x,y,z,nx,ny,nz,nextNormalX,nextNormalY,nextNormalZ)
   else
    AddSpan(texture,tiles,body,px,py,pz,px,py,pz,nx,ny,nz)
    AddSpan(texture,tiles,body,x,y,z,x,y,z,nextNormalX,nextNormalY,nextNormalZ)
   end
   px,py,pz,nx,ny,nz=x,y,z,nextNormalX,nextNormalY,nextNormalZ
  end
 end
end
local function RasterTile(texture: Texture,tile: Tile,diagnostics: Diagnostics?): ()
 local m=tile.mapping
 local radiusSquared=(Config.PaintVisualWidth*.5)^2
 local minX,minY,maxX,maxY=texture.minX,texture.minY,texture.maxX,texture.maxY
 for y=tile.y,math.min(texture.size-1,tile.y+TileSize-1) do
  for x=tile.x,math.min(texture.size-1,tile.x+TileSize-1) do
   local offset=(y*texture.size+x)*4
   -- 单色、只增不减的颜料：已着色像素无需对每条重叠路径再次测距。
   if buffer.readu8(texture.pixels,offset)==StrokeRed then continue end
   local px,py=x+.5-m.ax,y+.5-m.ay
   local u,v=(px*m.acy-py*m.acx)/m.det,(m.abx*py-m.aby*px)/m.det
   if u<-.005 or v<-.005 or u+v>1.005 then continue end
   local wx,wy,wz=m.ox+m.dxX*px+m.dyX*py,m.oy+m.dxY*px+m.dyY*py,m.oz+m.dxZ*px+m.dyZ*py
   for _,span in tile.spans do
    local dx,dy,dz=wx-span.x,wy-span.y,wz-span.z
    local t=math.clamp((dx*span.dx+dy*span.dy+dz*span.dz)*span.inverse,0,1)
    if m.nx*(span.nx+(span.ex-span.nx)*t)+m.ny*(span.ny+(span.ey-span.ny)*t)+m.nz*(span.nz+(span.ez-span.nz)*t)<.2 then continue end
    dx,dy,dz=dx-span.dx*t,dy-span.dy*t,dz-span.dz*t
    if dx*dx+dy*dy+dz*dz>radiusSquared then continue end
    buffer.writeu8(texture.pixels,offset,StrokeRed);buffer.writeu8(texture.pixels,offset+1,StrokeGreen);buffer.writeu8(texture.pixels,offset+2,StrokeBlue)
    texture.dirty=true
    minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
    break
   end
  end
 end
 texture.minX,texture.minY,texture.maxX,texture.maxY=minX,minY,maxX,maxY
 if diagnostics then
  diagnostics.scanned+=(math.min(texture.size,tile.x+TileSize)-tile.x)*(math.min(texture.size,tile.y+TileSize)-tile.y)
 end
end
local function DrawBatch(texture: Texture,segments: {Types.VisualSegment},diagnostics: Diagnostics?): number
 local tiles: {[number]: Tile}={}
 for _,segment in segments do Prepare(texture,tiles,segment);coroutine.yield() end
 -- 同批轨迹共享三角面分块，一个像素只扫描一次；分块之间检查帧预算。
 for _,tile in tiles do RasterTile(texture,tile,diagnostics);coroutine.yield() end
 return #segments
end
function View.IsReady(self: View,id: string): boolean
	local texture=self.textures[id]
	-- 图像 API 失败由客户端提示并退出，不能永久等待无法创建的图集。
	if not texture then return self.failed end
	return not texture.rebuilding and not texture.dirty and self.tasks[id]==nil and (self.heads[id] or 1)>#(self.queue[id] or {})
end
local function UploadTint(texture: Texture,brightness: number): ()
	local length=buffer.len(texture.pixels)
	local existing=texture.tinted
	local tinted: buffer=if existing and buffer.len(existing)==length then existing else buffer.create(length)
	texture.tinted=tinted
	buffer.copy(tinted,0,texture.pixels,0,length)
	if brightness>0 then
		local highlight=Config.AltarStrokeHighlight
		local targetRed,targetGreen,targetBlue=math.floor(highlight.R*255+.5),math.floor(highlight.G*255+.5),math.floor(highlight.B*255+.5)
		for offset=0,length-4,4 do
			if buffer.readu8(tinted,offset)==StrokeRed and buffer.readu8(tinted,offset+1)==StrokeGreen and buffer.readu8(tinted,offset+2)==StrokeBlue then
				buffer.writeu8(tinted,offset,math.floor(StrokeRed+(targetRed-StrokeRed)*brightness+.5))
				buffer.writeu8(tinted,offset+1,math.floor(StrokeGreen+(targetGreen-StrokeGreen)*brightness+.5))
				buffer.writeu8(tinted,offset+2,math.floor(StrokeBlue+(targetBlue-StrokeBlue)*brightness+.5))
			end
		end
	end
	texture.image:WritePixelsBuffer(Vector2.zero,Vector2.new(texture.size,texture.size),tinted)
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
			local segments: {Types.VisualSegment}={}
			for index=head,math.min(#queue,head+SegmentsPerBatch-1) do table.insert(segments,queue[index]) end
			head+=#segments
			task=coroutine.create(function(): number return DrawBatch(texture,segments,self.diagnostics) end)
			self.tasks[selected]=task
		end
		local ok,reason=coroutine.resume(task)
		if not ok then
			warn("[Paint] Raster failed: "..tostring(reason))
			self:RemoveTexture(selected);self.failed=true;self.retryAfter[selected]=os.clock()+3
			return
		end
		if coroutine.status(task)=="dead" then
			self.tasks[selected]=nil
			if self.diagnostics then self.diagnostics.completed+=reason :: number end
		end
		if os.clock()>=deadline then break end
	end
	self.heads[selected]=head
	local complete=not self.tasks[selected] and head>#queue
	if complete then self.queue[selected]={};self.heads[selected]=1 end
	-- 历史恢复只在完整重建后显示；正常输入仍逐帧提交变化区域。
	local committed=false
	if texture.dirty and (not texture.rebuilding or complete) then
		local diagnostics=self.diagnostics
		local before=if diagnostics then os.clock() else 0
		Commit(texture)
		committed=true
		if diagnostics then diagnostics.commits+=1;diagnostics.commitSeconds+=os.clock()-before end
	end
	if texture.rebuilding and complete then texture.rebuilding=false;Attach(texture) end
	local brightness=self.sacrifice[selected]
	if brightness and brightness>0 and not texture.rebuilding then
		local step=math.floor(brightness*SacrificeSteps+.5)
		if committed or self.sacrificeStep[selected]~=step then
			self.sacrificeStep[selected]=step
			UploadTint(texture,brightness)
		end
	end
end
function View.SetSacrifice(self: View,id: string,brightness: number): ()
	local step=math.floor(math.clamp(brightness,0,1)*SacrificeSteps+.5)
	local shown=step/SacrificeSteps
	if step==0 then self.sacrifice[id]=nil else self.sacrifice[id]=shown end
	local texture=self.textures[id]
	if not texture or texture.rebuilding then return end
	if self.sacrificeStep[id]==step then return end
	self.sacrificeStep[id]=step
	UploadTint(texture,shown or 0)
end
function View.Remove(self: View,id: string): ()
	self:RemoveTexture(id)
	self.models[id],self.records[id],self.queue[id],self.retryAfter[id],self.heads[id],self.sacrifice[id],self.sacrificeStep[id]=nil,nil,nil,nil,nil,nil,nil
end
function View.Destroy(self: View): () for id in self.models do self:Remove(id) end end
return View
