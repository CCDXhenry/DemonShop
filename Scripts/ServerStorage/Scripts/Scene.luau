-- 场景契约：静态锚点、街道路面采样、工位放置与安全地面回收
--!strict
local Scene = {}
local district = workspace:WaitForChild("NeonContractDistrict")
local PointRowBand = 0.5 -- 同一排点位的高度差上限，studs
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
Scene.PoolDrop = Part(district:WaitForChild("SoulHoldingPool"), "DropPointAnchor")
Scene.PoolPickup = Part(district:WaitForChild("SoulHoldingPool"), "PickupPointAnchor")
Scene.Table = Part(district:WaitForChild("RuneBodyTable"), "BodyPlacementAnchor")
Scene.TableInteract = Part(district:WaitForChild("RuneBodyTable"), "TransferStartAnchor")
Scene.Altar = Part(district:WaitForChild("SoulConversionAltar"), "BodyArrivalAnchor")
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
Scene.SigilPosition = Part(district, "SummoningSubmitAnchor").Position
function Scene.TablePose(): CFrame
	return Scene.Table.CFrame * CFrame.new(0, 4, 0)
end
function Scene.CameraPose(): CFrame
	local center = Scene.TablePose().Position
	return CFrame.lookAt(center + Vector3.new(0, 1, 12), center)
end
function Scene.PoolPose(slot: number): CFrame
	return CFrame.new(Scene.PoolPickup.Position + Vector3.new(((slot - 1) % 4 - 1.5) * 4, 1.7, -5 - math.floor((slot - 1) / 4) * 4))
		* CFrame.Angles(math.pi / 2, 0, 0)
end
function Scene.ShelfPose(slot: number): CFrame
	local index = math.clamp(slot, 1, #potionPoints)
	return CFrame.new(potionPoints[index].Position)
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
