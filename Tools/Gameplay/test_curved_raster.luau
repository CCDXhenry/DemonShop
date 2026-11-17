-- 正式曲面渲染器回归：像素等价、预算恢复、局部提交、缓存和退出收尾。
local R=require('@lune/roblox')
local View=require('./CurvedPaintView')
local Curve=require('./CurvedSurface')
local Data=require('./BodySurfaceData')
local Config=require('./GameConfig')
local B=require('./CurvedRasterBoundary')
local Reference=require('./CurvedRasterReference')
local Upload=require('./VisualUpload')
local Net=require('./VisualNet')
local count=0
local function check(value,message) assert(value,message);count+=1 end
local parts={}
for _,name in {'UpperTorso','Head','LeftHand','LeftFoot'} do
 local part=R.Instance.new('Part')
 part.Name,part.Size=name,Data.Parts[name].size
 part:SetAttribute('Paintable',true);part:SetAttribute('SurfaceVersion',Curve.Version)
 table.insert(parts,part)
end
local model=B.Model(parts)
local records={}
local view=View.new()
view:Bind('body',model,records)
view:Update('body')
local texture=view.textures.body
check(view:IsReady('body') and #texture.image.writes==1,'empty active texture initialized and ready')
check(texture.size==1024 and model.meshes[1].TextureContent==texture.image,'active texture attached at full resolution')
local reference={model=model,size=texture.size,pixels=buffer.create(texture.size^2*4),scanned=0,slices=0}
buffer.fill(reference.pixels,0,255)
local serial=0
local function segment(part,a,b)
 serial+=1
 return {key='session:1:'..serial,version=1,gesture=1,part=part.Name,face=1,u0=a.u,v0=a.v,u1=b.u,v1=b.v,triangle0=a.triangle,triangle1=b.triangle,surfaceVersion=Curve.Version}
end
local function projected(part,x,y,z) return Curve.ProjectLocal(part,R.Vector3.new(x,y,z)*part.Size) end
local function add(s)
 records[s.key]=s;view:Apply('body',s);Reference.Draw(reference,s)
end
-- 短线、长线、跨面路径、接缝两侧、不同尺寸部件以及重复覆盖。
for _,part in parts do
 local p=projected(part,-.1,.05,-.49)
 add(segment(part,p,p))
 add(segment(part,p,projected(part,.12,.08,-.49)))
 add(segment(part,projected(part,-.35,.1,-.4),projected(part,.35,.1,-.4)))
 for _,points in {{.49,.05,0,.49,.18,.08},{-.01,.05,.49,.01,.05,.49},{.1,-.45,-.2,.12,-.45,-.18}} do
  add(segment(part,projected(part,points[1],points[2],points[3]),projected(part,points[4],points[5],points[6])))
 end
end
-- 从实际资产查找位置相同、UV 分离的接缝顶点，验证笔刷同时覆盖图集两侧。
local head=parts[2]
local source=Data.Parts.Head
local seamA,seamB
for first,a in source.vertices do
 if math.abs(a.Y)>.2 then continue end
 for second=first+1,#source.vertices do
  if (a-source.vertices[second]).Magnitude<1e-5 and (source.uvs[first]-source.uvs[second]).Magnitude>.1 then seamA,seamB=first,second;break end
 end
 if seamA then break end
end
check(seamA~=nil and seamB~=nil,'fixture discovers a real duplicated-position UV seam')
local seam=Curve.ProjectLocal(head,source.vertices[seamA]*head.Size)
add(segment(head,seam,seam))
local repeatStroke=segment(parts[1],projected(parts[1],-.1,.05,-.49),projected(parts[1],.12,.08,-.49))
add(repeatStroke);add(repeatStroke)
local function drain(target,active)
 local frames=0
 repeat target:Update(active);frames+=1;assert(frames<20000,'raster queue failed to drain') until target:IsReady('body')
 return frames
end
B.step=.001
local writes=#texture.image.writes
view:Update('body')
check(not view:IsReady('body') and view.tasks.body~=nil,'long work yields within a frame and retains its continuation')
check((view.heads.body or 1)<=2,'budget does not consume the whole pending queue')
local readStart=B.clockReads
local frames=drain(view,'body')
local rasterSlices=B.clockReads-readStart
check(frames>1,'long paths resume across frames')
check(buffer.tostring(texture.pixels)==buffer.tostring(reference.pixels),'optimized raster exactly matches old pixels for all fixtures')
check(buffer.tostring(texture.image.pixels)==buffer.tostring(texture.pixels),'partial GPU writes reproduce the complete CPU image')
for _,vertex in {seamA,seamB} do
 local uv=source.uvs[vertex]
 local x,y=math.floor(uv.X*texture.size),math.floor((1-uv.Y)*texture.size)
 local painted=false
 for dy=-2,2 do for dx=-2,2 do
  local offset=((y+dy)*texture.size+x+dx)*4
  if buffer.readu8(texture.pixels,offset)==176 then painted=true end
 end end
 check(painted,'brush paints actual UV seam island '..vertex)
end
check(#view.queue.body==0 and view.tasks.body==nil,'queue and completed continuation released')
local partial=false
for index=writes+1,#texture.image.writes do
 local write=texture.image.writes[index]
 if write.size.X<texture.size or write.size.Y<texture.size then partial=true end
end
check(partial,'live strokes submit dirty rectangles instead of the entire atlas')
-- 每次 clock 读取对应一次可中断切片，连同帧调度开销仍应少于完整扫描所需切片。
check(rasterSlices<reference.slices,'bounded brush scan reduces deterministic work even including frame scheduling')
local allocations=#B.images
local oldImage=texture.image
local oldWrites=#oldImage.writes
view:Update(nil)
check(view.textures.body==texture and #B.images==allocations,'exit keeps resident high-resolution texture')
check(#oldImage.writes==oldWrites and #view.queue.body==0,'exit neither redraws nor requeues history')
view:Update('body')
check(view.textures.body.image==oldImage,'immediate reentry reuses completed atlas')
local replacement=B.Model(parts)
view:Bind('body',replacement,records)
check(replacement.meshes[1].TextureContent==oldImage,'model replacement rebinds completed atlas')
view:RemoveTexture('body')
check(oldImage.destroyed,'eviction destroys image')
view:Update(nil)
local rebuilt=view.textures.body
check(rebuilt.rebuilding and #rebuilt.image.writes==0,'history rebuild has no partial image submission')
check(replacement.meshes[1].TextureContent=='none','history stays detached while rebuilding')
drain(view,nil)
check(#rebuilt.image.writes==1 and replacement.meshes[1].TextureContent==rebuilt.image,'history becomes visible only after complete reconstruction')
check(rebuilt.size==512,'evicted observer atlas restores at observer resolution')
local lowReference={model=model,size=512,pixels=buffer.create(512^2*4),scanned=0,slices=0}
buffer.fill(lowReference.pixels,0,255)
for _,s in records do Reference.Draw(lowReference,s) end
check(buffer.tostring(rebuilt.pixels)==buffer.tostring(lowReference.pixels),'observer rebuild retains every canonical stroke')
view:Update('body');drain(view,'body')
check(view.textures.body.size==1024,'observer texture upgrades when painting resumes')
check(buffer.tostring(view.textures.body.pixels)==buffer.tostring(reference.pixels),'upgrade preserves exact high-resolution history')
-- 网络已确认但本地未画完时，不能结束会话。
table.clear(Net.requests)
local upload=Upload.new();upload:Begin('session');upload.closing=true
upload:Update({},1,1,0,0,true,nil,false)
check(#Net.requests==0,'exit waits for local raster even with no pending network batches')
upload:Update({},1.1,1,0,0,true,nil,true)
check(#Net.requests==1 and Net.requests[1].action=='EndPaint','raster completion permits final EndPaint')
upload:Update({},1.2,1,0,0,true,nil,true)
check(#Net.requests==1,'repeated exit completion cannot send EndPaint twice')
-- 取消处理中任务不允许继续写已销毁纹理；重生/移除沿用相同释放点。
local nextStroke=segment(parts[1],projected(parts[1],-.3,.1,-.49),projected(parts[1],.3,.1,-.49))
records[nextStroke.key]=nextStroke;view:Apply('body',nextStroke);view:Update('body')
local pending=view.tasks.body
check(pending~=nil,'cleanup fixture has suspended raster work')
view:Remove('body')
check(coroutine.status(pending)=='dead' and view.tasks.body==nil and view.heads.body==nil,'body removal closes continuation and clears cursor')
check(view.models.body==nil and view.records.body==nil and view.queue.body==nil,'removal releases geometry ownership')
view:Destroy()
local failed=View.new()
failed:Bind('body',model,records)
B.failNext=true;failed:Update('body')
check(failed.failed and failed.textures.body==nil and failed:IsReady('body'),'image API failure releases the raster wait so error exit can complete')
failed:Destroy()
for _,part in parts do part:Destroy() end
print('PASS: '..count..' production curved raster assertions; optimized slices '..rasterSlices..', full-scan slices '..reference.slices..', baseline pixels scanned '..reference.scanned)
