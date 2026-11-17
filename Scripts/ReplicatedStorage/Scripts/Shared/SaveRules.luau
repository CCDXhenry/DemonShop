-- 玩家存档纯规则：迁移金币旧档，校验基础资料并生成独立保存快照
--!strict
local Config = require(script.Parent.GameConfig)
export type Settings = Config.SettingInfo
-- 版本 2 的实际持久化形状仅属于保存边界，不污染基础 GameConfig 类型。
export type Profile = {
	version: number,
	coins: number,
	settingInfo: Settings,
	firstEnterTime: number,
	firstEnterVersion: string,
	gameTime: number,
	loginDays: number,
	lastOnlineDateUTC: number,
	ownedGamePassList: { number },
}
local Rules = {}
local function Finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Integer(value: unknown): boolean
	return Finite(value) and (value :: number) >= 0 and (value :: number) % 1 == 0 and (value :: number) <= Config.MaximumCoins
end
function Rules.New(now: number?): Profile
	return Rules.FromPlayerSaveInfo(Config.CreateDefaultPlayerSaveInfo(now))
end
function Rules.FromPlayerSaveInfo(info: Config.PlayerSaveInfo): Profile
	return {
		version = info.dataVersion,
		coins = info.coins,
		settingInfo = table.clone(info.settingInfo),
		firstEnterTime = info.firstEnterTime,
		firstEnterVersion = info.firstEnterVersion,
		gameTime = info.gameTime,
		loginDays = info.loginDays,
		lastOnlineDateUTC = info.lastOnlineDateUTC,
		ownedGamePassList = table.clone(info.ownedGamePassList),
	}
end
function Rules.ToPlayerSaveInfo(profile: Profile): Config.PlayerSaveInfo
	return {
		dataVersion = profile.version,
		coins = profile.coins,
		settingInfo = table.clone(profile.settingInfo),
		firstEnterTime = profile.firstEnterTime,
		firstEnterVersion = profile.firstEnterVersion,
		gameTime = profile.gameTime,
		loginDays = profile.loginDays,
		lastOnlineDateUTC = profile.lastOnlineDateUTC,
		ownedGamePassList = table.clone(profile.ownedGamePassList),
	}
end
function Rules.Validate(value: unknown): (boolean, string?)
	if type(value) ~= "table" then
		return false, "invalidProfile"
	end
	local p = value :: { [string]: unknown }
	if p.version ~= Config.SaveVersion then
		return false, "invalidVersion"
	end
	if not Integer(p.coins) then
		return false, "invalidCoins"
	end
	if
		not Integer(p.firstEnterTime)
		or type(p.firstEnterVersion) ~= "string"
		or #p.firstEnterVersion > 64
		or not Finite(p.gameTime)
		or (p.gameTime :: number) < 0
		or (p.gameTime :: number) > Config.MaximumCoins
		or not Integer(p.loginDays)
		or not Integer(p.lastOnlineDateUTC)
	then
		return false, "invalidStatistics"
	end
	if type(p.settingInfo) ~= "table" then
		return false, "invalidSettings"
	end
	local settings = p.settingInfo :: { [string]: unknown }
	for _, key in { "bgmVolume", "soundEffectVolume" } do
		local v = settings[key]
		if not Finite(v) or (v :: number) < 0 or (v :: number) > 1 then
			return false, "invalidSettings"
		end
	end
	if type(settings.vibrationOn) ~= "boolean" then
		return false, "invalidSettings"
	end
	if type(p.ownedGamePassList) ~= "table" then
		return false, "invalidPasses"
	end
	local passes = p.ownedGamePassList :: { [unknown]: unknown }
	local seen: { [number]: boolean } = {}
	local count = 0
	for index, id in passes do
		if not Integer(index) or (index :: number) < 1 or (index :: number) > #passes or not Integer(id) or (id :: number) < 1 or seen[id :: number] then
			return false, "invalidPasses"
		end
		seen[id :: number] = true
		count += 1
	end
	if count ~= #passes then
		return false, "invalidPasses"
	end
	return true, nil
end
function Rules.Copy(profile: Profile): Profile
	local result = table.clone(profile)
	result.settingInfo = table.clone(profile.settingInfo)
	result.ownedGamePassList = table.clone(profile.ownedGamePassList)
	return result
end
function Rules.Equal(a: Profile, b: Profile): boolean
	for _, key in { "version", "coins", "firstEnterTime", "firstEnterVersion", "gameTime", "loginDays", "lastOnlineDateUTC" } do
		local left = (a :: unknown) :: { [string]: unknown }
		local right = (b :: unknown) :: { [string]: unknown }
		if left[key] ~= right[key] then
			return false
		end
	end
	if
		a.settingInfo.bgmVolume ~= b.settingInfo.bgmVolume
		or a.settingInfo.soundEffectVolume ~= b.settingInfo.soundEffectVolume
		or a.settingInfo.vibrationOn ~= b.settingInfo.vibrationOn
		or #a.ownedGamePassList ~= #b.ownedGamePassList
	then
		return false
	end
	for i, id in a.ownedGamePassList do
		if b.ownedGamePassList[i] ~= id then
			return false
		end
	end
	return true
end
function Rules.Migrate(value: unknown, now: number?): (Profile?, string?)
	if type(value) ~= "table" then
		return nil, "invalidProfile"
	end
	local old = value :: { [string]: unknown }
	if old.version == 1 then
		if not Integer(old.coins) then
			return nil, "invalidCoins"
		end
		local result = Rules.New(now)
		result.coins = old.coins :: number
		return result, nil
	end
	local valid, reason = Rules.Validate(value)
	return if valid then Rules.Copy(value :: Profile) else nil, reason
end
return Rules
