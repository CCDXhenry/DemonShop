-- 原生存档第二步迁移：补齐恶魔商店金币，保留已有基础资料
--!strict
return function(playerSaveInfo: { [string]: unknown }): ()
	if playerSaveInfo.coins == nil then
		playerSaveInfo.coins = 0
	end
	playerSaveInfo.dataVersion = 2
end
