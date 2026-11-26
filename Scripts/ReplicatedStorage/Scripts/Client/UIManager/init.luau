-- 界面管理器：维护模板克隆、窗口栈、模态遮罩和交互资源
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local tweenService: TweenService = game:GetService("TweenService")
local userInputService: UserInputService = game:GetService("UserInputService")
local guiService: GuiService = game:GetService("GuiService")
local UIManager = {}
local LifecycleTool = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local scope = LifecycleTool.new()
local initialized = false
local buttonEffects: { [GuiObject]: { beginPress: (InputObject) -> (), cleanup: () -> () } } = {}

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
local ButtonPressTweenInfo = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type WindowConfig = {
	frameName: string,
	isModal: boolean,
	modalTransparency: number?,
	modalContentRegions: {string}?,
	containsModalPoint: ((Frame, ScreenGui, Vector2) -> boolean)?,
	openAnimation: string?,
	newWindow: (frame: Frame, windowId: string, uiActions: UIActions, ...any) -> WindowBase,
}

local WindowConfigs: { [string]: WindowConfig } = {}

local addedWindows: { [string]: WindowBase } = {}
local gameScreenGui: ScreenGui?
local modalButton: ImageButton
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

-- AbsolutePosition and touch Position use GUI coordinates; mouse location includes the top-bar inset.
function UIManager.GetModalPointerPosition(input: InputObject): Vector2?
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return userInputService:GetMouseLocation() - guiService:GetGuiInset()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return nil
end

local function InsideModalContent(window: Frame, config: WindowConfig, gui: ScreenGui, input: InputObject?): boolean
	if not input then return false end
	local contains = config.containsModalPoint
	if contains then
		local point = UIManager.GetModalPointerPosition(input)
		return point == nil or contains(window, gui, point)
	end
	local point = if input.UserInputType == Enum.UserInputType.MouseButton1
		then userInputService:GetMouseLocation()
		else Vector2.new(input.Position.X, input.Position.Y)
	if not gui.IgnoreGuiInset then point -= guiService:GetGuiInset() end
	local regions = config.modalContentRegions
	if not regions then return false end
	for _, name in regions do
		local region = window:FindFirstChild(name, true)
		if region and region:IsA("GuiObject") and region.Visible then
			local topLeft = region.AbsolutePosition
			local size = region.AbsoluteSize
			local visibleHeight = region:GetAttribute("ModalContentHeight") :: number? or 1
			local bottomRight = topLeft + Vector2.new(size.X, size.Y * visibleHeight)
			if point.X >= topLeft.X and point.X < bottomRight.X and point.Y >= topLeft.Y and point.Y < bottomRight.Y then
				return true
			end
		end
	end
	return false
end

-- 按钮按住时保持缩小，松开恢复设计比例。
local function ApplyButtonEffects(button: GuiButton): ()
	if not button:GetAttribute("HasInteractionEffect") or buttonEffects[button] then
		return
	end
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		return
	end

	local buttonScope = LifecycleTool.new()
	local normalScale = uiScale.Scale
	local pressedScale = button:GetAttribute("PressedScale")
	local pressRatio = if typeof(pressedScale) == "number" then pressedScale else ButtonPressedScale
	local hover = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = ButtonHoveredScale * normalScale })
	local reset = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	local press = tweenService:Create(uiScale, ButtonPressTweenInfo, { Scale = normalScale * pressRatio })
	local playing: Tween? = nil
	local heldInputConnection: RBXScriptConnection? = nil

	local function CancelTween(): ()
		if playing then
			playing:Cancel()
			playing = nil
		end
	end

	local function Play(tween: Tween): ()
		CancelTween()
		playing = tween
		buttonScope:Play(tween)
	end

	local function ClearHeldInput(): ()
		if heldInputConnection then
			heldInputConnection:Disconnect()
			heldInputConnection = nil
		end
	end

	local function RestoreScale(): ()
		ClearHeldInput()
		CancelTween()
		if uiScale.Parent == button then
			uiScale.Scale = normalScale
		end
	end

	local function BeginPress(input: InputObject): ()
		if not button.Active or not button.Interactable or not button.Visible or heldInputConnection
			or input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		heldInputConnection = input:GetPropertyChangedSignal("UserInputState"):Connect(function(): ()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				ClearHeldInput()
				Play(reset)
			end
		end)
		Play(press)
	end

	local function Cleanup(): ()
		buttonEffects[button] = nil
		RestoreScale()
		buttonScope:Destroy()
	end

	buttonEffects[button] = { beginPress = BeginPress, cleanup = Cleanup }
	buttonScope:Connect(button.Destroying:Connect(Cleanup))
	buttonScope:Connect(button.MouseEnter:Connect(function(): ()
		if button.Active and button.Interactable and not heldInputConnection
			and userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			Play(hover)
		end
	end))
	buttonScope:Connect(button.MouseLeave:Connect(function(): ()
		if not heldInputConnection and userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			Play(reset)
		end
	end))
	buttonScope:Connect(button:GetPropertyChangedSignal("Visible"):Connect(function(): ()
		if not button.Visible then
			RestoreScale()
		end
	end))
	buttonScope:Connect(button:GetPropertyChangedSignal("Interactable"):Connect(function(): ()
		if not button.Interactable then
			RestoreScale()
		end
	end))
	buttonScope:Connect(userInputService.WindowFocusReleased:Connect(function(): ()
		if heldInputConnection then
			RestoreScale()
		end
	end))
	buttonScope:Connect(button.InputBegan:Connect(function(input: InputObject): ()
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			BeginPress(input)
		end
	end))
	buttonScope:Connect(button.Activated:Connect(function(): ()
		if button:GetAttribute("HasClickSound") ~= false then GameSoundTool.Play("UIClick") end
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
	local overlay = gameScreenGuiNew:WaitForChild("OverlayCanvas") :: Frame
	local overlayScale = overlay:WaitForChild("UIScale") :: UIScale
	local cameraScope = LifecycleTool.new()
	local function Resize(): ()
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = math.min(camera.ViewportSize.X / 1920, camera.ViewportSize.Y / 1080)
			overlayScale.Scale = scale.Scale
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
	scope:Connect(modalButton.Activated:Connect(function(input: InputObject): ()
		for index = #windowOrder, 1, -1 do
			local id = windowOrder[index]
			local config = WindowConfigs[id]
			if config.isModal then
				if not InsideModalContent(addedWindows[id].frame, config, gameScreenGuiNew, input) then
					UIManager.CloseWindow(id)
				end
				break
			end
		end
	end))
	scope:Connect(userInputService.InputBegan:Connect(function(input: InputObject): ()
		if input.KeyCode == Enum.KeyCode.ButtonA then
			local selected = guiService.SelectedObject
			local effect = if selected then buttonEffects[selected] else nil
			if effect then
				effect.beginPress(input)
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

	scope:Connect(gameScreenGuiNew.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("GuiButton") then
			ApplyButtonEffects(descendant)
		end
	end))
	for _: number, descendant: Instance in gameScreenGuiNew:GetDescendants() do
		if descendant:IsA("GuiButton") then
			ApplyButtonEffects(descendant)
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
	for _, effect in buttonEffects do
		effect.cleanup()
	end
	scope:Destroy()
	if viewportScope then
		viewportScope:Destroy()
		viewportScope = nil
	end
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
