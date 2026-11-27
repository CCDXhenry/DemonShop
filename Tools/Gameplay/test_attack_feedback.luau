-- 提取正式客户端和服务端受击方法，验证预测、确认、取消及服务端拒绝分支
local R=require("@lune/roblox")
local B=require("./AttackFeedbackBoundary")
local Rules=require("./HitFeedbackRules")
local Client=require("./AttackFeedbackClient")
local Server=require("./AttackFeedbackServer")
local GameData=require("./GameData")
local checks=0
local function Check(value,message) assert(value,message); checks+=1 end
local Protocol=require("./VisualProtocol")
Check(Protocol.Validate({action="Attack",attackSequence=1}),"positive integer attack sequence accepted")
Check(Protocol.Validate({action="Attack"}),"optional sequence preserves compatibility")
Check(Protocol.Validate({action="Attack",targets={"A","B"},attackPose=R.CFrame.new(100,5,-200)}),"attack targets and world attackPose accepted")
local tooManyTargets = {}
for i = 1, 33 do tooManyTargets[i] = "T" .. tostring(i) end
Check(not Protocol.Validate({action="Attack",targets=tooManyTargets}),"more than 32 attack targets rejected")
Check(not Protocol.Validate({action="Attack",targets={123}}),"non-string attack target rejected")
Check(not Protocol.Validate({action="Attack",targets={""}}),"empty attack target rejected")
Check(not Protocol.Validate({action="Attack",attackPose=R.CFrame.new(0/0,0,0)}),"NaN attackPose rejected")
Check(Protocol.Validate({action="PersonalUpgrade",category="weapon",expectedNextLevel=6}),"valid upper weapon tier is accepted")
Check(not Protocol.Validate({action="PersonalUpgrade",category="moveSpeed",expectedNextLevel=6}),"tier is bounded by category")
Check(not Protocol.Validate({action="PersonalUpgrade",category="unknown",expectedNextLevel=2}),"unknown upgrade category is rejected")
Check(not Protocol.Validate({action="PersonalUpgrade",category="moveSpeed",expectedNextLevel=math.huge}),"non-finite tier is rejected")
Check(Protocol.Validate({action="Sprint",sprint=false}),"sprint release is accepted")
Check(not Protocol.Validate({action="Sprint",sprint=1}),"non-boolean sprint intent is rejected")
for _,sequence in {0,-1,1.5,math.huge,0/0,1e16,"1"} do
	Check(not Protocol.Validate({action="Attack",attackSequence=sequence}),"invalid attack sequence rejected")
end
local world=R.Instance.new("Folder")
local function Body(name,position)
	local model=R.Instance.new("Model"); model.Name=name; model.Parent=world
	local root=R.Instance.new("Part"); root.Name="HumanoidRootPart"; root.CFrame=R.CFrame.new(position); root.Position=position; root.Parent=model; model.PrimaryPart=root
	local torso=R.Instance.new("Part"); torso.Name="UpperTorso"; torso.CFrame=root.CFrame; torso.Position=position; torso.Parent=model
	return model
end
local character=Body("Character",R.Vector3.zero)
local humanoid=R.Instance.new("Humanoid"); humanoid.Parent=character; humanoid.Health=100
local tool=R.Instance.new("Tool"); tool.Name="W01_RustyPan"; tool.Parent=character
B.player.Character=character
local item={id="A",model=Body("WhiteNPC",R.Vector3.new(0,0,-4)),kind="Body",location="Street",hits=0,version=1}
local calls={pose=0,burst=0,stop=0,shake=0,upgrade=0,remove=0}
local client=setmetatable({hitState=Rules.New(),items={A=item},lastAttack=10,attackSequence=1}, {__index=Client})
client.bodies={AcceptNotice=function() return true end,Hit=function() return false end,Reject=function() end,GetVisualPart=function() return item.model.PrimaryPart end,pureModel=false}
local carriedBody = {kind="Body"}
local clientHeld = carriedBody
function client:Held() return clientHeld end
function client:ShoulderOccupied() return clientHeld ~= nil and clientHeld.kind ~= "Body" end
client.characterView={HitStop=function() calls.stop+=1 end}
client.hitView={ResetCamera=function() end,Apply=function() end,Play=function() calls.pose+=1 end,
	Burst=function() calls.burst+=1 end,Shake=function() calls.shake+=1 end,Remove=function() calls.remove+=1 end,
	UpgradeBurst=function() calls.upgrade+=1 end}
Rules.Begin(client.hitState,1,"A",10.16,12)
client:UpdateHits(10.15)
Check(calls.burst==0,"no early hit")
B.now=10.16; client:UpdateHits(B.now)
Check(calls.pose==1 and calls.burst==1 and calls.stop==1 and calls.shake==1,"local frontloaded response")
local notice={id="A",version=2,hits=1,started=10.16,direction=R.Vector3.zAxis,position=R.Vector3.zero,actor=1,attackSequence=1}
Rules.Result(client.hitState,1,true)
client:OnHit(notice); client:OnHit(notice)
Check(calls.pose==1 and calls.burst==1 and calls.shake==1,"confirmation and duplicate never replay")
notice=table.clone(notice); notice.actor=2; notice.version=3; notice.hits=2
client:OnHit(notice)
Check(calls.pose==2 and calls.burst==2 and calls.shake==1,"other actor animates target only")
notice.version=2; client:OnHit(notice)
Check(calls.burst==2,"out of order ignored")
notice.version=4; notice.started=8; client:OnHit(notice)
Check(calls.burst==2,"expired observer event ignored")
B.now=10.9
notice.actor=0; notice.version=4; notice.started=10.16
client:OnHit(notice)
Check(B.healthHits[#B.healthHits].version==4 and calls.burst==2,"brute damage updates health beyond the pose replay window")
Rules.Begin(client.hitState,2,"A",11,13); client.attackSequence=2
Rules.Result(client.hitState,2,false)
client:UpdateHits(11)
Check(calls.burst==2,"miss result cancels prediction")
Rules.Begin(client.hitState,3,"A",11,13); client.attackSequence=3; client.lastAttack=11; item.hits=2
B.now=11; client:UpdateHits(11)
notice={id="A",version=5,hits=3,started=11,direction=R.Vector3.zAxis,position=R.Vector3.zero,actor=1,attackSequence=3}
client:OnHit(notice)
Check(calls.upgrade==1 and calls.remove>=1 and calls.burst==3,"third hit upgrades without second burst and releases pose")
Rules.Begin(client.hitState,4,"A",12,14); client.paintId="A"; client:UpdateHits(12)
Check(client.hitState.pending[4].resolved,"painting cancels waiting feedback")
client.paintId=nil

local weaponEffects = 0
local trackedPredictions = 0
local visualParts: { [string]: any } = {}
client.bodies = {
	AcceptNotice = function() return true end,
	Hit = function() return false end,
	Reject = function() end,
	TrackPrediction = function() trackedPredictions += 1 end,
	GetVisualPart = function(_, id, partName)
		if partName == "HumanoidRootPart" and visualParts[id] then
			return visualParts[id]
		end
		local targetItem = client.items[id]
		return if targetItem then targetItem.model:FindFirstChild(partName) or targetItem.model.PrimaryPart else nil
	end,
	pureModel = false,
}
client.hitView.WeaponEffect = function() weaponEffects += 1 end

local visBody = Body("WhiteVis", R.Vector3.new(0, 0, -20))
local visRoot = R.Instance.new("Part"); visRoot.Name = "HumanoidRootPart"; visRoot.CFrame = R.CFrame.new(0, 0, -5); visRoot.Position = R.Vector3.new(0, 0, -5)
visualParts["Vis"] = visRoot
client.items = { Vis = { id = "Vis", model = visBody, kind = "Body", location = "Street", hits = 0, version = 1 } }
client.attackSequence = 5
client.lastAttack = 15
B.now = 15.15
B.request = nil
Rules.Begin(client.hitState, 5, nil, 15.16, 17, true, 1)
client:UpdateHits(15.15)
Check(B.request == nil and calls.burst == 3, "deferred hit waits for windup")
B.now = 15.16
client:UpdateHits(15.16)
Check(B.request ~= nil and B.request.action == "Attack" and B.request.target == "Vis" and B.request.targets ~= nil and #B.request.targets == 1 and B.request.targets[1] == "Vis",
	"deferred single attack selects by visual position and sends targets")
Check(B.request.attackPose ~= nil and B.request.attackSequence == 5 and trackedPredictions == 1 and calls.burst == 4,
	"deferred hit includes attackPose and triggers local feedback")

tool.Name = "W03_DemonScimitar"
visualParts = {}
client.items = {
	A1 = { id = "A1", model = Body("A1", R.Vector3.new(0, 0, -2)), kind = "Body", location = "Street", hits = 0, version = 1 },
	A2 = { id = "A2", model = Body("A2", R.Vector3.new(0, 0, -3)), kind = "Body", location = "Street", hits = 0, version = 1 },
	A3 = { id = "A3", model = Body("A3", R.Vector3.new(0, 0, -4)), kind = "Body", location = "Street", hits = 0, version = 1 },
	A4 = { id = "A4", model = Body("A4", R.Vector3.new(0, 0, -5)), kind = "Body", location = "Street", hits = 0, version = 1 },
	B1 = { id = "B1", model = Body("B1", R.Vector3.new(0, 0, 3)), kind = "Body", location = "Street", hits = 0, version = 1 },
}
client.attackSequence = 6
client.lastAttack = 16
B.now = 16.16
B.request = nil
Rules.Begin(client.hitState, 6, nil, 16.16, 18, true, 3)
client:UpdateHits(16.16)
Check(weaponEffects == 1 and B.request ~= nil and B.request.targets ~= nil and #B.request.targets == 3,
	"deferred AoE plays local weapon effect and caps targets to tier limit")
Check(B.request.targets[1] == "A1" and B.request.targets[2] == "A2" and B.request.targets[3] == "A3",
	"deferred AoE picks nearest three targets inside cone")
local burstBeforeAoeConfirm = calls.burst
local stopBeforeAoeConfirm = calls.stop
for _, targetId in { "A1", "A2", "A3" } do
	client:OnHit({
		id = targetId,
		version = 2,
		hits = 3,
		hp = 0,
		maxHp = 30,
		started = 16.16,
		direction = R.Vector3.zAxis,
		position = R.Vector3.zero,
		actor = 1,
		attackSequence = 6,
	})
end
Check(calls.burst == burstBeforeAoeConfirm, "multi-target server confirmation never replays burst")
Check(calls.stop == stopBeforeAoeConfirm + 1, "multi-stun plays final hit feedback once")

tool.Name = "W01_RustyPan"
client.items = { A = item }

local Config=require("./GameConfig")
local server=setmetatable({players={[B.player]={lastAttack=0,levels={weapon=1}}},items={A=item},scope={Spawn=function(_,callback) callback() end}}, {__index=Server})
function server:Root() return character.PrimaryPart end
local serverHeld = carriedBody
function server:Held() return serverHeld end
function server:ShoulderOccupied() return serverHeld ~= nil and serverHeld.kind ~= "Body" end
function server:Near() return false end
function server:Tell() end
function server:Changed() end
item.hits=0; item.version=1; B.now=20
server:Attack(B.player,{target="A",version=1,attackSequence=10})
Check(B.hits==1 and B.notices[#B.notices].hit==true,"accepted attack returns success even when Near would reject")
local hit=B.broadcasts[#B.broadcasts]
Check(hit.kind=="Hit" and hit.attackSequence==10 and hit.version==2 and hit.hits==1 and hit.position~=nil,"authoritative hit payload")
B.now=20.2; server:Attack(B.player,{target="A",version=2,attackSequence=11})
Check(B.hits==1 and B.notices[#B.notices].hit==false,"cooldown rejection returns miss")
-- 冷却抖动宽限内放行，且背对目标不再拒伤
item.model.PrimaryPart.Position=R.Vector3.new(0,0,4)
B.now=20+Config.AttackCooldown-Config.AttackCooldownTolerance+0.01
server:Attack(B.player,{target="A",version=2,attackSequence=15})
Check(B.hits==2 and B.notices[#B.notices].hit==true,"jitter within cooldown tolerance and turned facing still accepted")
item.model.PrimaryPart.Position=R.Vector3.new(0,0,-4)
B.now=22; server:Attack(B.player,{target="A",version=1,attackSequence=12})
Check(B.hits==3 and B.notices[#B.notices].hit==true,"stale target version accepted without version gate")
B.now=23; server:Attack(B.player,{attackSequence=13})
Check(B.hits==3 and not B.notices[#B.notices].hit,"empty swing returns miss")
item.hits=0; item.hp=30
item.model.PrimaryPart.Position=R.Vector3.new(0,0,-(7 + Config.AttackServerRangeBuffer - 1))
B.now=24; server:Attack(B.player,{targets={"A"},attackSequence=14})
Check(B.hits==4 and B.notices[#B.notices].hit==true,"target within range + AttackServerRangeBuffer accepted")
item.model.PrimaryPart.Position=R.Vector3.new(0,0,-(7 + Config.AttackServerRangeBuffer + 1))
B.now=25; server:Attack(B.player,{targets={"A"},attackSequence=15})
Check(B.hits==4 and not B.notices[#B.notices].hit,"target beyond range + AttackServerRangeBuffer rejected")

local record = server.players[B.player]
server.runtime = world
local function Citizen(id, position)
	return {id=id, model=Body(id,position), kind="Body", location="Street", hits=0, hp=30, version=1}
end
local function Swing(level, request)
	record.levels.weapon = level
	tool.Name = GameData.GetWeaponByLevel(level).model
	B.now += 1
	server:Attack(B.player, request or {})
end
local target = Citizen("Target", R.Vector3.new(0,0,-4))
server.items={Target=target}
Swing(2, {targets={"Target"}})
Check(target.hp==15 and target.hits<3,"W02 first hit removes half HP")
Swing(2, {targets={"Target"}})
Check(target.hp==0 and target.hits==3,"W02 second hit stuns")
local a = Citizen("A", R.Vector3.new(0,0,-3))
local b = Citizen("B", R.Vector3.new(0,0,-4))
local c = Citizen("C", R.Vector3.new(0,0,-5))
local distant = Citizen("D", R.Vector3.new(0,0,-6))
local nonStreet = Citizen("Pool", R.Vector3.new(0,0,-2))
nonStreet.location = "Pool"
server.items={A=a,B=b,C=c,D=distant,Pool=nonStreet}
Swing(3, {targets={"Pool","A","B","A","C","D"}, attackSequence=20})
Check(a.hp==0 and b.hp==0 and c.hp==0 and distant.hp==30 and nonStreet.hp==30,
	"W03 skips non-street, deduplicates, and caps hits to tier.targets")
local seqCount = 0
for index = #B.broadcasts - 2, #B.broadcasts do
	if B.broadcasts[index] and B.broadcasts[index].kind == "Hit" and B.broadcasts[index].attackSequence == 20 then
		seqCount += 1
	end
end
Check(seqCount == 3, "multi-target Hit broadcasts carry attackSequence for every hit target")
local pull = Citizen("Pull", R.Vector3.new(0,0,10))
server.items={Pull=pull}
Swing(6, {targets={"Pull"}, attackPose=R.CFrame.new(0,0,0)})
Check(pull.hp==0 and B.hitTravel==7 and B.hitDirection.Z==-1,"W06 stuns and pulls toward the attacker with a 3-stud stopping distance")
Check(B.attackerPosition==R.Vector3.zero,"W06 passes the attacker position independently of its reversed impulse")
record.levels.weapon = 1
B.now += 1
server:Attack(B.player,{targets={"Target"}})
Check(B.notices[#B.notices].hit==false,"mismatched weapon cannot attack even while equipped")
for level, limit in {[4]=8, [5]=20, [6]=30} do
	server.items={}
	local ids = {}
	for index=1,limit+2 do
		local id = tostring(index)
		server.items[id] = Citizen(id,R.Vector3.new(0,0,-(2+index/10)))
		ids[index] = id
	end
	Swing(level, {targets=ids})
	Check(server.items[tostring(limit)].hp==0 and server.items[tostring(limit+1)].hp==30,
		"target limit respected at tier " .. level)
end
local swingTool = character:FindFirstChildWhichIsA("Tool")
local before = B.hits
swingTool.Parent = nil
B.now += 2
server:Attack(B.player,{targets={"1"}, attackSequence=16})
Check(B.hits==before and not B.notices[#B.notices].hit,"unequipped weapon rejects attack")
swingTool.Parent = character
serverHeld = {kind="Potion"}
B.now += 2
server:Attack(B.player,{targets={"1"}, attackSequence=17})
Check(B.hits==before and not B.notices[#B.notices].hit,"non-body shoulder load still blocks attacks")
serverHeld = carriedBody
server.paint = {player = B.player}
B.now += 2
server:Attack(B.player,{targets={"1"}, attackSequence=18})
Check(B.hits==before and not B.notices[#B.notices].hit,"painting still blocks attacks")
server.paint = nil
local w1Cooldown = GameData.GetWeaponByLevel(1).attackCooldown
Check(w1Cooldown > 0, "W01 attackCooldown configured in GameData")
local broadcastSwing = nil
for _, notice in B.broadcasts do
	if notice.kind == "Swing" then broadcastSwing = notice end
end
Check(broadcastSwing ~= nil and typeof(broadcastSwing.weaponLevel) == "number" and broadcastSwing.weaponLevel >= 1, "Swing broadcast includes weaponLevel")
local top = {id="Top", version=7, kind="Body", stage="Painted"}
local stack = {top, carriedBody}
function server:Carried() return stack end
function server:Restack() end
record.lastThrow = 0
local throw = {target=top.id,version=top.version,direction=R.Vector3.zAxis}
server:Throw(B.player,throw)
Check(B.tossed==nil and record.lastThrow==0,"equipped weapon blocks throw without spending cooldown")
swingTool.Parent = nil
server:Throw(B.player,throw)
Check(B.tossed==top and B.restoreTool==false and record.lastThrow==B.now,"holstering allows throwing the top body")
table.remove(stack, 2)
B.tossed = nil
B.now += 2
server:Throw(B.player,throw)
Check(B.tossed==top and B.restoreTool==false,"last manual throw leaves weapon holstered")
B.request = nil
local ThrowController = require("./ManualThrowController")
local function signal()
	local listener = nil
	return {
		Connect = function(_, callback)
			listener = callback
			return {Disconnect = function() listener = nil end}
		end,
		Fire = function(_, ...)
			if listener then listener(...) end
		end,
	}
end
local equipped = false
local hidden = 0
local equippedSignal = signal()
local inputSignal = signal()
B.player.Character = {ChildAdded = equippedSignal}
local mouse = {
	UserInputType = R.Enum.UserInputType.MouseButton1,
	UserInputState = R.Enum.UserInputState.Begin,
	GetPropertyChangedSignal = function() return inputSignal end,
}
local controller = setmetatable({
	host = {TopBody = function() return top end, CanAim = function() return not equipped end},
	preview = {Hide = function() hidden += 1 end},
	AimDirection = function() return R.Vector3.zAxis end,
	nextThrow = 0,
}, ThrowController)
Check(controller:OnMouseBegan(mouse) and controller.input == mouse, "holstered weapon permits starting an aim")
equipped = true
equippedSignal:Fire(swingTool)
equipped = false
Check(controller.input == nil and hidden == 1, "weapon equip cancels aim even when holstered before the next frame")
controller:OnInputEnded(mouse)
Check(B.request == nil, "releasing a cancelled aim never sends a throw")
controller:OnMouseBegan(mouse)
equipped = true
controller:OnInputEnded(mouse)
Check(B.request == nil, "release checks current equipment even before equip event is processed")
equipped = false
controller:OnMouseBegan(mouse)
controller:OnInputEnded(mouse)
Check(B.request and B.request.action == "Throw" and B.request.target == top.id, "new aim works after holstering again")
print(string.format("PASS: %d attack feedback flow assertions (production methods; network/clock/physics mocked)",checks))
