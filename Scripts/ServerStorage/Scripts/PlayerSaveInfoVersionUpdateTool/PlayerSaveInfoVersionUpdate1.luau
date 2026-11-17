-- 基础框架保留的历史示例入口：当前初始版本零未注册，也不会调用本模块
--!strict
local function PlayerSaveInfoVersionUpdate1(playerSaveInfo: { [string]: unknown }): ()
	playerSaveInfo.dataVersion = 1
end
return PlayerSaveInfoVersionUpdate1
