-- 底部工具栏：木棒和药水各占槽位，最多显示 9 个，点击和数字键装备或放回
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local Config = require(Shared:WaitForChild("GameConfig"))
local UIManager = require(script.Parent.UIManager)
local Toolbar = {}
Toolbar.__index = Toolbar
local player = Players.LocalPlayer
local ToolOrder: { [string]: number } = { Club = 1 }
local ToolNames: { [string]: string } = { Club = "Club", Potion = "Potion" }
local FixedNames: { string } = { "Club" }
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
local function ToolLabel(tool: Tool): string
	if tool.Name == "Potion" then
		return string.format("Potion %d", StackCount(tool))
	end
	return ToolNames[tool.Name] or tool.Name
end
local function ApplyToolName(button: ImageButton, tool: Tool): ()
	local nameLabel = button:FindFirstChild("ToolNameText")
	if nameLabel and nameLabel:IsA("TextLabel") then
		local text = ToolLabel(tool)
		if nameLabel.Text ~= text then
			nameLabel.Text = text
			UIManager.FitTextLabel(nameLabel)
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
	local fixed: { [string]: Tool } = {}
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
				elseif ToolOrder[child.Name] then
					fixed[child.Name] = child
				end
			end
		end
	end
	Take(player:FindFirstChildOfClass("Backpack"))
	Take(player.Character)
	local list: { Tool } = {}
	for _, name in FixedNames do
		local tool = fixed[name]
		if tool then
			table.insert(list, tool)
		end
	end
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
local function PreviewCamera(viewport: ViewportFrame): Camera
	local existing = viewport:FindFirstChildOfClass("Camera")
	if existing then
		return existing
	end
	-- 界面克隆进 PlayerGui 后，模板里的 Camera 不会跟着过去，预览时再补一台。
	local camera = Instance.new("Camera")
	camera.Name = "Camera"
	camera.Parent = viewport
	return camera
end
local function RenderPreview(button: ImageButton, tool: Tool): ()
	local viewport = button:WaitForChild("ToolViewport")
	local world = viewport:WaitForChild("WorldModel")
	assert(viewport:IsA("ViewportFrame") and world:IsA("WorldModel"))
	for _, child in world:GetChildren() do
		child:Destroy()
	end
	-- 优先克隆 ReplicatedStorage.Models 里的纯净模板，避免运行时持握与角色骨骼动画污染道具世界坐标与朝向
	local modelsFolder = ReplicatedStorage:FindFirstChild("Models")
	local template = if modelsFolder then modelsFolder:FindFirstChild(tool.Name) else nil
	local fromTemplate = template ~= nil and template:IsA("Tool")
	local clone = if fromTemplate then (template :: Tool):Clone() else tool:Clone()
	local discard: { Instance } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			table.insert(discard, descendant)
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	for _, descendant in discard do
		descendant:Destroy()
	end

	-- 姿态标准化：提取主参考部件并归一化到原点，消除角色运行时的任意旋转与位置偏移
	local referencePart: BasePart? = nil
	if clone.PrimaryPart and clone.PrimaryPart:IsA("BasePart") then
		referencePart = clone.PrimaryPart
	elseif clone:FindFirstChild("Handle") and (clone:FindFirstChild("Handle") :: Instance):IsA("BasePart") then
		referencePart = clone:FindFirstChild("Handle") :: BasePart
	else
		referencePart = clone:FindFirstChildWhichIsA("BasePart")
	end

	if referencePart then
		local refCFrame = referencePart.CFrame
		local targetCFrame = if fromTemplate then CFrame.new(Vector3.zero) * refCFrame.Rotation else CFrame.identity
		local offsets: { [BasePart]: CFrame } = {}
		for _, item in clone:GetDescendants() do
			if item:IsA("BasePart") then
				offsets[item] = refCFrame:ToObjectSpace(item.CFrame)
			end
		end
		for part, rel in offsets do
			part.CFrame = targetCFrame * rel
		end
	end

	clone.Parent = world
	local directionAttribute = viewport:GetAttribute("ViewDirection")
	local direction = if typeof(directionAttribute) == "Vector3" and directionAttribute.Magnitude >= 1e-4
		then directionAttribute
		else Vector3.new(-1, 0.7, -1.5)
	local fovAttribute = viewport:GetAttribute("PreviewFieldOfView")
	local fov = if typeof(fovAttribute) == "number" then fovAttribute else 35
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum
	local found = false
	for _, item in clone:GetDescendants() do
		if item:IsA("BasePart") then
			found = true
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local corner = item.CFrame:PointToWorldSpace(item.Size * Vector3.new(x, y, z) * 0.5)
						minimum = minimum:Min(corner)
						maximum = maximum:Max(corner)
					end
				end
			end
		end
	end
	local center = if found then (minimum + maximum) * 0.5 else Vector3.zero
	local radius = if found then math.max((maximum - minimum).Magnitude * 0.5, 0.2) else 1
	local width = if viewport.AbsoluteSize.X > 0 then viewport.AbsoluteSize.X else viewport.Size.X.Offset
	local height = if viewport.AbsoluteSize.Y > 0 then viewport.AbsoluteSize.Y else viewport.Size.Y.Offset
	local aspect = math.max(0.01, width) / math.max(1, height)
	local halfAngle = math.atan(math.tan(math.rad(fov * 0.5)) * math.min(1, aspect))
	local distance = radius / math.max(math.sin(halfAngle), 1e-3) * 1.12
	local camera = PreviewCamera(viewport)
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(center + direction.Unit * distance, center)
	viewport.CurrentCamera = camera
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
	ApplyToolName(button, tool)
	local nameLabel = button:FindFirstChild("ToolNameText")
	if nameLabel and nameLabel:IsA("TextLabel") then
		UIManager.FitTextLabel(nameLabel)
	end
	RenderPreview(button, tool)
	slotScope:Connect(tool:GetAttributeChangedSignal("StackCount"):Connect(function(): ()
		ApplyToolName(button, tool)
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
		ApplyToolName(slot.button, tool)
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
		if key and key:IsA("TextLabel") and key.Text ~= keyText then
			key.Text = keyText
			UIManager.FitTextLabel(key)
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
