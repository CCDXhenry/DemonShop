--!strict
local UIActions = require(script.Parent:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions

local GuiWrapperBase = {}
GuiWrapperBase.__index = GuiWrapperBase

export type GuiWrapperBase = typeof(setmetatable(
	{} :: {
		uiActions: UIActions,
	},
	GuiWrapperBase
))

function GuiWrapperBase.OnDestroy(self: GuiWrapperBase) end

function GuiWrapperBase.new(gui: GuiObject, uiActions: UIActions): GuiWrapperBase
	local self: GuiWrapperBase = setmetatable({}, GuiWrapperBase) :: GuiWrapperBase
	self.uiActions = uiActions
	gui.Destroying:Connect(function()
		self:OnDestroy()
	end)
	return self
end

function GuiWrapperBase.CloseWindow(self: GuiWrapperBase, windowId: string)
	self.uiActions.closeWindow(windowId)
end

function GuiWrapperBase.CloseAllWindow(self: GuiWrapperBase)
	self.uiActions.closeAllWindow()
end

function GuiWrapperBase.OpenWindow(self: GuiWrapperBase, windowId: string, ...: any)
	self.uiActions.openWindow(windowId, ...)
end

function GuiWrapperBase.CreateFrame(self: GuiWrapperBase, frameName: string, frameParent: GuiBase2d?, zIndex: number?): Frame
	return self.uiActions.createFrame(frameName, frameParent, zIndex)
end

function GuiWrapperBase.HasShowingWindow(self: GuiWrapperBase): boolean
	return self.uiActions.hasShowingWindow()
end

function GuiWrapperBase.IsWindowShowing(self: GuiWrapperBase, windowId: string): boolean
	return self.uiActions.isWindowShowing(windowId)
end

return GuiWrapperBase
