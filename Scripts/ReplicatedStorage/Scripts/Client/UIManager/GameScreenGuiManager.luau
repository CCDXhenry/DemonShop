-- 主界面管理器：持有主 GUI、控件缓存、文案绑定、画符按钮和贴跳跃键的移动端攻击钮
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lifecycle = require(script.Parent.Parent.Parent.Shared.LifecycleTool)
local GameTexts = require(script.Parent.Parent.Parent.Shared.GameTexts)
local Types = require(script.Parent.Parent.Parent.Shared.GameTypes)
local ProcessingText = require(script.Parent.Parent.ProcessingTextTool)
local PaintPointer = require(script.Parent.Parent.PaintPointer)
local Manager = {}
Manager.__index = Manager
export type Actions = {
	attack: () -> (),
	exitPaint: () -> (),
	resetView: () -> (),
}
export type DisplayState = {
	painting: boolean,
	hasTarget: boolean,
	windowOpen: boolean?,
	carryingBody: boolean?,
}
export type Manager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		root: Frame?,
		owned: boolean,
		texts: ProcessingText.Controller,
		scope: Lifecycle.Lifecycle,
		actionScope: Lifecycle.Lifecycle,
		jumpScope: Lifecycle.Lifecycle?,
		cameraScope: Lifecycle.Lifecycle?,
		labels: { [string]: TextLabel },
		buttons: { [string]: GuiButton },
		touchFrames: { [string]: Frame },
		touchAttack: Frame?,
		throwStick: Frame?,
		attackButton: ImageButton?,
		carryingBody: boolean,
		jumpButton: GuiObject?,
		pressTween: Tween?,
		releaseTween: Tween?,
		heldInput: InputObject?,
		painting: boolean,
		windowOpen: boolean,
		brushCursor: boolean,
		savedMouseIcon: boolean?,
		paintFrame: Frame?,
		fill: Frame?,
	},
	Manager
))
function Manager.new(): Manager
	return setmetatable(
		{
			gui = nil,
			root = nil,
			owned = false,
			texts = ProcessingText.new(),
			scope = Lifecycle.new(),
			actionScope = Lifecycle.new(),
			labels = {},
			buttons = {},
			touchFrames = {},
			painting = false,
			windowOpen = false,
			carryingBody = false,
			brushCursor = false,
			savedMouseIcon = nil,
		},
		Manager
	)
end
function Manager.SetText(self: Manager, name: string, description: GameTexts.Description?): ()
	local label = self.labels[name]
	if not label then
		return
	end
	if description then
		self.texts:Bind(label, description)
	else
		self.texts:Clear(label)
	end
end
function Manager.ShowNotice(self: Manager, notice: Types.Notice): ()
	local label = self.labels.NoticeText
	if label then
		self.texts:Notice(label, notice.textId, notice.textArgs, notice.text)
	end
end
-- 攻击钮独立于 1920 画布，按跳跃键的屏幕坐标放在其左上方。
function Manager.LayoutTouch(self: Manager): ()
	local frame = self.touchAttack
	if not frame then
		return
	end
	local jump = self.jumpButton
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	local jumpVisible = jump ~= nil and jump.Parent ~= nil and jump.AbsoluteSize.X > 0
	if jump then
		local ancestor: Instance? = jump
		while ancestor do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				jumpVisible = false
			end
			if ancestor:IsA("ScreenGui") and not ancestor.Enabled then
				jumpVisible = false
			end
			ancestor = ancestor.Parent
		end
	end
	local show = touch and jumpVisible and not self.painting and not self.windowOpen
	frame.Visible = show and not self.carryingBody
	local stick = self.throwStick
	if stick then
		stick.Visible = show and self.carryingBody
	end
	if not jump or not jumpVisible then
		return
	end
	local ratio = frame:GetAttribute("JumpSizeRatio")
	local minimum = frame:GetAttribute("MinimumTouchSize")
	local gap = frame:GetAttribute("JumpGap")
	assert(typeof(ratio) == "number" and typeof(minimum) == "number" and typeof(gap) == "number", "TouchAttackFrame is missing jump layout attributes")
	local size = math.max(minimum, jump.AbsoluteSize.X * ratio)
	local origin = frame.AbsolutePosition - Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
	local topLeft = jump.AbsolutePosition - Vector2.new(size + gap, size + gap)
	local placed = UDim2.fromOffset(math.max(0, topLeft.X - origin.X), math.max(0, topLeft.Y - origin.Y))
	frame.Size = UDim2.fromOffset(size, size)
	frame.Position = placed
	if stick then
		local stickOrigin = stick.AbsolutePosition - Vector2.new(stick.Position.X.Offset, stick.Position.Y.Offset)
		stick.Size = UDim2.fromOffset(size, size)
		stick.Position = UDim2.fromOffset(math.max(0, topLeft.X - stickOrigin.X), math.max(0, topLeft.Y - stickOrigin.Y))
	end
end
function Manager.Refresh(self: Manager, state: DisplayState): ()
	if not self.gui then
		return
	end
	local touch = UserInputService.TouchEnabled
	self.painting = state.painting
	self.windowOpen = state.windowOpen == true
	self.carryingBody = state.carryingBody == true
	if not state.painting or GuiService.MenuIsOpen then
		self:ApplyBrushCursor(false)
	end
	self.buttons.ExitPaintButton.Visible = state.painting and not touch
	self.buttons.ResetViewButton.Visible = state.painting and not touch
	self.touchFrames.TouchPaintFrame.Visible = touch and state.painting
	local paintFrame = self.paintFrame
	if paintFrame then
		paintFrame.Visible = state.painting
	end
	local bar = if self.root then self.root:FindFirstChild("BottomButtonsFrame") else nil
	if bar and bar:IsA("GuiObject") then
		bar.Visible = not state.painting
	end
	self:LayoutTouch()
end
function Manager.SetPainting(self: Manager, painting: boolean): ()
	self:Refresh({ painting = painting, hasTarget = false })
end
function Manager.SetProgress(self: Manager, progress: number): ()
	local label = self.labels.ProgressText
	if label then
		label.Text = string.format("%d%%", math.floor(progress * 100))
	end
	local fill = self.fill
	if fill then
		fill.Size = UDim2.fromScale(progress, 1)
	end
end
function Manager.ApplyBrushCursor(self: Manager, show: boolean): ()
	if show == self.brushCursor then
		return
	end
	self.brushCursor = show
	local root = self.root
	local brush = if root then root:FindFirstChild("PaintBrushCursorImage") else nil
	if brush and brush:IsA("GuiObject") then
		brush.Visible = show
	end
	if show then
		if self.savedMouseIcon == nil then
			self.savedMouseIcon = UserInputService.MouseIconEnabled
		end
		UserInputService.MouseIconEnabled = false
	elseif self.savedMouseIcon ~= nil then
		UserInputService.MouseIconEnabled = self.savedMouseIcon
		self.savedMouseIcon = nil
	end
end
function Manager.UpdatePointer(self: Manager, pointer: Vector2?, drawing: boolean): ()
	local root = self.root
	if not root then
		return
	end
	PaintPointer.HideLegacyCursor(root)
	local show = pointer ~= nil and self.painting and not GuiService.MenuIsOpen
	self:ApplyBrushCursor(show)
	PaintPointer.PlaceBrush(root, pointer or Vector2.zero, show, drawing)
end
function Manager.ReleaseAttack(self: Manager): ()
	self.heldInput = nil
	if self.pressTween then
		self.pressTween:Cancel()
	end
	if self.releaseTween then
		self.releaseTween:Play()
	end
end
function Manager.UnbindActions(self: Manager): ()
	self.actionScope:Destroy()
	self.actionScope = Lifecycle.new()
	if self.pressTween then
		self.pressTween:Cancel()
		self.pressTween:Destroy()
		self.pressTween = nil
	end
	if self.releaseTween then
		self.releaseTween:Cancel()
		self.releaseTween:Destroy()
		self.releaseTween = nil
	end
	self.heldInput = nil
end
function Manager.BindActions(self: Manager, actions: Actions): ()
	self:UnbindActions()
	local callbacks: { [string]: () -> () } = {
		ExitPaintButton = actions.exitPaint,
		ResetViewButton = actions.resetView,
	}
	local gui = self.gui
	if not gui then
		return
	end
	for _, node in gui:GetDescendants() do
		if node:IsA("GuiButton") then
			local callback = callbacks[node.Name]
			if callback then
				self.actionScope:Connect(node.Activated:Connect(callback))
			end
		end
	end
	local attack = self.attackButton
	if not attack then
		return
	end
	local useScale = attack:FindFirstChildOfClass("UIScale")
	local pressedScale = attack:GetAttribute("PressedScale")
	local duration = attack:GetAttribute("PressTweenSeconds")
	if useScale and useScale:IsA("UIScale") and typeof(pressedScale) == "number" and typeof(duration) == "number" then
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		self.pressTween = TweenService:Create(useScale, info, { Scale = pressedScale })
		self.releaseTween = TweenService:Create(useScale, info, { Scale = useScale.Scale })
	end
	self.actionScope:Connect(attack.InputBegan:Connect(function(input: InputObject): ()
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self.heldInput = input
		if self.releaseTween then
			self.releaseTween:Cancel()
		end
		if self.pressTween then
			self.pressTween:Play()
		end
		actions.attack()
	end))
	self.actionScope:Connect(attack.InputEnded:Connect(function(input: InputObject): ()
		if input ~= self.heldInput then
			return
		end
		self:ReleaseAttack()
	end))
end
function Manager.Init(self: Manager, gui: ScreenGui, owned: boolean?): ()
	if self.gui == gui then
		return
	end
	self:Destroy()
	self.gui, self.owned = gui, owned == true
	self.scope = Lifecycle.new()
	local template = ReplicatedStorage.UI:WaitForChild("TouchAttackFrame") :: Frame
	local attackFrame = template:Clone()
	attackFrame.Parent = gui
	self.touchAttack = attackFrame
	self.attackButton = attackFrame:WaitForChild("AttackButton") :: ImageButton
	local stickTemplate = ReplicatedStorage.UI:WaitForChild("ThrowStick") :: Frame
	local throwStick = stickTemplate:Clone()
	throwStick.Parent = gui
	self.throwStick = throwStick
	local root = gui:WaitForChild("CenterFrame") :: Frame
	self.root = root
	for _, node in gui:GetDescendants() do
		if node:IsA("TextLabel") then
			self.texts:Watch(node)
			if node:IsDescendantOf(root) then
				self.labels[node.Name] = node
			end
		end
	end
	for _, name in { "ExitPaintButton", "ResetViewButton" } do
		self.buttons[name] = root:WaitForChild(name) :: GuiButton
	end
	self.touchFrames.TouchPaintFrame = gui:WaitForChild("TouchPaintFrame") :: Frame
	self.paintFrame = root:WaitForChild("PaintFrame") :: Frame
	self.fill = root:FindFirstChild("FillFrame", true) :: Frame
	local player = Players.LocalPlayer
	assert(player, "UI requires a local player")
	local playerGui = player:WaitForChild("PlayerGui")
	local function OnJumpFound(instance: Instance): ()
		if instance.Name ~= "JumpButton" or not instance:IsA("GuiObject") then
			return
		end
		if self.jumpScope then
			self.jumpScope:Destroy()
		end
		self.jumpButton = instance
		local jumpScope = Lifecycle.new()
		self.jumpScope = jumpScope
		local function OnLayout(): ()
			self:LayoutTouch()
		end
		for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
			jumpScope:Connect(instance:GetPropertyChangedSignal(property):Connect(OnLayout))
		end
		jumpScope:Connect(instance.AncestryChanged:Connect(OnLayout))
		self:LayoutTouch()
	end
	for _, instance in playerGui:GetDescendants() do
		OnJumpFound(instance)
	end
	self.scope:Connect(playerGui.DescendantAdded:Connect(OnJumpFound))
	local function BindCamera(): ()
		if self.cameraScope then
			self.cameraScope:Destroy()
		end
		local cameraScope = Lifecycle.new()
		self.cameraScope = cameraScope
		local camera = workspace.CurrentCamera
		if camera then
			cameraScope:Connect(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function(): ()
				self:LayoutTouch()
			end))
		end
	end
	self.scope:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function(): ()
		BindCamera()
		self:LayoutTouch()
	end))
	BindCamera()
	self.scope:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function(): ()
		self:LayoutTouch()
	end))
	self.scope:Connect(gui.Destroying:Connect(function(): ()
		self.owned = false
		self:Destroy()
	end))
	self:LayoutTouch()
end
function Manager.GetThrowStick(self: Manager): Frame?
	return self.throwStick
end
function Manager.Create(self: Manager): ScreenGui
	if self.gui then
		return self.gui
	end
	local player = Players.LocalPlayer
	assert(player, "UI requires a local player")
	local parent = player:WaitForChild("PlayerGui")
	assert(not parent:FindFirstChild("GameScreenGui"), "Duplicate GameScreenGui outside UIManager")
	local template = ReplicatedStorage.UI:WaitForChild("GameScreenGui") :: ScreenGui
	for _, name in { "CenterFrame", "WindowCanvas", "ModalButton" } do
		local child = template:FindFirstChild(name)
		assert(child and child:IsA(if name == "ModalButton" then "ImageButton" else "Frame"), "Missing UI template node: " .. name)
		if name ~= "ModalButton" then
			assert(child:FindFirstChildOfClass("UIScale"), "Missing canvas UIScale: " .. name)
		end
	end
	local gui = template:Clone()
	self:Init(gui, true)
	gui.Parent = parent
	return gui
end
function Manager.Destroy(self: Manager): ()
	self:ApplyBrushCursor(false)
	self:UnbindActions()
	if self.jumpScope then
		self.jumpScope:Destroy()
		self.jumpScope = nil
	end
	if self.cameraScope then
		self.cameraScope:Destroy()
		self.cameraScope = nil
	end
	self.scope:Destroy()
	self.texts:Destroy()
	local gui, owned = self.gui, self.owned
	local attack = self.touchAttack
	local stick = self.throwStick
	self.gui, self.root, self.paintFrame, self.fill = nil, nil, nil, nil
	self.touchAttack, self.throwStick, self.attackButton, self.jumpButton = nil, nil, nil, nil
	self.painting, self.windowOpen, self.carryingBody = false, false, false
	self.owned = false
	table.clear(self.labels)
	table.clear(self.buttons)
	table.clear(self.touchFrames)
	if attack then
		attack:Destroy()
	end
	if stick then
		stick:Destroy()
	end
	if gui and owned then
		gui:Destroy()
	end
end
return Manager
