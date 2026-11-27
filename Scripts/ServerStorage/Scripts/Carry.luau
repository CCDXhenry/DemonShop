-- 搬运模块：无碰撞柔性肩扛、入池与祭坛抛掷、有限惯性释放及资源回收
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Ragdoll = require(script.Parent.Ragdoll)
local NPC = require(script.Parent.NPC)
local Scene = require(script.Parent.Scene)
local Config = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local GameConfig = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local ThrowArc = require(ReplicatedStorage.Scripts.Shared.ThrowArc)
local CageGeometry = require(ReplicatedStorage.Scripts.Shared.CageGeometry)
local Ground = require(script.Parent.GroundAuthority)
local PersonalRules = require(ReplicatedStorage.Scripts.Shared.PersonalUpgradeRules)
local Carry = {}
local random = Random.new()
local nextCarryOrder = 0
local Stack = Config.CarryStack
local Altar = Config.AltarToss
local ReferenceTorsoSize = Vector3.new(2, 1.6, 1)

local function StackOffset(scale: Vector3, layer: number): CFrame
	if layer == 0 then
		return CFrame.new(Config.ShoulderOffset * scale) * Config.ShoulderRotation
	end
	local height = Stack.SecondGap
	if layer >= 2 then
		height += Stack.ThirdGap + Stack.NextGap * (1 - Stack.GapDecay ^ (layer - 2)) / (1 - Stack.GapDecay)
	end
	local side = if layer % 2 == 1 then 1 else -1
	local stagger = Vector3.new(side * Stack.SideOffset, height, math.min(Stack.BackStep * layer, Stack.BackLimit))
	return CFrame.new((Config.ShoulderOffset + stagger) * scale)
		* CFrame.Angles(0, side * Stack.Yaw, 0) * Config.ShoulderRotation
end

local function Smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function LiftPose(from: CFrame, support: CFrame, base: CFrame, scale: Vector3, t: number): CFrame
	local fromPoint = from.Position
	local destination = support * base
	local right = support.RightVector
	local sideStep = Vector3.new(right.X, 0, right.Z) * (Stack.OutsideClearance * scale.X)
	local up = Vector3.yAxis * scale.Y
	local arc = destination.Position + sideStep + up * Stack.ArcClearance
	local raised = fromPoint + Vector3.yAxis * math.max(
		Stack.LiftStartClearance * scale.Y, arc.Y - fromPoint.Y
	)
	local dip = destination.Position - up * Stack.SettleDepth
	local point: Vector3
	if t < Stack.RaiseFraction then
		point = fromPoint:Lerp(raised, Smooth(t / Stack.RaiseFraction))
	elseif t < Stack.LandFraction then
		point = raised:Lerp(arc, Smooth((t - Stack.RaiseFraction) / (Stack.LandFraction - Stack.RaiseFraction)))
	elseif t < Stack.DipFraction then
		point = arc:Lerp(dip, Smooth((t - Stack.LandFraction) / (Stack.DipFraction - Stack.LandFraction)))
	else
		point = dip:Lerp(destination.Position, Smooth((t - Stack.DipFraction) / (1 - Stack.DipFraction)))
	end
	return CFrame.new(point) * from.Rotation:Lerp(destination.Rotation, Smooth(t))
end
local function SetOwner(model: Model, owner: Player?): ()
	model:SetAttribute("PhysicsOwnerUserId", if owner then owner.UserId else nil)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then pcall(function(): () part:SetNetworkOwner(owner) end) end
	end
end
local function ClearRelease(item: Types.Item): ()
	local contacts = item.model:FindFirstChild("ReleaseContacts")
	if contacts then contacts:Destroy() end
	item.releaseUntil, item.releaseCharacter = nil, nil
end
function Carry.Detach(item: Types.Item, restoreTool: boolean?): ()
	item.fall=nil
	item.poolToss=nil
	item.altarToss = nil
	if item.carryTween then item.carryTween:Cancel(); item.carryTween:Destroy(); item.carryTween = nil end
	if item.carryWeld then item.carryWeld:Destroy(); item.carryWeld = nil end
	if item.carryResources then
		local reference=item.carryResources:FindFirstChild("Anchor")
		if reference and reference:IsA("ObjectValue") and reference.Value then reference.Value:Destroy() end
		item.carryResources:Destroy(); item.carryResources = nil
	end
	if item.carryTarget then item.carryTarget:Destroy(); item.carryTarget = nil end
	item.carryErrorSince=nil
	item.carryLayer, item.carryTransition = nil, nil
	item.carryBaseOffset,item.carryVelocity,item.carryUpdated,item.carrySway,item.carryOrder=nil,nil,nil,nil,nil
	local contacts = item.model:FindFirstChild("CarryContacts")
	if contacts then contacts:Destroy() end
	ClearRelease(item)
	SetOwner(item.model, nil)
	local owner = item.holder
	item.holder = nil
	-- 处理白膜时保留工具栏选择。其他搬运物仍沿用原来的武器恢复逻辑。
	if item.kind == "Body" then return end
	local humanoid = owner and owner.Character and owner.Character:FindFirstChildOfClass("Humanoid")
	local backpack = owner and owner:FindFirstChild("Backpack")
	local weapon = if backpack then PersonalRules.FindWeapon(backpack) else nil
	local restore = if restoreTool == nil then true else restoreTool
	if restore and humanoid and humanoid.Health > 0 and weapon then humanoid:EquipTool(weapon) end
end
function Carry.Static(item: Types.Item, pose: CFrame, restoreTool: boolean?): ()
	Carry.Detach(item, restoreTool)
	NPC.StopMotion(item)
	item.model:SetAttribute("MotionState", "Static")
	if item.kind == "Body" then Ragdoll.SetMode(item.model, "Static") else
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored,part.CanCollide=true,false end
		end
	end
	item.model:PivotTo(pose)
end
local function VerticalHalfExtent(frame: CFrame, size: Vector3): number
	return (math.abs(frame.RightVector.Y) * size.X + math.abs(frame.UpVector.Y) * size.Y + math.abs(frame.LookVector.Y) * size.Z) * 0.5
end
function Carry.Contain(item: Types.Item, cage: string, preserveOwner: boolean?): ()
	if item.model:GetAttribute("CageContained") == cage then return end
	Ragdoll.SetCageContained(item.model, cage)
	Ragdoll.SetThrowPhysics(item.model, false)
	if preserveOwner then return end
	SetOwner(item.model, nil)
	local damping = Config.Cage.EntryHorizontalDamping
	local maxHoriz = Config.Cage.EntryMaxHorizontalSpeed
	for _, part in item.model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			local v = part.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z) * damping
			if flat.Magnitude > maxHoriz then
				flat = flat.Unit * maxHoriz
			end
			part.AssemblyLinearVelocity = Vector3.new(flat.X, v.Y, flat.Z)
		end
	end
end

function Carry.ReleaseIntoChute(item: Types.Item, pose: CFrame, pile: { Model }, restoreTool: boolean?): ()
	local ChuteReleaseClearance = 0.25
	local supportY = pose.Position.Y
	for _, model in pile do
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.CanCollide then
				supportY = math.max(supportY, part.Position.Y + VerticalHalfExtent(part.CFrame, part.Size))
			end
		end
	end
	Carry.Static(item, pose, restoreTool)
	local frame, size = item.model:GetBoundingBox()
	local bottom = frame.Position.Y - VerticalHalfExtent(frame, size)
	item.model:PivotTo(pose + Vector3.yAxis * (supportY - bottom + ChuteReleaseClearance))
	Ragdoll.SetMode(item.model, "Loose")
	Carry.Contain(item, "Chute")
	item.motionState = "ChutePile"
	item.model:SetAttribute("MotionState", item.motionState)
end
function Carry.Take(item: Types.Item, player: Player, bodyLayer: number?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local primary = item.model.PrimaryPart
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or not primary then return false end
	local torso = item.model:FindFirstChild("UpperTorso")
	if item.kind == "Body" and (not torso or not torso:IsA("BasePart")) then return false end
	Carry.Detach(item)
	NPC.StopMotion(item)
	if item.kind == "Body" then
		if not torso or not torso:IsA("BasePart") then return false end
		local shoulder = character:FindFirstChild("UpperTorso")
		local support = if shoulder and shoulder:IsA("BasePart") then shoulder else root
		local layer = bodyLayer or 0
		local now = workspace:GetServerTimeNow()
		local from = torso.CFrame
		local offset = StackOffset(support.Size / ReferenceTorsoSize, layer)
		local resources = Instance.new("Folder")
		resources.Name,resources.Parent="CarryResources",item.model
		item.carryResources=resources
		local target = Instance.new("Attachment")
		target.Name,target.CFrame,target.Parent="WhiteBodyShoulder",support.CFrame:ToObjectSpace(from),support
		item.carryTarget=target
		item.carryBaseOffset,item.carryVelocity,item.carryUpdated,item.carrySway=offset,support.AssemblyLinearVelocity,now,Vector2.zero
		item.carryLayer = layer
		item.carryTransition = {kind="Lift", from=from, started=now, ends=now + Config.Presentation.Carry.LiftSeconds}
		Ragdoll.SetMode(item.model, "Carried", player)
		local anchor = Instance.new("Attachment")
		anchor.Name,anchor.Parent="CarryAnchor",torso
		local reference=Instance.new("ObjectValue")
		reference.Name,reference.Value,reference.Parent="Anchor",anchor,resources
		local align=Instance.new("AlignPosition")
		align.Attachment0,align.Attachment1=anchor,target
		align.ApplyAtCenterOfMass,align.ReactionForceEnabled,align.RigidityEnabled=true,false,false
		align.MaxForce=math.max(torso.AssemblyMass,1)*Config.CarryForcePerMass
		align.MaxVelocity,align.Responsiveness=Config.CarryMaxVelocity,Config.CarryResponsiveness
		align.Parent=resources
		local orientation=Instance.new("AlignOrientation")
		orientation.Attachment0,orientation.Attachment1=anchor,target
		orientation.ReactionTorqueEnabled,orientation.RigidityEnabled=false,false
		orientation.MaxTorque=math.max(torso.AssemblyMass,1)*Config.CarryTorquePerMass
		orientation.MaxAngularVelocity,orientation.Responsiveness=Config.CarryMaxAngularVelocity,Config.CarryOrientationResponsiveness
		orientation.Parent=resources
	else
		item.model:PivotTo(root.CFrame*CFrame.new(1,-.1,-1.3))
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored,part.CanCollide,part.CanTouch,part.Massless=false,false,false,true end
		end
		local weld=Instance.new("Weld")
		weld.Name,weld.Part0,weld.Part1="CarryWeld",root,primary
		weld.C0,weld.Parent=root.CFrame:ToObjectSpace(primary.CFrame),primary
		item.carryWeld=weld
	end
	if item.kind == "Body" then
		nextCarryOrder += 1
		item.carryOrder = nextCarryOrder
	else
		humanoid:UnequipTools()
	end
	item.holder,item.location,item.motionState=player,"Carried","Carried"
	item.model:SetAttribute("MotionState","Carried")
	item.streetSlot=false
	item.version+=1
	return true
end
function Carry.Restack(items: { Types.Item }): ()
	local now = workspace:GetServerTimeNow()
	for index, item in items do
		local target = item.carryTarget
		local support = target and target.Parent
		local layer = index - 1
		if target and support and support:IsA("BasePart") and item.carryLayer ~= layer then
			item.carryLayer = layer
			item.carryBaseOffset = StackOffset(support.Size / ReferenceTorsoSize, layer)
			local previous = item.carryTransition
			if previous and previous.kind == "Lift" and now < previous.ends then
				item.carryTransition = {
					kind="Lift", from=support.CFrame * target.CFrame, started=now,
					ends=math.max(previous.ends, now + Stack.RestackSeconds),
				}
			else
				item.carryTransition = {kind="Restack", from=target.CFrame, started=now, ends=now + Stack.RestackSeconds}
			end
			item.carryErrorSince = nil
		end
	end
end

function Carry.AdvanceTransition(item: Types.Item, now: number): ()
	local transition = item.carryTransition
	local target = item.carryTarget
	local support = target and target.Parent
	local base = item.carryBaseOffset
	if not transition or not target or not support or not support:IsA("BasePart") or not base then return end
	local progress = math.clamp((now - transition.started) / (transition.ends - transition.started), 0, 1)
	if progress >= 1 then
		target.CFrame = base
		item.carryTransition, item.carryErrorSince = nil, nil
		item.carrySway, item.carryVelocity, item.carryUpdated = Vector2.zero, support.AssemblyLinearVelocity, now
	elseif transition.kind == "Lift" then
		local frame = LiftPose(transition.from, support.CFrame, base, support.Size / ReferenceTorsoSize, progress)
		target.CFrame = support.CFrame:ToObjectSpace(frame)
	else
		target.CFrame = transition.from:Lerp(base, Smooth(progress))
	end
end
local function ReleaseContacts(item: Types.Item, character: Model): ()
	local folder=Instance.new("Folder")
	folder.Name,folder.Parent="ReleaseContacts",item.model
	for _, body in item.model:GetDescendants() do
		if body:IsA("BasePart") then
			for _, playerPart in character:GetDescendants() do
				if playerPart:IsA("BasePart") then
					local contact=Instance.new("NoCollisionConstraint")
					contact.Part0,contact.Part1,contact.Parent=body,playerPart,folder
				end
			end
		end
	end
	item.releaseCharacter=character
	item.releaseUntil=workspace:GetServerTimeNow()+Config.ReleaseGraceSeconds
end
local function SetFlightCollision(model: Model, enabled: boolean): ()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = enabled
			part.CanTouch = enabled
		end
	end
end
local function FreezePose(item: Types.Item, collision: boolean): ()
	NPC.StopMotion(item)
	local model = item.model
	if model:GetAttribute("CageContained") then Ragdoll.SetCageContained(model, nil) end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
	end
	for _, inst in model:GetDescendants() do
		if inst:IsA("Motor6D") and inst.Name ~= "Root" and inst.Name ~= "RootJoint" then
			inst.Enabled = false
		elseif inst:IsA("BallSocketConstraint") then
			inst.Enabled = false
		elseif inst:IsA("BasePart") then
			inst.AssemblyLinearVelocity = Vector3.zero
			inst.AssemblyAngularVelocity = Vector3.zero
			inst.Anchored = true
			local collide = collision and inst.Name ~= "HumanoidRootPart"
			inst.CanCollide = collide
			inst.CanTouch = collide
		end
	end
end
local function AnchorAltarBody(item: Types.Item): ()
	item.poolToss = nil
	item.altarToss = nil
	FreezePose(item, false)
	local model = item.model
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.Transparency = 1
		end
	end
	model:SetAttribute("PhysicsMode", "AltarAnchored")
	model:SetAttribute("MotionState", "Altar")
	item.motionState = "Altar"
	item.version += 1
end
local function ReleasePool(item: Types.Item): ()
	item.poolToss = nil
	SetFlightCollision(item.model, true)
	Carry.Contain(item, "Pool")
	item.motionState = "Pool"
	item.model:SetAttribute("PhysicsMode", "Loose")
	item.model:SetAttribute("MotionState", "Pool")
	item.version += 1
end
function Carry.BeginToss(item: Types.Item, target: CFrame, thrower: Player?, restoreTool: boolean?): boolean
	-- 落点由调用方给定，不读取镜头或角色朝向。飞行由抛掷客户端持有物理所有权。
	-- 没有抛掷者时放到落点并返回 true，由调用方交回活物理状态。
	local character = thrower and thrower.Character
	local from = item.model:GetPivot()
	Carry.Detach(item, restoreTool)
	NPC.StopMotion(item)
	if not thrower then
		item.model:PivotTo(target)
		return true
	end
	Ragdoll.SetMode(item.model, "Loose", thrower)
	SetFlightCollision(item.model, false)
	for _, part in item.model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	if character then ReleaseContacts(item, character) end
	item.poolToss = { kind = "Pool", from = from, target = target, started = workspace:GetServerTimeNow(), owner = thrower.UserId }
	item.motionState = "PoolToss"
	item.model:SetAttribute("MotionState", "PoolToss")
	return false
end
function Carry.TossIntoPool(item: Types.Item, restoreTool: boolean?): ()
	local owner = item.holder
	local target = Scene.PoolDropTarget(random)
	if Carry.BeginToss(item, target, owner, restoreTool) then
		Ragdoll.SetMode(item.model, "Loose")
		ReleasePool(item)
	end
end
local function BodyTorso(model: Model): BasePart?
	local torso = model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return model.PrimaryPart
end
local function SafeManualRelease(model: Model, character: Model?, forward: Vector3): CFrame
	local torso = BodyTorso(model)
	local current = if torso then torso.CFrame else model:GetPivot()
	if not character then
		return current
	end
	local anchor = character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
	if not anchor or not anchor:IsA("BasePart") then
		return current
	end
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Include
	cast.FilterDescendantsInstances = { Scene.District, workspace.Terrain }
	cast.RespectCanCollide = true
	cast.CollisionGroup = Config.BodyGroup
	local origin = anchor.Position
	local delta = current.Position - origin
	if delta.Magnitude > 0.05 then
		local hit = workspace:Raycast(origin, delta, cast)
		if hit then
			local safePoint = hit.Position - delta.Unit * math.min(0.85, delta.Magnitude * 0.5)
			model:PivotTo(model:GetPivot() + (safePoint - current.Position))
			return if torso then torso.CFrame else model:GetPivot()
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = cast.FilterDescendantsInstances
	overlap.RespectCanCollide = true
	overlap.CollisionGroup = Config.BodyGroup
	overlap.MaxParts = 1
	if torso and #workspace:GetPartsInPart(torso, overlap) > 0 then
		local fallback = origin + ThrowArc.Horizontal(forward, anchor.CFrame.LookVector) * 0.85 + Vector3.yAxis * 0.5
		if workspace:Raycast(origin, fallback - origin, cast) then
			fallback = origin + Vector3.yAxis * 0.5
		end
		model:PivotTo(model:GetPivot() + (fallback - torso.Position))
		return torso.CFrame
	end
	return current
end
function Carry.BeginManualToss(item: Types.Item, _from: CFrame, velocity: Vector3, duration: number, target: CFrame, thrower: Player, restoreTool: boolean, _chuteDropFrom: Vector3?, _contact: Vector3?, canEnterChute: boolean?): ()
	local character = thrower.Character
	Carry.Detach(item, restoreTool)
	NPC.StopMotion(item)
	local releasePose = SafeManualRelease(item.model, character, velocity)
	Ragdoll.SetMode(item.model, "Loose", thrower)
	Ragdoll.SetThrowPhysics(item.model, true)
	if character then
		ReleaseContacts(item, character)
	end
	local manual = Config.ManualThrow
	local flat = ThrowArc.Horizontal(velocity, Vector3.zAxis)
	-- 右手系下 Look×Up 为右方，绕左向轴（Up×Look）正角速度使上半身向前滚翻。
	local pitchAxis = Vector3.yAxis:Cross(flat)
	local pitchSpeed = random:NextNumber(manual.PitchSpinMin, manual.PitchSpinMax)
	local sideLimit = manual.SideSpinMax
	local sideSpin = Vector3.new(
		random:NextNumber(-sideLimit, sideLimit),
		random:NextNumber(-sideLimit, sideLimit),
		random:NextNumber(-sideLimit, sideLimit)
	)
	local spin = pitchAxis * pitchSpeed + sideSpin
	for _, part in item.model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			part.AssemblyLinearVelocity = velocity
			part.AssemblyAngularVelocity = spin
		end
	end
	item.location = "Thrown"
	item.streetSlot = false
	item.version += 1
	item.motionState = "ManualToss"
	item.model:SetAttribute("MotionState", "ManualToss")
	item.poolToss = {
		kind = "Manual",
		from = releasePose,
		target = target,
		started = workspace:GetServerTimeNow(),
		owner = thrower.UserId,
		velocity = velocity,
		duration = duration,
		spin = spin,
		canEnterChute = canEnterChute == true,
	}
end
function Carry.FinishPool(item: Types.Item): ()
	item.fall = nil
	item.poolToss = nil
	if item.model:GetAttribute("PhysicsMode") ~= "Loose" then
		Ragdoll.SetMode(item.model, "Loose")
	end
	Carry.Contain(item, "Pool", true)
	item.location = "Pool"
	item.stage = "Unpainted"
	item.streetSlot = false
	item.motionState = "Pool"
	item.model:SetAttribute("PhysicsMode", "Loose")
	item.model:SetAttribute("MotionState", "Pool")
	item.version += 1
end
function Carry.FinishChute(item: Types.Item): ()
	item.fall = nil
	item.poolToss = nil
	if item.model:GetAttribute("PhysicsMode") ~= "Loose" then
		Ragdoll.SetMode(item.model, "Loose")
	end
	Carry.Contain(item, "Chute", true)
	item.location = "Chute"
	item.stage = "Unpainted"
	item.streetSlot = false
	item.motionState = "ChutePile"
	item.model:SetAttribute("PhysicsMode", "Loose")
	item.model:SetAttribute("MotionState", "ChutePile")
	item.version += 1
end
function Carry.FinishGround(item: Types.Item, keepCage: boolean?): ()
	item.fall = nil
	item.poolToss = nil
	if item.model:GetAttribute("PhysicsMode") ~= "Loose" then
		Ragdoll.SetMode(item.model, "Loose")
	end
	if not keepCage and item.model:GetAttribute("CageContained") then Ragdoll.SetCageContained(item.model, nil) end
	Ragdoll.SetThrowPhysics(item.model, false)
	SetOwner(item.model, nil)
	item.location = "Ground"
	item.motionState = "Down"
	item.model:SetAttribute("PhysicsMode", "Loose")
	item.model:SetAttribute("MotionState", "Down")
	item.version += 1
end
local function NearLanding(item: Types.Item, bed: BasePart): boolean
	local torso = item.model:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then
		return false
	end
	return bed.CFrame:PointToObjectSpace(torso.Position).Y <= bed.Size.Y * 0.5 + 3
end
local function AdvanceToss(item: Types.Item, now: number, bed: BasePart, release: (Types.Item) -> (), settledMotion: string, onSettled: ((Types.Item) -> ())?): boolean
	local toss = item.poolToss
	if not toss or item.model.Parent == nil then
		item.poolToss = nil
		return false
	end
	local flight = Config.PoolTossSeconds
	local flightDone = now >= toss.started + flight
	local player = Players:GetPlayerByUserId(toss.owner)
	if not player then
		item.model:PivotTo(toss.target)
		Ragdoll.SetMode(item.model, "Loose")
		if onSettled then
			onSettled(item)
		else
			release(item)
		end
		return true
	end
	if not flightDone then return false end
	if not toss.collision then
		local torso = BodyTorso(item.model)
		if not torso or not Scene.PoolBasinContains(torso.Position) then
			-- 客户端的最后一帧可能晚于服务器。等待交接，超时后使用既定存入落点。
			if now < toss.started + flight + Config.ReleaseGraceSeconds then return false end
			item.model:PivotTo(toss.target)
			Ragdoll.SetMode(item.model, "Loose")
		end
		toss.collision = true
		Carry.Contain(item, "Pool")
		SetFlightCollision(item.model, true)
		item.motionState = settledMotion
		item.model:SetAttribute("MotionState", settledMotion)
	end
	local nearFloor = NearLanding(item, bed)
	local asleep = nearFloor
	if asleep then
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored and (part.AssemblyLinearVelocity.Magnitude > 1.2 or part.AssemblyAngularVelocity.Magnitude > 1.2) then
				asleep = false
				break
			end
		end
	end
	local settle = toss.started + flight + Config.PoolSettleSeconds
	if now >= settle or (asleep and now >= toss.started + flight + Config.PoolAsleepDelay) then
		if onSettled then
			onSettled(item)
		else
			release(item)
		end
		return true
	end
	return false
end
function Carry.AdvancePoolToss(item: Types.Item, now: number): boolean
	return AdvanceToss(item, now, Scene.PoolFloor, ReleasePool, "Pool")
end
function Carry.AdvanceManualToss(item: Types.Item, now: number, onSettled: (Types.Item) -> (), chuteUnlocked: boolean?): boolean
	local toss = item.poolToss
	if not toss or toss.kind ~= "Manual" then return false end
	if not item.model.Parent then
		item.poolToss = nil
		return false
	end
	local manual = Config.ManualThrow
	Ragdoll.LimitVelocity(item.model, manual.MaxFlightLinearSpeed, manual.MaxFlightAngularSpeed)
	local torso = BodyTorso(item.model)
	if not torso then
		onSettled(item)
		return true
	end
	local elapsed = math.max(0, now - toss.started)
	local pos = torso.Position
	local cage = item.model:GetAttribute("CageContained") :: string?
	if not cage then
		local allowChute = chuteUnlocked == true and toss.canEnterChute == true
		cage = Scene.CageAt(pos, allowChute)
		if cage then
			local hasOwner = Players:GetPlayerByUserId(toss.owner) ~= nil
			Carry.Contain(item, cage, hasOwner)
		end
	end
	if cage and Players:GetPlayerByUserId(toss.owner) == nil then
		if Scene.IsSoftCageEnabled and Scene.CageFloor and Scene.CageInset and Scene.IsSoftCageEnabled(cage) then
			local floor = Scene.CageFloor(cage)
			if floor then
				CageGeometry.ApplySoftBounceToModel(item.model, floor.CFrame, floor.Size, Scene.CageInset(cage))
				pos = torso.Position
			end
		end
	end
	-- 快速通道落料垫：纯自然抛物线落入 FastChuteLanding 并减速稳定后才收纳。
	if toss.canEnterChute and Scene.ChuteLandingContains(pos) and torso.AssemblyLinearVelocity.Magnitude <= manual.PoolSettleSpeed then
		toss.chuteStableSince = toss.chuteStableSince or now
		if now - (toss.chuteStableSince :: number) >= manual.PoolStableSeconds then
			onSettled(item)
			return true
		end
	else
		toss.chuteStableSince = nil
	end
	-- 严格存放池：仅在真正落入池底盆内并减速稳定后才收纳。
	if item.stage ~= "Painted" and Scene.PoolBasinContains(pos) and torso.AssemblyLinearVelocity.Magnitude <= manual.PoolSettleSpeed then
		toss.poolStableSince = toss.poolStableSince or now
		if now - (toss.poolStableSince :: number) >= manual.PoolStableSeconds then
			onSettled(item)
			return true
		end
	else
		toss.poolStableSince = nil
	end
	-- 普通地面：仅在真正近地贴合且速度匹配地面状态时累计触地计时，重新悬空立即清零。
	if elapsed >= manual.MinGroundCheckSeconds then
		local cast = RaycastParams.new()
		cast.FilterType = Enum.RaycastFilterType.Include
		cast.FilterDescendantsInstances = { Scene.District, workspace.Terrain }
		cast.RespectCanCollide = true
		local hit = workspace:Raycast(pos, -Vector3.yAxis * manual.GroundProbeStuds, cast)
		local velocity = torso.AssemblyLinearVelocity
		local speed = velocity.Magnitude
		local onFloor = hit ~= nil and hit.Normal.Y > 0.5 and velocity.Y <= 2.0 and velocity.Y >= -12.0
		if onFloor or speed <= manual.GroundSlowSpeed then
			toss.groundedAt = toss.groundedAt or now
		else
			toss.groundedAt = nil
		end
	else
		toss.groundedAt = nil
	end
	if (toss.groundedAt and now - toss.groundedAt >= manual.GroundPickupDelaySeconds)
		or (not cage and elapsed >= manual.MaxFlightSeconds)
		or (cage ~= nil and elapsed >= manual.MaxFlightSeconds + Config.Cage.SoftBounceSettleGrace)
		or pos.Y < -35
	then
		onSettled(item)
		return true
	end
	return false
end
local function AltarRestOffset(part: BasePart, model: Model, pivot: CFrame): CFrame
	if part == model.PrimaryPart then return CFrame.identity end
	local rest = part:GetAttribute("RestPose")
	return if typeof(rest) == "CFrame" then rest else pivot:ToObjectSpace(part.CFrame)
end
function Carry.BeginAltarToss(item: Types.Item, fromTable: boolean, now: number, restoreTool: boolean?): ()
	local from = item.model:GetPivot()
	Carry.Detach(item, restoreTool)
	FreezePose(item, false)
	local flightStarts = now + (if fromTable then Altar.LiftSeconds else 0)
	local landSeconds = Altar.LandSeconds or 0.32
	local mouth = Scene.AltarMouth.WorldCFrame
	local yaw = if item.paintFlipped then math.pi else 0
	local rest = mouth * CFrame.new(0, -Altar.IntakeDepth, 0) * CFrame.Angles(GameConfig.PaintLiePitch, 0, 0)
		* CFrame.Angles(0, yaw, 0)
	item.altarToss = {
		from = from,
		mouth = mouth,
		rest = rest,
		started = now,
		flightStarts = flightStarts,
		landEnds = flightStarts + Altar.FlightSeconds + landSeconds,
	}
	item.motionState = "AltarToss"
	item.model:SetAttribute("MotionState", "AltarToss")
end
function Carry.AdvanceAltarToss(item: Types.Item, now: number): boolean
	local toss = item.altarToss
	if not toss then return false end
	local landEnds = toss.landEnds or (toss.flightStarts + Altar.FlightSeconds + (Altar.LandSeconds or 0.32))
	if now < landEnds then
		return false
	end
	local model = item.model
	local pivot = model:GetPivot()
	model:PivotTo(toss.rest)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = toss.rest * AltarRestOffset(part, model, pivot)
		end
	end
	AnchorAltarBody(item)
	return true
end
function Carry.RecoverPool(item: Types.Item): ()
	item.poolToss = nil
	NPC.StopMotion(item)
	local target = Scene.PoolDropTarget(random)
	item.model:PivotTo(target)
	Ragdoll.SetMode(item.model, "Loose")
	ReleasePool(item)
end
function Carry.Drop(item: Types.Item, position: Vector3, restoreTool: boolean?): ()
	local owner=item.holder
	local character=owner and owner.Character
	local primary=item.model.PrimaryPart
	local velocity=if primary then primary.AssemblyLinearVelocity else Vector3.zero
	local pose=item.model:GetPivot()
	Carry.Detach(item, restoreTool)
	local ignored: {Instance}={item.model}
	if character then table.insert(ignored,character) end
	local fallback=if item.kind=="Body" then Scene.PoolPickup.Position else Scene.Shelf.Position
	local safePose=Scene.SafePose(position,fallback,ignored)
	if item.kind=="Body" then
		local params=OverlapParams.new()
		params.FilterType,params.FilterDescendantsInstances=Enum.RaycastFilterType.Exclude,ignored
		params.RespectCanCollide=true
		local frame,size=item.model:GetBoundingBox()
		local blocked=#workspace:GetPartBoundsInBox(frame,size*0.85,params)>0
		if not owner or blocked or pose.Position.Y < -35 then
			item.model:PivotTo(pose + (safePose.Position-pose.Position))
		end
		if Config.GroundRootEnabled then
			local forward=if character then character:GetPivot().LookVector else pose.LookVector
			Ground.Place(item,forward,velocity)
		else
			Ragdoll.SetMode(item.model,"Loose")
			if velocity.Magnitude>Config.DropMaximumSpeed then velocity=velocity.Unit*Config.DropMaximumSpeed end
			for _,part in item.model:GetDescendants() do
				if part:IsA("BasePart") then part.AssemblyLinearVelocity=velocity end
			end
			if character then ReleaseContacts(item,character) end
		end
	else
		item.model:PivotTo(safePose)
		for _,part in item.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored,part.CanCollide,part.CanTouch,part.Massless=false,true,true,false
				part.AssemblyLinearVelocity,part.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
			end
		end
	end
	item.location,item.motionState="Ground","Down"
	item.model:SetAttribute("MotionState","Down")
	item.version+=1
end
function Carry.Update(item: Types.Item, now: number): boolean
	if item.releaseUntil and now>=item.releaseUntil then
		local character=item.releaseCharacter
		local overlapping=false
		if character and character.Parent then
			local params=OverlapParams.new()
			params.FilterType,params.FilterDescendantsInstances=Enum.RaycastFilterType.Include,{character}
			for _,part in item.model:GetChildren() do
				if part:IsA("BasePart") and part.CanCollide and #workspace:GetPartsInPart(part,params)>0 then overlapping=true;break end
			end
		end
		if overlapping then item.releaseUntil=now+.15 else ClearRelease(item) end
	end
	local target=item.carryTarget
	local torso=item.model:FindFirstChild("UpperTorso")
	if item.holder and target and torso and torso:IsA("BasePart") then
		local character = item.holder.Character
		if not character or not target:IsDescendantOf(character) then Carry.Drop(item,torso.Position);return true end
		local support=target.Parent
		local base=item.carryBaseOffset
		if support and support:IsA("BasePart") and base and not item.carryTransition then
			local dt=math.clamp(now-(item.carryUpdated or now),.01,.2)
			local velocity=support.AssemblyLinearVelocity
			local acceleration=support.CFrame:VectorToObjectSpace((velocity-(item.carryVelocity or velocity))/dt)
			local layerScale = math.min(1 + (item.carryLayer or 0) * Stack.SwayPerLayer, Stack.SwayMaximumScale)
			local limit = Config.CarrySwayRadians * layerScale
			local amount = Config.CarrySwayAccelerationScale * layerScale
			local desired=Vector2.new(math.clamp(acceleration.Z*amount,-limit,limit),math.clamp(-acceleration.X*amount,-limit,limit))
			local sway=(item.carrySway or Vector2.zero):Lerp(desired,1-math.exp(-Config.CarrySwayResponse*dt))
			target.CFrame=base*CFrame.Angles(sway.X,0,sway.Y)
			item.carrySway,item.carryVelocity,item.carryUpdated=sway,velocity,now
		end
		if (torso.Position-target.WorldPosition).Magnitude>Config.CarryRecoveryDistance then
			-- 两套客户端装配可能在不同复制帧到达，连续超限才按脱肩处理。
			local since=item.carryErrorSince or now
			item.carryErrorSince=since
			if now-since>=Config.CarryRecoveryGraceSeconds then Carry.Drop(item,torso.Position);return true end
		else item.carryErrorSince=nil end
	end
	return false
end
return Carry
