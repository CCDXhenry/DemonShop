-- 客户端基础入口：资料握手、音效设置、UI 框架与加工子系统的幂等装配
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Scripts.Shared
local Net = require(Shared.NetMsg)
local Config = require(Shared.GameConfig)
local Sound = require(Shared.GameSoundTool)
local Lifecycle = require(Shared.LifecycleTool)
local Info = require(script.Parent.ClientGameInfo)
local UIManager = require(script.Parent.UIManager)
local Processing = require(script.Parent.ClientProcessingManager)
local Manager = {}
Manager.__index = Manager
export type Manager = typeof(setmetatable(
	{} :: { initialized: boolean, started: boolean, scope: Lifecycle.Lifecycle, processing: Processing.Client?, lastSync: number },
	Manager
))
function Manager.new(): Manager
	return setmetatable({ initialized = false, started = false, scope = Lifecycle.new(), processing = nil, lastSync = -math.huge }, Manager)
end
function Manager.OnPlayerInfo(
	self: Manager,
	value: Config.ClientLocalPlayerSaveInfo,
	others: { [string]: Config.ClientOtherPlayerSyncInfo },
	config: Config.PlayerConfigInfo
): ()
	Info.InitPlayerInfo(value, others, config)
	Sound.SetBGMVolume(value.settingInfo.bgmVolume)
	Sound.SetSoundEffectVolume(value.settingInfo.soundEffectVolume)
	Sound.SetVibrationsOnOffState(value.settingInfo.vibrationOn)
	if self.started then
		return
	end
	local gui = UIManager.CreateGameScreenGui()
	local processing = Processing.new()
	self.processing = processing
	processing:Init(gui)
	self.started = true
	Sound.PlayBGM()
end
function Manager.Init(self: Manager): ()
	if self.initialized then
		return
	end
	self.initialized = true
	Sound.Init()
	self.scope:Connect(Net.ConnectNotifyPlayerInfoInit(function(value, others, config): ()
		self:OnPlayerInfo(value, others, config)
	end))
	self.scope:Connect(Net.ConnectNotifyPlayersOtherPlayerInfoInit(function(id, info): ()
		if id ~= Players.LocalPlayer.UserId then
			Info.InitOtherPlayerInfo(id, info)
		end
	end))
	self.scope:Connect(Net.ConnectNotifyPlayerAcquiredGamePass(Info.SetLocalPlayerGamePassAcquired))
	self.scope:Connect(Net.ConnectNotifyPlayerLeft(Info.RemoveOtherPlayerInfo))
	self.scope:Connect(RunService.Heartbeat:Connect(function(): ()
		if not self.started and os.clock() - self.lastSync >= 3 then
			self.lastSync = os.clock()
			Net.FireRequestPlayerInfoInit()
		end
	end))
	Net.FireRequestPlayerInfoInit()
	self.lastSync = os.clock()
end
function Manager.Destroy(self: Manager): ()
	if not self.initialized then
		return
	end
	self.scope:Destroy()
	if self.processing then
		self.processing:Destroy()
		self.processing = nil
	end
	UIManager.Destroy()
	Sound.Destroy()
	Info.Destroy()
	self.initialized = false
	self.started = false
end
export type ClientGameManager = Manager
return Manager
