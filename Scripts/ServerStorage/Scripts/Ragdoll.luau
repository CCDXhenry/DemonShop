-- R15 布娃娃模块：关节限位、自碰撞隔离、静态展示与肩扛物理切换
--!strict
local PhysicsService = game:GetService("PhysicsService")
local Config = require(game:GetService("ReplicatedStorage").Scripts.Shared.PhysicsConfig)
local Ragdoll = {}
local Group = Config.BodyGroup
function Ragdoll.Init(): ()
	if not PhysicsService:IsCollisionGroupRegistered(Group) then
		PhysicsService:RegisterCollisionGroup(Group)
	end
	PhysicsService:CollisionGroupSetCollidable(Group, Group, true)
end
function Ragdoll.Setup(model: Model): ()
	if model:FindFirstChild("RagdollConstraints") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "R15 Humanoid missing")
	humanoid.BreakJointsOnDeath, humanoid.RequiresNeck = false, false
	local constraints = Instance.new("Folder")
	constraints.Name, constraints.Parent = "RagdollConstraints", model
	for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then
			v.CollisionGroup = Group
			if model.PrimaryPart then
				v:SetAttribute("RestPose", model.PrimaryPart.CFrame:ToObjectSpace(v.CFrame))
			end
		end
		if (v:IsA("Motor6D") or v:IsA("AnimationConstraint")) and v.Name ~= "Root" and v.Name ~= "RootJoint" then
			local a: Attachment? = nil
			local b: Attachment? = nil
			local part0: BasePart? = nil
			local part1: BasePart? = nil
			if v:IsA("Motor6D") and v.Part0 and v.Part1 then
				part0, part1 = v.Part0, v.Part1
				local createdA, createdB = Instance.new("Attachment"), Instance.new("Attachment")
				createdA.Name, createdB.Name, createdA.CFrame, createdB.CFrame = "RagdollA", "RagdollB", v.C0, v.C1
				createdA.Parent, createdB.Parent = part0, part1
				a, b = createdA, createdB
			elseif v:IsA("AnimationConstraint") then
				a, b = v.Attachment0, v.Attachment1
				local parent0, parent1 = if a then a.Parent else nil, if b then b.Parent else nil
				part0 = if parent0 and parent0:IsA("BasePart") then parent0 else nil
				part1 = if parent1 and parent1:IsA("BasePart") then parent1 else nil
			end
			if not a or not b or not part0 or not part1 then continue end
			-- AJU 已创建安全关节，复用其附件与约束，不叠加第二套球形关节。
			local existing: BallSocketConstraint? = nil
			for _, candidate in model:GetDescendants() do
				if candidate:IsA("BallSocketConstraint") and candidate.Attachment0 == a and candidate.Attachment1 == b then existing = candidate; break end
			end
			local joint = existing or Instance.new("BallSocketConstraint")
			joint.Name, joint.Attachment0, joint.Attachment1 = v.Name, a, b
			joint.LimitsEnabled, joint.TwistLimitsEnabled = true, true
			local settings = Config.Joints.Shoulder
			for name, candidate in Config.Joints do
				if string.find(v.Name, name, 1, true) then
					settings = candidate
					break
				end
			end
			joint.UpperAngle = settings.cone
			joint.TwistLowerAngle, joint.TwistUpperAngle = settings.lower, settings.upper
			joint.MaxFrictionTorque, joint.Restitution, joint.Enabled, joint.Parent = settings.friction, 0, false, constraints
			-- 只隔离相邻关节，保留非相邻肢体及不同身体之间的接触。
			local contact = Instance.new("NoCollisionConstraint")
			contact.Name, contact.Part0, contact.Part1, contact.Parent = v.Name .. "Contact", part0, part1, constraints
		end
	end
end
function Ragdoll.SetMode(model: Model, mode: string, owner: Player?): ()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid)
	local base = if model.PrimaryPart then model.PrimaryPart.CFrame else model:GetPivot()
	model:SetAttribute("PhysicsMode", mode)
	local loose, static = mode == "Loose" or mode == "Carried", mode == "Static"
	-- Humanoid 的状态机每帧重写躯干碰撞；布娃娃状态由本模块完整接管。
	humanoid.EvaluateStateMachine = mode == "Walking"
	humanoid.PlatformStand, humanoid.AutoRotate = loose or static, not (loose or static)
	humanoid.WalkSpeed = if mode == "Walking" then 7 else 0
	if loose then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	local descendants = model:GetDescendants()
	if not static then
		for _, part in descendants do
			if part:IsA("BasePart") then part.Anchored = false end
		end
	end
	for _, v in descendants do
		if v:IsA("Motor6D") then
			v.Enabled = not loose or v.Name == "Root" or v.Name == "RootJoint"
			if static then
				v.Transform = CFrame.identity
			end
		elseif v:IsA("AnimationConstraint") then
			local rootJoint = v.Name == "Root" or v.Name == "RootJoint"
			v.Enabled = true
			v.IsKinematic = not loose or rootJoint
			v.MaxTorque = if loose and not rootJoint then 0 else 3000
			v.MaxForce = 0
			if static then v.Transform = CFrame.identity end
		elseif v:IsA("BallSocketConstraint") then
			v.Enabled = loose
			local settings = Config.Joints.Shoulder
			for name, candidate in Config.Joints do
				if string.find(v.Name, name, 1, true) then settings = candidate; break end
			end
			v.UpperAngle = settings.cone * (if mode == "Carried" then Config.CarrySwingScale else 1)
		elseif v:IsA("BasePart") then
			if static then
				v.Anchored = true
				local rest = v:GetAttribute("RestPose")
				if typeof(rest) == "CFrame" then
					v.CFrame = base * rest
				end
			end
			local walkingContact = mode ~= "Walking" or v.Name == "Head" or v.Name == "UpperTorso" or v.Name == "LowerTorso"
			v.CanCollide = walkingContact and not static and mode ~= "Carried" and v.Name ~= "HumanoidRootPart"
			v.CanTouch = not static and mode ~= "Carried" and v.Name ~= "HumanoidRootPart"
			v.CanQuery = v.Name ~= "HumanoidRootPart" and v:GetAttribute("Paintable")==true
			v.Massless = mode == "Carried"
			-- 击晕保留行走瞬间的有限速度；静态和搬运切换清掉旧动量。
			if mode ~= "Loose" then
				v.AssemblyLinearVelocity, v.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			end
		end
	end
	if not static then
		-- 布娃娃的刚性装配在全部解锚并切换关节后才确定。
		local assigned: { [BasePart]: boolean } = {}
		for _, part in descendants do
			local root = if part:IsA("BasePart") then part.AssemblyRootPart else nil
			if root and not assigned[root] then
				assigned[root] = true
				local canSet, reason = root:CanSetNetworkOwnership()
				if canSet then
					root:SetNetworkOwner(owner)
				elseif owner then
					warn("Cannot transfer ragdoll ownership:", root:GetFullName(), reason)
				end
			end
		end
	end
end
function Ragdoll.LimitVelocity(model: Model): ()
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and not part.Anchored then
			local linear, angular = part.AssemblyLinearVelocity, part.AssemblyAngularVelocity
			if linear.Magnitude > Config.MaximumLinearSpeed then
				part.AssemblyLinearVelocity = linear.Unit * Config.MaximumLinearSpeed
			end
			if angular.Magnitude > Config.MaximumAngularSpeed then
				part.AssemblyAngularVelocity = angular.Unit * Config.MaximumAngularSpeed
			end
		end
	end
end
return Ragdoll
