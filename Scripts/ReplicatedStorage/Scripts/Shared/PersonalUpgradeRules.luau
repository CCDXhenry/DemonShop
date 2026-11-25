-- 个人升级档位、顺序购买、独立分红和耐力的纯规则
--!strict
local Config = require(script.Parent.GameConfig)
local GameData = require(script.Parent.GameData)

local Rules = {}
export type Levels = { [string]: number }

function Rules.New(): Levels
	local levels: Levels = {}
	for _, category in GameData.GetPersonalUpgradeOrder() do
		levels[category] = 1
	end
	return levels
end

function Rules.GetPurchaseCost(levels: Levels, category: unknown, expectedNextLevel: unknown): number?
	if typeof(category) ~= "string" or typeof(expectedNextLevel) ~= "number" then
		return nil
	end
	local maxLevel = GameData.GetMaxUpgradeLevel(category)
	local current = levels[category]
	if maxLevel < 2 or not current or current < 1 or current % 1 ~= 0 or expectedNextLevel ~= current + 1 then
		return nil
	end
	return GameData.GetUpgradeCost(category, expectedNextLevel)
end

function Rules.IsAffordable(levels: Levels, category: string, coins: number): boolean
	local cost = Rules.GetPurchaseCost(levels, category, (levels[category] or 0) + 1)
	return cost ~= nil and coins >= cost and coins <= Config.MaximumCoins and coins % 1 == 0
end

function Rules.GetMoveTier(level: number): GameData.MoveTierConfig
	return GameData.GetMoveTier(level)
end

function Rules.GetRuneBatch(level: number): number
	return GameData.GetRuneBatchTier(level).runeBatch
end

function Rules.GetSellBonus(level: number): number
	return GameData.GetSellBonusTier(level).sellBonus
end

function Rules.GetWeaponTier(level: number): GameData.WeaponConfig
	return GameData.GetWeaponByLevel(level)
end

function Rules.WeaponLevel(name: string): number?
	return GameData.GetWeaponLevelByModel(name)
end

function Rules.FindWeapon(container: Instance?): Tool?
	if container then
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and Rules.WeaponLevel(child.Name) then return child end
		end
	end
	return nil
end

function Rules.InWeaponArea(level: number, pose: CFrame, position: Vector3): boolean
	local tier = Rules.GetWeaponTier(level)
	local offset = pose:PointToObjectSpace(position)
	if tier.shape == "Line" then
		local width = if tier.width > 0 then tier.width else 5
		return offset.Z <= 0 and offset.Z >= -tier.range
			and math.abs(offset.X) <= width / 2 and math.abs(offset.Y) <= 5
	end
	if offset.Magnitude > tier.range then return false end
	if tier.shape ~= "Cone" then return true end
	local angle = if tier.angle > 0 then tier.angle else 120
	local horizontal = Vector2.new(offset.X, offset.Z)
	return horizontal.Magnitude < 0.01 or -offset.Z / horizontal.Magnitude >= math.cos(math.rad(angle / 2))
end

function Rules.RemainingNpcHp(hp: number?, hits: number, damage: number): number
	local before = hp or (Config.StreetNpcMaxHp - hits * Config.BruteDamage)
	return math.clamp(before - damage, 0, Config.StreetNpcMaxHp)
end

function Rules.GetCarryTier(level: number): GameData.CarryToolConfig
	return GameData.GetCarryToolByLevel(level)
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
