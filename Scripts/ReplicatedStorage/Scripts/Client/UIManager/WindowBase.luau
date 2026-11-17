-- 窗口基类：管理显示动画、窗口动作与关闭清理
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local tweenService: TweenService = game:GetService("TweenService")
local UIActions = require(script.Parent:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions

local WindowOpenScaleTweenInfo: TweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local GameSoundTool = require(sharedScripts:WaitForChild("GameSoundTool"))
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
		scope: LifecycleTool.Lifecycle,
		onClosed: (() -> ())?,
	},
	WindowBase
))

function WindowBase.new(frame: Frame, windowId: string, uiActions: UIActions, openAnimation: string?): WindowBase
	local self: WindowBase = setmetatable({}, WindowBase) :: WindowBase
	self.frame = frame
	self.windowId = windowId
	self.uiActions = uiActions
	self.openAnimation = openAnimation
	self.scope = LifecycleTool.new()
	return self
end

local function PlayScaleOpenAnimation(window: Frame, scope: LifecycleTool.Lifecycle): ()
 local scale = window:FindFirstChild("AnimationScale")
 if not scale or not scale:IsA("UIScale") then return end
 scale.Scale = 0
 local tween = tweenService:Create(scale, WindowOpenScaleTweenInfo, { Scale = 1 })
 scope:Play(tween)
end

function WindowBase.OnInit(self: WindowBase): ()
	GameSoundTool.Play("UIOpen")
	if self.openAnimation == WindowBase.OpenAnimation.Scale then
		PlayScaleOpenAnimation(self.frame, self.scope)
	end
end

function WindowBase.OnClose(self: WindowBase): ()
	GameSoundTool.Play("UIClose")
	local onClosed = self.onClosed
	self.onClosed = nil
	if onClosed then onClosed() end
	self.scope:Destroy()
		self.frame:Destroy()
end

function WindowBase.Close(self: WindowBase): ()
	self.uiActions.closeWindow(self.windowId)
end

function WindowBase.CloseWindow(self: WindowBase, windowId: string): ()
	self.uiActions.closeWindow(windowId)
end

function WindowBase.CloseAllWindow(self: WindowBase): ()
	self.uiActions.closeAllWindow()
end

function WindowBase.OpenWindow(self: WindowBase, windowId: string, ...: any): ()
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
