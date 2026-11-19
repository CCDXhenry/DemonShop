-- 用街区支撑面和躯干扫掠决定地面交互根，保留 R15 供原生提示与旧版搬运使用。
--!strict
local PhysicsService = game:GetService("PhysicsService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Physics = require(Shared.PhysicsConfig)
local Types = require(Shared.GameTypes)
local Scene = require(script.Parent.Scene)
local Ragdoll = require(script.Parent.Ragdoll)
local Ground = {}
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
function Ground.Place(item: Types.Item, direction: Vector3, velocity: Vector3)
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
	local travel=Physics.GroundTravel
	local obstacle=workspace:Blockcast(upper.CFrame,upper.Size*.95,forward*travel,cast)
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
			local half=part.Size*.5
			local radius=math.abs(frame.RightVector:Dot(normal))*half.X+math.abs(frame.UpVector:Dot(normal))*half.Y+math.abs(frame.LookVector:Dot(normal))*half.Z
			lowest=math.min(lowest,frame.Position:Dot(normal)-radius)
		end
	end
	local target=CFrame.new(floor+normal*(.025-lowest))*supportRotation
	local speed=velocity.Magnitude
	item.fall={target=target,started=workspace:GetServerTimeNow(),velocity=if speed>Physics.DropMaximumSpeed then velocity.Unit*Physics.DropMaximumSpeed else velocity}
	Ragdoll.SetMode(model,"Static")
	model:PivotTo(target)
	-- Motor6D 把全身刚接到唯一锚定根，地面只保留上下躯干的查询与阻挡。
	-- AnimationConstraint 的连接类型不同，沿用逐件锚定的兼容路径。
	local rigid=model:FindFirstChildWhichIsA("AnimationConstraint",true)==nil
	for _,part in model:GetChildren() do
		if part:IsA("BasePart") then
			local boundary=part==upper or part.Name=="LowerTorso"
			part.CanCollide,part.CanQuery=boundary,boundary
			if rigid then part.Anchored=part==root end
		end
	end
	model:SetAttribute("PhysicsMode","GroundRoot")
end
return Ground
