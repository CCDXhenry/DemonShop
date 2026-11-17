-- 基础网络契约：恢复参考框架具名事件，加工旧接口仅转发到独立协议
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.GameConfig)
local Processing = require(script.Parent.ProcessingNet)
local folder = ReplicatedStorage:WaitForChild("RemoteEvents")
local Net = {}
local RequestSetBGMVolume = folder:WaitForChild("RequestSetBGMVolume") :: RemoteEvent
function Net.FireRequestSetBGMVolume(volume: number): ()
	RequestSetBGMVolume:FireServer(volume)
end
function Net.ConnectRequestSetBGMVolume(callback: (Player, number) -> ()): RBXScriptConnection
	return RequestSetBGMVolume.OnServerEvent:Connect(function(player: Player, volume: number): ()
		if type(volume) == "number" and volume == volume and volume >= 0 and volume <= 1 then
			callback(player, volume)
		end
	end)
end
local RequestSetSoundEffectVolume = folder:WaitForChild("RequestSetSoundEffectVolume") :: RemoteEvent
function Net.FireRequestSetSoundEffectVolume(volume: number): ()
	RequestSetSoundEffectVolume:FireServer(volume)
end
function Net.ConnectRequestSetSoundEffectVolume(callback: (Player, number) -> ()): RBXScriptConnection
	return RequestSetSoundEffectVolume.OnServerEvent:Connect(function(player: Player, volume: number): ()
		if type(volume) == "number" and volume == volume and volume >= 0 and volume <= 1 then
			callback(player, volume)
		end
	end)
end
local RequestSetVibrationsOnOffState = folder:WaitForChild("RequestSetVibrationsOnOffState") :: RemoteEvent
function Net.FireRequestSetVibrationsOnOffState(vibrationsOn: boolean): ()
	RequestSetVibrationsOnOffState:FireServer(vibrationsOn)
end
function Net.ConnectRequestSetVibrationsOnOffState(callback: (Player, boolean) -> ()): RBXScriptConnection
	return RequestSetVibrationsOnOffState.OnServerEvent:Connect(function(player: Player, vibrationsOn: boolean): ()
		if type(vibrationsOn) == "boolean" then
			callback(player, vibrationsOn)
		end
	end)
end
local NotifyPlayerInfoInit = folder:WaitForChild("NotifyPlayerInfoInit") :: RemoteEvent
function Net.FireNotifyPlayerInfoInit(
	player: Player,
	localPlayerSaveInfo: Config.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: Config.ClientOtherPlayerSyncInfo },
	playerConfigInfo: Config.PlayerConfigInfo
): ()
	NotifyPlayerInfoInit:FireClient(player, localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
end
function Net.ConnectNotifyPlayerInfoInit(
	callback: (Config.ClientLocalPlayerSaveInfo, { [string]: Config.ClientOtherPlayerSyncInfo }, Config.PlayerConfigInfo) -> ()
): RBXScriptConnection
	return NotifyPlayerInfoInit.OnClientEvent:Connect(callback)
end
local NotifyPlayersOtherPlayerInfoInit = folder:WaitForChild("NotifyPlayersOtherPlayerInfoInit") :: RemoteEvent
function Net.FireNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: Config.ClientOtherPlayerSyncInfo): ()
	NotifyPlayersOtherPlayerInfoInit:FireAllClients(playerId, otherPlayerSaveInfo)
end
function Net.ConnectNotifyPlayersOtherPlayerInfoInit(callback: (number, Config.ClientOtherPlayerSyncInfo) -> ()): RBXScriptConnection
	return NotifyPlayersOtherPlayerInfoInit.OnClientEvent:Connect(callback)
end
local NotifyPlayerAcquiredGamePass = folder:WaitForChild("NotifyPlayerAcquiredGamePass") :: RemoteEvent
function Net.FireNotifyPlayerAcquiredGamePass(player: Player, gamePassId: number): ()
	NotifyPlayerAcquiredGamePass:FireClient(player, gamePassId)
end
function Net.ConnectNotifyPlayerAcquiredGamePass(callback: (number) -> ()): RBXScriptConnection
	return NotifyPlayerAcquiredGamePass.OnClientEvent:Connect(callback)
end
local NotifyPlayerLeft = folder:WaitForChild("NotifyPlayerLeft") :: RemoteEvent
function Net.FireNotifyPlayerLeft(playerId: number): ()
	NotifyPlayerLeft:FireAllClients(playerId)
end
function Net.ConnectNotifyPlayerLeft(callback: (number) -> ()): RBXScriptConnection
	return NotifyPlayerLeft.OnClientEvent:Connect(callback)
end
local handshake = folder:WaitForChild("FoundationRequest") :: RemoteEvent
function Net.FireRequestPlayerInfoInit(): ()
	handshake:FireServer({ action = "RequestPlayerInfoInit" })
end
function Net.ConnectRequestPlayerInfoInit(callback: (Player) -> ()): RBXScriptConnection
	return handshake.OnServerEvent:Connect(function(player: Player, value: unknown): ()
		if type(value) ~= "table" then
			return
		end
		local request = value :: { [string]: unknown }
		if request.action == "RequestPlayerInfoInit" and request.value == nil then
			callback(player)
		end
	end)
end
Net.Validate = Processing.Validate
Net.FireRequest = Processing.FireRequest
Net.ConnectRequest = Processing.ConnectRequest
Net.FireNotify = Processing.FireNotify
Net.Broadcast = Processing.Broadcast
Net.ConnectNotify = Processing.ConnectNotify
return Net
