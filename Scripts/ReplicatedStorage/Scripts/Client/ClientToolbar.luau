-- 底部工具栏：武器和药水各占槽位，最多显示 9 个，点击和数字键装备或放回
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberExtension = require(ReplicatedStorage.Core.Scripts.Shared.NumberExtension)
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local Config = require(Shared:WaitForChild("GameConfig"))
local GameData = require(Shared:WaitForChild("GameData"))
local ProcessingTextTool = require(script.Parent.ProcessingTextTool)
local UIManager = require(script.Parent.UIManager)
local Toolbar = {}
Toolbar.__index = Toolbar
local player = Players.LocalPlayer
local PersonalRules = require(Shared:WaitForChild("PersonalUpgradeRules"))
local KeyCodes: { Enum.KeyCode } = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}
local SlotLimit = math.min(Config.ToolbarSlotLimit, #KeyCodes)
type Slot = {
	tool: Tool,
	button: ImageButton,
	scope: Lifecycle.Lifecycle,
}
export type Controller = typeof(setmetatable({} :: {
	scope: Lifecycle.Lifecycle,
	texts: ProcessingTextTool.Controller,
	characterScope: Lifecycle.Lifecycle?,
	backpackScope: Lifecycle.Lifecycle?,
	bar: Frame?,
	template: ImageButton?,
	slots: { [Tool]: Slot },
	ordered: { Tool },
	ready: boolean,
	refreshQueued: boolean,
	refreshing: boolean,
	refreshAgain: boolean,
	closed: boolean,
}, Toolbar))
local function StackCount(tool: Tool): number
	local count = tool:GetAttribute("StackCount")
	if typeof(count) == "number" and count > 0 then
		return math.floor(count)
	end
	return 1
end
local function WeaponSource(tool: Tool): string
	local level = GameData.GetWeaponLevelByModel(tool.Name)
	if level then
		return GameData.GetWeaponByLevel(level).name_t
	end
	return string.gsub(string.gsub(tool.Name, "^W%d%d_", ""), "(%l)(%u)", "%1 %2")
end
local function ApplyToolName(texts: ProcessingTextTool.Controller, button: ImageButton, tool: Tool): ()
	local nameLabel = button:FindFirstChild("ToolNameText")
	if nameLabel and nameLabel:IsA("TextLabel") then
		if tool.Name == "Potion" then
			texts:Bind(nameLabel, { textId = "ToolbarPotion", args = { NumberExtension.FormatBigNumberAA(StackCount(tool)) } })
		else
			texts:BindSource(nameLabel, WeaponSource(tool))
		end
	end
end
local function ToolbarOrderOf(tool: Tool): number
	local value = tool:GetAttribute("ToolbarOrder")
	if typeof(value) == "number" then
		return value
	end
	return 0
end
local function CollectTools(): { Tool }
	local weapon: Tool? = nil
	local potions: { Tool } = {}
	local seen: { [Tool]: boolean } = {}
	local function Take(container: Instance?): ()
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and not seen[child] then
				seen[child] = true
				if child.Name == "Potion" then
					table.insert(potions, child)
				elseif PersonalRules.WeaponLevel(child.Name) then
					weapon = child
				end
			end
		end
	end
	Take(player:FindFirstChildOfClass("Backpack"))
	Take(player.Character)
	local list: { Tool } = {}
	if weapon then table.insert(list, weapon) end
	table.sort(potions, function(a: Tool, b: Tool): boolean
		return ToolbarOrderOf(a) < ToolbarOrderOf(b)
	end)
	local character = player.Character
	local equipped: Tool? = nil
	for _, tool in potions do
		if character ~= nil and tool.Parent == character then
			equipped = tool
			break
		end
	end
	local room = math.max(0, SlotLimit - #list)
	local visible: { Tool } = {}
	for _, tool in potions do
		if #visible >= room then
			break
		end
		table.insert(visible, tool)
	end
	if equipped and room > 0 then
		local shown = false
		for _, tool in visible do
			if tool == equipped then
				shown = true
				break
			end
		end
		if not shown then
			visible[math.max(#visible, 1)] = equipped
		end
	end
	for _, tool in visible do
		table.insert(list, tool)
	end
	return list
end
local function SetToolIcon(button: ImageButton, tool: Tool): ()
	local icon = button:WaitForChild("IconImage") :: ImageLabel
	local level = PersonalRules.WeaponLevel(tool.Name)
	icon.Image = if tool.Name == "Potion" then Config.PotionIcon elseif level then GameData.GetWeaponByLevel(level).icon else ""
end

local function SetEquipped(button: ImageButton, tool: Tool): ()
	local image = button:WaitForChild("EquippedImage")
	if image:IsA("GuiObject") then
		local character = player.Character
		image.Visible = character ~= nil and tool.Parent == character
	end
end
function Toolbar.new(): Controller
	return setmetatable({
		scope = Lifecycle.new(),
		texts = ProcessingTextTool.new(),
		slots = {},
		ordered = {},
		ready = false,
		refreshQueued = false,
		refreshing = false,
		refreshAgain = false,
		closed = false,
	}, Toolbar)
end
function Toolbar.ScheduleRefresh(self: Controller): ()
	if self.refreshQueued or not self.scope.alive then
		return
	end
	-- 工具在背包和角色之间移动时会连续触发移除和添加，延后到下一帧再重排。
	self.refreshQueued = true
	self.scope:Delay(0, function(): ()
		self.refreshQueued = false
		self:Refresh()
	end)
end
function Toolbar.Select(self: Controller, tool: Tool): ()
	if not self.scope.alive or tool.Parent == nil then
		return
	end
	if UIManager.HasShowingWindow() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	-- 画符时不能切换工具，工具栏只反映装备状态。
	if player:GetAttribute("Painting") == true then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end
function Toolbar.Create(self: Controller, tool: Tool): Slot
	local template = self.template
	local bar = self.bar
	assert(template and bar, "Toolbar template is missing")
	local button = template:Clone()
	button.Visible = true
	button.Parent = bar
	local slotScope = Lifecycle.new()
	ApplyToolName(self.texts, button, tool)
	SetToolIcon(button, tool)
	slotScope:Connect(tool:GetAttributeChangedSignal("StackCount"):Connect(function(): ()
		ApplyToolName(self.texts, button, tool)
	end))
	slotScope:Connect(button.Activated:Connect(function(): ()
		self:Select(tool)
	end))
	return { tool = tool, button = button, scope = slotScope }
end
function Toolbar.FinishRefresh(self: Controller): ()
	self.refreshing = false
	if self.closed or not self.scope.alive then
		return
	end
	if self.refreshAgain then
		self.refreshAgain = false
		self:Refresh()
	end
end
function Toolbar.Refresh(self: Controller): ()
	if self.closed or not self.scope.alive or not self.bar or not self.template then
		return
	end
	if self.refreshing then
		self.refreshAgain = true
		return
	end
	self.refreshing = true
	local tools = CollectTools()
	local seen: { [Tool]: boolean } = {}
	self.ordered = tools
	for index, tool in tools do
		if self.closed then
			self:FinishRefresh()
			return
		end
		seen[tool] = true
		local slot = self.slots[tool]
		if not slot then
			local created = self:Create(tool)
			self.slots[tool] = created
			slot = created
		end
		ApplyToolName(self.texts, slot.button, tool)
		if self.closed or self.slots[tool] ~= slot then
			self:FinishRefresh()
			return
		end
		local current = self.slots[tool]
		assert(current)
		current.button.LayoutOrder = index
		current.button.Visible = true
		local key = current.button:FindFirstChild("KeyCodeText")
		local keyText = tostring(index)
		if key and key:IsA("TextLabel") then
			key.AutoLocalize = false
			if key.Text ~= keyText then
				key.Text = keyText
				UIManager.FitTextLabel(key)
			end
		end
		if self.closed or self.slots[tool] ~= current then
			self:FinishRefresh()
			return
		end
		SetEquipped(current.button, tool)
	end
	local remove: { Tool } = {}
	for tool in self.slots do
		if not seen[tool] then
			table.insert(remove, tool)
		end
	end
	for _, tool in remove do
		local slot = self.slots[tool]
		self.slots[tool] = nil
		if slot then
			local nameLabel = slot.button:FindFirstChild("ToolNameText")
			if nameLabel and nameLabel:IsA("TextLabel") then
				self.texts:Clear(nameLabel)
			end
			slot.scope:Destroy()
			slot.button:Destroy()
		end
	end
	self:FinishRefresh()
end
function Toolbar.WatchContainer(self: Controller, container: Instance, kind: "character" | "backpack"): ()
	local previous = if kind == "character" then self.characterScope else self.backpackScope
	if previous then
		previous:Destroy()
	end
	local scope = Lifecycle.new()
	if kind == "character" then
		self.characterScope = scope
	else
		self.backpackScope = scope
	end
	local function Queue(child: Instance): ()
		if child:IsA("Tool") then
			self:ScheduleRefresh()
		end
	end
	scope:Connect(container.ChildAdded:Connect(Queue))
	scope:Connect(container.ChildRemoved:Connect(Queue))
end
function Toolbar.Init(self: Controller, gui: ScreenGui): ()
	if self.ready then
		return
	end
	self.ready = true
	local center = gui:WaitForChild("CenterFrame")
	local bar = center:WaitForChild("BottomButtonsFrame")
	local template = bar:WaitForChild("ToolButton")
	assert(bar:IsA("Frame") and template:IsA("ImageButton"), "Missing toolbar template")
	self.bar = bar
	self.template = template
	self.scope:Connect(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean): ()
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		for index, code in KeyCodes do
			if input.KeyCode == code then
				local tool = self.ordered[index]
				if tool then
					self:Select(tool)
				end
				return
			end
		end
	end))
	self.scope:Connect(player.CharacterAdded:Connect(function(character: Model): ()
		self:WatchContainer(character, "character")
		self:ScheduleRefresh()
	end))
	self.scope:Connect(player.ChildAdded:Connect(function(child: Instance): ()
		if child:IsA("Backpack") then
			self:WatchContainer(child, "backpack")
			self:ScheduleRefresh()
		end
	end))
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		self:WatchContainer(backpack, "backpack")
	end
	local character = player.Character
	if character then
		self:WatchContainer(character, "character")
	end
	self:ScheduleRefresh()
end
function Toolbar.Destroy(self: Controller): ()
	if self.closed then
		return
	end
	self.closed = true
	self.ready = false
	self.refreshQueued = false
	self.refreshAgain = false
	self.texts:Destroy()
	for _, slot in self.slots do
		slot.scope:Destroy()
		slot.button:Destroy()
	end
	table.clear(self.slots)
	table.clear(self.ordered)
	if self.characterScope then
		self.characterScope:Destroy()
		self.characterScope = nil
	end
	if self.backpackScope then
		self.backpackScope:Destroy()
		self.backpackScope = nil
	end
	self.scope:Destroy()
	self.bar = nil
	self.template = nil
end
return Toolbar
