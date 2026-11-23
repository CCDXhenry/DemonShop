-- 搬运模块：无碰撞柔性肩扛、入池与祭坛抛掷、有限惯性释放及资源回收
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Ragdoll = require(script.Parent.Ragdoll)
local NPC = require(script.Parent.NPC)
local Scene = require(script.Parent.Scene)
local Config = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Ground = require(script.Parent.GroundAuthority)
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
	local humanoid = owner and owner.Character and owner.Character:FindFirstChildOfClass("Humanoid")
	local backpack = owner and owner:FindFirstChild("Backpack")
	local club = backpack and backpack:FindFirstChild("Club")
	local restore = if restoreTool == nil then true else restoreTool
	if restore and humanoid and humanoid.Health > 0 and club and club:IsA("Tool") then humanoid:EquipTool(club) end
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
	humanoid:UnequipTools()
	if item.kind == "Body" then
		nextCarryOrder += 1
		item.carryOrder = nextCarryOrder
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
local function AnchorLanded(item: Types.Item, physicsMode: string, motionState: string): ()
	-- 按落地姿态锚定，避免 SetMode("Static") 拉回休息姿态。
	item.poolToss = nil
	item.altarToss = nil
	FreezePose(item, true)
	local model = item.model
	model:SetAttribute("PhysicsMode", physicsMode)
	model:SetAttribute("MotionState", motionState)
	item.motionState = motionState
	item.version += 1
end
local function AnchorPool(item: Types.Item): ()
	AnchorLanded(item, "PoolAnchored", "Pool")
end
local function PlaceInside(item: Types.Item, target: CFrame, contains: (Vector3) -> boolean): ()
	local torso = item.model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") and not contains(torso.Position) then
		item.model:PivotTo(target)
	end
end
function Carry.BeginToss(item: Types.Item, target: CFrame, thrower: Player?, restoreTool: boolean?): boolean
	-- 落点由调用方给定，不读取镜头或角色朝向。飞行由抛掷客户端持有物理所有权。
	-- 没有抛掷者时放到落点并返回 true，由调用方锚定。
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
		AnchorPool(item)
	end
end
function Carry.BeginManualToss(item: Types.Item, origin: Vector3, velocity: Vector3, duration: number, target: CFrame, thrower: Player?, restoreTool: boolean?): boolean
	-- 飞行由抛掷客户端按共享抛物线驱动。没有抛掷者时直接放到落点，由调用方判定入池。
	local character = thrower and thrower.Character
	local rotation = item.model:GetPivot().Rotation
	Carry.Detach(item, restoreTool)
	NPC.StopMotion(item)
	item.location = "Thrown"
	item.streetSlot = false
	item.version += 1
	item.model:SetAttribute("MotionState", "PoolToss")
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
	item.poolToss = {
		kind = "Manual",
		from = CFrame.new(origin) * rotation,
		target = target,
		started = workspace:GetServerTimeNow(),
		owner = thrower.UserId,
		origin = origin,
		velocity = velocity,
		duration = duration,
	}
	item.motionState = "PoolToss"
	return false
end
function Carry.FinishPool(item: Types.Item): ()
	AnchorPool(item)
end
function Carry.FinishGround(item: Types.Item): ()
	item.poolToss = nil
	item.location = "Ground"
	item.motionState = "Down"
	item.model:SetAttribute("MotionState", "Down")
	item.version += 1
end
local function FlightLimit(toss: Types.PoolToss): number
	if toss.duration and (toss.duration > 0 or toss.kind == "Manual") then
		return toss.duration
	end
	return Config.PoolTossSeconds
end
local function NearLanding(item: Types.Item, toss: Types.PoolToss, bed: BasePart): boolean
	local torso = item.model:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then
		return false
	end
	if toss.kind == "Manual" then
		return torso.Position.Y <= toss.target.Position.Y + Config.ManualThrow.LandingClearanceStuds
	end
	return bed.CFrame:PointToObjectSpace(torso.Position).Y <= bed.Size.Y * 0.5 + 3
end
local function AdvanceToss(item: Types.Item, now: number, bed: BasePart, contains: (Vector3) -> boolean, anchor: (Types.Item) -> (), settledMotion: string, onSettled: ((Types.Item) -> ())?): boolean
	local toss = item.poolToss
	if not toss or item.model.Parent == nil then
		item.poolToss = nil
		return false
	end
	local flight = FlightLimit(toss)
	local flightDone = now >= toss.started + flight
	local player = Players:GetPlayerByUserId(toss.owner)
	if not player then
		item.model:PivotTo(toss.target)
		if onSettled then
			onSettled(item)
		else
			PlaceInside(item, toss.target, contains)
			anchor(item)
		end
		return true
	end
	if not flightDone then return false end
	if not toss.collision then
		toss.collision = true
		SetFlightCollision(item.model, true)
		item.motionState = settledMotion
		item.model:SetAttribute("MotionState", settledMotion)
	end
	local nearFloor = NearLanding(item, toss, bed)
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
			PlaceInside(item, toss.target, contains)
			anchor(item)
		end
		return true
	end
	return false
end
function Carry.AdvancePoolToss(item: Types.Item, now: number): boolean
	return AdvanceToss(item, now, Scene.PoolFloor, Scene.PoolContains, AnchorPool, "Pool")
end
function Carry.AdvanceManualToss(item: Types.Item, now: number, onSettled: (Types.Item) -> ()): boolean
	return AdvanceToss(item, now, Scene.PoolFloor, Scene.PoolContainsStrict, AnchorPool, "Thrown", onSettled)
end
local function AltarRestOffset(part: BasePart, model: Model, pivot: CFrame): CFrame
	if part == model.PrimaryPart then return CFrame.identity end
	local rest = part:GetAttribute("RestPose")
	return if typeof(rest) == "CFrame" then rest else pivot:ToObjectSpace(part.CFrame)
end
local function AltarRestPose(model: Model, pivot: CFrame, surface: CFrame): CFrame
	-- 由整副白膜沿坛面法线的实际厚度确定落座高度。
	local up = Scene.AltarRest.CFrame.UpVector
	local bottom = math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local pose = surface.Rotation * AltarRestOffset(part, model, pivot)
			local half = part.Size * 0.5
			local extent = math.abs(pose.RightVector:Dot(up)) * half.X
				+ math.abs(pose.UpVector:Dot(up)) * half.Y
				+ math.abs(pose.LookVector:Dot(up)) * half.Z
			bottom = math.min(bottom, pose.Position:Dot(up) - extent)
		end
	end
	return surface - up * (if bottom < math.huge then bottom else 0)
end
function Carry.BeginAltarToss(item: Types.Item, layer: number, fromTable: boolean, now: number, restoreTool: boolean?): ()
	local from = item.model:GetPivot()
	Carry.Detach(item, restoreTool)
	FreezePose(item, false)
	local flightStarts = now + (if fromTable then Altar.LiftSeconds else 0)
	local landSeconds = Altar.LandSeconds or 0.32
	local surface = Scene.AltarPilePose(item.id, layer)
	if item.paintFlipped then
		surface = surface * CFrame.Angles(0, math.pi, 0)
	end
	item.altarToss = {
		from = from,
		rest = AltarRestPose(item.model, from, surface),
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
	AnchorLanded(item, "AltarAnchored", "Altar")
	return true
end
function Carry.RecoverPool(item: Types.Item): ()
	item.poolToss = nil
	NPC.StopMotion(item)
	local target = Scene.PoolDropTarget(random)
	item.model:PivotTo(target)
	AnchorPool(item)
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
