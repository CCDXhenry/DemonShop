-- NPC 模块：受限街道采样、白膜生成、闲逛动画及击晕转换
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Surface = require(ReplicatedStorage.Scripts.Shared.PaintSurface)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Ragdoll = require(script.Parent.Ragdoll)
local Scene = require(script.Parent.Scene)
local NPC = {}
local random = Random.new()
function NPC.StopMotion(item: Types.Item): ()
	if item.hitVelocity then item.hitVelocity.Enabled=false end
	if item.walkTrack then item.walkTrack:Stop(Config.MotionFadeSeconds) end
	if item.idleTrack then item.idleTrack:Stop(Config.MotionFadeSeconds) end
	for _, record in ipairs(item.hitJoints or {}) do
		if record.joint.Parent then record.joint.C0 = record.base end
	end
	item.staggerEnds, item.hitDirection = nil, nil
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
	local model = ReplicatedStorage.Models.WhiteR15:Clone() :: Model
	local id = HttpService:GenerateGUID(false)
	model.Name = "WhiteNPC"
	model:SetAttribute("ItemId", id)
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
	local hitJoints: { { joint: Motor6D, base: CFrame } } = {}
	item.hitJoints = hitJoints
	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") and (joint.Name == "Waist" or joint.Name == "Neck" or string.find(joint.Name,"Hip")) then
			table.insert(hitJoints, {joint=joint, base=joint.C0})
		end
	end
	SetMotion(item, "Idle")
	local hitAttachment=Instance.new("Attachment")
	hitAttachment.Name,hitAttachment.Parent="StaggerAttachment",model.PrimaryPart
	local hitVelocity=Instance.new("LinearVelocity")
	hitVelocity.Name,hitVelocity.Attachment0="StaggerVelocity",hitAttachment
	hitVelocity.VelocityConstraintMode=Enum.VelocityConstraintMode.Plane
	hitVelocity.RelativeTo=Enum.ActuatorRelativeTo.World
	hitVelocity.PrimaryTangentAxis,hitVelocity.SecondaryTangentAxis=Vector3.xAxis,Vector3.zAxis
	hitVelocity.MaxForce,hitVelocity.Enabled=10000,false
	hitVelocity.Parent=model.PrimaryPart
	item.hitVelocity=hitVelocity
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
			local age = Config.HitStaggerSeconds - remaining
			if item.hitVelocity and age>Config.HitPushSeconds then item.hitVelocity.Enabled=false end
			local amount = math.sin(math.min(age / Config.HitLeanRiseSeconds, 1) * math.pi / 2) * math.clamp(remaining / Config.HitStaggerSeconds, 0, 1)
			local direction = root.CFrame:VectorToObjectSpace(item.hitDirection or Vector3.zAxis)
			local hitJoints: { { joint: Motor6D, base: CFrame } }=item.hitJoints or {}
			for _, record in hitJoints do
				local hip=string.find(record.joint.Name,"Hip")~=nil
				local side=if string.sub(record.joint.Name,1,4)=="Left" then 1 else -1
				local lean=if hip then math.sin(age/Config.HitStaggerSeconds*math.pi)*Config.HitLeanRadians*side else Config.HitLeanRadians*amount
				record.joint.C0 = record.base * CFrame.Angles(direction.Z * lean, 0, -direction.X * lean)
			end
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
function NPC.Hit(item: Types.Item, direction: Vector3?): ()
	item.hits += 1
	item.version += 1
	local humanoid = item.model:FindFirstChildOfClass("Humanoid")
	local root = item.model.PrimaryPart
	if humanoid and root then humanoid:MoveTo(root.Position) end
	item.nextWalk = workspace:GetServerTimeNow() + Config.HitStaggerSeconds
	NPC.StopMotion(item)
	item.motionState = "Hit"
	item.model:SetAttribute("MotionState", "Hit")
	item.staggerEnds = item.nextWalk
	item.hitDirection = direction
	if item.hits >= Config.StunHits then
		if item.walkTrack then
			item.walkTrack:Stop()
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
			root:ApplyImpulse(horizontal.Unit * Config.HitImpulseSpeed * root.AssemblyMass)
			if item.hitVelocity then
				local velocity=horizontal.Unit*Config.HitImpulseSpeed
				item.hitVelocity.PlaneVelocity=Vector2.new(velocity.X,velocity.Z)
				item.hitVelocity.Enabled=true
			end
		end
	end
end
return NPC
