-- 用街区支撑面和躯干扫掠决定地面交互根，保留 R15 供原生提示与旧版搬运使用。
--!strict
local PhysicsService = game:GetService("PhysicsService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Physics = require(Shared.PhysicsConfig)
local Types = require(Shared.GameTypes)
local Scene = require(script.Parent.Scene)
local Ragdoll = require(script.Parent.Ragdoll)
local Ground = {}
local GroundGap = 0.025
local ThrowSupportTolerance = 0.35
local ThrowBacktrackStep = 0.75
local ThrowSupportDepth = Physics.ManualThrow.WallFloorProbeStuds
function Ground.Init()
	for _,group in {Physics.FallGroup, Physics.SceneryGroup} do
		if not PhysicsService:IsCollisionGroupRegistered(group) then PhysicsService:RegisterCollisionGroup(group) end
	end
	for _,group in PhysicsService:GetRegisteredCollisionGroups() do
		local name = group.name
		PhysicsService:CollisionGroupSetCollidable(Physics.SceneryGroup,name,PhysicsService:CollisionGroupsAreCollidable("Default",name))
		PhysicsService:CollisionGroupSetCollidable(Physics.FallGroup,name,false)
	end
	PhysicsService:CollisionGroupSetCollidable(Physics.FallGroup,Physics.SceneryGroup,true)
	for _,part in Scene.District:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored and part.CanCollide and part.CollisionGroup=="Default" then
			part.CollisionGroup=Physics.SceneryGroup
		end
	end
end
local function ProjectedRadius(frame: CFrame, size: Vector3, axis: Vector3): number
	local half = size * 0.5
	return math.abs(frame.RightVector:Dot(axis)) * half.X + math.abs(frame.UpVector:Dot(axis)) * half.Y
		+ math.abs(frame.LookVector:Dot(axis)) * half.Z
end

local function RestParts(model: Model): { { part: BasePart, frame: CFrame } }
	local parts = {}
	for _, part in model:GetChildren() do
		local rest = part:GetAttribute("RestPose")
		if part:IsA("BasePart") and part ~= model.PrimaryPart and typeof(rest) == "CFrame" then
			table.insert(parts, { part = part, frame = rest })
		end
	end
	return parts
end

function Ground.SetRoot(model: Model, target: CFrame): ()
	local root = assert(model.PrimaryPart)
	Ragdoll.SetMode(model, "Static")
	model:PivotTo(target)
	-- Motor6D 连接的模型只需要锚定根，AnimationConstraint 模型逐件锚定。
	local rigid = model:FindFirstChildWhichIsA("AnimationConstraint", true) == nil
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local boundary = part.Name == "UpperTorso" or part.Name == "LowerTorso"
			part.CanCollide, part.CanQuery = boundary, boundary
			if rigid then part.Anchored = part == root end
		end
	end
	model:SetAttribute("PhysicsMode", "GroundRoot")
end

function Ground.ThrowRotation(direction: Vector3): CFrame
	return CFrame.fromAxisAngle(Vector3.yAxis:Cross(direction), math.rad(86))
		* CFrame.lookAt(Vector3.zero, direction)
end

function Ground.ThrowBounds(model: Model): (Vector3, Vector3)
	local low, high = Vector3.zero, Vector3.zero
	for _, entry in RestParts(model) do
		local frame, size = entry.frame, entry.part.Size
		local extent = Vector3.new(ProjectedRadius(frame, size, Vector3.xAxis),
			ProjectedRadius(frame, size, Vector3.yAxis), ProjectedRadius(frame, size, Vector3.zAxis))
		local cornerLow, cornerHigh = frame.Position - extent, frame.Position + extent
		low = low:Min(cornerLow)
		high = high:Max(cornerHigh)
	end
	return (low + high) * 0.5, high - low
end

function Ground.FindThrowPose(model: Model, landing: Vector3, launch: CFrame, shoulder: Vector3): (CFrame?, Vector3?)
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Include
	cast.FilterDescendantsInstances = { Scene.District, workspace.Terrain }
	cast.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = cast.FilterDescendantsInstances
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	local parts = RestParts(model)
	if #parts == 0 then return nil, nil end

	-- 精确检测场景的碰撞几何，避免用建筑 MeshPart 的外包围盒挡住室内落点。
	local probe = Instance.new("Part")
	probe.Name = "ThrowLandingProbe"
	probe.Anchored, probe.CanCollide, probe.CanTouch, probe.CanQuery = true, false, false, false
	probe.Transparency = 1
	probe.Parent = workspace
	local function Overlaps(frame: CFrame, size: Vector3): boolean
		probe.Size, probe.CFrame = size, frame
		return #workspace:GetPartsInPart(probe, overlap) > 0
	end
	local function FindAt(point: Vector3): (CFrame?, Vector3?)
		local support = workspace:Raycast(point + Vector3.yAxis * GroundGap, -Vector3.yAxis * ThrowSupportDepth, cast)
		if not support or support.Normal.Y <= 0.65 then return nil, nil end
		local normal = support.Normal
		local tilted = CFrame.fromRotationBetweenVectors(Vector3.yAxis, normal) * launch.Rotation
		local lowest = 0
		for _, entry in parts do
			local frame = tilted * entry.frame
			lowest = math.min(lowest, frame.Position:Dot(normal) - ProjectedRadius(frame, entry.part.Size, normal))
		end
		local target = CFrame.new(support.Position + normal * (GroundGap - lowest)) * tilted
		for _, entry in parts do
			local frame = target * entry.frame
			if Overlaps(frame, entry.part.Size) then return nil, nil end
			if entry.part.Name == "UpperTorso" or entry.part.Name == "LowerTorso" then
				local torsoSupport = workspace:Raycast(frame.Position, -normal * ThrowSupportDepth, cast)
				if not torsoSupport or torsoSupport.Normal.Y <= 0.65
					or math.abs((torsoSupport.Position - support.Position):Dot(normal)) > ThrowSupportTolerance then
					return nil, nil
				end
			end
		end
		return target, support.Position
	end
	local origin = launch.Position
	-- Blockcast 不返回起点已经重叠的几何，出手位置和肩部到出手位置须单独验证。
	if workspace:Raycast(shoulder, origin - shoulder, cast) then
		probe:Destroy()
		return nil, nil
	end
	for _, entry in parts do
		if Overlaps(launch * entry.frame, entry.part.Size) then
			probe:Destroy()
			return nil, nil
		end
	end
	local span = Vector3.new(origin.X - landing.X, 0, origin.Z - landing.Z).Magnitude
	local steps = math.max(1, math.ceil(span / ThrowBacktrackStep))
	local target, contact
	for step = 0, steps do
		target, contact = FindAt(landing:Lerp(origin, step / steps))
		if target then break end
	end
	probe:Destroy()
	return target, contact
end

function Ground.Place(item: Types.Item, direction: Vector3, velocity: Vector3, groundTravel: number?)
	local model=item.model
	local root=assert(model.PrimaryPart)
	local upper=model:FindFirstChild("UpperTorso") :: BasePart
	local origin=root.CFrame
	local forward=Vector3.new(direction.X,0,direction.Z)
	if forward.Magnitude<0.01 then forward=Vector3.zAxis else forward=forward.Unit end
	local upright=Vector3.new(origin.LookVector.X,0,origin.LookVector.Z)
	if upright.Magnitude<0.01 then upright=forward end
	local rotation=CFrame.fromAxisAngle(Vector3.yAxis:Cross(forward),math.rad(86))*CFrame.lookAt(Vector3.zero,upright)
	local cast=RaycastParams.new()
	cast.FilterType=Enum.RaycastFilterType.Include
	cast.FilterDescendantsInstances={Scene.District,workspace.Terrain}
	cast.RespectCanCollide=true
	local travel=groundTravel or Physics.GroundTravel
	local obstacle=if travel > 0 then workspace:Blockcast(upper.CFrame,upper.Size*.95,forward*travel,cast) else nil
	if obstacle then travel=math.max(0,obstacle.Distance-.08) end
	local point=origin.Position+forward*travel
	local function Support(at: Vector3): RaycastResult?
		local hit=workspace:Raycast(at+Vector3.yAxis*1.5,-Vector3.yAxis*32,cast)
		return if hit and hit.Normal.Y>.65 then hit else nil
	end
	local support=Support(point) or Support(origin.Position) or Support(Scene.PoolPickup.Position)
	local normal=if support then support.Normal else Vector3.yAxis
	local floor=if support then support.Position else Scene.PoolPickup.Position
	local supportRotation=CFrame.fromRotationBetweenVectors(Vector3.yAxis,normal)*rotation
	local lowest=0
	for _,part in model:GetChildren() do
		local rest=part:GetAttribute("RestPose")
		if part:IsA("BasePart") and (part==upper or part.Name=="LowerTorso") and typeof(rest)=="CFrame" then
			local frame=supportRotation*rest
			lowest=math.min(lowest,frame.Position:Dot(normal)-ProjectedRadius(frame,part.Size,normal))
		end
	end
	local target=CFrame.new(floor+normal*(GroundGap-lowest))*supportRotation
	local speed=velocity.Magnitude
	item.fall={target=target,started=workspace:GetServerTimeNow(),velocity=if speed>Physics.DropMaximumSpeed then velocity.Unit*Physics.DropMaximumSpeed else velocity}
	Ground.SetRoot(model,target)
end
return Ground
