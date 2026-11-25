-- 在 Play 客户端用独立 WhiteR15 验证倒地额度、工位预占、远景、旁路和重绑。
--!strict
local rs=game:GetService("ReplicatedStorage")
local client=rs.Scripts.Client
local Manager=require(client.WhiteBodyPresentationManager)
local Tuning=require(client.PresentationTuning)
local TableView=require(client.BodyPresentation)
local Hit=require(client.HitPresentation)
local run=game:GetService("RunService")
assert(run:IsClient() and run:IsStudio())
local bodies=Manager.new(TableView.new(),Hit.new(),function() end)
local fixtures={}
local report={}
local cfg=Tuning.GetEffectiveConfig()
local function Start(id: string,distance: number)
	local rig=rs.Models.Characters.WhiteR15:Clone()
	table.insert(fixtures,rig)
	local camera=assert(workspace.CurrentCamera)
	local pose=camera.CFrame*CFrame.new(0,0,-distance)
	rig:PivotTo(pose)
	rig.Parent=workspace
	rig.PrimaryPart.Anchored=true
	local item={id=id,version=3,hits=2,model=rig,kind="Body",location="Street",stage="Unpainted",progress=0}
	bodies:Bind(item)
	local view=assert(bodies.views[id])
	local display=view.visualModel
	local down=table.clone(item) :: any
	down.hits,down.version=3,4
	down.fall={target=pose*CFrame.Angles(math.pi/2,0,0),started=workspace:GetServerTimeNow(),velocity=Vector3.xAxis*3}
	bodies:Bind(down)
	assert(view.fall and view.visualModel==display and bodies:GetAuthorityModel(id)==rig)
	return view,down
end
local function Run()
	local cap=if game:GetService("UserInputService").TouchEnabled then cfg.Fall.MobileBodies else cfg.Fall.DesktopBodies
	local total=0
	for i=1,cap+1 do
		local view=Start("near"..i,8)
		local fall=assert(view.fall)
		assert(fall.active==(i<=cap) and #fall.sockets==(if i<=cap then 6 else 0))
		total+=#fall.sockets
	end
	report.nearBodies,report.openSockets=cap,total
	bodies:Step(workspace:GetServerTimeNow(),1/60,true)
	local active=0
	for _,v in bodies.views do if v.fall and v.fall.active then active+=1 end end
	assert(active==cap-1)
	report.afterTableReservation=active
	local far,down=Start("far",90)
	assert(far.fall and far.fall.sleepPose and #far.fall.sockets==0)
	local before=far.visualModel
	down.model=down.model:Clone();down.model.Parent=workspace;table.insert(fixtures,down.model)
	bodies:Bind(down)
	local replacement=bodies.views.far
	assert(before and before.Parent==nil and replacement.bindGeneration>far.bindGeneration)
	assert(replacement.fall and replacement.fall.sleepPose and replacement.fall~=far.fall)
	bodies:SetLayer("LocalRagdoll",false)
	for _,v in bodies.views do assert(v.fall and #v.fall.sockets==0) end
	bodies:SetEnabled(false)
	for _,v in bodies.views do assert(v.mode=="Authority" and not v.visualModel) end
	report.farAsleep,report.rebind,report.bypass=true,true,true
	for id in bodies.items do bodies:Unbind(id) end
	assert(Tuning.ApplyOverrides({Fall={DesktopBodies=1,MobileBodies=1}},100))
	Tuning.Commit()
	bodies:SetEnabled(true);bodies:SetLayer("LocalRagdoll",true)
	local one=Start("touchBudget1",8)
	local two=Start("touchBudget2",8)
	assert(one.fall and one.fall.active and two.fall and not two.fall.active)
	report.oneBodyBudget=true
	return report
end
local ok,result=pcall(Run)
bodies:Destroy()
for _,rig in fixtures do rig:Destroy() end
Tuning.Reset();Tuning.Commit()
assert(ok,result)
return result
