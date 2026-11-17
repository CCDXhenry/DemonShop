-- 玩家资料纯规则：UTC 登录、在线时长、设置和通行证变更
--!strict
local Config = require(script.Parent.GameConfig)
export type MutableProfile = {
	loginDays: number,
	lastOnlineDateUTC: number,
	gameTime: number,
	settingInfo: Config.SettingInfo,
	ownedGamePassList: { number },
}
local Rules = {}
function Rules.Login(profile: MutableProfile, now: number): ()
	local day = math.floor(now / 86400) * 86400
	if profile.loginDays == 0 or day > profile.lastOnlineDateUTC then
		profile.loginDays += 1
		profile.lastOnlineDateUTC = day
	end
end
function Rules.AddTime(profile: MutableProfile, seconds: number): boolean
	if seconds ~= seconds or seconds <= 0 or seconds == math.huge then
		return false
	end
	profile.gameTime = math.min(Config.MaximumCoins, profile.gameTime + seconds)
	return true
end
function Rules.Setting(profile: MutableProfile, key: string, value: unknown): boolean
	if key == "vibrationOn" then
		if type(value) ~= "boolean" or profile.settingInfo.vibrationOn == value then
			return false
		end
		profile.settingInfo.vibrationOn = value
	elseif key == "bgmVolume" or key == "soundEffectVolume" then
		if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
			return false
		end
		if key == "bgmVolume" then
			if profile.settingInfo.bgmVolume == value then
				return false
			end
			profile.settingInfo.bgmVolume = value
		else
			if profile.settingInfo.soundEffectVolume == value then
				return false
			end
			profile.settingInfo.soundEffectVolume = value
		end
	else
		return false
	end
	return true
end
function Rules.GrantPass(profile: MutableProfile, id: number): boolean
	if id ~= id or id <= 0 or id % 1 ~= 0 or id > Config.MaximumCoins or table.find(profile.ownedGamePassList, id) then
		return false
	end
	table.insert(profile.ownedGamePassList, id)
	return true
end
return Rules
