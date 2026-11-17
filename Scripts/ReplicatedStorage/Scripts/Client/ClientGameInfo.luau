-- 客户端基础资料视图：本地与其他玩家缓存、通行证查询映射及离场清理
--!strict
local Config = require(script.Parent.Parent.Shared.GameConfig)
local ClientMsg = require(script.Parent.ClientMsg)
local profile: Config.ClientLocalPlayerInfo? = nil
local others: { [number]: Config.ClientOtherPlayerInfo } = {}
local Info = {}
function Info.InitPlayerInfo(
	value: Config.ClientLocalPlayerSaveInfo,
	otherPlayers: { [string]: Config.ClientOtherPlayerSyncInfo }?,
	config: Config.PlayerConfigInfo?
): ()
	local owned: { [number]: boolean } = {}
	for _, id in value.ownedGamePassList do
		owned[id] = true
	end
	profile = {
		coins = value.coins,
		settingInfo = table.clone(value.settingInfo),
		ownedGamePassList = table.clone(value.ownedGamePassList),
		ownedGamePassMap = owned,
		playerConfigInfo = table.clone(config or {}),
	}
	table.clear(others)
	local received: { [string]: Config.ClientOtherPlayerSyncInfo } = otherPlayers or {}
	for key, info in received do
		local id = tonumber(key)
		if id then
			others[id] = table.clone(info)
		end
	end
	ClientMsg.FireLocalPlayerInfoInit()
end
function Info.InitOtherPlayerInfo(id: number, value: Config.ClientOtherPlayerSyncInfo): ()
	others[id] = table.clone(value)
	ClientMsg.FireOtherPlayerInfoInit(id)
end
function Info.GetOtherPlayerInfo(id: number): Config.ClientOtherPlayerInfo?
	return others[id]
end
function Info.RemoveOtherPlayerInfo(id: number): ()
	others[id] = nil
end
function Info.GetLocalPlayerInfo(): Config.ClientLocalPlayerInfo?
	return profile
end
function Info.SetLocalPlayerGamePassAcquired(id: number): ()
	local current = profile
	if not current or current.ownedGamePassMap[id] then
		return
	end
	table.insert(current.ownedGamePassList, id)
	current.ownedGamePassMap[id] = true
	ClientMsg.FireLocalPlayerAcquiredGamePass(id)
end
function Info.Destroy(): ()
	profile = nil
	table.clear(others)
end
return Info
