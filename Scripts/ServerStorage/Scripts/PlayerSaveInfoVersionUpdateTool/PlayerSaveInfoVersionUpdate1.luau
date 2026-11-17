-- 原生存档第一步迁移：保留基础框架 dataVersion 从零升级到一的语义
--!strict
return function(playerSaveInfo: { [string]: unknown }): ()
	playerSaveInfo.dataVersion = 1
end
