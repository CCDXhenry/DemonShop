-- 主界面管理器：持有主 GUI、控件缓存、文案绑定、双端画符按钮及固定 1920×1080 触控操作区
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberExtension = require(ReplicatedStorage.Core.Scripts.Shared.NumberExtension)
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
	canAttack: boolean?,
	canThrow: boolean?,
}
export type Manager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		root: Frame?,
		owned: boolean,
		texts: ProcessingText.Controller,
		scope: Lifecycle.Lifecycle,
		actionScope: Lifecycle.Lifecycle,
		labels: { [string]: TextLabel },
		buttons: { [string]: GuiButton },
		touchControls: Frame?,
		touchJump: Frame?,
		touchAttack: Frame?,
		touchSprint: Frame?,
		throwStick: Frame?,
		jumpControlButton: ImageButton?,
		attackButton: ImageButton?,
		canAttack: boolean,
		canThrow: boolean,
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
			touchControls = nil,
			touchJump = nil,
			touchAttack = nil,
			touchSprint = nil,
			throwStick = nil,
			jumpControlButton = nil,
			attackButton = nil,
			painting = false,
			windowOpen = false,
			canAttack = false,
			canThrow = false,
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
function Manager.RefreshTouchVisibility(self: Manager): ()
	local isTouch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	local show = isTouch and not self.painting and not self.windowOpen
	if self.touchControls then
		self.touchControls.Visible = show
	end
	if self.touchJump then
		self.touchJump.Visible = show
	end
	if self.touchAttack then
		self.touchAttack.Visible = show and self.canAttack
	end
	if self.throwStick then
		self.throwStick.Visible = show and self.canThrow
	end
	if self.touchSprint then
		self.touchSprint.Visible = show
	end
end
function Manager.Refresh(self: Manager, state: DisplayState): ()
	if not self.gui then
		return
	end
	self.painting = state.painting
	self.windowOpen = state.windowOpen == true
	self.canAttack = state.canAttack == true
	self.canThrow = state.canThrow == true
	if not state.painting or GuiService.MenuIsOpen then
		self:ApplyBrushCursor(false)
	end
	self.buttons.ExitPaintButton.Visible = state.painting
	self.buttons.ResetViewButton.Visible = state.painting
	local paintFrame = self.paintFrame
	if paintFrame then
		paintFrame.Visible = state.painting
	end
	local bar = if self.root then self.root:FindFirstChild("BottomButtonsFrame") else nil
	if bar and bar:IsA("GuiObject") then
		bar.Visible = not state.painting
	end
	self:RefreshTouchVisibility()
end
function Manager.SetPainting(self: Manager, painting: boolean): ()
	self:Refresh({ painting = painting, hasTarget = false })
end
function Manager.SetProgress(self: Manager, progress: number): ()
	local label = self.labels.ProgressText
	if label then
		label.Text = NumberExtension.FormatBigNumberAA(math.floor(progress * 100)) .. "%"
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
function Manager.UnbindActions(self: Manager): ()
	self.actionScope:Destroy()
	self.actionScope = Lifecycle.new()
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
	self.actionScope:Connect(attack.InputBegan:Connect(function(input: InputObject): ()
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			actions.attack()
		end
	end))
end
function Manager.Init(self: Manager, gui: ScreenGui, owned: boolean?): ()
	if self.gui == gui then
		return
	end
	self:Destroy()
	self.gui, self.owned = gui, owned == true
	self.scope = Lifecycle.new()
	local root = gui:WaitForChild("CenterFrame") :: Frame
	local overlay = gui:WaitForChild("OverlayCanvas") :: Frame
	self.root = root
	local touchControls = root:WaitForChild("TouchControlsFrame") :: Frame
	self.touchControls = touchControls
	local touchJump = touchControls:WaitForChild("TouchJumpFrame") :: Frame
	self.touchJump = touchJump
	self.jumpControlButton = touchJump:WaitForChild("JumpButton") :: ImageButton
	local touchAttack = touchControls:WaitForChild("TouchAttackFrame") :: Frame
	self.touchAttack = touchAttack
	self.attackButton = touchAttack:WaitForChild("AttackButton") :: ImageButton
	self.touchSprint = touchControls:WaitForChild("TouchSprintFrame") :: Frame
	self.throwStick = touchControls:WaitForChild("ThrowStick") :: Frame
	for _, node in gui:GetDescendants() do
		if node:IsA("TextLabel") and node.Name ~= "ShadowText" then
			self.texts:Watch(node)
			if node:IsDescendantOf(root) or node:IsDescendantOf(overlay) then
				self.labels[node.Name] = node
			end
		end
	end
	for _, name in { "ExitPaintButton", "ResetViewButton" } do
		self.buttons[name] = root:WaitForChild(name) :: GuiButton
	end
	self.paintFrame = root:WaitForChild("PaintFrame") :: Frame
	self.fill = root:FindFirstChild("FillFrame", true) :: Frame
	self.scope:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function(): ()
		self:RefreshTouchVisibility()
	end))
	self.scope:Connect(gui.Destroying:Connect(function(): ()
		self.owned = false
		self:Destroy()
	end))
	self:RefreshTouchVisibility()
end
function Manager.GetJumpButton(self: Manager): ImageButton
	return assert(self.jumpControlButton, "Touch jump button is not initialized")
end
function Manager.GetSprintButton(self: Manager): ImageButton
	local frame = assert(self.touchSprint, "Touch sprint template is not initialized")
	return frame:WaitForChild("SprintButton") :: ImageButton
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
	for _, name in { "CenterFrame", "WindowCanvas", "OverlayCanvas", "ModalButton" } do
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
	self.scope:Destroy()
	self.texts:Destroy()
	local gui, owned = self.gui, self.owned
	self.gui, self.root, self.paintFrame, self.fill = nil, nil, nil, nil
	self.touchControls, self.touchJump, self.touchAttack, self.touchSprint, self.throwStick = nil, nil, nil, nil, nil
	self.jumpControlButton, self.attackButton = nil, nil
	self.painting, self.windowOpen, self.canAttack, self.canThrow = false, false, false, false
	self.owned = false
	table.clear(self.labels)
	table.clear(self.buttons)
	if gui and owned then
		gui:Destroy()
	end
end
return Manager
