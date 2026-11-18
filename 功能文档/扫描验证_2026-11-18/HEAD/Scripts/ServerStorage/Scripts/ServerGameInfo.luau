-- 服务端原生资料：公开普通 PlayerInfo，私有记录负责租约、串行快照和修订保护
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local SaveRules = require(Shared.SaveRules)
local ProfileRules = require(Shared.PlayerProfileRules)
local Config = require(Shared.GameConfig)
local Net = require(Shared.NetMsg)
local Store = require(script.Parent.ServerPlayerSaveStore)
local ServerMsg = require(script.Parent.ServerMsg)
export type PlayerInfo = Config.PlayerInfo
type Session = { revision: number, closing: boolean, saving: boolean, releasing: boolean }
local records: { [Player]: PlayerInfo } = {}
local sessions: { [Player]: Session } = {}
local store: Store.ServerPlayerSaveStore? = nil
local Info = {}
local function NewSession(): Session
	return { revision = 0, closing = false, saving = false, releasing = false }
end
local function Date(timestamp: number): Config.DateTimeTable
	local date = os.date("!*t", timestamp)
	return { Year = date.year, Month = date.month, Day = date.day, Hour = 0, Minute = 0, Second = 0, Millisecond = 0 }
end
function Info.Init(value: Store.ServerPlayerSaveStore): ()
	assert(store == nil or store == value, "Player store already initialized")
	store = value
end
function Info.GetPlayerInfo(player: Player): PlayerInfo?
	return records[player]
end
function Info.IsActive(player: Player): boolean
	local session = sessions[player]
	return records[player] ~= nil and session ~= nil and not session.closing and not session.releasing and store ~= nil and store:IsActive(player.UserId)
end
function Info.MarkPlayerInfoChanged(player: Player): ()
	local info, session = records[player], sessions[player]
	if info and session then
		session.revision += 1
		info.playerInfoChanged = true
	end
end
function Info.SendPlayerInfo(player: Player): ()
	local info, session = records[player], sessions[player]
	if not info or not session or session.closing or session.releasing then
		return
	end
	local others: { [string]: Config.ClientOtherPlayerSyncInfo } = {}
	for other in records do
		local otherSession = sessions[other]
		if other ~= player and otherSession and not otherSession.closing then
			others[tostring(other.UserId)] = {}
		end
	end
	Net.FireNotifyPlayerInfoInit(
		player,
		{ coins = info.coins, settingInfo = table.clone(info.settingInfo), ownedGamePassList = table.clone(info.ownedGamePassList) },
		others,
		table.clone(info.playerConfigInfo)
	)
end
function Info.AcquirePlayerSaveInfo(player: Player): (Config.PlayerSaveInfo?, string?)
	if sessions[player] then
		return nil, "alreadyLoading"
	end
	local currentStore = store
	assert(currentStore, "Player store not initialized")
	local session = NewSession()
	sessions[player] = session
	local ok, value, reason = currentStore:Acquire(player.UserId)
	if session.releasing then
		-- 退出流程已拥有释放操作；等待它完成，避免对同一租约并发 Release。
		while sessions[player] == session do
			task.wait()
		end
		return nil, reason or "playerLeft"
	end
	if not ok or not player.Parent then
		currentStore:Release(player.UserId)
		if sessions[player] == session then
			sessions[player] = nil
		end
		return nil, reason or "playerLeft"
	end
	return SaveRules.Copy(value :: SaveRules.Profile), nil
end
function Info.InitPlayerInfo(player: Player, playerSaveInfo: Config.PlayerSaveInfo, countryRegion: string, playerConfigInfo: Config.PlayerConfigInfo): ()
	assert(records[player] == nil, "Player info already initialized")
	local valid, reason = SaveRules.Validate(playerSaveInfo)
	assert(valid, reason)
	local session = sessions[player] or NewSession()
	assert(not session.closing and not session.releasing, "Player session is closing")
	sessions[player] = session
	local oldDays, oldDate = playerSaveInfo.loginDays, playerSaveInfo.lastOnlineDateUTC
	local info: PlayerInfo = {
		dataVersion = playerSaveInfo.dataVersion,
		coins = playerSaveInfo.coins,
		firstEnterTime = playerSaveInfo.firstEnterTime,
		firstEnterVersion = playerSaveInfo.firstEnterVersion,
		gameTime = playerSaveInfo.gameTime,
		loginDays = oldDays,
		lastOnlineDateUTC = oldDate,
		settingInfo = table.clone(playerSaveInfo.settingInfo),
		ownedGamePassList = table.clone(playerSaveInfo.ownedGamePassList),
		playerInfoChanged = false,
		timeOfThisLogin = os.time(),
		countryRegion = countryRegion,
		lastOnlineDate = Date(oldDate),
		ownedGamePassMap = {},
		playerConfigInfo = table.clone(playerConfigInfo),
	}
	ProfileRules.Login(info, os.time())
	info.lastOnlineDate = Date(info.lastOnlineDateUTC)
	info.playerInfoChanged = info.loginDays ~= oldDays or info.lastOnlineDateUTC ~= oldDate
	session.revision = 1
	for _, id in info.ownedGamePassList do
		info.ownedGamePassMap[id] = true
	end
	records[player] = info
	player:SetAttribute("Coins", info.coins)
	ServerMsg.FirePlayerInfoInit(player)
	Info.SendPlayerInfo(player)
	Net.FireNotifyPlayersOtherPlayerInfoInit(player.UserId, {})
end
function Info.CreatePlayerSaveInfoByPlayerInfo(info: Config.PlayerInfo): Config.PlayerSaveInfo
	return {
		dataVersion = info.dataVersion,
		coins = info.coins,
		firstEnterTime = info.firstEnterTime,
		firstEnterVersion = info.firstEnterVersion,
		gameTime = info.gameTime,
		loginDays = info.loginDays,
		lastOnlineDateUTC = info.lastOnlineDateUTC,
		settingInfo = table.clone(info.settingInfo),
		ownedGamePassList = table.clone(info.ownedGamePassList),
	}
end
function Info.ChangePlayerLoginDays(player: Player, loginDays: number, date: Config.DateTimeTable): ()
	local info = records[player]
	if not Info.IsActive(player) or not info or loginDays ~= loginDays or loginDays % 1 ~= 0 or loginDays < info.loginDays then
		return
	end
	local ok, timestamp = pcall(function(): number
		return DateTime.fromUniversalTime(date.Year, date.Month, date.Day).UnixTimestamp
	end)
	if not ok or timestamp < info.lastOnlineDateUTC then
		return
	end
	info.loginDays = loginDays
	info.lastOnlineDateUTC = timestamp
	info.lastOnlineDate = Date(timestamp)
	Info.MarkPlayerInfoChanged(player)
end
function Info.CanAddCoins(player: Player, coins: number): boolean
	local info = records[player]
	return Info.IsActive(player) and info ~= nil and coins == coins and coins >= 0 and coins % 1 == 0 and info.coins <= Config.MaximumCoins - coins
end
function Info.AddCoins(player: Player, coins: number): boolean
	if not Info.CanAddCoins(player, coins) then
		return false
	end
	local info = records[player]
	info.coins += coins
	Info.MarkPlayerInfoChanged(player)
	player:SetAttribute("Coins", info.coins)
	Info.SendPlayerInfo(player)
	return true
end
function Info.UpdateSetting(player: Player, key: string, value: unknown): boolean
	local info = records[player]
	if not Info.IsActive(player) or not info or not ProfileRules.Setting(info, key, value) then
		return false
	end
	Info.MarkPlayerInfoChanged(player)
	Info.SendPlayerInfo(player)
	return true
end
function Info.SetPlayerGamePassAcquired(player: Player, id: number): boolean
	local info = records[player]
	if not Info.IsActive(player) or not info or not ProfileRules.GrantPass(info, id) then
		return false
	end
	info.ownedGamePassMap[id] = true
	Info.MarkPlayerInfoChanged(player)
	Net.FireNotifyPlayerAcquiredGamePass(player, id)
	return true
end
function Info.Tick(player: Player, seconds: number): ()
	local info = records[player]
	if Info.IsActive(player) and info and ProfileRules.AddTime(info, seconds) then
		ProfileRules.Login(info, os.time())
		info.lastOnlineDate = Date(info.lastOnlineDateUTC)
		Info.MarkPlayerInfoChanged(player)
	end
end
Info.AddPlayerGameTime = Info.Tick
function Info.Freeze(player: Player): ()
	local session = sessions[player]
	if session then
		session.closing = true
	end
	player:SetAttribute("GameReady", false)
end
function Info.Save(player: Player): (boolean, string?)
	local info, session, currentStore = records[player], sessions[player], store
	if not info or not session or not currentStore then
		return false, "missingPlayer"
	end
	-- 在等待前不抓快照，兼容基础模块直接修改普通 PlayerInfo 的调用方式。
	while session.saving and not session.releasing do
		task.wait()
	end
	if sessions[player] ~= session or session.releasing then
		return false, "missingPlayer"
	end
	session.saving = true
	local revision = session.revision
	local snapshot = Info.CreatePlayerSaveInfoByPlayerInfo(info)
	local ok, reason = currentStore:Save(player.UserId, snapshot, revision)
	if ok then
		local current = Info.CreatePlayerSaveInfoByPlayerInfo(info)
		info.playerInfoChanged = session.revision ~= revision or not SaveRules.Equal(snapshot, current)
	end
	session.saving = false
	return ok, reason
end
function Info.RemovePlayerInfo(player: Player): ()
	local session = sessions[player]
	if session then
		if session.releasing then
			return
		end
		session.releasing = true
		while session.saving do
			task.wait()
		end
	end
	local currentStore = store
	if currentStore then
		currentStore:Release(player.UserId)
	end
	local existed = records[player] ~= nil
	records[player] = nil
	sessions[player] = nil
	if existed then
		Net.FireNotifyPlayerLeft(player.UserId)
	end
end
function Info.Reset(): ()
	assert(next(records) == nil and next(sessions) == nil, "Player data must be released before reset")
	store = nil
end
return Info
