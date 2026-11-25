-- 加工文案 Edit 模板迁移：仅增量配置文字及独立键位，不重建 HUD
--!strict
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "DemonShop Edit required")
local ui = game:GetService("ReplicatedStorage").UI
local gui = ui.GameScreenGui
for _, value in gui:GetDescendants() do
	if value:IsA("TextLabel") then
		local dynamic = value.Name == "CoinsText" or value.Name == "CarryText" or value.Name == "StockText"
			or value.Name == "HintText" or value.Name == "NoticeText" or value.Name == "ProgressText"
		value.AutoLocalize = not dynamic and not string.find(value.Name, "KeyText")
		if dynamic and value.Name ~= "ProgressText" then value.Text = "" end
	end
end
for _, node in gui:GetDescendants() do
	if node.Name == "InteractButton" or node.Name == "HintKeyText" or node.Name == "DropButton" or (node.Name == "AttackButton" and not node:FindFirstAncestor("TouchControlsFrame")) then node:Destroy() end
end
local target = ui:FindFirstChild("TargetGui")
if target then
	local content = target:FindFirstChild("ContentFrame")
	if content then
		local count = content:FindFirstChild("CountText")
		if count then count:Destroy() end
		local key = content:FindFirstChild("KeyText")
		if key then key:Destroy() end
	end
end

local existingPrompt = ui:FindFirstChild("WorldInteractionPrompt")
local prompt: ProximityPrompt
if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
	prompt = existingPrompt
else
	local created = Instance.new("ProximityPrompt")
	created.Name = "WorldInteractionPrompt"
	created.Parent = ui
	prompt = created
end
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
