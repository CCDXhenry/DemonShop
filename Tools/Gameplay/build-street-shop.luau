-- 在一楼街道创建商店占位 Part 和可独立保留的交互锚点
--!strict
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "DemonShop Edit required")

local district = workspace:WaitForChild("NeonContractDistrict")
local shop = district:FindFirstChild("PersonalShop")
if not shop then
	local location = Vector3.new(-36, 20.35, -44)
	local model = Instance.new("Model")
	model.Name = "PersonalShop"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local placeholder = Instance.new("Part")
	placeholder.Name = "ShopPlaceholder"
	placeholder.Size = Vector3.new(4, 3, 2)
	placeholder.Position = location + Vector3.new(0, 1.5, 0)
	placeholder.Color = Color3.fromRGB(108, 44, 148)
	placeholder.Anchored = true
	placeholder.Parent = model

	local anchor = Instance.new("Part")
	anchor.Name = "InteractionAnchor"
	anchor.Size = Vector3.one
	anchor.Position = location + Vector3.new(0, 2.4, -1.25)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = model
	model.PrimaryPart = anchor
	model.Parent = district
	shop = model
end

local anchor = shop:FindFirstChild("InteractionAnchor")
assert(anchor and anchor:IsA("BasePart"), "PersonalShop.InteractionAnchor is required")
local existing = anchor:FindFirstChild("ShopPrompt")
assert(existing == nil or existing:IsA("ProximityPrompt"), "Invalid ShopPrompt")
local prompt = existing or Instance.new("ProximityPrompt")
prompt.Name = "ShopPrompt"
prompt.ActionText = "SHOP"
prompt.ObjectText = ""
prompt.AutoLocalize = true
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.ClickablePrompt = true
prompt.MaxActivationDistance = 10
prompt.RequiresLineOfSight = false
prompt.Parent = anchor
return prompt:GetFullName()
