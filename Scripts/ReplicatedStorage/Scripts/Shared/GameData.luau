-- 只读强类型游戏配置表查询层：统一加载、校验、索引并冻结配置子模块
--!strict
local Config = require(script.Parent.GameConfig)
local rawWeapons = require(script.Parent.GameConfig.WeaponData) :: { { [string]: unknown } }
local rawCarryTools = require(script.Parent.GameConfig.CarryToolData) :: { { [string]: unknown } }
local rawAbilities = require(script.Parent.GameConfig.PersonalAbilityData) :: { { [string]: unknown } }
local rawFacilities = require(script.Parent.GameConfig.AutomationFacilityData) :: { { [string]: unknown } }

export type UpgradeCategory = "moveSpeed" | "runeBatch" | "sellBonus" | "weapon" | "carryTool"

export type WeaponConfig = {
	id: number,
	level: number,
	name_t: string,
	model: string,
	cost: number,
	damage: number,
	targets: number,
	shape: string,
	range: number,
	angle: number,
	width: number,
	attackCooldown: number,
	slashAnim: string,
	slashSound: string,
	slashAnimation: Animation?,
	slashSoundTemplate: Sound?,
	icon: string,
}

export type CarryToolConfig = {
	id: number,
	level: number,
	name_t: string,
	model: string,
	previewModel: string,
	cost: number,
	capacity: number,
	icon: string,
}

export type MoveTierConfig = {
	id: number,
	level: number,
	cost: number,
	walk: number,
	sprint: number,
	unlimited: boolean,
}

export type RuneBatchConfig = {
	id: number,
	level: number,
	cost: number,
	runeBatch: number,
}

export type SellBonusConfig = {
	id: number,
	level: number,
	cost: number,
	sellBonus: number,
}

export type PersonalAbilityConfig = {
	id: number,
	category: "moveSpeed" | "runeBatch" | "sellBonus",
	level: number,
	cost: number,
	walk: number,
	sprint: number,
	unlimited: boolean,
	runeBatch: number,
	sellBonus: number,
}

export type AutomationFacilityConfig = {
	id: number,
	order: number,
	name_t: string,
	desc_t: string,
	cost: number,
	prerequisite: number?,
	padName: string,
}

local GameData = {}

GameData.FacilityId = table.freeze({
	FastChute = 1,
	Brute1 = 2,
	Brute2 = 3,
	AutoRune = 4,
	AutoSmelter = 5,
	AutoClerk = 6,
})

local personalUpgradeOrder: { UpgradeCategory } = table.freeze({
	"moveSpeed",
	"runeBatch",
	"sellBonus",
	"weapon",
	"carryTool",
} :: { UpgradeCategory })

local function AsNumber(row: { [string]: unknown }, key: string, context: string): number
	local value = row[key]
	assert(typeof(value) == "number" and value == value, context .. "." .. key .. " must be a number")
	return value
end

local function AsPositiveInt(row: { [string]: unknown }, key: string, context: string): number
	local value = AsNumber(row, key, context)
	assert(value >= 1 and value % 1 == 0, context .. "." .. key .. " must be a positive integer")
	return value
end

local function AsNonNegativeInt(row: { [string]: unknown }, key: string, context: string): number
	local value = AsNumber(row, key, context)
	assert(value >= 0 and value % 1 == 0, context .. "." .. key .. " must be a non-negative integer")
	return value
end

local function AsString(row: { [string]: unknown }, key: string, context: string): string
	local value = row[key]
	assert(typeof(value) == "string", context .. "." .. key .. " must be a string")
	return value
end

local function AsAssetId(row: { [string]: unknown }, key: string, context: string): string
	local value = AsString(row, key, context)
	assert(string.sub(value, 1, 13) == "rbxassetid://", context .. "." .. key .. " must be an asset id")
	return value
end

local function AsBoolean(row: { [string]: unknown }, key: string, context: string): boolean
	local value = row[key]
	assert(typeof(value) == "boolean", context .. "." .. key .. " must be a boolean")
	return value
end

-- 离线测试没有 DataModel；缺模板或资产 ID 时回退到 GameConfig。
local function ReadWeaponPresentation(modelName: string): (string, string, Animation?, Sound?)
	local animId = Config.WeaponSlashAnimation
	local soundId = Config.WeaponSlashSound
	local ok, foundAnim, foundSound = pcall(function(): (Animation?, Sound?)
		local replicated = game:GetService("ReplicatedStorage")
		local models = replicated:FindFirstChild("Models")
		local weapons = if models then models:FindFirstChild("Weapons") else nil
		local tool = if weapons then weapons:FindFirstChild(modelName) else nil
		if not tool then
			return nil, nil
		end
		local animation = tool:FindFirstChild("Slash")
		local sound = tool:FindFirstChild("SlashSound")
		return if animation and animation:IsA("Animation") then animation else nil,
			if sound and sound:IsA("Sound") then sound else nil
	end)
	if not ok then
		return animId, soundId, nil, nil
	end
	local slashAnimation = if typeof(foundAnim) == "Instance" and (foundAnim :: Instance):IsA("Animation") then foundAnim :: Animation else nil
	local slashSoundTemplate = if typeof(foundSound) == "Instance" and (foundSound :: Instance):IsA("Sound") then foundSound :: Sound else nil
	if slashAnimation and slashAnimation.AnimationId ~= "" then
		animId = slashAnimation.AnimationId
	else
		slashAnimation = nil
	end
	if slashSoundTemplate and slashSoundTemplate.SoundId ~= "" then
		soundId = slashSoundTemplate.SoundId
	else
		slashSoundTemplate = nil
	end
	return animId, soundId, slashAnimation, slashSoundTemplate
end

-- 武器表索引
local weaponsByLevel: { WeaponConfig } = {}
local weaponsById: { [number]: WeaponConfig } = {}
local weaponLevelByModel: { [string]: number } = {}
for index, row in rawWeapons do
	local context = "WeaponData[" .. tostring(index) .. "]"
	local id = AsPositiveInt(row, "id", context)
	local rawCooldown = AsNumber(row, "attackCooldown", context)
	local modelName = AsString(row, "model", context)
	local slashAnim, slashSound, slashAnimation, slashSoundTemplate = ReadWeaponPresentation(modelName)
	local item: WeaponConfig = {
		id = id,
		level = AsPositiveInt(row, "level", context),
		name_t = AsString(row, "name_t", context),
		model = modelName,
		cost = AsNumber(row, "cost", context),
		damage = AsNumber(row, "damage", context),
		targets = AsNumber(row, "targets", context),
		shape = AsString(row, "shape", context),
		range = AsNumber(row, "range", context),
		angle = AsNumber(row, "angle", context),
		width = AsNumber(row, "width", context),
		attackCooldown = if rawCooldown > 0 then rawCooldown else Config.AttackCooldown,
		slashAnim = slashAnim,
		slashSound = slashSound,
		slashAnimation = slashAnimation,
		slashSoundTemplate = slashSoundTemplate,
		icon = AsAssetId(row, "icon", context),
	}
	assert(weaponsById[item.id] == nil, context .. ".id duplicate")
	assert(item.model ~= "" and weaponLevelByModel[item.model] == nil, context .. ".model duplicate or empty")
	local frozen = table.freeze(item)
	weaponsById[item.id] = frozen
	weaponLevelByModel[item.model] = item.level
	table.insert(weaponsByLevel, frozen)
end
table.sort(weaponsByLevel, function(a: WeaponConfig, b: WeaponConfig): boolean
	return a.level < b.level
end)
assert(#weaponsByLevel >= 1, "WeaponData must not be empty")
for i, item in weaponsByLevel do
	assert(item.level == i, "WeaponData levels must be contiguous from 1")
end
table.freeze(weaponsByLevel)
table.freeze(weaponsById)
table.freeze(weaponLevelByModel)

-- 背包表索引
local carryToolsByLevel: { CarryToolConfig } = {}
local carryToolsById: { [number]: CarryToolConfig } = {}
for index, row in rawCarryTools do
	local context = "CarryToolData[" .. tostring(index) .. "]"
	local id = AsPositiveInt(row, "id", context)
	local item: CarryToolConfig = {
		id = id,
		level = AsPositiveInt(row, "level", context),
		name_t = AsString(row, "name_t", context),
		model = AsString(row, "model", context),
		previewModel = AsString(row, "previewModel", context),
		cost = AsNumber(row, "cost", context),
		capacity = AsNumber(row, "capacity", context),
		icon = AsAssetId(row, "icon", context),
	}
	assert(carryToolsById[item.id] == nil, context .. ".id duplicate")
	local frozen = table.freeze(item)
	carryToolsById[item.id] = frozen
	table.insert(carryToolsByLevel, frozen)
end
table.sort(carryToolsByLevel, function(a: CarryToolConfig, b: CarryToolConfig): boolean
	return a.level < b.level
end)
assert(#carryToolsByLevel >= 1, "CarryToolData must not be empty")
for i, item in carryToolsByLevel do
	assert(item.level == i, "CarryToolData levels must be contiguous from 1")
end
table.freeze(carryToolsByLevel)
table.freeze(carryToolsById)

-- 个人能力升级表索引
local moveTiers: { MoveTierConfig } = {}
local runeBatchTiers: { RuneBatchConfig } = {}
local sellBonusTiers: { SellBonusConfig } = {}
local personalAbilitiesById: { [number]: PersonalAbilityConfig } = {}
for index, row in rawAbilities do
	local context = "PersonalAbilityData[" .. tostring(index) .. "]"
	local id = AsPositiveInt(row, "id", context)
	assert(personalAbilitiesById[id] == nil, context .. ".id duplicate")
	local category = AsString(row, "category", context)
	local level = AsPositiveInt(row, "level", context)
	local cost = AsNumber(row, "cost", context)
	local walk = AsNumber(row, "walk", context)
	local sprint = AsNumber(row, "sprint", context)
	local unlimited = AsBoolean(row, "unlimited", context)
	local runeBatch = AsNumber(row, "runeBatch", context)
	local sellBonus = AsNumber(row, "sellBonus", context)
	if category == "moveSpeed" then
		personalAbilitiesById[id] = table.freeze({
			id = id,
			category = "moveSpeed" :: "moveSpeed",
			level = level,
			cost = cost,
			walk = walk,
			sprint = sprint,
			unlimited = unlimited,
			runeBatch = runeBatch,
			sellBonus = sellBonus,
		})
		table.insert(moveTiers, table.freeze({
			id = id,
			level = level,
			cost = cost,
			walk = walk,
			sprint = sprint,
			unlimited = unlimited,
		}))
	elseif category == "runeBatch" then
		personalAbilitiesById[id] = table.freeze({
			id = id,
			category = "runeBatch" :: "runeBatch",
			level = level,
			cost = cost,
			walk = walk,
			sprint = sprint,
			unlimited = unlimited,
			runeBatch = runeBatch,
			sellBonus = sellBonus,
		})
		table.insert(runeBatchTiers, table.freeze({
			id = id,
			level = level,
			cost = cost,
			runeBatch = runeBatch,
		}))
	elseif category == "sellBonus" then
		personalAbilitiesById[id] = table.freeze({
			id = id,
			category = "sellBonus" :: "sellBonus",
			level = level,
			cost = cost,
			walk = walk,
			sprint = sprint,
			unlimited = unlimited,
			runeBatch = runeBatch,
			sellBonus = sellBonus,
		})
		table.insert(sellBonusTiers, table.freeze({
			id = id,
			level = level,
			cost = cost,
			sellBonus = sellBonus,
		}))
	else
		error(context .. ".category unsupported: " .. category)
	end
end
table.freeze(personalAbilitiesById)

local function SortAndVerifyContiguous<T>(list: { T }, getLevel: (T) -> number, label: string): { T }
	assert(#list >= 1, label .. " must not be empty")
	table.sort(list, function(a: T, b: T): boolean
		return getLevel(a) < getLevel(b)
	end)
	for i, item in list do
		assert(getLevel(item) == i, label .. " levels must be contiguous from 1")
	end
	return table.freeze(list)
end

SortAndVerifyContiguous(moveTiers, function(item: MoveTierConfig): number return item.level end, "PersonalAbilityData.moveSpeed")
SortAndVerifyContiguous(runeBatchTiers, function(item: RuneBatchConfig): number return item.level end, "PersonalAbilityData.runeBatch")
SortAndVerifyContiguous(sellBonusTiers, function(item: SellBonusConfig): number return item.level end, "PersonalAbilityData.sellBonus")

-- 统一价格与最大等级索引
local costsByCategory: { [string]: { number } } = {}
do
	local moveCosts: { number } = {}
	for i, item in moveTiers do moveCosts[i] = item.cost end
	costsByCategory.moveSpeed = table.freeze(moveCosts)

	local runeCosts: { number } = {}
	for i, item in runeBatchTiers do runeCosts[i] = item.cost end
	costsByCategory.runeBatch = table.freeze(runeCosts)

	local sellCosts: { number } = {}
	for i, item in sellBonusTiers do sellCosts[i] = item.cost end
	costsByCategory.sellBonus = table.freeze(sellCosts)

	local weaponCosts: { number } = {}
	for i, item in weaponsByLevel do weaponCosts[i] = item.cost end
	costsByCategory.weapon = table.freeze(weaponCosts)

	local carryCosts: { number } = {}
	for i, item in carryToolsByLevel do carryCosts[i] = item.cost end
	costsByCategory.carryTool = table.freeze(carryCosts)
end
table.freeze(costsByCategory)

-- 自动化设施表索引
local facilitiesList: { AutomationFacilityConfig } = {}
local facilitiesById: { [number]: AutomationFacilityConfig } = {}
local facilityOrder: { number } = {}
for index, row in rawFacilities do
	local context = "AutomationFacilityData[" .. tostring(index) .. "]"
	local id = AsPositiveInt(row, "id", context)
	local rawPrereq = AsNonNegativeInt(row, "prerequisite", context)
	local item: AutomationFacilityConfig = {
		id = id,
		order = AsPositiveInt(row, "order", context),
		name_t = AsString(row, "name_t", context),
		desc_t = AsString(row, "desc_t", context),
		cost = AsNumber(row, "cost", context),
		prerequisite = if rawPrereq > 0 then rawPrereq else nil,
		padName = AsString(row, "padName", context),
	}
	assert(facilitiesById[item.id] == nil, context .. ".id duplicate")
	local frozen = table.freeze(item)
	table.insert(facilitiesList, frozen)
	facilitiesById[item.id] = frozen
end
table.sort(facilitiesList, function(a: AutomationFacilityConfig, b: AutomationFacilityConfig): boolean
	if a.order == b.order then
		return a.id < b.id
	end
	return a.order < b.order
end)
for _, item in facilitiesList do
	if item.prerequisite ~= nil then
		assert(item.prerequisite ~= item.id, "Self prerequisite on facility " .. tostring(item.id))
		assert(facilitiesById[item.prerequisite] ~= nil, "Unknown prerequisite " .. tostring(item.prerequisite) .. " on facility " .. tostring(item.id))
	end
	table.insert(facilityOrder, item.id)
end
table.freeze(facilitiesList)
table.freeze(facilitiesById)
table.freeze(facilityOrder)

function GameData.GetPersonalUpgradeOrder(): { UpgradeCategory }
	return personalUpgradeOrder
end

function GameData.GetUpgradeCost(category: string, level: number): number?
	local costs = costsByCategory[category]
	if not costs or level < 1 or level % 1 ~= 0 then
		return nil
	end
	return costs[level]
end

function GameData.GetMaxUpgradeLevel(category: string): number
	local costs = costsByCategory[category]
	return if costs then #costs else 0
end

function GameData.GetWeaponByLevel(level: number): WeaponConfig
	return weaponsByLevel[level] or weaponsByLevel[1]
end

function GameData.GetWeaponById(id: number): WeaponConfig?
	return weaponsById[id]
end

function GameData.GetWeaponLevelByModel(modelName: string): number?
	return weaponLevelByModel[modelName]
end

function GameData.GetAllWeapons(): { WeaponConfig }
	return weaponsByLevel
end

function GameData.GetCarryToolByLevel(level: number): CarryToolConfig
	return carryToolsByLevel[level] or carryToolsByLevel[1]
end

function GameData.GetCarryToolById(id: number): CarryToolConfig?
	return carryToolsById[id]
end

function GameData.GetAllCarryTools(): { CarryToolConfig }
	return carryToolsByLevel
end

function GameData.GetPersonalAbilityById(id: number): PersonalAbilityConfig?
	return personalAbilitiesById[id]
end

function GameData.GetMoveTier(level: number): MoveTierConfig
	return moveTiers[level] or moveTiers[1]
end

function GameData.GetRuneBatchTier(level: number): RuneBatchConfig
	return runeBatchTiers[level] or runeBatchTiers[1]
end

function GameData.GetSellBonusTier(level: number): SellBonusConfig
	return sellBonusTiers[level] or sellBonusTiers[1]
end

function GameData.GetFacility(facilityId: number): AutomationFacilityConfig?
	return facilitiesById[facilityId]
end

function GameData.GetFacilityOrder(): { number }
	return facilityOrder
end

function GameData.GetAllFacilities(): { AutomationFacilityConfig }
	return facilitiesList
end

table.freeze(GameData)
return GameData
