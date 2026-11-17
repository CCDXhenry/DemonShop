-- 基础框架预留存档入口：当前无旧档且未启用迁移，仅校验初始版本原生资料
--!strict
local Config = require(game:GetService("ReplicatedStorage").Scripts.Shared.GameConfig)
local Rules = require(game:GetService("ReplicatedStorage").Scripts.Shared.SaveRules)
local Tool = {}
function Tool.Update(value: unknown): (Config.PlayerSaveInfo?, string?)
	local valid, reason = Rules.Validate(value)
	if not valid then
		return nil, reason
	end
	return value :: Config.PlayerSaveInfo, nil
end
return Tool
