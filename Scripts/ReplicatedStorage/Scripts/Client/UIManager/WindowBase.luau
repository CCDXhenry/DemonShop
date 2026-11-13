--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local tweenService: TweenService = game:GetService("TweenService")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))

local UIActions = require(script.Parent:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions

local WindowOpenScaleTweenInfo: TweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local WindowBase = {}
WindowBase.__index = WindowBase

WindowBase.OpenAnimation = {
	Scale = "Scale",
}

export type WindowBase = typeof(setmetatable(
	{} :: {
		frame: Frame,
		windowId: string,
		uiActions: UIActions,
		openAnimation: string?,
	},
	WindowBase
))

function WindowBase.new(frame: Frame, windowId: string, uiActions: UIActions, openAnimation: string?): WindowBase
	local self: WindowBase = setmetatable({}, WindowBase) :: WindowBase
	self.frame = frame
	self.windowId = windowId
	self.uiActions = uiActions
	self.openAnimation = openAnimation
	return self
end

local function OnOpenAnimScaleValueChanged(window: Frame, openAnimScaleValue: NumberValue)
	UIAdapter.SetOpenAnimScale(window, openAnimScaleValue.Value)
	UIAdapter.RefreshAdaptiveFrame(window)
end

local function OnScaleOpenAnimationCompleted(window: Frame, openAnimScaleValue: NumberValue, playbackState: Enum.PlaybackState)
	if playbackState == Enum.PlaybackState.Completed then
		UIAdapter.SetOpenAnimScale(window, 1)
		UIAdapter.RefreshAdaptiveFrame(window)
	end
	openAnimScaleValue:Destroy()
end

local function PlayScaleOpenAnimation(window: Frame)
	UIAdapter.SetOpenAnimScale(window, 0)
	local openAnimScaleValue: NumberValue = Instance.new("NumberValue")
	openAnimScaleValue.Name = "OpenAnimScaleValue"
	openAnimScaleValue.Value = 0
	openAnimScaleValue.Parent = window
	openAnimScaleValue:GetPropertyChangedSignal("Value"):Connect(function()
		OnOpenAnimScaleValueChanged(window, openAnimScaleValue)
	end)
	local openAnimScaleTween: Tween = tweenService:Create(openAnimScaleValue, WindowOpenScaleTweenInfo, { Value = 1 })
	openAnimScaleTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		OnScaleOpenAnimationCompleted(window, openAnimScaleValue, playbackState)
	end)
	openAnimScaleTween:Play()
end

function WindowBase.OnInit(self: WindowBase)
	if self.openAnimation == WindowBase.OpenAnimation.Scale then
		PlayScaleOpenAnimation(self.frame)
	end
end

function WindowBase.OnClose(self: WindowBase)
	UIAdapter.RemoveAdaptiveFrame(self.frame)
	self.frame:Destroy()
end

function WindowBase.Close(self: WindowBase)
	self.uiActions.closeWindow(self.windowId)
end

function WindowBase.CloseWindow(self: WindowBase, windowId: string)
	self.uiActions.closeWindow(windowId)
end

function WindowBase.CloseAllWindow(self: WindowBase)
	self.uiActions.closeAllWindow()
end

function WindowBase.OpenWindow(self: WindowBase, windowId: string, ...: any)
	self.uiActions.openWindow(windowId, ...)
end

function WindowBase.CreateFrame(self: WindowBase, frameName: string, frameParent: GuiBase2d?, zIndex: number?): Frame
	return self.uiActions.createFrame(frameName, frameParent, zIndex)
end

function WindowBase.HasShowingWindow(self: WindowBase): boolean
	return self.uiActions.hasShowingWindow()
end

function WindowBase.IsWindowShowing(self: WindowBase, windowId: string): boolean
	return self.uiActions.isWindowShowing(windowId)
end

return WindowBase
