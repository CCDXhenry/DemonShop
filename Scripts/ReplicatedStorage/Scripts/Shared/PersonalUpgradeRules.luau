-- 个人升级档位、顺序购买、独立分红和耐力的纯规则
--!strict
local Config = require(script.Parent.GameConfig)

local Rules = {}
export type Levels = { [string]: number }

function Rules.New(): Levels
	local levels: Levels = {}
	for _, category in Config.PersonalUpgradeOrder do
		levels[category] = 1
	end
	return levels
end

function Rules.GetPurchaseCost(levels: Levels, category: unknown, expectedNextLevel: unknown): number?
	if typeof(category) ~= "string" or typeof(expectedNextLevel) ~= "number" then
		return nil
	end
	local costs = Config.PersonalUpgradeCosts[category]
	local current = levels[category]
	if not costs or not current or current < 1 or current % 1 ~= 0 or expectedNextLevel ~= current + 1 then
		return nil
	end
	return costs[expectedNextLevel]
end

function Rules.IsAffordable(levels: Levels, category: string, coins: number): boolean
	local cost = Rules.GetPurchaseCost(levels, category, (levels[category] or 0) + 1)
	return cost ~= nil and coins >= cost and coins <= Config.MaximumCoins and coins % 1 == 0
end

function Rules.GetMoveTier(level: number)
	return Config.PersonalMoveTiers[level] or Config.PersonalMoveTiers[1]
end

function Rules.GetRuneBatch(level: number): number
	return Config.PersonalRuneBatches[level] or 1
end

function Rules.GetSellBonus(level: number): number
	return Config.PersonalSellBonuses[level] or 0
end

function Rules.GetWeaponTier(level: number)
	return Config.PersonalWeaponTiers[level] or Config.PersonalWeaponTiers[1]
end

function Rules.GetCarryTier(level: number)
	return Config.PersonalCarryTiers[level] or Config.PersonalCarryTiers[1]
end

function Rules.ComputePlayerPayout(baseTotal: number, sellLevel: number): number
	return math.round(baseTotal * (1 + Rules.GetSellBonus(sellLevel)))
end

function Rules.StepStamina(stamina: number, recoverDelay: number, sprinting: boolean, unlimited: boolean, dt: number): (number, number)
	local sprint = Config.Sprint
	if unlimited then
		return sprint.stamina, 0
	elseif sprinting then
		return math.max(0, stamina - sprint.drainPerSecond * dt), sprint.recoverDelay
	end
	local recoverTime = math.max(0, dt - recoverDelay)
	return math.min(sprint.stamina, stamina + sprint.recoverPerSecond * recoverTime), math.max(0, recoverDelay - dt)
end

return Rules
