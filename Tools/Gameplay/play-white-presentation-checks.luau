-- 在 Play 客户端独立克隆正式 WhiteR15，检查两类关节、回退、流出流入及资源释放。
--!strict
local client=game:GetService("ReplicatedStorage").Scripts.Client
local WhiteBodies=require(client.WhiteBodyPresentationManager)
local TableView=require(client.BodyPresentation)
local HitView=require(client.HitPresentation)
local Adapter=require(client.JointAdapter)
local template=game:GetService("ReplicatedStorage").Models.Characters.WhiteR15
local rig=template:Clone()
rig.Name="Phase1Fixture"
-- 测试在单次同步调用内结束，不改正式实例或运行中玩家。
local manager=WhiteBodies.new(TableView.new(),HitView.new(),function() end)
local function Run()
	rig.Parent=workspace
	local head=rig.Head
	head.LocalTransparencyModifier=.375
	local item={stage="Blank",progress=0,id="fixture",model=rig,kind="Body",location="Street",version=1,hits=0}
	local function Inspect()
		manager:Bind(item)
		local view=manager.views.fixture
		assert(view.mode=="Street",view.diagnostic)
		local visual=assert(view.visualModel)
		local n=0
		manager:Step(0,1/60)
		for name,joint in view.jointMap do
			assert(joint.submissions==1 and joint.step==manager.step,name)
			n+=1
		end
		for _,part in rig:GetChildren() do
			if part:IsA("MeshPart") then
				local display=visual:FindFirstChild(part.Name)
				assert(display and display:IsA("MeshPart") and display.MeshId==part.MeshId and display:GetAttribute("Paintable")==part:GetAttribute("Paintable"))
			end
		end
		assert(n==15 and visual:GetAttribute("SurfaceVersion")==rig:GetAttribute("SurfaceVersion"))
		manager:Unbind("fixture")
		return n
	end
	local motors=Inspect()
	for _,m in Adapter.Map(rig) do
		local a,b=Instance.new("Attachment"),Instance.new("Attachment")
		a.CFrame,a.Parent=m.c0,m.parent
		b.CFrame,b.Parent=m.c1,m.child
		local drive=Instance.new("AnimationConstraint")
		drive.Name,drive.Attachment0,drive.Attachment1="Drive"..m.child.Name,a,b
		drive.IsKinematic,drive.Parent=true,m.child
		m.drive:Destroy()
	end
	local animation=Inspect()
	local peak=0
	for _=1,50 do
		manager:Bind(item)
		local view=manager.views.fixture
		local copy=view.visualModel
		local connections=table.clone(view.cleanup)
		peak=math.max(peak,#connections)
		assert(copy and not copy:FindFirstChildWhichIsA("Animator",true))
		manager:Unbind("fixture")
		assert(copy.Parent==nil and head.LocalTransparencyModifier==.375)
		for _,c in connections do assert(not c.Connected) end
	end
	manager:Bind(item)
	local previous=manager.views.fixture.bindGeneration
	rig.Parent=nil
	manager:Step(1,1/60)
	assert(manager:GetVisualModel("fixture")==nil and head.LocalTransparencyModifier==.375)
	rig.Parent=workspace
	manager:Step(2,1/60)
	assert(manager.views.fixture.bindGeneration>previous)
	local root=Adapter.Map(rig).Root.drive
	assert(root:IsA("AnimationConstraint"))
	root.Attachment0=nil
	manager:Unbind("fixture")
	manager:Bind(item)
	assert(manager.views.fixture.diagnostic and not manager.views.fixture.visualModel and head.LocalTransparencyModifier==.375)
	manager:Destroy()
	assert(not next(manager.views) and manager:GetDebugStats().runServiceConnections==0)
	return {Motor6D=motors,AnimationConstraint=animation,cycles=50,peakBindingConnections=peak,remainingConnections=0,
		remainingClones=0,remainingTracks=0,hiddenParts=0,streamRebind=true,brokenAttachmentFallback=true}
end
local ok,result=pcall(Run)
manager:Destroy()
rig:Destroy()
assert(ok,result)
return result
