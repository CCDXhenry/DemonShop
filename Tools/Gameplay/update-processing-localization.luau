-- 加工文案 Edit 模板迁移：仅增量配置文字及独立键位，不重建 HUD
--!strict
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "DemonShop Edit required")
local ui = game:GetService("ReplicatedStorage").UI
local gui = ui.GameScreenGui
local root = gui.CenterFrame
local function SplitKey(label: TextLabel, name: string, key: string, width: number): TextLabel
	local parent = label.Parent :: Instance
	local existing = parent:FindFirstChild(name) :: TextLabel?
	if existing then return existing end
	local keyLabel = label:Clone()
	keyLabel.Name, keyLabel.Text, keyLabel.AutoLocalize = name, key, false
	keyLabel.Size = UDim2.new(0, width, label.Size.Y.Scale, label.Size.Y.Offset)
	keyLabel.Visible = false
	keyLabel.Parent = parent
	label.Position += UDim2.fromOffset(width, 0)
	label.Size -= UDim2.fromOffset(width, 0)
	return keyLabel
end
for _, value in gui:GetDescendants() do
	if value:IsA("TextLabel") then
		local dynamic = value.Name == "CoinsText" or value.Name == "CarryText" or value.Name == "StockText"
			or value.Name == "HintText" or value.Name == "NoticeText" or value.Name == "ProgressText"
			or (value.Name == "LabelText" and value.Parent and value.Parent.Name == "DropButton")
		value.AutoLocalize = not dynamic and not string.find(value.Name, "KeyText")
		if dynamic and value.Name ~= "ProgressText" then value.Text = "" end
	end
end
for _, node in gui:GetDescendants() do
	if node.Name == "InteractButton" or node.Name == "HintKeyText" then node:Destroy() end
end
local dropKey = SplitKey(root.DropButton.LabelText, "KeyText", "Q", 48)
dropKey.Visible = true
root.DropButton.LabelText.Text = ""
root.DropButton.LabelText.AutoLocalize = false
local target = ui:FindFirstChild("TargetGui")
if target then
	local count = target.ContentFrame.CountText
	count.AutoLocalize, count.Text = false, ""
	local key = count.Parent:FindFirstChild("KeyText"); if key then key:Destroy() end
end

local prompt = ui:FindFirstChild("WorldInteractionPrompt") :: ProximityPrompt?
if not prompt then prompt = Instance.new("ProximityPrompt"); prompt.Name = "WorldInteractionPrompt"; prompt.Parent = ui end
prompt.Style = Enum.ProximityPromptStyle.Default
prompt.HoldDuration = 0.5
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.ClickablePrompt = true
prompt.RequiresLineOfSight = true
prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
prompt.MaxActivationDistance = 8
prompt.Enabled = false
prompt.AutoLocalize = false
return "Updated processing localization templates"
