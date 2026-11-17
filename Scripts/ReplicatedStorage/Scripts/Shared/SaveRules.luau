-- 金币存档纯规则：严格校验存档版本与有限非负整数金币
--!strict
local Config = require(script.Parent.GameConfig)
export type Profile = { version: number, coins: number }
local Rules = {}
function Rules.New(): Profile
	return { version = Config.SaveVersion, coins = 0 }
end
function Rules.Validate(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalidProfile"
	end
	local p = value :: { [string]: unknown }
	if p.version ~= Config.SaveVersion then
		return false, "invalidVersion"
	end
	local coins = p.coins
	if typeof(coins) ~= "number" or coins ~= coins or coins < 0 or coins > Config.MaximumCoins or coins % 1 ~= 0 then
		return false, "invalidCoins"
	end
	return true, nil
end
return Rules
