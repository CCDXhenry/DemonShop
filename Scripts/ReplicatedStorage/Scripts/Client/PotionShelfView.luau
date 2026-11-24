-- 药水架客户端陈列：按权威槽位摆瓶，播放落位与整批领取动画
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local View = {}
View.__index = View

local DepositSeconds = 0.20
local DepositHeight = 0.42
local CollectSeconds = 0.24
local CollectLift = 0.25

type Bottle = {
	model: Model,
	pose: CFrame,
	parts: { BasePart },
	lights: { [PointLight]: number },
}
type Departure = { bottle: Bottle, from: CFrame, target: CFrame, started: number }
export type View = typeof(setmetatable({} :: {
	folder: Folder,
	pickup: Vector3,
	bottles: { [string]: Bottle },
	entering: { [string]: number },
	departing: { [string]: Departure },
}, View))

function View.new(pickup: Vector3, folderName: string?): View
	local folder = Instance.new("Folder")
	folder.Name = folderName or "PotionShelfPresentation"
	folder.Parent = workspace
	return setmetatable({
		folder = folder,
		pickup = pickup,
		bottles = {},
		entering = {},
		departing = {},
	}, View)
end

local function CreateBottle(id: string, pose: CFrame, initialPose: CFrame, parent: Folder): Bottle
	local model = ReplicatedStorage.Models.Potion:Clone() :: Model
	local parts: { BasePart } = {}
	local lights: { [PointLight]: number } = {}
	model:SetAttribute("ItemId", id)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			table.insert(parts, child)
		elseif child:IsA("PointLight") then
			lights[child] = child.Brightness
		end
	end
	model:PivotTo(initialPose)
	model.Parent = parent
	return { model = model, pose = pose, parts = parts, lights = lights }
end

function View.Apply(self: View, slots: { [string]: CFrame }, animate: boolean, now: number): ()
	if not animate then
		for _, departure in self.departing do
			departure.bottle.model:Destroy()
		end
		table.clear(self.departing)
		for id in self.entering do
			local bottle = self.bottles[id]
			bottle.model:PivotTo(bottle.pose)
		end
		table.clear(self.entering)
	end

	for id, bottle in self.bottles do
		if slots[id] then continue end
		self.bottles[id] = nil
		self.entering[id] = nil
		if animate then
			local from = bottle.model:GetPivot()
			-- 保持当前层的高度收拢，避免下层瓶子穿过上层隔板。
			local target = Vector3.new(self.pickup.X, from.Position.Y + CollectLift, self.pickup.Z)
			self.departing[id] = { bottle = bottle, from = from, target = from.Rotation + target, started = now }
		else
			bottle.model:Destroy()
		end
	end

	for id, pose in slots do
		local bottle = self.bottles[id]
		if bottle and bottle.pose == pose then continue end
		for departingId, departure in self.departing do
			if departingId == id or departure.bottle.pose == pose then
				departure.bottle.model:Destroy()
				self.departing[departingId] = nil
			end
		end
		if bottle then
			self.entering[id] = nil
			bottle.pose = pose
			bottle.model:PivotTo(pose)
		else
			local initialPose = if animate then pose + Vector3.yAxis * DepositHeight else pose
			self.bottles[id] = CreateBottle(id, pose, initialPose, self.folder)
			if animate then
				self.entering[id] = now
			end
		end
	end
end

function View.Step(self: View, now: number): ()
	for id, started in self.entering do
		local bottle = self.bottles[id]
		local remaining = 1 - math.clamp((now - started) / DepositSeconds, 0, 1)
		bottle.model:PivotTo(bottle.pose + Vector3.yAxis * (DepositHeight * remaining ^ 3))
		if remaining == 0 then
			self.entering[id] = nil
		end
	end
	for id, departure in self.departing do
		local progress = math.clamp((now - departure.started) / CollectSeconds, 0, 1)
		local bottle = departure.bottle
		if progress == 1 then
			bottle.model:Destroy()
			self.departing[id] = nil
		else
			bottle.model:PivotTo(departure.from:Lerp(departure.target, 1 - (1 - progress) ^ 2))
			for _, part in bottle.parts do
				part.LocalTransparencyModifier = progress
			end
			for light, brightness in bottle.lights do
				light.Brightness = brightness * (1 - progress)
			end
		end
	end
end

function View.Destroy(self: View): ()
	self.folder:Destroy()
	table.clear(self.bottles)
	table.clear(self.entering)
	table.clear(self.departing)
end

return View
