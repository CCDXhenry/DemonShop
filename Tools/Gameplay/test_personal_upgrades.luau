-- 验证个人升级档位、购买边界、独立分账与耐力计算
local Rules = require("./PersonalUpgradeRules")
local Config = require("./GameConfig")
local GameData = require("./GameData")
local first, second = Rules.New(), Rules.New()
local total = 0
for _, category in GameData.GetPersonalUpgradeOrder() do
	assert(first[category] == 1 and second[category] == 1)
	local maxLevel = GameData.GetMaxUpgradeLevel(category)
	assert(maxLevel >= 2)
	for level = 2, maxLevel do
		local cost = GameData.GetUpgradeCost(category, level)
		assert(cost ~= nil)
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
assert(GameData.GetWeaponById(1).model == "W01_RustyPan")
assert(GameData.GetWeaponLevelByModel("W06_AbyssalHammer") == 6)
assert(#GameData.GetAllWeapons() == 6)
assert(GameData.GetCarryToolById(1).capacity == 1 and GameData.GetCarryToolById(1).previewModel == "T0" and GameData.GetCarryToolById(5).capacity == 30)
assert(GameData.GetPersonalAbilityById(1).category == "moveSpeed" and GameData.GetPersonalAbilityById(15).sellBonus == 1)
assert(GameData.GetUpgradeCost("unknown", 2) == nil and GameData.GetMaxUpgradeLevel("unknown") == 0)
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
local R = require("@lune/roblox")
local frame, point = R.CFrame.identity, R.Vector3.new
assert(Rules.InWeaponArea(3, frame, point(0, 0, -8)))
assert(not Rules.InWeaponArea(3, frame, point(0, 0, 5)))
assert(Rules.InWeaponArea(4, frame, point(0, 0, 10)))
assert(not Rules.InWeaponArea(4, frame, point(0, 11, 0)))
assert(Rules.InWeaponArea(5, frame, point(2.5, 0, -20)))
assert(not Rules.InWeaponArea(5, frame, point(2.51, 0, -20)))
assert(not Rules.InWeaponArea(5, frame, point(0, 0, 1)))
assert(Rules.InWeaponArea(6, frame, point(18, 0, 0)))
assert(not Rules.InWeaponArea(6, frame, point(18.1, 0, 0)))
assert(Rules.RemainingNpcHp(30, 0, 15) == 15 and Rules.RemainingNpcHp(15, 1, 15) == 0)
assert(Rules.RemainingNpcHp(nil, 2, 10) == 0)
assert(Config.StreetPopulation == 18 and Config.SpawnInterval == 2 and Config.MaximumBodies == 60)
print("Personal upgrade and M8 combat rules passed")
