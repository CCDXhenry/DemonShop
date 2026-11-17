-- 固定画布包装器：复用父画布缩放，独立画布只维护自身视口缩放
--!strict
local Lifecycle = require(script.Parent.Parent.Parent.Shared.LifecycleTool)
local GuiWrapperBase = require(script.Parent.GuiWrapperBase)
local UIActions = require(script.Parent.UIActions)
local Wrapper = {}
setmetatable(Wrapper, GuiWrapperBase)
Wrapper.__index = Wrapper
export type GameFrameWrapper =
	GuiWrapperBase.GuiWrapperBase
	& typeof(setmetatable({} :: { gameFrame: Frame, cameraCleanup: (() -> ())?, canvasBound: boolean? }, Wrapper))
function Wrapper.new(frame: Frame, actions: UIActions.UIActions): GameFrameWrapper
	local self = setmetatable(GuiWrapperBase.new(frame, actions) :: GameFrameWrapper, Wrapper)
	self.gameFrame = frame
	self:Init()
	return self
end
function Wrapper.Init(self: GameFrameWrapper): ()
	if self.canvasBound then
		return
	end
	self.canvasBound = true
	GuiWrapperBase.Init(self)
	local parent = self.gameFrame.Parent
	if parent and parent:IsA("GuiObject") then
		return
	end
	local scale = self.gameFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		return
	end
	local scope = self.scope
	assert(scope)
	local function Resize(): ()
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = math.min(camera.ViewportSize.X / 1920, camera.ViewportSize.Y / 1080)
		end
	end
	local cameraScope = Lifecycle.new()
	local function BindCamera(): ()
		cameraScope:Destroy()
		cameraScope = Lifecycle.new()
		local camera = workspace.CurrentCamera
		if camera then
			cameraScope:Connect(camera:GetPropertyChangedSignal("ViewportSize"):Connect(Resize))
		end
		Resize()
	end
	scope:Connect(self.gameFrame.Destroying:Connect(function(): ()
		cameraScope:Destroy()
	end))
	self.cameraCleanup = function(): ()
		cameraScope:Destroy()
	end
	scope:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(BindCamera))
	BindCamera()
end
function Wrapper.OnDestroy(self: GameFrameWrapper): ()
	self.canvasBound = false
	if self.cameraCleanup then
		self.cameraCleanup()
		self.cameraCleanup = nil
	end
	GuiWrapperBase.OnDestroy(self)
end
return Wrapper
