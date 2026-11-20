-- 曲面首笔端到端回归：正式渲染器生成标识，经上传队列和服务端规则保存后重建
local Roblox=require('@lune/roblox')
local View=require('./PaintView')
local Curve=require('./CurvedSurface')
local Data=require('./BodySurfaceData')
local Rules=require('./VisualRules')
local Protocol=require('./VisualProtocol')
local Upload=require('./VisualUpload')
local Net=require('./VisualNet')
local count=0
local function check(value,message) assert(value,message);count+=1 end
local model=Roblox.Instance.new('Model')
model:SetAttribute('SurfaceVersion',Curve.Version)
local part=Roblox.Instance.new('Part')
part.Name,part.Size='UpperTorso',Data.Parts.UpperTorso.size
part:SetAttribute('Paintable',true)
part:SetAttribute('SurfaceVersion',Curve.Version)
part.Parent=model
local bodyId='1314d4e7-f70a-4f54-a2d9-d0e1612bf7ec'
local session='7d1516b7-104c-4ab3-91ba-a17d51bb7bd4'
local view=View.new()
view:Bind(bodyId,model)
local first=Curve.ProjectLocal(part,Roblox.Vector3.new(-.15,.1,-.5))
local second=Curve.ProjectLocal(part,Roblox.Vector3.new(.15,.1,-.5))
view:DrawLocal(bodyId,session,1,{first,second})
local dirty=view:Drain(bodyId)
local state=Rules.New()
table.clear(Net.requests)
local upload=Upload.new()
upload:Begin(session)
upload:Update(dirty,.1,10,false)
check(#Net.requests==1,'first actual renderer stroke produces one upload')
local request=Net.requests[1]
check(Protocol.Validate(request),'actual generated curved packet passes boundary validation')
local accepted,reason=Rules.Apply(state,request.segments,session)
check(accepted~=nil,'first actual renderer stroke accepted: '..tostring(reason))
check(state.count==2,'both first stroke samples stored by server')
for _,segment in accepted do
 check(string.sub(segment.key,1,#session+1)==session..':','session owns generated segment key')
 check(segment.surfaceVersion==Curve.Version and segment.triangle0~=nil and segment.triangle1~=nil,'server retains curve geometry')
end
upload:Ack(request.sequence)
upload.closing=true
upload:Update({},.2,10,true)
check(Net.requests[2].action=='EndPaint' and Net.requests[2].sequence==1,'intentional exit waits for stored stroke acknowledgement')
local observer=View.new()
observer:Bind(bodyId,model)
observer:Apply(bodyId,accepted)
check(observer.counts[bodyId]==2,'observer rebuild restores saved stroke')
local replacement=model:Clone()
observer:Bind(bodyId,replacement)
check(observer.counts[bodyId]==2,'reenter/rebind keeps canonical paint history')
observer:Apply(bodyId,accepted)
check(observer.counts[bodyId]==2,'sync replay does not duplicate paint')
local secondSession='8796426c-7ee0-4ea8-a0cf-2f29eaf840b4'
view:DrawLocal(bodyId,secondSession,1,{first})
local nextBatch={}
for _,segment in view:Drain(bodyId) do table.insert(nextBatch,segment) end
check(Rules.Apply(state,nextBatch,secondSession)~=nil,'new painting session can append to existing body')
check(Rules.Apply(state,nextBatch,session)==nil,'foreign session remains rejected')
local triangle=1
for index,geometry in Curve.Geometry(part).triangles do
 if geometry.allowed and geometry.area>Curve.Geometry(part).triangles[triangle].area then triangle=index end
end
local function onTriangle(u,v)
 return {part=part.Name,face=1,u=u,v=v,triangle=triangle,surfaceVersion=Curve.Version}
end
local before=view.counts[bodyId]
view:DrawLocal(bodyId,secondSession,2,{onTriangle(.1,.2),onTriangle(.2,.2),onTriangle(.3,.2)})
local key,line=next(view:Drain(bodyId))
check(view.counts[bodyId]==before+1 and line.version==3 and line.u0==.1 and line.u1==.3,
 'three straight samples queue only the latest continuous segment')
check(Rules.Apply(state,{line},secondSession)~=nil,'merged line retains valid origin and version')
view:DrawLocal(bodyId,secondSession,2,{onTriangle(.3,.4)})
local corner=next(view:Drain(bodyId))
check(corner~=key and view.counts[bodyId]==before+2,'a corner starts a new segment without straightening the earlier path')
-- 长笔画填满精确线段历史后，继续写入固定大小的表面遮罩，重复描画和接力均可重放。
local Config=require('./GameConfig')
view.counts[bodyId]=Config.PaintLocalSegmentBudget
state.count=Config.PaintLocalSegmentBudget
local more={onTriangle(.1,.1),onTriangle(.2,.2),onTriangle(.3,.2)}
view:DrawLocal(bodyId,secondSession,3,more)
local inkKey,patch=next(view:Drain(bodyId))
check(more[1].packedInk and patch and patch.ink and not view.budgetReached,'saturated vector history continues painting')
check(Protocol.Validate({action='PaintVisual',sequence=3,started=1,segments={patch}}),'bounded triangle mask passes transport validation')
local inkAccepted=Rules.Apply(state,{patch},secondSession)
check(inkAccepted and #inkAccepted==1 and state.count==Config.PaintLocalSegmentBudget+1,'one additional record per occupied triangle')
observer:Apply(bodyId,inkAccepted)
view:DrawLocal(bodyId,secondSession,4,more)
check(not next(view:Drain(bodyId)),'repainting a full stroke creates no additional history')
local independent=table.clone(patch)
independent.ink=Curve.CopyInk(nil)
Curve.MarkInk(independent.ink,.1,.6)
local merged=Rules.Apply(state,{independent},'next-operator')
observer:Apply(bodyId,merged)
local nodes=0
Curve.EachInk(observer.segments[bodyId][inkKey].ink,function() nodes+=1 end)
check(nodes==4 and state.inkCount==1,'reentry and partial updates union all ink without increasing storage')
local tampered=table.clone(patch)
tampered.key='ink:other'
check(not Rules.Validate(tampered),'non-canonical mask key rejected')
tampered=table.clone(patch)
tampered.ink=buffer.create(42)
check(not Rules.Validate(tampered),'oversized masks rejected')
view:Destroy();observer:Destroy();model:Destroy();replacement:Destroy()
print('PASS: '..count..' curved first-stroke pipeline assertions (production renderer, queue, protocol and server storage; GPU boundary mocked)')
