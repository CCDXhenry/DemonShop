-- 主界面管理器：持有主 GUI、控件缓存、文案绑定及桌面触控操作生命周期
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lifecycle = require(script.Parent.Parent.Parent.Shared.LifecycleTool)
local GameTexts = require(script.Parent.Parent.Parent.Shared.GameTexts)
local Types = require(script.Parent.Parent.Parent.Shared.GameTypes)
local ProcessingText = require(script.Parent.Parent.ProcessingTextTool)
local PaintPointer = require(script.Parent.Parent.PaintPointer)
local Manager = {}
Manager.__index = Manager
export type Actions = {
	interact: () -> (),
	drop: () -> (),
	attack: () -> (),
	exitPaint: () -> (),
	resetView: () -> (),
}
export type DisplayState = {
	painting: boolean,
	hasTarget: boolean,
	dropDescription: GameTexts.Description?,
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
		touchFrames: { [string]: Frame },
		dropLabels: { TextLabel },
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
			dropLabels = {},
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
function Manager.Refresh(self: Manager, state: DisplayState): ()
	if not self.gui then
		return
	end
	local touch = UserInputService.TouchEnabled
	local camera = workspace.CurrentCamera
	local landscape = not camera or camera.ViewportSize.X >= camera.ViewportSize.Y
	for _, name in { "InteractButton", "DropButton", "AttackButton" } do
		self.buttons[name].Visible = not state.painting and not touch
	end
	self.buttons.ExitPaintButton.Visible = state.painting and not touch
	self.buttons.ResetViewButton.Visible = state.painting and not touch
	self.touchFrames.TouchLandscapeFrame.Visible = touch and not state.painting and landscape
	self.touchFrames.TouchPortraitFrame.Visible = touch and not state.painting and not landscape
	self.touchFrames.TouchPaintFrame.Visible = touch and state.painting
	self.labels.HintKeyText.Visible = state.hasTarget and not state.painting and not touch
	local paintFrame = self.paintFrame
	if paintFrame then
		paintFrame.Visible = state.painting
	end
	if state.dropDescription then
		for _, label in self.dropLabels do
			self.texts:Bind(label, state.dropDescription)
		end
	end
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
function Manager.UpdatePointer(self: Manager, model: Model?, camera: Camera, pointer: Vector2, enabled: boolean): ()
	local root = self.root
	if root then
		PaintPointer.Update(root, model, camera, pointer, enabled)
	end
end
function Manager.UnbindActions(self: Manager): ()
	self.actionScope:Destroy()
	self.actionScope = Lifecycle.new()
end
function Manager.BindActions(self: Manager, actions: Actions): ()
	self:UnbindActions()
	local callbacks: { [string]: () -> () } = {
		InteractButton = actions.interact,
		DropButton = actions.drop,
		AttackButton = actions.attack,
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
end
function Manager.Init(self: Manager, gui: ScreenGui, owned: boolean?): ()
	if self.gui == gui then
		return
	end
	self:Destroy()
	self.gui, self.owned = gui, owned == true
	self.scope = Lifecycle.new()
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
	for _, name in { "InteractButton", "DropButton", "AttackButton", "ExitPaintButton", "ResetViewButton" } do
		self.buttons[name] = root:WaitForChild(name) :: GuiButton
	end
	table.insert(self.dropLabels, self.buttons.DropButton:WaitForChild("LabelText") :: TextLabel)
	for _, name in { "TouchLandscapeFrame", "TouchPortraitFrame", "TouchPaintFrame" } do
		local frame = gui:WaitForChild(name) :: Frame
		self.touchFrames[name] = frame
		local drop = frame:FindFirstChild("DropButton")
		if drop then
			table.insert(self.dropLabels, drop:WaitForChild("LabelText") :: TextLabel)
		end
	end
	self.paintFrame = root:WaitForChild("PaintFrame") :: Frame
	self.fill = root:FindFirstChild("FillFrame", true) :: Frame
	self.scope:Connect(gui.Destroying:Connect(function(): ()
		self.owned = false
		self:Destroy()
	end))
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
	self:UnbindActions()
	self.scope:Destroy()
	self.texts:Destroy()
	local gui, owned = self.gui, self.owned
	self.gui, self.root, self.paintFrame, self.fill = nil, nil, nil, nil
	self.owned = false
	table.clear(self.labels)
	table.clear(self.buttons)
	table.clear(self.touchFrames)
	table.clear(self.dropLabels)
	if gui and owned then
		gui:Destroy()
	end
end
return Manager
