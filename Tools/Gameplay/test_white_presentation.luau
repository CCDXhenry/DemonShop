-- 正式白膜及独立 AnimationConstraint 副本的关节、流送、交接及热调回归。
local R = require("@lune/roblox")
local fs = require("@lune/fs")
local B = require("./Boundary")
local Adapter = require("./JointAdapter")
local Manager = require("./WhiteBodyPresentationManager")
local Tuning = require("./PresentationTuning")
local template = R.deserializeModel(fs.readFile("Assets/Models/GameModels.rbxm"))[1].Characters["WhiteR15-People"]
local count = 0
local function check(value, message)
	assert(value,message)
	count += 1
end
local function size(map)
	local n=0
	for _ in map do n+=1 end
	return n
end
local function rig(animation)
	local model=template:Clone()
	for _,node in model:GetDescendants() do
		if node:IsA("BasePart") then node.LocalTransparencyModifier=0 end
		if node:IsA("Motor6D") then
			node.Transform=R.CFrame.identity
			if animation then
				local a,b=R.Instance.new("Attachment"),R.Instance.new("Attachment")
				a.CFrame,a.Parent=node.C0,node.Part0
				b.CFrame,b.Parent=node.C1,node.Part1
				local drive=R.Instance.new("AnimationConstraint")
				drive.Name,drive.Attachment0,drive.Attachment1="Drive"..node.Part1.Name,a,b
				drive.Enabled,drive.IsKinematic,drive.Transform,drive.Parent=true,true,R.CFrame.identity,node.Parent
				node:Destroy()
			end
		end
	end
	model.Head.LocalTransparencyModifier=.375
	model.Parent=B.world
	return model
end
local tableView={model=nil}
function tableView:Attach(_,model) self.model=model end
function tableView:Clear() self.model=nil end
local hit={Remove=function() end,Sample=function() return R.CFrame.Angles(.1,0,0) end}
local routed={}
local detachCount=0
local m=Manager.new(tableView,hit,function(id,model)
	routed[id]=model
	if not model then detachCount+=1 end
end)
local source=rig(false)
local item={id="body",kind="Body",location="Street",version=1,hits=0,model=source}
local function noClone()
	for _,child in B.world:GetChildren() do if child.Name=="LocalWhiteBody" then return false end end
	return true
end
local function fallback(model,cause)
	item.model=model
	m:Bind(item)
	check(not m.views.body.visualModel and string.find(m.views.body.diagnostic,cause,1,true),"expected "..cause)
	check(model.Head.LocalTransparencyModifier==.375 and noClone(),"failed bind must restore source")
	m:Unbind("body")
	model:Destroy()
end
for _,animation in {false,true} do
	local model=rig(animation)
	local map=Adapter.Map(model)
	check(size(map)==15 and map.Root.parent==model.HumanoidRootPart and map.Root.child==model.LowerTorso,"15 directed semantic edges")
	for name,joint in map do
		check((name=="Root" or joint.limit~=nil) and joint.drive.ClassName==(if animation then "AnimationConstraint" else "Motor6D"),name)
	end
	item.model=model
	m:Bind(item)
	local v=m.views.body
	check(v.mode=="Street" and m:GetPaintModel("body")==v.visualModel and m:GetAuthorityModel("body")==model,"independent display")
	m:Step(0,1/60)
	local joint=v.jointMap.Waist
	check(joint.submissions==1 and not pcall(Adapter.Commit,joint,R.CFrame.identity,nil,m.step),"reject duplicate submission")
	Adapter.Write(joint,R.CFrame.Angles(0,.4,0))
	local external=Adapter.Read(joint)
	m:Restore()
	check(Adapter.Read(joint)==external,"restore preserves replacement base")
	check(v.visualModel.Head.ClassName==model.Head.ClassName and v.visualModel.Head:GetAttribute("Paintable")==true,"mesh and paint identity")
	check(not v.visualModel.Head.CanCollide and not v.visualModel.Head.CanQuery and not v.visualModel.Head.CanTouch,"no collision/query")
	check(not v.visualModel:FindFirstChildWhichIsA("Animator",true),"no clone tracks")
	m:Unbind("body")
	model:Destroy()
end
local bad=rig(false)
Adapter.Map(bad).Root.drive:Destroy()
fallback(bad,"missing semantic joint Root")
bad=rig(true)
Adapter.Map(bad).Waist.drive.Attachment0.Parent=nil
fallback(bad,"attachment")
bad=rig(false)
Adapter.Map(bad).Neck.drive.Name=Adapter.Map(bad).Waist.drive.Name
fallback(bad,"duplicate drive name")
item.model=source
m:Bind(item)
local first=m.views.body
local stale=B.signal(source,"added").last
m:Bind(item)
check(m.views.body==first,"idempotent bind")
local prediction={expires=10,played=false,resolved=false}
m:TrackPrediction("body",12,prediction)
local replacement=rig(false)
item.model=replacement
m:Bind(item)
check(source.Head.LocalTransparencyModifier==.375 and replacement.Head.LocalTransparencyModifier==1,"replacement restored former source")
check(prediction.resolved,"windup on replaced generation cancelled")
stale(source.Head)
check(not m.views.body.dirty,"stale generation callback ignored")
replacement.Parent=nil
m:Step(1,1/60)
check(noClone() and routed.body==nil and replacement.Head.LocalTransparencyModifier==.375,"stream out")
replacement.Parent=B.world
m:Step(2,1/60)
check(m.views.body.bindGeneration>first.bindGeneration and m.views.body.visualModel~=nil,"stream back in")
m:SetEnabled(false)
check(noClone() and routed.body==replacement,"disabled path restored")
m:SetEnabled(true)
check(m:GetVisualPart("body","Head")~=replacement.Head,"enabled path rebound")
item.location="Table"
m:UpdateState({body=item})
check(m.views.body.mode=="Table" and m:GetPaintModel("body")==tableView.model,"one table display")
local detachBefore=detachCount
item.location="Carried"
m:UpdateState({body=item})
check(tableView.model==nil and m:GetPaintModel("body")==replacement and detachBefore==detachCount,"table departure retains resident paint binding")
item.location="Street"
m:Unbind("body")
for i=1,50 do
	m:Bind(item)
	local connections=table.clone(m.views.body.cleanup)
	m:Unbind("body")
	m:Unbind("body")
	check(#connections==3 and not connections[1].Connected and not connections[2].Connected and not connections[3].Connected,"disconnected "..i)
	check(noClone() and replacement.Head.LocalTransparencyModifier==.375 and not next(m.views),"restored "..i)
end
m:Bind(item)
m:Destroy()
m:Bind(item)
check(noClone() and not next(m.views) and m:GetDebugStats().runServiceConnections==0 and hit.managed==nil,"terminal destroy")
local defaults=Tuning.GetEffectiveConfig()
check(Tuning.ApplyOverrides({Contact={WaistDegrees=12}},1),"valid revision")
check(Tuning.GetEffectiveConfig()==defaults,"pending until simulation")
for _,patch in {{Hit={FrequencyHz=0/0}},{Hit={FrequencyHz=math.huge}},{Unknown={}},{Hit={Typo=1}},{LOD={NearStuds=500}},{Carry={LiftSeconds="bad"}},{Hit={DampingRatio=8}}} do
	check(not Tuning.ApplyOverrides(patch,2),"reject invalid patch")
end
for _,revision in {0,1,1.5,math.huge,0/0} do check(not Tuning.ApplyOverrides({},revision),"invalid revision") end
Tuning.Commit()
local cfg,rev=Tuning.GetEffectiveConfig()
check(rev==1 and cfg.Contact.WaistDegrees==12 and cfg.Hit.FrequencyHz==defaults.Hit.FrequencyHz,"atomic update retained valid values")
Tuning.Reset()
Tuning.Commit()
check(Tuning.GetEffectiveConfig()==defaults,"identical frozen defaults")
local Spring=require("./Spring")
local Contact=require("./SoftContact")
local Impact=require("./ImpactReaction")
local Mixer=require("./PoseMixer")
local V,F=R.Vector3,R.CFrame
for _,z in {0.75,1,1.6} do
	local reference=Spring.new(4,z,10,100)
	reference:Impulse(V.xAxis*10)
	local expected=reference:Step(0.2)
	for _,fps in {15,30,60,120} do
		local s=Spring.new(4,z,10,100)
		s:Impulse(V.xAxis*10)
		local peak,settled=0,0
		for i=1,fps*2 do
			local p=s:Step(1/fps)
			peak=math.max(peak,p.X)
			if i==math.round(fps*0.2) then check((p-expected).Magnitude<0.00002,"analytic state at common time") end
			if not s.Sleeping then settled=i/fps end
		end
		check(s.Sleeping and s.Position==V.zero,"rest at all rates")
		print(string.format("SPRING fps=%d z=%.2f peak=%.6f sleepBy=%.4f errorAt2s=%.7f",fps,z,peak,settled+1/fps,s.Position.Magnitude))
	end
end
local s=Spring.new(5,0.8,0.3,8)
s:Impulse(V.xAxis*5);s:Step(0.015)
local velocity=s.Velocity
s.Frequency=6
s:Impulse(V.yAxis*2)
check((s.Velocity-velocity-V.yAxis*2).Magnitude<0.00001,"retune and second impulse retain momentum")
s:Impulse(V.one*1000);check(s.Velocity.Magnitude<=8.00001,"velocity cap")
local before=s.Position
s:Impulse(V.new(0/0,0,0))
for _,dt in {0,-1,0/0,math.huge} do check(s:Step(dt)==before,"invalid dt ignored") end
s.Target=V.one*100
for _,dt in {1/15,3,10000} do check(s:Step(dt).Magnitude<0.30001,"long frame bounded") end
s.Target=V.new(math.huge,0,0);s.Frequency=0/0;s.DampingRatio=math.huge
check(s:Step(1).Magnitude<0.30001,"invalid parameters contained")

local model=rig(false)
local map=Adapter.Map(model)
local cfg=Tuning.GetEffectiveConfig()
local root=model.PrimaryPart
local torso=model.UpperTorso
torso.Position=V.zero;torso.CFrame=F.identity;torso.AssemblyLinearVelocity=V.zero
root.CFrame=F.identity
local body={id="contact",root=root,torso=torso,previous=V.zero}
local playerModel=R.Instance.new("Model")
local part=R.Instance.new("Part");part.Parent=playerModel;part.Size=V.new(2,2,1)
part.Position=V.new(-1.2,0,0);part.AssemblyLinearVelocity=V.xAxis*16
local actor={part=part,radius=0.9,previous=V.new(-3,0,0)}
local states={}
local function contactStep(actors,dt) return Contact.Update({body},actors,states,dt,cfg) end
check(contactStep({actor},1/60)==1 and states.contact.phase=="Enter","swept enter")
local contactState=states.contact
check(contactState.springs.LeftShoulder.Position.Magnitude>0 and contactState.springs.Waist.Position.Magnitude==0,"contact-side shoulder leads waist")
actor.previous=part.Position
for i=1,180 do contactStep({actor},1/60);check(contactState.phase=="Stay","no repeated enter on pressure") end
check(contactState.springs.Waist.Velocity.Magnitude<0.001,"sustained pressure injects no repeated impulse")
local hold=contactState.springs.Waist.Position
contactStep({},1/60)
check(contactState.phase=="Exit" and contactState.springs.Waist.Position.Magnitude>0 and contactState.springs.Waist.Position.Magnitude<hold.Magnitude,"release has residual")
for i=1,90 do contactStep({},1/60) end
check(not states.contact,"sleep drops contact state")
check(Contact.Sweep(V.xAxis*-4,V.xAxis*4,V.one)==V.xAxis and Contact.Sweep(V.new(-4,4,0),V.new(4,4,0),V.one)==nil,"fast crossing and miss")
local actors={}
for i=1,14 do local clone=part:Clone();clone.Parent=playerModel;clone.Position=part.Position;clone.AssemblyLinearVelocity=V.xAxis*60
	table.insert(actors,{part=clone,radius=0.9,previous=V.new(-3,0,0)}) end
local bodies={}
for i=1,7 do table.insert(bodies,{id=tostring(i),root=root,torso=torso,previous=V.zero}) end
check(Contact.Update(bodies,actors,states,1/60,cfg)==12,"global query cap")
for _,c in states do check(size(c.touches)<=3 and c.springs.Waist.Position.Magnitude<=math.rad(cfg.Contact.StrongDegrees)+0.0001,"per body budget and saturation") end

local pulses={}
local function input(key,degree,confirm,canCreate,dir)
	Impact.Input(pulses,key,map,F.identity,V.yAxis,dir or V.zAxis,degree,0,confirm,canCreate,cfg)
end
input("1/5",1,false,true)
local r=Impact.Step(pulses,1/60,cfg)
check(r.Waist.Magnitude>0 and r.RightWrist.Magnitude==0,"torso leads wrists in first simulation step")
local p=pulses["1/5"];local residual=p.channels[1].Velocity
input("1/5",2,true,false,V.xAxis)
check(p.confirmed and p.channels[1].Velocity==residual and size(pulses)==1,"authoritative correction preserves pulse")
input("2/5",1,true,true);input("1/6",3,false,true)
Impact.Reject(pulses,"1/5");Impact.Reject(pulses,"1/6")
Impact.Step(pulses,0.06,cfg)
check(p.gain==1 and pulses["2/5"].gain==1 and pulses["1/6"].gain<1,"reject isolated attacker/sequence")
local offsets={}
local mask={}
local cloneMap=Adapter.Map(model:Clone())
local c={touches={},phase="Stay",springs={Waist=Spring.new(5,1,1,10)}}
c.springs.Waist:Reset(V.zAxis*0.2)
Mixer.Commit(cloneMap,map,mask,F.identity,c,{Waist=V.yAxis*0.3},V.xAxis*0.06,nil,1,offsets,1/120,10)
local joint=cloneMap.Waist
local _,angle=(joint.drive.Transform*joint.base:Inverse()):ToAxisAngle()
check(angle>0 and angle<=10/120+0.0001 and cloneMap.Root.drive.Transform.Position.Magnitude>0,"mixed contact and impact bounded speed")
map.Waist.drive.Enabled=false
Mixer.Commit(cloneMap,map,mask,F.identity,c,r,V.zero,nil,2,offsets,1/60,22)
check(mask.Waist and joint.submissions==0 and offsets.Waist==nil,"physical takeover excludes drive")
map.Waist.drive.Enabled=true
local managed=Manager.new(tableView,hit,function() end)
item.model,item.location,item.hits,item.version=model,"Street",0,5
managed:Bind(item)
local function mh(seq,version,h,at,replay)
	return managed:Hit("body",1,seq,version,h,V.zAxis,V.yAxis,at,true,replay)
end
mh(1,4,1,0,true);check(not next(managed.views.body.impacts),"stale version")
mh(2,5,1,0,true);check(size(managed.views.body.impacts)==1,"delta before hit accepted")
managed:SetLayer("ImpactReaction",false);check(not next(managed.views.body.impacts),"bypass releases pulses")
managed:SetLayer("ImpactReaction",true)
check(managed:AcceptNotice("body",5,1,0) and not managed:AcceptNotice("body",4,1,0),"accept equal state version, reject stale notice before deduplication")
mh(3,6,3,0,true);mh(4,7,2,0,true);check(size(managed.views.body.impacts)==1,"final prevents reentry")
item.hits,item.version=3,6;model:SetAttribute("PhysicsMode","Loose")
managed:Bind(item);check(managed.views.body.mode=="Authority" and not next(managed.views.body.impacts),"third hit handoff")
check(managed:AcceptNotice("body",6,3,0) and not managed:AcceptNotice("body",6,2,0),"Down before Hit permits final feedback only")
item.location="Carried"; managed:Bind(item)
check(not managed:AcceptNotice("body",6,3,0),"carried excludes stale final")
item.location,item.hits="Street",0
item.model=rig(false);managed:Bind(item)
check(not managed:AcceptNotice("body",7,2,-0.1),"old timestamp cannot advance new rig's notice version")
managed:Destroy();item.model:Destroy();model:Destroy();playerModel:Destroy()
local Feedback=require("./FeedbackClient")
local Rules=require("./HitFeedbackRules")
local function noticeFixture()
	local fx={bursts=0,upgrades=0,Remove=function() end}
	function fx:Burst() self.bursts+=1 end
	function fx:UpgradeBurst() self.upgrades+=1 end
	return setmetatable({bodies=Manager.new(tableView,fx,function() end),items={},waitingHits={},hitView=fx,
		potionShelf={Apply=function() end},
		hitState=Rules.New(),presentation={SetFlipped=function() end},characterView={carriers={}},attackSequence=5,HitFeedback=function() end,Held=function() return nil end},
		{__index=Feedback})
end
local function hitNotice(h)
	return {kind="Hit",id="body",version=2,hits=h,started=0,actor=1,attackSequence=5,position=V.yAxis,direction=V.zAxis}
end
local noticeRig=rig(false)
local function snapshot(h,rev)
	local fall=if h==3 then {started=0,target=F.new(1,2,3),velocity=V.xAxis*3} else nil
	return {revision=rev,shelfItems={},items={{id="body",kind="Body",location="Street",version=rev,hits=h,model=noticeRig,fall=fall}}}
end
for _,order in {"HRD","HDR","RDH","RHD","DHR","DRH"} do
	for _,level in {1,3} do
		local client=noticeFixture()
		client:OnNotice({kind="State",snapshot=snapshot(level-1,1)})
		Rules.Begin(client.hitState,5,"body",0,2)
		local prediction=client.hitState.pending[5]
		client.bodies:TrackPrediction("body",5,prediction)
		Rules.TakePrediction(client.hitState,5,0)
		client.bodies:Hit("body",1,5,2,level,V.xAxis,V.zero,0,false,true)
		local before=client.bodies.views.body
		local display=before.visualModel
		local pulse=before.impacts["1/5"]
		check(before.mode=="Street" and not before.fall,"prediction cannot start a fall "..order)
		for action in order:gmatch(".") do
			if action=="H" then client:OnNotice(hitNotice(level))
			elseif action=="R" then client:OnNotice({kind="AttackResult",attackSequence=5,hit=true})
			else client:OnNotice({kind="Delta",snapshot=snapshot(level,2)}) end
		end
		client:OnNotice(hitNotice(level))
		check(client.hitState.versions.body==2 and client.hitView.bursts==0,"confirmation deduplicated "..order)
		local view=client.bodies.views.body
		if level==1 then check(size(view.impacts)==1 and view.impacts["1/5"]==pulse and pulse.confirmed,"same confirmed spring "..order)
		else
			check(view.mode=="Ground" and view.visualModel==display and view==before and not next(view.impacts) and client.hitView.upgrades==1,"one ground handoff "..order)
			check(view.fall and not view.fall.active and #view.fall.sockets==0,"distant fall opens no sockets")
			client.bodies:Bind(snapshot(3,2).items[1])
			check(client.bodies.views.body.fall==view.fall,"duplicate packet preserves solver")
			local replacement=rig(false)
			local changed=snapshot(3,3).items[1];changed.model=replacement
			client.bodies:Bind(changed)
			check(client.bodies.views.body.bindGeneration>view.bindGeneration and client.bodies.views.body.fall~=view.fall and display.Parent==nil,"replacement has fresh pose cache")
			client.bodies:Unbind("body");replacement:Destroy()
		end
		client.bodies:Destroy()
	end
end
local client=noticeFixture()
local remote=hitNotice(1);remote.actor=2
client:OnNotice(remote)
check(#client.waitingHits==1,"hit before first item")
client:OnNotice({kind="State",snapshot=snapshot(1,2)})
check(#client.waitingHits==0 and client.bodies.views.body.impacts["2/5"].confirmed,"state drains delayed remote once")
Rules.Begin(client.hitState,5,"body",0,2)
client.bodies:Hit("body",1,5,3,2,V.xAxis,V.zero,0,false,true)
client:OnNotice({kind="AttackResult",attackSequence=5,hit=false})
check(client.bodies.views.body.impacts["1/5"].rejected and not client.bodies.views.body.impacts["2/5"].rejected,"real notice rejects only local input")
client:OnNotice({kind="State",snapshot=snapshot(2,3)})
Rules.Begin(client.hitState,6,"body",0,2)
client.bodies:Hit("body",1,6,4,3,V.xAxis,V.zero,0,false,true)
client:OnNotice({kind="AttackResult",attackSequence=6,hit=false})
check(client.bodies.views.body.mode=="Street" and not client.bodies.views.body.fall and client.bodies.views.body.impacts["1/6"].rejected,"rejected final leaves no physics or sleep cache")
client.bodies:Destroy();noticeRig:Destroy()
local shoulder=rig(false)
local shoulders=Manager.new(tableView,{Remove=function() end,Sample=function() return F.identity end},function() end)
local down={id="shoulder",kind="Body",location="Street",version=1,hits=3,model=shoulder,fall={target=F.new(0,1,0),started=0,velocity=V.zero}}
shoulders:Bind(down)
local fallen=shoulders.views.shoulder.visualModel
check(shoulders.views.shoulder.mode=="Ground" and fallen~=nil and fallen.Parent~=nil,"fallen body has local pose")
shoulder:SetAttribute("PhysicsMode","Carried")
shoulders:Bind(down)
check(shoulders.views.shoulder.mode=="CarryHandoff" and shoulders:GetVisualModel("shoulder")==fallen,"physics-first carry retains the visible downed pose")
local carried=table.clone(down)
carried.location,carried.version,carried.fall="Carried",2,nil
shoulders:Bind(carried)
local start=fallen.PrimaryPart.CFrame
shoulder.PrimaryPart.CFrame=start+V.new(4,0,0)
shoulders:Step(.06,1/60)
check((fallen.PrimaryPart.CFrame.Position-start.Position-V.new(2,0,0)).Magnitude<1e-4,"handoff follows the moving replicated pose")
check(shoulder.Head.LocalTransparencyModifier==1 and fallen.Head.Anchored and not fallen.Head.CanCollide,"one non-colliding display during carry handoff")
shoulders:Step(.12,1/60)
check(shoulders.views.shoulder.mode=="Authority" and fallen.Parent==nil and shoulder.Head.LocalTransparencyModifier==.375,"carry handoff releases the local clone and restores visibility")
shoulders:Unbind("shoulder")
shoulder:SetAttribute("PhysicsMode",nil)
shoulders:Bind(down)
fallen=shoulders:GetVisualModel("shoulder")
local bruteCarried=table.clone(carried)
bruteCarried.location="BruteCarried"
shoulders:Bind(bruteCarried)
check(shoulders.views.shoulder.mode=="CarryHandoff","snapshot-first brute pickup blends out of the local fallen pose")
shoulder:SetAttribute("PhysicsMode","Carried")
shoulders:Bind(bruteCarried)
check(shoulders:GetVisualModel("shoulder")==fallen,"brute carry attributes preserve the handoff until it finishes")
shoulder:SetAttribute("PhysicsMode",nil)
local dropped=table.clone(down)
dropped.location,dropped.version="Ground",3
shoulders:Bind(dropped)
check(fallen.Parent==nil and shoulders.views.shoulder.mode=="Ground","newer drop cancels carry handoff")
fallen=shoulders:GetVisualModel("shoulder")
carried.version=4
shoulders:Bind(carried)
shoulder.Parent=nil
shoulders:Step(.02,1/60)
check(fallen.Parent==nil and shoulders.views.shoulder==nil and shoulder.Head.LocalTransparencyModifier==.375,"stream out cancels carry handoff")
shoulder.Parent=B.world
shoulders:Step(.03,1/60)
check(shoulders.views.shoulder.mode=="Authority" and shoulders:GetVisualModel("shoulder")==shoulder,"stream in while carried sees the current replicated pose")
shoulders:Unbind("shoulder")
shoulder:SetAttribute("MotionState","Carried")
down.location,down.hits,down.version,down.fall="Street",0,3,nil
shoulders:Bind(down)
check(shoulders.views.shoulder.mode=="Authority" and shoulders.views.shoulder.diagnostic==nil and shoulders.views.shoulder.visualModel==nil,"carried motion skips joint parse")
shoulders:Destroy();shoulder:Destroy()
local offering=rig(false)
local displayCalls=0
local altar=Manager.new(tableView,{Remove=function() end},function() displayCalls+=1 end)
local painting={id="offering",kind="Body",location="Table",version=1,hits=3,model=offering}
altar:UpdateState({offering=painting})
local paintingClone=altar:GetVisualModel("offering")
local tableGeneration=altar.views.offering.bindGeneration
local tableDisplays=displayCalls
local targetRest=offering.PrimaryPart.CFrame+V.new(-10,1,-6)
local flying=table.clone(painting)
flying.location,flying.version,flying.altarTossStarted="Altar",2,0
flying.altarToss={from=paintingClone.PrimaryPart.CFrame,rest=targetRest,started=0,flightStarts=.25,landEnds=1.52}
altar:UpdateState({offering=flying})
check(altar.views.offering.mode=="Altar" and not tableView.model and paintingClone.Parent==B.world,"table display transitions in-place to altar without destroying clone")
check(altar:GetAltarModel("offering")==paintingClone and altar.views.offering.bindGeneration==tableGeneration and displayCalls==tableDisplays,"in-place transition avoids re-cloning or re-binding rune textures")
check(offering.Head.LocalTransparencyModifier==1 and altar:IsAltarTossing("offering",.1),"authority stays hidden while client drives altar toss")
local start=paintingClone.PrimaryPart.CFrame.Position
altar:Step(.125,1/60)
check((paintingClone.PrimaryPart.CFrame.Position-start-V.yAxis*(.85*.5)).Magnitude<1e-4,"client lift phase elevates smoothly from table pose")
altar:Step(.25+.95*.5,1/60)
check(paintingClone.PrimaryPart.CFrame.Position.Y>targetRest.Position.Y+2.5 and altar:IsAltarTossing("offering",.25+.95*.5),"client flight phase follows parabolic arc above drop clearance")
altar:Step(1.20+.32*.7,1/60)
check(paintingClone.PrimaryPart.CFrame.Position.Y>=targetRest.Position.Y and altar:IsAltarTossing("offering",1.20+.32*.7),"client landing phase cushions body on altar surface")
altar:Step(1.52,1/60)
check(not altar:IsAltarTossing("offering",1.52) and (paintingClone.PrimaryPart.CFrame.Position-targetRest.Position).Magnitude<1e-4,"client toss settles cleanly at altar rest pose")
local landed=table.clone(flying)
landed.version,landed.altarToss,landed.altarTossStarted,landed.convertEnds=3,nil,nil,8
altar:UpdateState({offering=landed})
local landedVisual=altar:GetAltarModel("offering")
check(landedVisual==paintingClone and altar.views.offering.bindGeneration==tableGeneration,"landing confirmation keeps the same local altar clone for sacrifice float")
-- 其他客户端（旁观者）从肩扛或远端收到祭坛抛掷快照时，同样创建本地克隆并完整播放抛掷与落台过程
local remoteOffering=rig(false)
local observer=Manager.new(tableView,{Remove=function() end},function() end)
local shoulderToss={
	id="remote",kind="Body",location="Altar",version=1,hits=3,model=remoteOffering,
	altarTossStarted=0,
	altarToss={from=remoteOffering.PrimaryPart.CFrame,rest=targetRest,started=0,flightStarts=0,landEnds=1.27},
}
observer:UpdateState({remote=shoulderToss})
local observerClone=observer:GetAltarModel("remote")
check(observerClone~=nil and observerClone~=remoteOffering and remoteOffering.Head.LocalTransparencyModifier==1 and observer:IsAltarTossing("remote",.2),"other client creates local altar clone and hides authority immediately on toss")
observer:Step(.475,1/60)
check(observerClone.PrimaryPart.CFrame.Position.Y>targetRest.Position.Y+2.2,"other client sees the full parabolic toss arc locally")
observer:Step(1.27,1/60)
check(not observer:IsAltarTossing("remote",1.27) and (observerClone.PrimaryPart.CFrame.Position-targetRest.Position).Magnitude<1e-4,"other client settles smoothly onto altar surface")
observer:Destroy();remoteOffering:Destroy()
altar:Destroy();offering:Destroy()
local waiting=rig(false)
local waits=Manager.new(tableView,{Remove=function() end,Sample=function() return F.identity end},function() end)
local pending={id="wait",kind="Body",location="Street",version=1,hits=0,model=waiting}
waits:Bind(pending)
local kept=waits.views.wait.visualModel
local keptGeneration=waits.views.wait.bindGeneration
local saved=waiting.PrimaryPart
waiting.PrimaryPart=waiting.Head
B.signal(waiting,"root").last(saved)
pending.version=2
waits:Bind(pending)
check(waits.views.wait.visualModel==kept and waits.views.wait.bindGeneration==keptGeneration and waits.views.wait.diagnostic==nil and waits.views.wait.dirty,"missing root keeps previous view")
waiting.PrimaryPart=saved
pending.version=3
waits:Bind(pending)
check(waits.views.wait.bindGeneration>keptGeneration and waits.views.wait.visualModel~=nil and waits.views.wait.visualModel~=kept and waits.views.wait.diagnostic==nil,"root return rebinds")
waits:Destroy();waiting:Destroy()
print("PASS",count,"presentation assertions; 50 rebinds, 0 remaining clones, tracks, hidden parts or connections")
