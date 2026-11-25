-- NPC 模块：受限街道采样、白膜生成、闲逛动画及击晕转换
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Surface = require(ReplicatedStorage.Scripts.Shared.PaintSurface)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Ragdoll = require(script.Parent.Ragdoll)
local Scene = require(script.Parent.Scene)
local Physics = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Ground = require(script.Parent.GroundAuthority)
local PersonalRules = require(ReplicatedStorage.Scripts.Shared.PersonalUpgradeRules)
local ModelTemplates = require(ReplicatedStorage.Scripts.Shared.ModelTemplates)
local NPC = {}
local random = Random.new()
function NPC.StopMotion(item: Types.Item): ()
	if item.pushConnection then item.pushConnection:Disconnect(); item.pushConnection=nil end
	if item.walkTrack then item.walkTrack:Stop(Config.MotionFadeSeconds) end
	if item.idleTrack then item.idleTrack:Stop(Config.MotionFadeSeconds) end
	item.staggerEnds = nil
end
local function SetMotion(item: Types.Item, state: string): ()
	if item.motionState == state then return end
	item.motionState = state
	item.model:SetAttribute("MotionState", state)
	local walking = state == "Walking"
	local track = if walking then item.walkTrack else item.idleTrack
	local other = if walking then item.idleTrack else item.walkTrack
	if other then other:Stop(Config.MotionFadeSeconds) end
	if track and not track.IsPlaying then track:Play(Config.MotionFadeSeconds) end
end
function NPC.Spawn(runtime: Folder, items: { [string]: Types.Item }): Types.Item?
	local point: Vector3? = nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Scene.District }
	for _ = 1, 24 do
		local candidate = Scene.StreetPoint(random)
		local hit = workspace:Raycast(candidate + Vector3.new(0, 8, 0), Vector3.new(0, -10, 0), params)
		if not hit or hit.Instance ~= Scene.Deck then
			continue
		end
		local occupied = false
		for _, item in items do
			if item.model.PrimaryPart and (item.model.PrimaryPart.Position - candidate).Magnitude < 5 then
				occupied = true
				break
			end
		end
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { Scene.Deck, runtime }
		if #workspace:GetPartBoundsInBox(CFrame.new(candidate + Vector3.new(0, 3, 0)), Vector3.new(3, 5.5, 3), overlap) > 0 then
			occupied = true
		end
		if not occupied then
			point = candidate
			break
		end
	end
	if not point then
		return nil
	end
	local model = ModelTemplates.WaitCharacter("WhiteR15"):Clone()
	local id = HttpService:GenerateGUID(false)
	model.Name = "WhiteNPC"
	model:SetAttribute("ItemId", id)
	model:SetAttribute("GroundPresentation", Physics.GroundRootEnabled)
	model:PivotTo(CFrame.new(point + Vector3.new(0, 3.2, 0)))
	model.Parent = runtime
	Ragdoll.Setup(model)
	Ragdoll.SetMode(model, "Walking")
	local item: Types.Item = {
		id = id,
		kind = "Body",
		stage = "Unpainted",
		location = "Street",
		version = 1,
		model = model,
		holder = nil,
		hits = 0,
		hp = Config.StreetNpcMaxHp,
		maxHp = Config.StreetNpcMaxHp,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = Surface.Total(model),
		progress = 0,
		paintSeconds = 0,
		streetSlot = true,
		nextWalk = 0,
		carryWeld = nil,
		walkTrack = nil,
	}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = Config.WalkAnimation
	local ok, track = pcall(function(): AnimationTrack
		return (animator :: Animator):LoadAnimation(animation)
	end)
	animation:Destroy()
	if ok and track then
		item.walkTrack = track
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement
	end
	local idle = Instance.new("Animation")
	idle.AnimationId = Config.IdleAnimation
	local idleOk, idleTrack = pcall(function(): AnimationTrack return (animator :: Animator):LoadAnimation(idle) end)
	idle:Destroy()
	if idleOk and idleTrack then
		item.idleTrack = idleTrack
		idleTrack.Looped, idleTrack.Priority = true, Enum.AnimationPriority.Idle
	end
	SetMotion(item, "Idle")
	return item
end
function NPC.Update(item: Types.Item, now: number): ()
	if item.location ~= "Street" or item.hits >= Config.StunHits then
		return
	end
	local root = item.model.PrimaryPart
	local humanoid = item.model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	if item.staggerEnds then
		local remaining = item.staggerEnds - now
		if remaining > 0 then
			humanoid:Move(Vector3.zero)
			humanoid.WalkSpeed = 0
			return
		end
		NPC.StopMotion(item)
		humanoid.WalkSpeed = 7
		item.motionState = nil
	end
	local localPoint = Scene.Deck.CFrame:PointToObjectSpace(root.Position)
	if
		math.abs(localPoint.X) > Scene.Deck.Size.X / 2 - 1
		or math.abs(localPoint.Z) > Scene.Deck.Size.Z / 2 - 1
		or root.Position.Y < Scene.Deck.Position.Y - 4
	then
		item.model:PivotTo(CFrame.new(Scene.StreetPoint(random) + Vector3.new(0, 3.2, 0)))
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walking = if item.motionState == "Walking" then speed > Config.WalkExitSpeed else speed > Config.WalkEnterSpeed
	SetMotion(item, if walking then "Walking" else "Idle")
	if walking and item.walkTrack then item.walkTrack:AdjustSpeed(math.clamp(speed / 7, 0.15, 1.2)) end
	if now >= item.nextWalk then
		if random:NextNumber() < Config.WalkPauseChance then
			humanoid:MoveTo(root.Position)
			item.nextWalk = now + random:NextNumber(0.6, 1.2)
		else
			humanoid:MoveTo(Scene.StreetPoint(random))
			item.nextWalk = now + random:NextNumber(2, 4)
		end
	end
end
-- 按绝对时间采样 ease-out 曲线，每步仅移动尚未消耗的距离；任一躯干先碰墙即结束。
local function Push(item: Types.Item, root: BasePart, direction: Vector3)
	local model=item.model
	local cast=RaycastParams.new()
	cast.FilterType=Enum.RaycastFilterType.Exclude
	cast.FilterDescendantsInstances={model}
	cast.RespectCanCollide=true
	cast.CollisionGroup=root.CollisionGroup
	local overlap=OverlapParams.new()
	overlap.FilterType=Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances={model}
	overlap.RespectCanCollide=true
	overlap.CollisionGroup=root.CollisionGroup
	overlap.MaxParts=1
	local parts: {BasePart}={}
	for _,name in {"Head","UpperTorso","LowerTorso"} do
		local part=model:FindFirstChild(name)
		if part and part:IsA("BasePart") then table.insert(parts,part) end
	end
	local started=workspace:GetServerTimeNow()
	local traveled=0
	root.AssemblyLinearVelocity=Vector3.yAxis*root.AssemblyLinearVelocity.Y
	local function Finish()
		if item.pushConnection then item.pushConnection:Disconnect(); item.pushConnection=nil end
	end
	item.pushConnection=RunService.PreSimulation:Connect(function()
		if item.location~="Street" or not model.Parent or root.Parent~=model or item.hits>=Config.StunHits then Finish(); return end
		local t=math.clamp((workspace:GetServerTimeNow()-started)/Config.HitPushSeconds,0,1)
		local requested=Config.HitPushDistance*(1-(1-t)^2)-traveled
		if requested<=0 then if t>=1 then Finish() end; return end
		local distance=requested
		for _,part in parts do
			local size=part.Size*0.94
			local hit=workspace:Blockcast(part.CFrame,size,direction*distance,cast)
			if hit then distance=math.max(0,hit.Distance-0.03) end
			if distance<=0 or #workspace:GetPartBoundsInBox(part.CFrame+direction*distance,size,overlap)>0 then distance=0; break end
		end
		if distance>0 then model:PivotTo(model:GetPivot()+direction*distance); traveled+=distance end
		if t>=1 or distance<requested then Finish() end
	end)
end
function NPC.Hit(item: Types.Item, direction: Vector3?, damage: number?, groundTravel: number?): ()
	item.maxHp = item.maxHp or Config.StreetNpcMaxHp
	local hp = PersonalRules.RemainingNpcHp(item.hp, item.hits, damage or Config.BruteDamage)
	item.hp = hp
	-- 保留已有击晕和表现协议的三档状态，血条读取实际 HP。
	item.hits = Config.StunHits - math.ceil(hp / Config.BruteDamage)
	item.version += 1
	local humanoid = item.model:FindFirstChildOfClass("Humanoid")
	local root = item.model.PrimaryPart
	if humanoid and root then humanoid:MoveTo(root.Position) end
	item.nextWalk = workspace:GetServerTimeNow() + Config.HitStaggerSeconds
	NPC.StopMotion(item)
	item.motionState = "Hit"
	item.model:SetAttribute("MotionState", "Hit")
	item.staggerEnds = item.nextWalk
	if item.hits >= Config.StunHits then
		if item.walkTrack then
			item.walkTrack:Stop()
		end
		if Physics.GroundRootEnabled and root then
			local axis=direction or root.CFrame.LookVector
			Ground.Place(item,axis,root.AssemblyLinearVelocity+axis*Config.StunImpulseSpeed, groundTravel)
			item.motionState="Down"
			item.model:SetAttribute("MotionState","Down")
			return
		end
		Ragdoll.SetMode(item.model, "Loose")
		item.model:SetAttribute("MotionState", "Down")
		local torso = item.model:FindFirstChild("UpperTorso")
		if direction and torso and torso:IsA("BasePart") then
			local horizontal = Vector3.new(direction.X, 0, direction.Z)
			if horizontal.Magnitude > 0.01 then torso:ApplyImpulse(horizontal.Unit * Config.StunImpulseSpeed * torso.AssemblyMass) end
		end
	elseif humanoid and root then
		humanoid.WalkSpeed = 0
		local horizontal = if direction then Vector3.new(direction.X,0,direction.Z) else Vector3.zero
		if horizontal.Magnitude > 0.01 then
			Push(item,root,horizontal.Unit)
		end
	end
end
return NPC
