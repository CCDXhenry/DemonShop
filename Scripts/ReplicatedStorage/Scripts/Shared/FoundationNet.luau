-- 基础网络兼容适配器：具名事件是唯一传输路径，旧通知事件不再派发
--!strict
local Config = require(script.Parent.GameConfig)
local NetMsg = require(script.Parent.NetMsg)
export type Request = { action: string, value: unknown? }
export type Notice = {
	kind: string,
	localInfo: Config.ClientLocalPlayerSaveInfo?,
	otherPlayers: { [string]: Config.ClientOtherPlayerSyncInfo }?,
	playerConfigInfo: Config.PlayerConfigInfo?,
	gamePassId: number?,
	playerId: number?,
	otherInfo: Config.ClientOtherPlayerSyncInfo?,
}
export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }
local Net = {}
local function Combine(connections: { RBXScriptConnection }): Connection
	return {
		Connected = true,
		Disconnect = function(self: Connection): ()
			if not self.Connected then
				return
			end
			self.Connected = false
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
	}
end
function Net.Validate(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local r = value :: { [string]: unknown }
	if r.action == "RequestPlayerInfoInit" then
		return r.value == nil
	end
	if r.action == "SetVibrationsOnOffState" then
		return type(r.value) == "boolean"
	end
	if r.action == "SetBGMVolume" or r.action == "SetSoundEffectVolume" then
		return type(r.value) == "number" and r.value == r.value and r.value >= 0 and r.value <= 1
	end
	return false
end
function Net.ConnectRequest(callback: (Player, Request) -> ()): Connection
	return Combine({
		NetMsg.ConnectRequestPlayerInfoInit(function(p: Player): ()
			callback(p, { action = "RequestPlayerInfoInit" })
		end),
		NetMsg.ConnectRequestSetBGMVolume(function(p: Player, v: number): ()
			callback(p, { action = "SetBGMVolume", value = v })
		end),
		NetMsg.ConnectRequestSetSoundEffectVolume(function(p: Player, v: number): ()
			callback(p, { action = "SetSoundEffectVolume", value = v })
		end),
		NetMsg.ConnectRequestSetVibrationsOnOffState(function(p: Player, v: boolean): ()
			callback(p, { action = "SetVibrationsOnOffState", value = v })
		end),
	})
end
function Net.ConnectNotify(callback: (Notice) -> ()): Connection
	return Combine({
		NetMsg.ConnectNotifyPlayerInfoInit(function(info, others, config): ()
			callback({ kind = "PlayerInfoInit", localInfo = info, otherPlayers = others, playerConfigInfo = config })
		end),
		NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(function(id, info): ()
			callback({ kind = "OtherPlayerInfoInit", playerId = id, otherInfo = info })
		end),
		NetMsg.ConnectNotifyPlayerAcquiredGamePass(function(id): ()
			callback({ kind = "GamePassAcquired", gamePassId = id })
		end),
		NetMsg.ConnectNotifyPlayerLeft(function(id): ()
			callback({ kind = "PlayerLeft", playerId = id })
		end),
	})
end
function Net.FireNotify(player: Player, notice: Notice): ()
	if notice.kind == "PlayerInfoInit" and notice.localInfo then
		NetMsg.FireNotifyPlayerInfoInit(player, notice.localInfo, notice.otherPlayers or {}, notice.playerConfigInfo or {})
	elseif notice.kind == "GamePassAcquired" and notice.gamePassId then
		NetMsg.FireNotifyPlayerAcquiredGamePass(player, notice.gamePassId)
	end
end
function Net.FireRequest(request: Request): ()
	if not Net.Validate(request) then
		return
	end
	if request.action == "RequestPlayerInfoInit" then
		NetMsg.FireRequestPlayerInfoInit()
	elseif request.action == "SetBGMVolume" then
		NetMsg.FireRequestSetBGMVolume(request.value :: number)
	elseif request.action == "SetSoundEffectVolume" then
		NetMsg.FireRequestSetSoundEffectVolume(request.value :: number)
	elseif request.action == "SetVibrationsOnOffState" then
		NetMsg.FireRequestSetVibrationsOnOffState(request.value :: boolean)
	end
end
Net.RequestPlayerInfoInit = NetMsg.FireRequestPlayerInfoInit
Net.RequestSetBGMVolume = NetMsg.FireRequestSetBGMVolume
Net.RequestSetSoundEffectVolume = NetMsg.FireRequestSetSoundEffectVolume
Net.RequestSetVibrationsOnOffState = NetMsg.FireRequestSetVibrationsOnOffState
return Net
