-- 验证个人升级档位、购买边界、独立分账与耐力计算
local Rules = require("./PersonalUpgradeRules")
local Config = require("./GameConfig")
local first, second = Rules.New(), Rules.New()
local total = 0
for _, category in Config.PersonalUpgradeOrder do
	assert(first[category] == 1 and second[category] == 1)
	for level = 2, #Config.PersonalUpgradeCosts[category] do
		local cost = Config.PersonalUpgradeCosts[category][level]
		assert(Rules.GetPurchaseCost(first, category, level) == cost)
		assert(Rules.IsAffordable(first, category, cost))
		assert(not Rules.IsAffordable(first, category, cost - 1))
		total += cost
		first[category] = level
	end
	assert(not Rules.IsAffordable(first, category, math.huge))
	assert(second[category] == 1)
end
assert(total == 54430)
for _, level in {-1, 0, 1, 2.5, 3, 0/0, math.huge, "2"} do
	assert(Rules.GetPurchaseCost(second, "moveSpeed", level) == nil)
end
assert(Rules.GetPurchaseCost(second, "unknown", 2) == nil)
assert(Rules.ComputePlayerPayout(101, 3) == 126)
assert(Rules.ComputePlayerPayout(300, second.sellBonus) == 300)
assert(Rules.ComputePlayerPayout(300, first.sellBonus) == 600)
assert(Rules.GetMoveTier(5).unlimited and Rules.GetMoveTier(5).sprint == 38)
assert(Rules.StepStamina(1, 0, true, false, 1) == 0)
assert(Rules.StepStamina(0, 0, false, false, 1) > 0)
assert(Rules.StepStamina(0, 0, true, true, 1) == Config.Sprint.stamina)
print("Personal upgrade rules passed")
