-- 历史迁移入口：委托统一迁移规则，不维护第二份版本逻辑
--!strict
local Rules = require(game:GetService("ReplicatedStorage").Scripts.Shared.SaveRules)
return Rules.Migrate
