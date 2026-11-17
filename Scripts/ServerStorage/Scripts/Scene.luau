-- 场景契约：静态锚点、街道路面采样、工位放置与安全地面回收
--!strict
local Scene = {}
local district = workspace:WaitForChild("NeonContractDistrict")
local function Part(root: Instance, name: string): BasePart
	local p = root:WaitForChild(name)
	assert(p:IsA("BasePart"))
	return p
end
Scene.District = district
Scene.Deck = Part(district:WaitForChild("deck"):WaitForChild("Generated"):WaitForChild("Street"):WaitForChild("Raised Street Deck With Stair Void"), "Box_005")
Scene.PoolDrop = Part(district:WaitForChild("SoulHoldingPool"), "DropPointAnchor")
Scene.PoolPickup = Part(district:WaitForChild("SoulHoldingPool"), "PickupPointAnchor")
Scene.Table = Part(district:WaitForChild("RuneBodyTable"), "BodyPlacementAnchor")
Scene.TableInteract = Part(district:WaitForChild("RuneBodyTable"), "TransferStartAnchor")
Scene.Altar = Part(district:WaitForChild("SoulConversionAltar"), "BodyArrivalAnchor")
Scene.Shelf = Part(district:WaitForChild("SoulCrystalDisplay"), "StockPickupAnchor")
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
	return CFrame.new(Scene.Shelf.Position + Vector3.new(((slot - 1) % 4 - 1.5) * 1.35, 2 + math.floor((slot - 1) / 4) * 1.8, -1))
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
	local direction = position - head.Position
	if direction.Magnitude < 0.01 then
		return true
	end
	local hit = workspace:Raycast(head.Position, direction, params)
	return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target)) or (hit.Position - position).Magnitude < 1
end
return Scene
