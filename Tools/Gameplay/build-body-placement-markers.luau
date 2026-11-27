-- 手动画符台 Edit 白膜放置位置标记构建器：在 RuneBodyTable 下生成 5 个半透明 WhiteR15 替身
assert(not game:GetService("RunService"):IsRunning(), "Edit mode required")
assert(game.PlaceId == 110812537538556, "DemonShop Edit required")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local district = workspace:WaitForChild("NeonContractDistrict")
local tableModel = district:WaitForChild("RuneBodyTable")
local anchor = tableModel:WaitForChild("BodyPlacementAnchor")
assert(anchor:IsA("BasePart"), "BodyPlacementAnchor must be a BasePart")

local whiteTemplate = ReplicatedStorage:WaitForChild("Models")
	:WaitForChild("Characters")
	:WaitForChild("WhiteR15")
assert(whiteTemplate:IsA("Model"), "WhiteR15 must be a Model")

local existing = tableModel:FindFirstChild("BodyPlacementMarkers")
if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "BodyPlacementMarkers"
folder.Parent = tableModel

local base1 = CFrame.fromMatrix(anchor.Position, -Vector3.zAxis, Vector3.xAxis)
local offsets = {
	Vector3.zero,
	Vector3.new(-5.55, 0, 0),
	Vector3.new(5.55, 0, 0),
	Vector3.new(0, 0, 3.25),
	Vector3.new(0, 0, -3.25),
}

local created = {}
for slot = 1, 5 do
	local clone = whiteTemplate:Clone()
	clone.Name = "Slot" .. tostring(slot)
	clone:SetAttribute("BodyPlacementMarker", true)
	clone:SetAttribute("PlacementSlot", slot)

	local color = if slot == 1 then Color3.fromRGB(70, 220, 255) else Color3.fromRGB(255, 195, 95)
	local transparency = if slot == 1 then 0.45 else 0.55

	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = true
			desc.CastShadow = false
			desc.Material = Enum.Material.SmoothPlastic
			if desc.Name == "HumanoidRootPart" then
				desc.Transparency = 1
			else
				desc.Color = color
				desc.Transparency = transparency
			end
		end
	end

	for _, desc in clone:GetDescendants() do
		if desc:IsA("LuaSourceContainer") or desc:IsA("Humanoid") or desc:IsA("Constraint") or desc:IsA("Motor6D") then
			desc:Destroy()
		end
	end

	clone:PivotTo(base1 + offsets[slot])

	local labelHost = clone:FindFirstChild("UpperTorso") or clone.PrimaryPart
	if labelHost and labelHost:IsA("BasePart") then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SlotLabel"
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(64, 26)
		billboard.StudsOffset = Vector3.new(0, 1.5, 0)
		billboard.Adornee = labelHost
		billboard.Parent = labelHost

		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
		label.BackgroundTransparency = 0.25
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextColor3 = color
		label.Text = if slot == 1 then "#1 主位" else "#" .. tostring(slot)
		label.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label
	end

	clone.Parent = folder
	table.insert(created, clone.Name)
end

return {
	folder = folder:GetFullName(),
	slots = created,
}
