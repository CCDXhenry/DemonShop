-- 正式受击规则及表现模块回归：预测确认、重复乱序、物理交接、相机恢复与特效池上限
local R=require("@lune/roblox")
local Rules=require("./HitFeedbackRules")
local Config=require("./GameConfig")
local View=require("./HitPresentation")
local World=require("./HitPresentationBoundary")
local checks=0
local function Check(value,message) assert(value,message); checks+=1 end
local state=Rules.New()
Rules.Begin(state,1,"A",0.16,2)
Check(Rules.TakePrediction(state,1,0.15)==nil,"windup respected")
Check(Rules.TakePrediction(state,1,0.16)=="A","immediate prediction")
Check(Rules.TakePrediction(state,1,0.17)==nil,"predict once")
Rules.Result(state,1,true)
Check(not Rules.Confirm(state,"A",2,1),"successful result before broadcast retains dedup")
Check(not Rules.Confirm(state,"A",2,nil),"duplicate version ignored")
Check(not Rules.Confirm(state,"A",1,nil),"old version ignored")
Check(Rules.Confirm(state,"A",3,nil),"another actor's newer hit plays")
Rules.Begin(state,2,"A",1,3)
Rules.Result(state,2,false)
Check(Rules.TakePrediction(state,2,1)==nil,"rejected attack cancels pending prediction")
Rules.Begin(state,3,"A",1,3)
Check(Rules.Confirm(state,"B",2,3),"different authoritative target plays")
Check(Rules.TakePrediction(state,3,1)==nil,"confirmation before due cancels prediction")
Rules.Begin(state,4,"A",1,2)
Check(Rules.TakePrediction(state,4,3)==nil,"stale prediction never plays")
Rules.Prune(state,4)
Check(next(state.pending)==nil,"expired requests released")
Check(Rules.Envelope(-1,0.35,0.05)==0 and Rules.Envelope(0.35,0.35,0.05)==0,"outside pose lifetime")
Check(math.abs(Rules.Envelope(0.05,0.35,0.05)-1)<0.00001,"peak matches configured time")
for _,fps in {30,60} do
	Check(Rules.Envelope(math.ceil(0.45*fps)/fps,0.45,0.05)==0,"time based recovery")
end
local model=R.Instance.new("Model")
model.Parent=World.world
local root=R.Instance.new("Part")
root.Parent=model
model.PrimaryPart=root
local joint=R.Instance.new("Motor6D")
joint.Name="Waist"
joint.Parent=root
joint.Enabled=true
joint.Transform=R.CFrame.identity
local view=View.new()
view:Play("A",model,1,R.Vector3.zAxis,0)
view:Apply(0.05)
Check(joint.Transform~=R.CFrame.identity,"local pose applied")
view:Restore()
Check(joint.Transform==R.CFrame.identity,"pose restored without cumulative offset")
view:Apply(0.1)
model:SetAttribute("MotionState","Down")
view:Restore(); view:Apply(0.11)
Check(view.poses.A==nil and joint.Transform==R.CFrame.identity,"ragdoll handoff")
model:SetAttribute("MotionState","Idle")
view:Play("A",model,2,R.Vector3.xAxis,1)
view:Apply(1.05); view:Remove("A")
Check(joint.Transform==R.CFrame.identity,"target removal undoes joint offset")
view:Play("A",model,1,R.Vector3.zAxis,2)
model.Parent=nil; view:Restore(); view:Apply(2.1)
model:Destroy()
Check(view.poses.A==nil,"destroyed model released")
local base=World.CurrentCamera.CFrame
view:Shake(0,false,false); view:UpdateCamera(0.02,true)
Check(World.CurrentCamera.CFrame~=base,"camera kick")
view:RestoreCamera()
Check((World.CurrentCamera.CFrame.Position-base.Position).Magnitude<0.00001,"camera translation restored")
view:UpdateCamera(0.03,true); view:ResetCamera()
Check(view.shakeStarted==nil,"camera interruption clears shake")
for index=1,Config.HitEffectPoolSize+5 do
	view:Burst("A",R.Vector3.zero,R.Vector3.zAxis,false,index/100)
end
Check(#view.pool==Config.HitEffectPoolSize,"bounded effect pool reuses oldest")
view:UpgradeBurst("A")
Check(view.pool[1].final,"third hit upgrades existing burst")
view:UpdateEffects(0.2)
for _,effect in view.pool do
	for _,part in effect.parts do Check(not part.CanCollide and not part.CanTouch and not part.CanQuery,"visuals do not affect queries") end
end
view:UpdateEffects(1)
for _,effect in view.pool do Check(not effect.active,"effect lifetime expires") end
view:Burst("Far",R.Vector3.new(1000,0,0),R.Vector3.zAxis,false,2)
Check(not view.pool[1].active,"distant effect skipped")
view:Clear()
Check(#view.pool==0,"owner clears pool")
print(string.format("PASS: %d hit feedback assertions (production rules and poses; service boundary replaced)",checks))
