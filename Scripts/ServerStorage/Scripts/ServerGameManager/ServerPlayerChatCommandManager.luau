-- 聊天管理器：保留 GM 校验，支持清档与非正式环境加金币命令
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
local Info = require(script.Parent.Parent.ServerGameInfo)
local Manager = {}
Manager.__index = Manager
export type Manager = typeof(setmetatable({} :: { scope: Lifecycle.Lifecycle? }, Manager))
local DefaultAddCoinsAmount = 1000
local function IsProductionEnvironment(): boolean
	if RunService:IsStudio() then
		return false
	end
	return Config.GameId > 0 and game.GameId == Config.GameId
end
local function ParseAddCoinsAmount(unfilteredText: string?): number?
	local rawArg = if type(unfilteredText) == "string" then string.match(unfilteredText, "^%S+%s+(%S+)") else nil
	if rawArg == nil then
		return DefaultAddCoinsAmount
	end
	local parsed = tonumber(rawArg)
	if not parsed or parsed ~= parsed or parsed <= 0 or parsed % 1 ~= 0 or parsed > Config.MaximumCoins then
		return nil
	end
	return parsed
end
function Manager.new(): Manager
	return setmetatable({ scope = nil }, Manager)
end
function Manager.Init(self: Manager): ()
	if self.scope then
		return
	end
	local scope = Lifecycle.new()
	self.scope = scope
	local folder = TextChatService:FindFirstChild("CustomTextChatCommands")
	if Config.ClearDataStorePlaceId > 0 then
		local command = folder and folder:FindFirstChild("ClearDataStoreCommand")
		if not command or not command:IsA("TextChatCommand") then
			warn("[Chat] Missing configured clear-data command")
		else
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
	end
	if not IsProductionEnvironment() then
		local addCommand = folder and folder:FindFirstChild("AddCoinsCommand")
		if addCommand and addCommand:IsA("TextChatCommand") then
			scope:Connect(addCommand.Triggered:Connect(function(source: TextSource, unfilteredText: string): ()
				if IsProductionEnvironment() or not GMConfig.IsGMPlayer(source.UserId) then
					return
				end
				local player = Players:GetPlayerByUserId(source.UserId)
				if not player then
					return
				end
				local amount = ParseAddCoinsAmount(unfilteredText)
				if not amount then
					return
				end
				Info.AddCoins(player, amount)
			end))
		else
			warn("[Chat] Missing AddCoinsCommand under TextChatService.CustomTextChatCommands")
		end
	end
end
function Manager.Destroy(self: Manager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end
export type ServerPlayerChatCommandManager = Manager
return Manager
