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
function client:Held() return nil end
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
local Config=require("./GameConfig")
local nearRange=0
local server=setmetatable({players={[B.player]={lastAttack=0,levels={weapon=1}}},items={A=item},scope={Spawn=function(_,callback) callback() end}}, {__index=Server})
function server:Root() return character.PrimaryPart end
function server:Held() return nil end
function server:Near(_, _, range) nearRange=range; return true end
function server:Tell() end
function server:Changed() end
item.hits=0; item.version=1; B.now=20
server:Attack(B.player,{target="A",version=1,attackSequence=10})
Check(B.hits==1 and B.notices[#B.notices].hit==true,"accepted attack returns success")
Check(nearRange==Config.AttackServerRange and Config.AttackServerRange>Config.AttackRange,"server attack uses relaxed anti-cheat range")
local hit=B.broadcasts[#B.broadcasts]
Check(hit.kind=="Hit" and hit.attackSequence==10 and hit.version==2 and hit.hits==1 and hit.position~=nil,"authoritative hit payload")
B.now=20.2; server:Attack(B.player,{target="A",version=2,attackSequence=11})
Check(B.hits==1 and B.notices[#B.notices].hit==false,"cooldown rejection returns miss")
-- 冷却抖动宽限内放行，且前摇后背对目标不再误拒
item.model.PrimaryPart.Position=R.Vector3.new(0,0,4)
B.now=20+Config.AttackCooldown-Config.AttackCooldownTolerance+0.01
server:Attack(B.player,{target="A",version=2,attackSequence=15})
Check(B.hits==2 and B.notices[#B.notices].hit==true,"jitter within cooldown tolerance and turned facing still accepted")
item.model.PrimaryPart.Position=R.Vector3.new(0,0,-4)
B.now=22; server:Attack(B.player,{target="A",version=1,attackSequence=12})
Check(B.hits==2 and not B.notices[#B.notices].hit,"stale target version rejected")
B.now=23; server:Attack(B.player,{attackSequence=13})
Check(B.hits==2 and not B.notices[#B.notices].hit,"empty swing returns miss")
function server:Near() return false end
B.now=24; server:Attack(B.player,{target="A",version=3,attackSequence=14})
Check(B.hits==2 and not B.notices[#B.notices].hit,"out of range or wall-blocked rejected")

local record = server.players[B.player]
server.runtime = world
local ignoredOccluders
function server:Near(_, _, _, model, ignored)
	ignoredOccluders = ignored
	return model.Name ~= "Blocked"
end
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
Swing(2, {target="Target",version=1})
Check(target.hp==15 and target.hits<3,"W02 first hit removes half HP")
Swing(2, {target="Target",version=2})
Check(target.hp==0 and target.hits==3,"W02 second hit stuns")
local a = Citizen("A", R.Vector3.new(0,0,-3))
local b = Citizen("B", R.Vector3.new(0,0,-4))
local c = Citizen("C", R.Vector3.new(0,0,-5))
local distant = Citizen("D", R.Vector3.new(0,0,-6))
local behind = Citizen("Behind", R.Vector3.new(0,0,3))
local blocked = Citizen("Blocked", R.Vector3.new(0,0,-2))
server.items={A=a,B=b,C=c,D=distant,Behind=behind,Blocked=blocked}
Swing(3, {target="Behind",version=999})
Check(a.hp==0 and b.hp==0 and c.hp==0 and distant.hp==30,"W03 stuns nearest three inside its cone regardless of request target")
Check(behind.hp==30 and blocked.hp==30,"W03 excludes rear and occluded NPCs")
Swing(4)
Check(behind.hp==0 and distant.hp==0 and blocked.hp==30,"W04 hits behind and respects occlusion")
local line = Citizen("Line", R.Vector3.new(2,0,-19))
local side = Citizen("Side", R.Vector3.new(3,0,-12))
server.items={Line=line,Side=side}
Swing(5)
Check(line.hp==0 and side.hp==30,"W05 uses a width-limited line through 20 studs")
Check(ignoredOccluders==server.runtime,"penetrating attacks ignore NPC occluders but still check scene obstruction")
local pull = Citizen("Pull", R.Vector3.new(0,0,10))
server.items={Pull=pull}
Swing(6)
Check(pull.hp==0 and B.hitTravel==7 and B.hitDirection.Z==-1,"W06 stuns and pulls toward the attacker with a 3-stud stopping distance")
record.levels.weapon = 1
B.now += 1
server:Attack(B.player,{})
Check(B.notices[#B.notices].hit==false,"mismatched weapon cannot attack even while equipped")
for level, limit in {[4]=8, [5]=20, [6]=30} do
	server.items={}
	for index=1,limit+2 do
		local id = tostring(index)
		server.items[id] = Citizen(id,R.Vector3.new(0,0,-(2+index/10)))
	end
	Swing(level)
	Check(server.items[tostring(limit)].hp==0 and server.items[tostring(limit+1)].hp==30,
		"target limit and distance ordering respected at tier " .. level)
end
local w1Cooldown = GameData.GetWeaponByLevel(1).attackCooldown
Check(w1Cooldown > 0, "W01 attackCooldown configured in GameData")
local broadcastSwing = nil
for _, notice in B.broadcasts do
	if notice.kind == "Swing" then broadcastSwing = notice end
end
Check(broadcastSwing ~= nil and typeof(broadcastSwing.weaponLevel) == "number" and broadcastSwing.weaponLevel >= 1, "Swing broadcast includes weaponLevel")
print(string.format("PASS: %d attack feedback flow assertions (production methods; network/clock/physics mocked)",checks))
