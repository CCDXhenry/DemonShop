-- 祭坛白膜演出：按服务器时间上浮，四肢向地面垂落，并计算笔迹亮度与淡出
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local View = {}
View.__index = View
type Limb = { name: string, parent: string }
export type Sample = { hang: number, rise: number, brightness: number, fade: number }
export type View = typeof(setmetatable({} :: {
	id: string?,
	model: Model?,
	parts: { [string]: BasePart },
	relative: { [string]: CFrame },
	pivot: { [string]: Vector3 },
	rootRest: CFrame,
}, View))
local LimbOrder: { Limb } = {
	{ name = "LowerTorso", parent = "HumanoidRootPart" },
	{ name = "UpperTorso", parent = "LowerTorso" },
	{ name = "Head", parent = "UpperTorso" },
	{ name = "LeftUpperArm", parent = "UpperTorso" },
	{ name = "LeftLowerArm", parent = "LeftUpperArm" },
	{ name = "LeftHand", parent = "LeftLowerArm" },
	{ name = "RightUpperArm", parent = "UpperTorso" },
	{ name = "RightLowerArm", parent = "RightUpperArm" },
	{ name = "RightHand", parent = "RightLowerArm" },
	{ name = "LeftUpperLeg", parent = "LowerTorso" },
	{ name = "LeftLowerLeg", parent = "LeftUpperLeg" },
	{ name = "LeftFoot", parent = "LeftLowerLeg" },
	{ name = "RightUpperLeg", parent = "LowerTorso" },
	{ name = "RightLowerLeg", parent = "RightUpperLeg" },
	{ name = "RightFoot", parent = "RightLowerLeg" },
}
local HangPart: { [string]: boolean } = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}
local function JointPivot(part: BasePart): Vector3
	for _, child in part:GetChildren() do
		if child:IsA("Motor6D") and child.Part1 == part then
			return child.C1.Position
		end
	end
	return Vector3.zero
end
local function Sample(now: number, altarEnds: number, shelfFull: boolean): Sample
	local charge = math.max(Config.ConversionSeconds - Config.AltarClimaxSeconds, 0.001)
	local elapsed = now - (altarEnds - Config.ConversionSeconds)
	local progress = math.clamp(elapsed / charge, 0, 1)
	local hang = progress * progress * (3 - 2 * progress)
	-- 超过淡出窗口仍留在祭坛上时，身体处于架满等待，保持可见。
	local overtime = now - altarEnds
	local fade = 0
	if not shelfFull and overtime <= Config.AltarClimaxSeconds then
		fade = math.clamp((elapsed - charge) / Config.AltarClimaxSeconds, 0, 1)
	end
	return { hang = hang, rise = hang * Config.AltarRiseStuds, brightness = progress, fade = fade }
end
local function RotationBetween(from: Vector3, to: Vector3): CFrame
	local source = if from.Magnitude > 1e-4 then from.Unit else Vector3.yAxis
	local target = if to.Magnitude > 1e-4 then to.Unit else Vector3.yAxis
	local dot = math.clamp(source:Dot(target), -1, 1)
	if dot > 0.9999 then
		return CFrame.identity
	end
	local axis = source:Cross(target)
	if axis.Magnitude < 1e-4 then
		axis = source:Cross(Vector3.xAxis)
		if axis.Magnitude < 1e-4 then
			axis = source:Cross(Vector3.zAxis)
		end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end
local function HangRelative(parent: BasePart, relative: CFrame, pivot: Vector3): CFrame
	local joint = relative * pivot
	local restUp = relative:VectorToWorldSpace(Vector3.yAxis)
	local worldUp = parent.CFrame:VectorToObjectSpace(Vector3.yAxis)
	local rotation = RotationBetween(restUp, worldUp) * relative.Rotation
	return CFrame.new(joint) * rotation * CFrame.new(-pivot)
end
function View.new(): View
	return setmetatable({
		id = nil,
		model = nil,
		parts = {},
		relative = {},
		pivot = {},
		rootRest = CFrame.identity,
	}, View)
end
function View.Clear(self: View): ()
	self.id, self.model = nil, nil
	table.clear(self.parts)
	table.clear(self.relative)
	table.clear(self.pivot)
end
local function Capture(self: View, model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	table.clear(self.parts)
	table.clear(self.relative)
	table.clear(self.pivot)
	self.model = model
	self.rootRest = root.CFrame
	self.parts.HumanoidRootPart = root
	for _, limb in LimbOrder do
		local part = model:FindFirstChild(limb.name)
		local parent = self.parts[limb.parent]
		if part and part:IsA("BasePart") and parent then
			self.parts[limb.name] = part
			self.relative[limb.name] = parent.CFrame:ToObjectSpace(part.CFrame)
			self.pivot[limb.name] = JointPivot(part)
		end
	end
	return true
end
local function Pose(self: View, hang: number, rise: number): ()
	local root = self.parts.HumanoidRootPart
	if not root then
		return
	end
	root.CFrame = self.rootRest + Vector3.yAxis * rise
	for _, limb in LimbOrder do
		local part = self.parts[limb.name]
		local parent = self.parts[limb.parent]
		local relative = self.relative[limb.name]
		if part and parent and relative then
			local posed = relative
			if HangPart[limb.name] and hang > 0 then
				posed = relative:Lerp(HangRelative(parent, relative, self.pivot[limb.name]), hang)
			end
			part.CFrame = parent.CFrame * posed
		end
	end
end
function View.Update(self: View, id: string, model: Model?, now: number, altarEnds: number, shelfFull: boolean): Sample?
	if not model or not model.Parent or model.Name ~= "LocalAltarBody" then
		return nil
	end
	if self.model ~= model and not Capture(self, model) then
		return nil
	end
	self.id = id
	local sample = Sample(now, altarEnds, shelfFull)
	Pose(self, sample.hang, sample.rise)
	for _, part in self.parts do
		part.LocalTransparencyModifier = sample.fade
	end
	return sample
end
return View
