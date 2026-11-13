-- 主界面包装器：注册固定画布适配并管理生命周期
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))

local GuiWrapperBase = require(script.Parent:FindFirstChild("GuiWrapperBase"))
type GuiWrapperBase = GuiWrapperBase.GuiWrapperBase
local UIActions = require(script.Parent:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions

local GameFrameWrapper = {}
setmetatable(GameFrameWrapper, GuiWrapperBase)
GameFrameWrapper.__index = GameFrameWrapper

export type GameFrameWrapper =
	GuiWrapperBase
	& typeof(setmetatable(
		{} :: {
			gameFrame: Frame,
		},
		GameFrameWrapper
	))

function GameFrameWrapper.new(gameFrame: Frame, uiActions: UIActions): GameFrameWrapper
	local self: GameFrameWrapper = setmetatable(GuiWrapperBase.new(gameFrame, uiActions) :: GameFrameWrapper, GameFrameWrapper)
	self.gameFrame = gameFrame
	UIAdapter.AddAdaptiveFrame(gameFrame, UIAdapter.AdaptiveType.Center)
	return self
end

function GameFrameWrapper.OnDestroy(self: GameFrameWrapper)
	GuiWrapperBase.OnDestroy(self)
end

return GameFrameWrapper
