-- 按部件有向连接解析 R15，保存局部坐标、限位及每步唯一姿态提交记录。
--!strict
local Physics = require(script.Parent.Parent.Shared.PhysicsConfig)
local Adapter = {}
type Drive = Motor6D | AnimationConstraint
export type Joint = {
	name: string, drive: Drive, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame,
	initial: CFrame, initialEnabled: boolean, initialKinematic: boolean?, initialForce: number?, initialTorque: number?, limit: Physics.Joint?,
	base: CFrame, applied: CFrame?, step: number, submissions: number,
}
export type Map = {[string]: Joint}
type Edge = {name: string, parent: string, family: string}
local edges: {[string]: Edge} = {}
local function Edge(child: string, parent: string, family: string, side: string?)
	edges[child] = {name = (side or "") .. family, parent = parent, family = family}
end
Edge("LowerTorso", "HumanoidRootPart", "Root")
Edge("UpperTorso", "LowerTorso", "Waist")
Edge("Head", "UpperTorso", "Neck")
for _, side in {"Left", "Right"} do
	Edge(side.."UpperArm", "UpperTorso", "Shoulder", side)
	Edge(side.."LowerArm", side.."UpperArm", "Elbow", side)
	Edge(side.."Hand", side.."LowerArm", "Wrist", side)
	Edge(side.."UpperLeg", "LowerTorso", "Hip", side)
	Edge(side.."LowerLeg", side.."UpperLeg", "Knee", side)
	Edge(side.."Foot", side.."LowerLeg", "Ankle", side)
end
function Adapter.Map(model: Model): Map
	assert(model.PrimaryPart and model.PrimaryPart.Name == "HumanoidRootPart", "missing HumanoidRootPart primary root")
	local mapped: Map = {}
	local parts: {[string]: BasePart} = {}
	local names: {[string]: boolean} = {}
	for _, node in model:GetDescendants() do
		if node:IsA("BasePart") then
			assert(not parts[node.Name], "duplicate part name "..node.Name)
			parts[node.Name] = node
		elseif node:IsA("Motor6D") or node:IsA("AnimationConstraint") then
			local p0: BasePart?
			local p1: BasePart?
			local c0: CFrame
			local c1: CFrame
			local kinematic: boolean? = nil
			if node:IsA("Motor6D") then
				p0, p1, c0, c1 = node.Part0, node.Part1, node.C0, node.C1
			else
				local a, b = node.Attachment0, node.Attachment1
				assert(a and b and a ~= b, "missing or shared attachment on "..node.Name)
				local first, second = a.Parent, b.Parent
				assert(first and first:IsA("BasePart") and second and second:IsA("BasePart"), "invalid attachment parent on "..node.Name)
				p0, p1, c0, c1 = first, second, a.CFrame, b.CFrame
				kinematic = node.IsKinematic
			end
			assert(p0 and p1 and p0.Parent == model and p1.Parent == model, "external or missing endpoint on "..node.Name)
			local edge = edges[p1.Name]
			assert(edge and edge.parent == p0.Name, "unexpected edge "..p0.Name.." -> "..p1.Name)
			assert(not mapped[edge.name], "duplicate semantic joint "..edge.name)
			assert(not names[node.Name], "duplicate drive name "..node.Name)
			names[node.Name] = true
			mapped[edge.name] = {name=edge.name, drive=node, parent=p0, child=p1, c0=c0, c1=c1,
				limit=Physics.Joints[edge.family], initial=node.Transform, initialEnabled=node.Enabled, initialKinematic=kinematic,
				initialForce=if node:IsA("AnimationConstraint") then node.MaxForce else nil,
				initialTorque=if node:IsA("AnimationConstraint") then node.MaxTorque else nil,
				base=node.Transform, applied=nil, step=-1, submissions=0}
		end
	end
	for _, edge in edges do assert(mapped[edge.name], "missing semantic joint "..edge.name) end
	return mapped
end
function Adapter.IsKinematic(joint: Joint): boolean
	local drive = joint.drive
	return drive.Enabled and (not drive:IsA("AnimationConstraint") or drive.IsKinematic)
end
function Adapter.Read(joint: Joint): CFrame
	return joint.drive.Transform
end
function Adapter.Write(joint: Joint, frame: CFrame)
	local drive = joint.drive
	if drive:IsA("Motor6D") then drive.Transform = frame else drive.Transform = frame end
end
function Adapter.Commit(joint: Joint, base: CFrame, offset: CFrame?, step: number)
	assert(joint.step ~= step, "second pose submission for "..joint.name)
	joint.step, joint.submissions = step, 0
	if not Adapter.IsKinematic(joint) then return end
	joint.base = base
	Adapter.Write(joint, if offset then offset * base else base)
	joint.applied = if offset then joint.drive.Transform else nil
	joint.submissions = 1
end
function Adapter.Restore(joint: Joint)
	if joint.applied and joint.drive.Parent and joint.drive.Transform == joint.applied then Adapter.Write(joint,joint.base) end
	joint.applied = nil
end
return Adapter
