-- 客户端游戏入口管理：绑定玩家通知并初始化预置 UI 与视口适配
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local SoundTool = require(coreSharedScripts:FindFirstChild("SoundTool"))
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)
local GameFrameWrapper = require(uiManagerScript:FindFirstChild("GameFrameWrapper"))
local players: Players = game:GetService("Players")
local starterGui: StarterGui = game:GetService("StarterGui")

local soundsFolder: Folder = workspace:FindFirstChild("Sounds")
local bgmSound: Sound = soundsFolder:FindFirstChild("BGM") :: Sound

local ClientGameManager = {}
ClientGameManager.__index = ClientGameManager

export type ClientGameManager = typeof(setmetatable({}, ClientGameManager))

local DesignScreenSize: Vector2 = Vector2.new(1920, 1080)

assert(players.LocalPlayer)

local function InitUI()
	local playerGui: PlayerGui = players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local uiTemplates = replicatedStorage:WaitForChild("UI")
	local screenTemplate = uiTemplates:FindFirstChild("GameScreenGui")
	assert(screenTemplate and screenTemplate:IsA("ScreenGui"), "缺少 UI.GameScreenGui 预置模板")
	local existing = playerGui:FindFirstChild("GameScreenGui")
	if existing then existing:Destroy() end
	local gameScreenGui: ScreenGui = screenTemplate:Clone()
	gameScreenGui.Parent = playerGui
	--禁用默认工具栏
	starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	--设置窗口容器
	UIManager.Init(gameScreenGui)
	local uiActions = UIManager.GetUIActions()
	--创建游戏主界面
	local gameFrame: Frame = UIManager.CreateFrame("GameFrame", gameScreenGui, 0)
	GameFrameWrapper.new(gameFrame, uiActions)
	--UI适配器初始化
	UIAdapter.Init(DesignScreenSize, gameScreenGui.AbsoluteSize)
	gameScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		UIAdapter.OnScreenSizeChange(gameScreenGui.AbsoluteSize)
	end)
end

--通知客户端玩家信息初始化
local function OnNotifyPlayerInfoInit(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
)
	ClientGameInfo.InitPlayerInfo(localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo ~= nil then
		SoundTool.SetBGMVolumn(localPlayerInfo.settingInfo.bgmVolume)
		SoundTool.SetSoundEffectVolume(localPlayerInfo.settingInfo.soundEffectVolume)
	end
	SoundTool.PlayBGM(bgmSound)
	--初始化UI
	task.spawn(function()
		InitUI()
	end)
end

local function OnNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo)
	if playerId ~= players.LocalPlayer.UserId then
		ClientGameInfo.InitOtherPlayerInfo(playerId, otherPlayerSaveInfo)
	end
end

local function OnNotifyPlayerAcquiredGamePass(gamePassId: number)
	ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId)
end

function ClientGameManager.new(): ClientGameManager
	return setmetatable({}, ClientGameManager) :: ClientGameManager
end

function ClientGameManager.Init(self: ClientGameManager)
	NetMsg.ConnectNotifyPlayerInfoInit(OnNotifyPlayerInfoInit)
	NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(OnNotifyPlayersOtherPlayerInfoInit)
	NetMsg.ConnectNotifyPlayerAcquiredGamePass(OnNotifyPlayerAcquiredGamePass)
end

return ClientGameManager
