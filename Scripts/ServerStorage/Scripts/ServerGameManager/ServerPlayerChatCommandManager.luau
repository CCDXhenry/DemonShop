-- 聊天管理器：保留 GM 校验，只有配置本项目清档目标时才注册命令
--!strict
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TeleportService = game:GetService("TeleportService")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Lifecycle = require(ReplicatedStorage.Scripts.Shared.LifecycleTool)
local GMConfig = require(ServerStorage.Core.Scripts.GMConfig)
local Manager = {}
Manager.__index = Manager
export type Manager = typeof(setmetatable({} :: { scope: Lifecycle.Lifecycle? }, Manager))
function Manager.new(): Manager
	return setmetatable({ scope = nil }, Manager)
end
function Manager.Init(self: Manager): ()
	if self.scope then
		return
	end
	local scope = Lifecycle.new()
	self.scope = scope
	if Config.ClearDataStorePlaceId <= 0 then
		return
	end
	local folder = TextChatService:FindFirstChild("CustomTextChatCommands")
	local command = folder and folder:FindFirstChild("ClearDataStoreCommand")
	if not command or not command:IsA("TextChatCommand") then
		warn("[Chat] Missing configured clear-data command")
		return
	end
	scope:Connect(command.Triggered:Connect(function(source: TextSource): ()
		if RunService:IsStudio() or not GMConfig.IsGMPlayer(source.UserId) then
			return
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then
			return
		end
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ gameStartPlaceId = Config.GamePlaceId, defaultPlayerSaveInfo = Config.CreateDefaultPlayerSaveInfo() })
		local ok, reason = pcall(function(): boolean
			TeleportService:TeleportAsync(Config.ClearDataStorePlaceId, { player }, options)
			return true
		end)
		options:Destroy()
		if not ok then
			warn("[Chat] Clear-data teleport failed", reason)
		end
	end))
end
function Manager.Destroy(self: Manager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end
export type ServerPlayerChatCommandManager = Manager
return Manager
