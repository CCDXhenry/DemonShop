-- 原生基础存档逐版本迁移：成功原地更新，验证或步骤失败不触碰输入
--!strict
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Config = require(Shared.GameConfig)
local Rules = require(Shared.SaveRules)
local Update1 = require(script.PlayerSaveInfoVersionUpdate1)
local Update2 = require(script.PlayerSaveInfoVersionUpdate2)
local Tool = {}
local Steps: { [number]: ({ [string]: unknown }) -> () } = { [1] = Update1, [2] = Update2 }
local Allowed: { [string]: boolean } = {
	dataVersion = true,
	coins = true,
	settingInfo = true,
	firstEnterTime = true,
	firstEnterVersion = true,
	gameTime = true,
	loginDays = true,
	lastOnlineDateUTC = true,
	ownedGamePassList = true,
}
function Tool.Update(value: unknown): (Config.PlayerSaveInfo?, string?)
	if type(value) ~= "table" then
		return nil, "invalidProfile"
	end
	local old = value :: { [string]: unknown }
	if table.isfrozen(old) then
		return nil, "invalidProfile"
	end
	for key in old do
		if not Allowed[key] then
			return nil, "unexpectedField"
		end
	end
	local version = old.dataVersion
	if type(version) ~= "number" or version ~= version or version % 1 ~= 0 or version < 0 or version > Config.PlayerSaveInfoDataVersion then
		return nil, "invalidVersion"
	end
	local staged = table.clone(old)
	for nextVersion = version + 1, Config.PlayerSaveInfoDataVersion do
		local step = Steps[nextVersion]
		if not step then
			return nil, "missingMigration"
		end
		local ok, reason = pcall(function(): boolean
			step(staged)
			return true
		end)
		if not ok then
			warn("[PlayerSaveInfoVersionUpdateTool]", nextVersion, reason)
			return nil, "migrationFailed"
		end
	end
	local durable = table.clone(staged)
	durable.version = durable.dataVersion
	durable.dataVersion = nil
	local valid, reason = Rules.Validate(durable)
	if not valid then
		return nil, reason
	end
	local native = Rules.ToPlayerSaveInfo((durable :: unknown) :: Rules.Profile)
	for key in old do
		old[key] = nil
	end
	for key, field in (native :: unknown) :: { [string]: unknown } do
		old[key] = field
	end
	return (old :: unknown) :: Config.PlayerSaveInfo, nil
end
return Tool
