-- 正式画符服务的离线回归：序号、姿态、遮挡、完成与笔划预算
local Roblox = require('@lune/roblox')
local C = Roblox.CFrame
local Painting = require('./Painting')
local Config = require('./GameConfig')
local Surface = require('./PaintSurface')
local World = require('./PaintingWorld')
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local container = Roblox.Instance.new('Model')
local model = {}
local part = Roblox.Instance.new('Part')
part.Name, part.Size = 'UpperTorso', Roblox.Vector3.new(2,2,1)
part.CFrame = Roblox.CFrame.identity
part:SetAttribute('Paintable',true)
part.Parent = container
function model:FindFirstChild(name) return container:FindFirstChild(name) end
function model:PivotTo(frame) part.CFrame = frame end
World.part = part
local session = { token = 'session', sequence = 0, last = 0, orientation = C.identity }
local item = { model = model, covered = {}, area = 0, totalArea = 100, paintSeconds = 0, progress = 0, strokes = {}, strokePoints = 0 }
local sample = { part = 'UpperTorso', face = 1, u = .5, v = .5 }
local request = { sequence = 1, orientation = C.identity, samples = {sample} }
local origin = Roblox.Vector3.new(0,0,-10)
local pose = Roblox.CFrame.identity
local first = Painting.Apply(session,item,request,pose,origin,.1)
check(first and first.stroke and #first.stroke.samples == 1,'accepted samples retain continuous stroke coordinates')
check(item.area > 0 and item.progress > 0,'visible accepted sample adds coverage')
local area = item.area
check(Painting.Apply(session,item,request,pose,origin,.2) == nil,'duplicate sequence rejected')
check(item.area == area and #item.strokes == 1,'duplicate does not append strokes or coverage')
request.sequence = 2
Painting.Apply(session,item,request,pose,origin,.2)
check(item.area == area,'repainting does not increase progress')
World.visible = false
request.sequence = 3
local smallTurn = C.Angles(0,.1,0)
request.orientation = smallTurn
local occluded = Painting.Apply(session,item,request,pose,origin,.3)
check(occluded and not occluded.stroke and session.orientation==smallTurn,'occluded sample leaves no stroke while display still rotates')
check(item.area == area,'occlusion cannot paint through body')
World.visible = true
local back = C.Angles(0,math.pi,0)
request.sequence, request.orientation = 4, back
request.samples = {
	{part='UpperTorso', face=1, u=.5, v=.5, orientation=C.identity},
	{part='UpperTorso', face=2, u=.5, v=.5, orientation=back},
	{part='UpperTorso', face=2, u=.5, v=.5, orientation=C.identity},
}
local fast = Painting.Apply(session,item,request,pose,origin,.4)
check(fast and fast.stroke and #fast.stroke.samples == 2 and fast.stroke.samples[2].face == 2,
	'front and back use their own sampled poses and the hidden face is rejected')
check(session.orientation==back and item.area>area,'back paint adds coverage and updates table orientation')
request.sequence, request.orientation = 5, C.identity
request.samples = {sample}
item.totalArea = item.area / Config.PaintTarget
local complete = Painting.Apply(session,item,request,pose,origin,.5)
check(complete and complete.complete and item.progress == 1 and item.paintSeconds < 12,'coverage completes without hidden 12 second gate')
item.strokePoints = Config.PaintStrokePointBudget
request.sequence = 6
local capped = Painting.Apply(session,item,request,pose,origin,.6)
check(capped and not capped.stroke and item.strokePoints == Config.PaintStrokePointBudget,'visual budget remains bounded independently of coverage')
local combined = C.Angles(.7,-.3,.4)
request.sequence, request.orientation, request.samples = 7, combined, {}
local beforeEmpty = item.area
local empty = Painting.Apply(session,item,request,pose,origin,.7)
check(empty and not empty.stroke and item.area == beforeEmpty,'pose-only batch cannot award coverage')
check(session.orientation == combined,'pose-only batch publishes complete orientation')
request.sequence = 6
request.orientation = C.identity
check(Painting.Apply(session,item,request,pose,origin,.8) == nil and session.orientation == combined,'old batch cannot roll pose back')
local originalTarget = Config.PaintTarget
item.totalArea = item.area / 0.4
Config.PaintTarget = 0.8
request.sequence = 8
local partial = Painting.Apply(session,item,request,pose,origin,.9)
check(partial and not partial.complete and math.abs(item.progress-.5)<1e-6,'changing the target changes the completion threshold')
Config.PaintTarget = originalTarget
Painting.SetPose(session,item,pose,C.identity)
check(part.CFrame.Position.Magnitude<1e-5 and part.CFrame.LookVector:Dot(Roblox.Vector3.new(0,0,-1))>.99999,
	'reset restores the original orientation')
-- 服务端与笔尖使用同一个可见网格，物理碰撞壳不可将前臂画穿到躯干。
local Curve=require('./CurvedSurface')
local mesh=Roblox.Instance.new('Model')
local function meshPart(name,z)
	local p=Roblox.Instance.new('Part')
	p.Name,p.Size,p.CFrame=name,Roblox.Vector3.one,C.new(0,0,z)
	p:SetAttribute('SurfaceVersion',Curve.Version);p:SetAttribute('Paintable',true);p.Parent=mesh
	return p
end
local arm=meshPart('LeftUpperArm',-2)
local chest=meshPart('UpperTorso',0)
local blocked=Curve.Intersect(chest,origin,Roblox.Vector3.zAxis,20)
local front=Curve.Intersect(arm,arm.CFrame:PointToObjectSpace(origin),Roblox.Vector3.zAxis,20)
World.visible=false
item.model,item.area,item.covered,item.strokePoints,item.totalArea=mesh,0,{},0,100
session.orientation=C.identity
local exact=Painting.Apply(session,item,{sequence=9,orientation=C.identity,samples={blocked,front}},pose,origin,1)
check(exact and exact.stroke and #exact.stroke.samples==1 and exact.stroke.samples[1].part==arm.Name and item.area>0,'exact frontmost curved mesh wins on server independent of collision shell')
-- 超出线段预算后的 packedInk 样本按 InkCenter 量子化盖章，不跨点插值，与客户端位图对齐。
local function visibleArm(x)
	local dir=(Roblox.Vector3.new(x,0,-2)-origin).Unit
	local hit=Curve.FirstHit(Curve.BodyMesh(mesh),origin,dir,20)
	assert(hit and hit.part==arm.Name,'packedInk fixture requires visible arm hit')
	return hit
end
local leftPacked,rightPacked=visibleArm(-.1),visibleArm(.1)
leftPacked.packedInk,rightPacked.packedInk=true,true
item.area,item.covered,item.strokePoints=0,{},0
local packedResult=Painting.Apply(session,item,{sequence=10,orientation=C.identity,samples={leftPacked,rightPacked}},pose,origin,1.1)
local expectedCovered,expectedArea={},0
for _,s in {leftPacked,rightPacked} do
	local q=table.clone(s)
	q.u,q.v=Curve.InkCenter(s.u,s.v)
	local _,added=Surface.Stamp(arm,q,expectedCovered)
	expectedArea+=added
end
local sameCells=true
for k in item.covered do if not expectedCovered[k] then sameCells=false;break end end
for k in expectedCovered do if not item.covered[k] then sameCells=false;break end end
check(packedResult and math.abs(item.area-expectedArea)<1e-6 and sameCells,'packedInk stamps only quantized InkCenter cells without segment interpolation')
local leftPlain,rightPlain=visibleArm(-.1),visibleArm(.1)
item.area,item.covered,item.strokePoints=0,{},0
Painting.Apply(session,item,{sequence=11,orientation=C.identity,samples={leftPlain,rightPlain}},pose,origin,1.2)
check(item.area>expectedArea,'non-packed adjacent curved samples still interpolate across the gap')
-- 旋转横截面采样（slice=true）允许被手臂遮挡的躯干凹处落墨，同时拒绝未旋转时的背面采样。
local sliceOccluded = table.clone(blocked)
sliceOccluded.slice = true
local backPoint = Curve.Intersect(chest, Roblox.Vector3.new(0, 0, 10), -Roblox.Vector3.zAxis, 20)
assert(backPoint, 'back point fixture')
local sliceBack = table.clone(backPoint)
sliceBack.slice = true
item.area, item.covered, item.strokePoints = 0, {}, 0
local sliceResult = Painting.Apply(session, item, { sequence = 12, orientation = C.identity, samples = { sliceOccluded, sliceBack } }, pose, origin, 1.3)
check(sliceResult and sliceResult.stroke and #sliceResult.stroke.samples == 1 and sliceResult.stroke.samples[1].part == chest.Name and item.area > 0,
	'slice mode accepts concave front-hemisphere surface occluded by limb and rejects unrotated back side')
-- 旋转连续采样即使每点 orientation 不同，服务端仍保留同面线段补采样。
local rotA = table.clone(leftPlain)
local rotB = table.clone(rightPlain)
rotA.slice, rotB.slice = true, true
rotA.orientation = C.identity
rotB.orientation = C.Angles(0, 0.02, 0)
item.area, item.covered, item.strokePoints = 0, {}, 0
Painting.Apply(session, item, { sequence = 13, orientation = C.identity, samples = { rotA, rotB } }, pose, origin, 1.4)
check(item.area > expectedArea, 'rotating consecutive samples keep server segment interpolation instead of resetting previous')
local sourceInk=Curve.CopyInk(nil)
Curve.MarkInk(sourceInk,.2,.2)
local mergedInk=Curve.MergeInk(nil,sourceInk)
Curve.MarkInk(sourceInk,.6,.2)
local mergedCount=0
Curve.EachInk(mergedInk,function() mergedCount+=1 end)
check(mergedCount==1,'MergeInk copies initial buffer instead of aliasing caller storage')
mesh:Destroy()
container:Destroy()
print(string.format('PASS: %d painting assertions (production module; mocked raycast boundary)',checks))
