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
SplitKey(root.HintText, "HintKeyText", "E", 48)
local interactKey = SplitKey(root.InteractButton.LabelText, "KeyText", "E", 48)
interactKey.Visible = true
root.InteractButton.LabelText.Text = "INTERACT"
root.InteractButton.LabelText.AutoLocalize = true
local dropKey = SplitKey(root.DropButton.LabelText, "KeyText", "Q", 48)
dropKey.Visible = true
root.DropButton.LabelText.Text = ""
root.DropButton.LabelText.AutoLocalize = false
local target = ui:FindFirstChild("TargetGui")
if target then
	local count = target.ContentFrame.CountText
	count.AutoLocalize, count.Text = false, ""
	SplitKey(count, "KeyText", "E", 32)
end
return "Updated processing localization templates"
