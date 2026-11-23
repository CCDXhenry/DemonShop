-- 场景契约：静态锚点、街道路面采样、工位放置、存放池边界与安全地面回收
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Physics = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local ThrowArc = require(ReplicatedStorage.Scripts.Shared.ThrowArc)
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local PaintRotation = require(ReplicatedStorage.Scripts.Shared.PaintRotation)
local Scene = {}
local district = workspace:WaitForChild("NeonContractDistrict")
local pool = district:WaitForChild("SoulHoldingPool")
local PointRowBand = 0.5 -- 同一排点位的高度差上限，studs
local ShelfPivotOffset = -0.35 -- 相对符文托位下调瓶身枢轴，studs
local ShelfSlotOffsets = {
	Vector3.new(0, ShelfPivotOffset, 0.85),
	Vector3.new(-1.20, ShelfPivotOffset, 0.85),
	Vector3.new(1.20, ShelfPivotOffset, 0.85),
	Vector3.new(0.45, ShelfPivotOffset, -0.35),
	Vector3.new(-0.75, ShelfPivotOffset, -0.35),
	Vector3.new(1.65, ShelfPivotOffset, -0.35),
}
local function Part(root: Instance, name: string): BasePart
	local p = root:WaitForChild(name)
	assert(p:IsA("BasePart"))
	return p
end
local function TopThenLeft(a: BasePart, b: BasePart): boolean
	if math.abs(a.Position.Y - b.Position.Y) > PointRowBand then
		return a.Position.Y > b.Position.Y
	end
	return a.Position.X < b.Position.X
end
Scene.District = district
Scene.Deck = Part(district:WaitForChild("deck"):WaitForChild("Generated"):WaitForChild("Street"):WaitForChild("Raised Street Deck With Stair Void"), "Box_005")
Scene.PoolDrop = Part(pool, "DropPointAnchor")
Scene.PoolPickup = Part(pool, "PickupPointAnchor")
Scene.PoolFloor = Part(pool, "PoolFloor")
Scene.Table = Part(district:WaitForChild("RuneBodyTable"), "BodyPlacementAnchor")
Scene.TableInteract = Part(district:WaitForChild("RuneBodyTable"), "TransferStartAnchor")
Scene.Altar = Part(district:WaitForChild("SoulConversionAltar"), "BodyArrivalAnchor")
Scene.AltarRest = Part(district:WaitForChild("SoulConversionAltar"), "BodyRest")
local display = district:WaitForChild("SoulCrystalDisplay")
Scene.Shelf = Part(display, "StockPickupAnchor")
local potionPointFolder = display:WaitForChild("PotionPoints")
local potionPoints: { BasePart } = {}
for _, child in potionPointFolder:GetChildren() do
	if child:IsA("BasePart") then
		table.insert(potionPoints, child)
	end
end
table.sort(potionPoints, TopThenLeft)
assert(#potionPoints > 0, "SoulCrystalDisplay.PotionPoints is empty")
Scene.Spawn = Part(district, "StreetSpawn")
local sigil = Part(district, "SummoningSubmitAnchor")
Scene.SigilPosition = sigil.Position
local function PromptRange(anchor: BasePart): number
	local prompt = anchor:FindFirstChild("WorldInteractionPrompt")
	if prompt and prompt:IsA("ProximityPrompt") and prompt.MaxActivationDistance > 0 then
		return prompt.MaxActivationDistance
	end
	return Config.InteractionRange
end
local stationRanges: { [string]: number } = {
	Pool = PromptRange(Scene.PoolPickup),
	Table = PromptRange(Scene.TableInteract),
	Altar = PromptRange(Scene.Altar),
	Shelf = PromptRange(Scene.Shelf),
	Sigil = PromptRange(sigil),
}
Scene.StationRanges = stationRanges
function Scene.StationRange(target: string): number
	local range = Scene.StationRanges[target]
	if typeof(range) == "number" and range > 0 then
		return range
	end
	return Config.InteractionRange
end
local function Unit(text: string, salt: number): number
	local value = salt
	for index = 1, #text do
		value = (value * 33 + string.byte(text, index)) % 1000003
	end
	return value / 1000003
end
function Scene.TablePose(): CFrame
	return PaintRotation.TablePose(Scene.Table.Position)
end
function Scene.CameraPose(): CFrame
	return PaintRotation.CameraPose(Scene.Table.Position)
end
function Scene.AltarPilePose(id: string, layer: number): CFrame
	local rest = Scene.AltarRest
	local x = (Unit(id, 1) - 0.5) * 2 * math.clamp(rest.Size.X / 2 - 1.5, 0, Config.AltarPileSpread)
	local z = (Unit(id, 4) - 0.5) * 2 * math.clamp(rest.Size.Z / 2 - 1.2, 0, Config.AltarPileSpread * 0.45)
	local yaw = -math.pi / 2 + (Unit(id, 2) - 0.5) * math.pi / 4
	local pitch = (Unit(id, 3) - 0.5) * 2 * Config.AltarPilePitch
	local height = rest.Size.Y / 2 + layer * Config.AltarPileStep
	return rest.CFrame * CFrame.new(x, height, z)
		* CFrame.Angles(0, yaw, 0) * CFrame.Angles(Config.PaintLiePitch + pitch, 0, 0)
end
function Scene.PoolPose(slot: number): CFrame
	return CFrame.new(Scene.PoolPickup.Position + Vector3.new(((slot - 1) % 4 - 1.5) * 4, 1.7, -5 - math.floor((slot - 1) / 4) * 4))
		* CFrame.Angles(math.pi / 2, 0, 0)
end
function Scene.PoolDropTarget(random: Random): CFrame
	local floor = Scene.PoolFloor
	local inset = math.min(Physics.PoolInset, floor.Size.X * 0.5, floor.Size.Z * 0.5)
	local x = random:NextNumber(-floor.Size.X * 0.5 + inset, floor.Size.X * 0.5 - inset)
	local z = random:NextNumber(-floor.Size.Z * 0.5 + inset, floor.Size.Z * 0.5 - inset)
	local yaw = random:NextNumber(-math.pi, math.pi)
	return floor.CFrame
		* CFrame.new(x, floor.Size.Y * 0.5 + Physics.PoolTossClearance, z)
		* CFrame.Angles(random:NextNumber(-0.4, 0.4), yaw, random:NextNumber(-0.4, 0.4))
end
function Scene.PoolContainsStrict(position: Vector3): boolean
	local floor = Scene.PoolFloor
	return ThrowArc.InsidePoolStrict(floor.CFrame, floor.Size, position, Physics.PoolWallHeight)
end
function Scene.PoolContains(position: Vector3): boolean
	local floor = Scene.PoolFloor
	local localPosition = floor.CFrame:PointToObjectSpace(position)
	local half = floor.Size * 0.5
	local pad = 1.5
	return math.abs(localPosition.X) <= half.X + pad
		and math.abs(localPosition.Z) <= half.Z + pad
		and localPosition.Y >= -2
		and localPosition.Y <= half.Y + Physics.PoolWallHeight + 2
end
function Scene.ShelfPose(quality: number, slot: number): CFrame
	local point = potionPoints[math.clamp(quality, 1, #potionPoints)]
	local offset = ShelfSlotOffsets[math.clamp(slot, 1, #ShelfSlotOffsets)]
	return point.CFrame * CFrame.new(offset)
end
function Scene.SafePose(position: Vector3, fallback: Vector3, ignored: { Instance }): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	local result = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -25, 0), params)
	if result and result.Normal.Y > 0.6 then
		return CFrame.new(result.Position + Vector3.new(0, 3, 0))
	end
	return CFrame.new(fallback + Vector3.new(0, 3, 0))
end
function Scene.StreetPoint(random: Random): Vector3
	local deck = Scene.Deck
	return deck.CFrame:PointToWorldSpace(
		Vector3.new(random:NextNumber(-deck.Size.X / 2 + 4, deck.Size.X / 2 - 4), deck.Size.Y / 2, random:NextNumber(-deck.Size.Z / 2 + 4, deck.Size.Z / 2 - 4))
	)
end
function Scene.Visible(character: Model, position: Vector3, target: Model?): boolean
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local direction = position - head.Position
	if direction.Magnitude < 0.01 then
		return true
	end
	local hit = workspace:Raycast(head.Position, direction, params)
	return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target)) or (hit.Position - position).Magnitude < 1
end
return Scene
