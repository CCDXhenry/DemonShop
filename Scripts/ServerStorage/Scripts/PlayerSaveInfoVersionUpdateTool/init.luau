-- 基础存档迁移入口：委托统一规则，返回独立快照，失败时不修改旧档
--!strict
local Rules = require(game:GetService("ReplicatedStorage").Scripts.Shared.SaveRules)
local Tool = {}
function Tool.Update(value: unknown): (Rules.Profile?, string?)
	local profile, reason = Rules.Migrate(value)
	if not profile then
		return nil, reason
	end
	-- 写回成功的迁移结果，兼容原框架忽略返回值的调用方式。
	local target = value :: { [string]: unknown }
	for key in target do
		target[key] = nil
	end
	local fields = (profile :: unknown) :: { [string]: unknown }
	for key, field in fields do
		target[key] = field
	end
	return profile, nil
end
return Tool
