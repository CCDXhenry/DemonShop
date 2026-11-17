-- 界面管理器：维护模板克隆、窗口栈、模态遮罩和交互资源
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local tweenService: TweenService = game:GetService("TweenService")
local userInputService: UserInputService = game:GetService("UserInputService")
local UIManager = {}
local LifecycleTool = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local scope = LifecycleTool.new()
local initialized = false
local buttonScopes: { [GuiButton]: LifecycleTool.Lifecycle } = {}

local uiTemplatesFolder: Folder = replicatedStorage:FindFirstChild("UI") :: Folder
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local WindowBase = require(script:FindFirstChild("WindowBase"))
type WindowBase = WindowBase.WindowBase
local UIActions = require(script:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions
local TextFitting = require(script:WaitForChild("TextFitting"))
local GameSoundTool = require(script.Parent.Parent.Shared.GameSoundTool)
local windowOrder: { string } = {}
local viewportScope: LifecycleTool.Lifecycle? = nil

local GameFrameWrapper = require(script.GameFrameWrapper)
local GameScreenGuiManager = require(script.GameScreenGuiManager)
local TargetGuiManager = require(script.TargetGuiManager)
local PaintFaceGuiManager = require(script.PaintFaceGuiManager)
local PaintCellFrameManager = require(script.PaintCellFrameManager)
local ScreenLayoutGuideFrameManager = require(script.ScreenLayoutGuideFrameManager)
local screenManager = GameScreenGuiManager.new()
local targetManager = TargetGuiManager.new()
local faceManager = PaintFaceGuiManager.new()
local cellManager = PaintCellFrameManager.new()
local guideManager = ScreenLayoutGuideFrameManager.new()
export type PaintFaceManager = PaintFaceGuiManager.Manager
export type PaintCellManager = PaintCellFrameManager.Manager
local hudWrapper: GameFrameWrapper.GameFrameWrapper? = nil

local ModalTransparency: number = 0.4
local ButtonHoveredScale: number = 1.1 --按钮鼠标移入放大
local ButtonPressedScale: number = 0.8 --按钮按下缩小
local ButtonInteractionTweenInfo: TweenInfo = TweenInfo.new(0.1) --按钮交互动画缓动信息

export type WindowConfig = {
	frameName: string,
	isModal: boolean,
	modalTransparency: number?,
	openAnimation: string?,
	newWindow: (frame: Frame, windowId: string, uiActions: UIActions, ...any) -> WindowBase,
}

local WindowConfigs: { [string]: WindowConfig } = {}

local addedWindows: { [string]: WindowBase } = {}
local gameScreenGui: ScreenGui?
local modalButton: ImageButton
local interactionEffectAppliedButtons: { [GuiButton]: boolean } = {}
local uiActions: UIActions

local function SetWindowLayer(frame: Frame, layer: number): ()
	local previous = frame.ZIndex
	for _, obj in frame:GetDescendants() do
		if obj:IsA("GuiObject") then
			obj.ZIndex = layer + math.max(0, obj.ZIndex - previous)
		end
	end
	frame.ZIndex = layer
end

function UIManager.RegisterWindow(windowId: string, config: WindowConfig): ()
	assert(not addedWindows[windowId], "Cannot replace an open window configuration")
	WindowConfigs[windowId] = config
end

local function MarkButtonApplied(appliedButtons: { [GuiButton]: boolean }, button: GuiButton): ()
	appliedButtons[button] = true
	scope:Connect(button.Destroying:Connect(function()
		appliedButtons[button] = nil
	end))
end

local function CheckModalButtonVisible(): ()
	if not initialized then
		return
	end
	local topModalWindow: Frame?
	local topModalWindowConfig: WindowConfig?
	local modalTransparency: number = 1
	for windowId: string, window: WindowBase in addedWindows do
		local windowConfig: WindowConfig = WindowConfigs[windowId]
		if windowConfig.isModal then
			if topModalWindow == nil or window.frame.ZIndex > topModalWindow.ZIndex then
				topModalWindow = window.frame
				topModalWindowConfig = windowConfig
			end
			modalTransparency *= windowConfig.modalTransparency or ModalTransparency
		end
	end
	if topModalWindow == nil or topModalWindowConfig == nil then
		modalButton.Visible = false
	else
		modalButton.Visible = true
		modalButton.ZIndex = topModalWindow.ZIndex - 1
		modalButton.BackgroundTransparency = modalTransparency
	end
end

--给按钮加点击和悬停缩放效果
local function ApplyButtonEffects(button: GuiButton): ()
	--如果按钮不需要交互效果
	if not button:GetAttribute("HasInteractionEffect") then
		return
	end
	if interactionEffectAppliedButtons[button] then
		return
	end
	--确保按钮有UIScale
	local uiScale: UIScale? = button:FindFirstChildOfClass("UIScale") :: UIScale?
	if uiScale == nil then
		return
	end
	local buttonScope = LifecycleTool.new()
	buttonScopes[button] = buttonScope
	buttonScope:Connect(button.Destroying:Connect(function(): ()
		buttonScope:Destroy()
		buttonScopes[button] = nil
		interactionEffectAppliedButtons[button] = nil
	end))
	MarkButtonApplied(interactionEffectAppliedButtons, button)
	local normalScale: number = uiScale.Scale
	local hoveredScale: number = ButtonHoveredScale * normalScale
	local pressedScale: number = ButtonPressedScale * normalScale
	local mouseEnterTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = hoveredScale })
	local mouseLeaveTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	local clickTween1: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = pressedScale })
	local clickTween2: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	buttonScope:Connect(clickTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed then
			buttonScope:Play(clickTween2)
		end
	end))
	buttonScope:Connect(button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			buttonScope:Play(mouseEnterTween)
		end
	end))
	buttonScope:Connect(button.MouseLeave:Connect(function()
		if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			buttonScope:Play(mouseLeaveTween)
		end
	end))
	buttonScope:Connect(button.Activated:Connect(function(inputObject: InputObject, clickCount: number)
		GameSoundTool.Play("UIClick")
		buttonScope:Play(clickTween1)
	end))
end

-- 基础框架创建唯一主 GUI；兼容外部传入 Init(gui) 的调用方式。
function UIManager.CreateGameScreenGui(): ScreenGui
	if gameScreenGui then
		return gameScreenGui
	end
	local gui = screenManager:Create()
	UIManager.Init(gui)
	return gui
end

--初始化
function UIManager.Init(gameScreenGuiNew: ScreenGui): ()
	if initialized then
		return
	end
	initialized = true
	if not scope.alive then
		scope = LifecycleTool.new()
	end
	screenManager:Init(gameScreenGuiNew)
	gameScreenGui = gameScreenGuiNew
	if gameScreenGui == nil then
		return
	end
	modalButton = gameScreenGuiNew:WaitForChild("ModalButton") :: ImageButton
	local canvas = gameScreenGuiNew:WaitForChild("WindowCanvas") :: Frame
	local scale = canvas:WaitForChild("UIScale") :: UIScale
	local cameraScope = LifecycleTool.new()
	local function Resize(): ()
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = math.min(camera.ViewportSize.X / 1920, camera.ViewportSize.Y / 1080)
		end
	end
	local function BindCamera(): ()
		cameraScope:Destroy()
		cameraScope = LifecycleTool.new()
		viewportScope = cameraScope
		local camera = workspace.CurrentCamera
		if camera then
			cameraScope:Connect(camera:GetPropertyChangedSignal("ViewportSize"):Connect(Resize))
		end
		Resize()
	end
	scope:Connect(canvas.Destroying:Connect(function(): ()
		cameraScope:Destroy()
	end))
	scope:Connect(gameScreenGuiNew.Destroying:Connect(function(): ()
		UIManager.Destroy()
	end))
	scope:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(BindCamera))
	scope:Connect(modalButton.Activated:Connect(function(): ()
		for index = #windowOrder, 1, -1 do
			local id = windowOrder[index]
			if WindowConfigs[id].isModal then
				UIManager.CloseWindow(id)
				break
			end
		end
	end))
	BindCamera()
	local center = gameScreenGuiNew:FindFirstChild("CenterFrame")
	if center and center:IsA("Frame") then
		local wrapper = GameFrameWrapper.new(center, uiActions)
		hudWrapper = wrapper
		wrapper:Init()
	end
	TextFitting.FitMarkedRoot(gameScreenGuiNew)

	local uiParents: { Instance } = { workspace, gameScreenGui }
	for uiParentIndex: number, uiParent: Instance in uiParents do
		scope:Connect(uiParent.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end))
		for descendantIndex: number, descendant: Instance in uiParent:GetDescendants() do
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end
	end
end

--非窗口方式创建界面
function UIManager.CreateFrame(frameName: string, frameParent: GuiBase2d?, ZIndex: number?): Frame
	if frameName == "ScreenLayoutGuideFrame" then
		assert(frameParent, "Design guide requires an explicit parent")
		local frame = guideManager:Create(frameParent)
		if ZIndex then frame.ZIndex=ZIndex end
		return frame
	end
	if frameName == "PaintCellFrame" then
		return cellManager:Create(frameParent or gameScreenGui, ZIndex)
	end
	local template = uiTemplatesFolder:FindFirstChild(frameName)
	assert(template and template:IsA("Frame"), "Missing UI template: " .. frameName)
	local frame: Frame = template:Clone()
	if frameParent == nil then
		frame.Parent = gameScreenGui
	else
		frame.Parent = frameParent
	end
	if ZIndex ~= nil then
		frame.ZIndex = ZIndex
	end
	return frame
end

function UIManager.FitTextLabel(label: TextLabel, options: TextFitting.TextFitOptions?): number
	return TextFitting.FitTextLabel(label, options)
end

function UIManager.FitTextWithShadow(label: TextLabel, shadow: Instance?, options: TextFitting.TextFitOptions?): number
	return TextFitting.FitTextWithShadow(label, shadow, options)
end

function UIManager.FitMarkedText(label: TextLabel): number?
	return TextFitting.FitMarkedText(label)
end

function UIManager.FitMarkedRoot(root: Instance): ()
	TextFitting.FitMarkedRoot(root)
end

--打开窗口
function UIManager.OpenWindow(windowId: string, ...: any): ()
	if gameScreenGui == nil then
		return
	end
	local existingWindow: WindowBase? = addedWindows[windowId]
	if existingWindow ~= nil then
		return
	end
	local windowConfig: WindowConfig? = WindowConfigs[windowId]
	if windowConfig == nil then
		return
	end
	local template = uiTemplatesFolder:FindFirstChild(windowConfig.frameName)
	if not template or not template:IsA("Frame") then
		warn("[UIManager] Missing window template", windowConfig.frameName)
		return
	end
	local frame = template:Clone()
	local canvas = gameScreenGui:FindFirstChild("WindowCanvas")
	assert(canvas and canvas:IsA("Frame"), "Missing WindowCanvas template")
	frame.Parent = canvas
	local window: WindowBase = windowConfig.newWindow(frame, windowId, uiActions, ...)
	if windowConfig.openAnimation ~= nil then
		window.openAnimation = windowConfig.openAnimation
	end
	addedWindows[windowId] = window
	table.insert(windowOrder, windowId)
	SetWindowLayer(frame, 100 + #windowOrder * 100)
	window:OnInit()
	CheckModalButtonVisible()
	ClientMsg.FireOpenWindow(windowId)
end

--窗口是否展示中
function UIManager.IsWindowShowing(windowId: string): boolean
	local window: WindowBase? = addedWindows[windowId]
	return window ~= nil
end

--关闭窗口
function UIManager.CloseWindow(windowId: string): ()
	local window: WindowBase? = addedWindows[windowId]
	if window == nil then
		return
	end
	addedWindows[windowId] = nil
	local orderIndex = table.find(windowOrder, windowId)
	if orderIndex then
		table.remove(windowOrder, orderIndex)
	end
	for index, id in windowOrder do
		SetWindowLayer(addedWindows[id].frame, 100 + index * 100)
	end
	window:OnClose()
	CheckModalButtonVisible()
	ClientMsg.FireCloseWindow(windowId)
end

--切换窗口显示状态
function UIManager.SwitchWindowShowing(windowId: string): ()
	if UIManager.IsWindowShowing(windowId) then
		UIManager.CloseWindow(windowId)
	else
		UIManager.OpenWindow(windowId)
	end
end

--关闭所有窗口
function UIManager.CloseAllWindow(): ()
	local closingWindows: { { windowId: string, window: WindowBase } } = {}
	for windowId: string, window: WindowBase in pairs(addedWindows) do
		table.insert(closingWindows, { windowId = windowId, window = window })
	end
	table.clear(addedWindows)
	table.clear(windowOrder)
	CheckModalButtonVisible()
	for _: number, entry: { windowId: string, window: WindowBase } in pairs(closingWindows) do
		entry.window:OnClose()
		ClientMsg.FireCloseWindow(entry.windowId)
	end
end

--是否有窗口正在展示中
function UIManager.HasShowingWindow(): boolean
	for _: string, _: WindowBase in pairs(addedWindows) do
		return true
	end
	return false
end

uiActions = {
	closeWindow = UIManager.CloseWindow,
	closeAllWindow = UIManager.CloseAllWindow,
	openWindow = UIManager.OpenWindow,
	createFrame = UIManager.CreateFrame,
	hasShowingWindow = UIManager.HasShowingWindow,
	isWindowShowing = UIManager.IsWindowShowing,
}

function UIManager.GetUIActions(): UIActions
	return uiActions
end

function UIManager.GetGameScreenGuiManager(): GameScreenGuiManager.Manager
	return screenManager
end
function UIManager.GetTargetGuiManager(): TargetGuiManager.Manager
	return targetManager
end
function UIManager.GetPaintFaceGuiManager(): PaintFaceGuiManager.Manager
	return faceManager
end
function UIManager.GetPaintCellFrameManager(): PaintCellFrameManager.Manager
	return cellManager
end
function UIManager.GetScreenLayoutGuideFrameManager(): ScreenLayoutGuideFrameManager.Manager
	return guideManager
end

function UIManager.Destroy(): ()
	screenManager:UnbindActions()
	UIManager.CloseAllWindow()
	for _, buttonScope in buttonScopes do
		buttonScope:Destroy()
	end
	table.clear(buttonScopes)
	scope:Destroy()
	if viewportScope then
		viewportScope:Destroy()
		viewportScope = nil
	end
	table.clear(interactionEffectAppliedButtons)
	if hudWrapper then
		hudWrapper:OnDestroy()
		hudWrapper = nil
	end
	gameScreenGui = nil
	initialized = false
	cellManager:Destroy()
	faceManager:Destroy()
	targetManager:Destroy()
	guideManager:Destroy()
	screenManager:Destroy()
end
return UIManager
