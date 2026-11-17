-- 服务端基础资料：唯一持有玩家存档、修订号与租约，提供加工和设置共享接口
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local SaveRules = require(Shared.SaveRules)
local ProfileRules = require(Shared.PlayerProfileRules)
local Config = require(Shared.GameConfig)
local Net = require(Shared.NetMsg)
local Store = require(script.Parent.ServerPlayerSaveStore)
local ServerMsg = require(script.Parent.ServerMsg)
export type PlayerInfo = Config.PlayerInfo & { profile: SaveRules.Profile, revision: number, savedRevision: number, closing: boolean }
local ProfileView = {
	__index = function(record: { [string]: unknown }, key: string): unknown
		local profile = record.profile :: SaveRules.Profile
		if key == "dataVersion" then
			return profile.version
		end
		if key == "playerInfoChanged" then
			return (record.revision :: number) > (record.savedRevision :: number)
		end
		return ((profile :: unknown) :: { [string]: unknown })[key]
	end,
	__newindex = function(record: { [string]: unknown }, key: string, value: unknown): ()
		if key == "playerInfoChanged" then
			if value == true then
				rawset(record, "revision", (record.revision :: number) + 1)
			end
			return
		end
		local profile = (record.profile :: unknown) :: { [string]: unknown }
		local field = if key == "dataVersion" then "version" else key
		if profile[field] ~= nil then
			profile[field] = value
		else
			rawset(record, key, value)
		end
	end,
}
local records: { [Player]: PlayerInfo } = {}
local store: Store.ServerPlayerSaveStore? = nil
local Info = {}
function Info.Init(value: Store.ServerPlayerSaveStore): ()
	assert(store == nil or store == value, "Player store already initialized")
	store = value
end
function Info.GetPlayerInfo(player: Player): PlayerInfo?
	return records[player]
end
function Info.IsActive(player: Player): boolean
	local record = records[player]
	return record ~= nil and not record.closing and store ~= nil and store:IsActive(player.UserId)
end
function Info.MarkPlayerInfoChanged(player: Player): ()
	local record = records[player]
	if record then
		record.revision += 1
	end
end
function Info.SendPlayerInfo(player: Player): ()
	local record = records[player]
	if not record or record.closing then
		return
	end
	local others: { [string]: Config.ClientOtherPlayerSyncInfo } = {}
	for other, value in records do
		if other ~= player and not value.closing then
			others[tostring(other.UserId)] = {}
		end
	end
	Net.FireNotifyPlayerInfoInit(
		player,
		{
			coins = record.profile.coins,
			settingInfo = table.clone(record.profile.settingInfo),
			ownedGamePassList = table.clone(record.profile.ownedGamePassList),
		},
		others,
		table.clone(record.playerConfigInfo)
	)
end
function Info.InitPlayerInfo(player: Player, playerSaveInfo: Config.PlayerSaveInfo, countryRegion: string, playerConfigInfo: Config.PlayerConfigInfo): ()
	assert(records[player] == nil, "Player info already initialized")
	local profile = SaveRules.FromPlayerSaveInfo(playerSaveInfo)
	local owned: { [number]: boolean } = {}
	for _, id in profile.ownedGamePassList do
		owned[id] = true
	end
	local date = os.date("!*t", profile.lastOnlineDateUTC)
	records[player] = (
		setmetatable({
			profile = profile,
			revision = 1,
			savedRevision = 0,
			closing = false,
			timeOfThisLogin = os.time(),
			countryRegion = countryRegion,
			playerConfigInfo = table.clone(playerConfigInfo),
			lastOnlineDate = { Year = date.year, Month = date.month, Day = date.day, Hour = 0, Minute = 0, Second = 0, Millisecond = 0 },
			ownedGamePassMap = owned,
		}, ProfileView) :: unknown
	) :: PlayerInfo
	player:SetAttribute("Coins", profile.coins)
	ServerMsg.FirePlayerInfoInit(player)
	Net.FireNotifyPlayersOtherPlayerInfoInit(player.UserId, {})
end
function Info.CreatePlayerSaveInfoByPlayerInfo(record: Config.PlayerInfo): Config.PlayerSaveInfo
	return {
		dataVersion = record.dataVersion,
		coins = record.coins,
		settingInfo = table.clone(record.settingInfo),
		firstEnterTime = record.firstEnterTime,
		firstEnterVersion = record.firstEnterVersion,
		gameTime = record.gameTime,
		loginDays = record.loginDays,
		lastOnlineDateUTC = record.lastOnlineDateUTC,
		ownedGamePassList = table.clone(record.ownedGamePassList),
	}
end
function Info.ChangePlayerLoginDays(player: Player, loginDays: number, date: Config.DateTimeTable): ()
	local record = records[player]
	if not record or not Info.IsActive(player) or loginDays % 1 ~= 0 or loginDays < record.profile.loginDays then
		return
	end
	local ok, timestamp = pcall(function(): number
		return DateTime.fromUniversalTime(date.Year, date.Month, date.Day).UnixTimestamp
	end)
	if not ok or timestamp < record.profile.lastOnlineDateUTC then
		return
	end
	record.profile.loginDays = loginDays
	record.profile.lastOnlineDateUTC = timestamp
	record.lastOnlineDate = table.clone(date)
	Info.MarkPlayerInfoChanged(player)
end
function Info.Load(player: Player, countryRegion: string?, playerConfigInfo: Config.PlayerConfigInfo?): (boolean, string?)
	if records[player] then
		return true, nil
	end
	local currentStore = store
	assert(currentStore, "Player store not initialized")
	local ok, value, reason = currentStore:Acquire(player.UserId)
	if not ok then
		currentStore:Release(player.UserId)
		return false, reason
	end
	if not player.Parent then
		currentStore:Release(player.UserId)
		return false, "playerLeft"
	end
	local profile = SaveRules.Copy(value :: SaveRules.Profile)
	ProfileRules.Login(profile, os.time())
	Info.InitPlayerInfo(player, SaveRules.ToPlayerSaveInfo(profile), countryRegion or "unknown", playerConfigInfo or Config.DefaultPlayerConfig)
	return true, nil
end
function Info.CanAddCoins(player: Player, coins: number): boolean
	local record = records[player]
	return Info.IsActive(player) and record ~= nil and coins == coins and coins >= 0 and coins % 1 == 0 and record.profile.coins <= Config.MaximumCoins - coins
end
function Info.AddCoins(player: Player, coins: number): boolean
	if not Info.CanAddCoins(player, coins) then
		return false
	end
	local record = records[player]
	record.profile.coins += coins
	Info.MarkPlayerInfoChanged(player)
	player:SetAttribute("Coins", record.profile.coins)
	Info.SendPlayerInfo(player)
	return true
end
function Info.UpdateSetting(player: Player, key: string, value: unknown): boolean
	local record = records[player]
	if not Info.IsActive(player) or not record or not ProfileRules.Setting(record.profile, key, value) then
		return false
	end
	Info.MarkPlayerInfoChanged(player)
	Info.SendPlayerInfo(player)
	return true
end
function Info.SetPlayerGamePassAcquired(player: Player, id: number): boolean
	local record = records[player]
	if not Info.IsActive(player) or not record or not ProfileRules.GrantPass(record.profile, id) then
		return false
	end
	Info.MarkPlayerInfoChanged(player)
	record.ownedGamePassMap[id] = true
	Net.FireNotifyPlayerAcquiredGamePass(player, id)
	return true
end
function Info.Tick(player: Player, seconds: number): ()
	local record = records[player]
	if record and Info.IsActive(player) and ProfileRules.AddTime(record.profile, seconds) then
		ProfileRules.Login(record.profile, os.time())
		local date = os.date("!*t", record.profile.lastOnlineDateUTC)
		record.lastOnlineDate = { Year = date.year, Month = date.month, Day = date.day, Hour = 0, Minute = 0, Second = 0, Millisecond = 0 }
		Info.MarkPlayerInfoChanged(player)
	end
end
function Info.Freeze(player: Player): ()
	local record = records[player]
	if record then
		record.closing = true
	end
	player:SetAttribute("GameReady", false)
end
function Info.Save(player: Player): (boolean, string?)
	local record, currentStore = records[player], store
	if not record or not currentStore then
		return false, "missingPlayer"
	end
	local revision = record.revision
	local ok, reason = currentStore:Save(player.UserId, SaveRules.FromPlayerSaveInfo(Info.CreatePlayerSaveInfoByPlayerInfo(record)), revision)
	if ok then
		record.savedRevision = math.max(record.savedRevision, revision)
	end
	return ok, reason
end
function Info.RemovePlayerInfo(player: Player): ()
	local currentStore = store
	if currentStore then
		currentStore:Release(player.UserId)
	end
	local existed = records[player] ~= nil
	records[player] = nil
	if existed then
		Net.FireNotifyPlayerLeft(player.UserId)
	end
end
Info.AddPlayerGameTime = Info.Tick
function Info.Reset(): ()
	assert(next(records) == nil, "Player data must be released before reset")
	store = nil
end
return Info
