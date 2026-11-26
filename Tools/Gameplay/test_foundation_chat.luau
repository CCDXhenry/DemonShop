-- 执行正式清档命令：验证原生默认存档、配置入口与权限隔离
local C=require('./ChatBoundary')
local Chat=require('./ServerPlayerChatCommandManager')
local checks=0
local function check(v,label)assert(v,label);checks+=1 end
local disabled=Chat.new();C.Config.ClearDataStorePlaceId=0;disabled:Init()
check(C.command:Count()==0,'unconfigured reset target registers no command')
check(C.addCoinsCommand:Count()==1,'non-production add-coins command registers without reset place')
disabled:Destroy()
check(C.addCoinsCommand:Count()==0,'destroy disconnects add-coins command')
C.Config.ClearDataStorePlaceId=123
local manager=Chat.new();manager:Init();manager:Init()
check(C.command:Count()==1 and C.addCoinsCommand:Count()==1,'configured commands register once')
C.gm=false;C.command:Fire({UserId=C.player.UserId})
check(#C.calls==0,'non GM cannot reset')
C.gm=true;C.studio=true;C.command:Fire({UserId=C.player.UserId})
check(#C.calls==0,'Studio cannot reset')
C.studio=false;C.command:Fire({UserId=-999})
check(#C.calls==0,'unresolved player cannot reset')
C.command:Fire({UserId=C.player.UserId})
check(#C.calls==1 and C.calls[1].place==123 and C.calls[1].data.gameStartPlaceId==456,'teleport uses configured reset and entry places')
local saved=C.calls[1].data.defaultPlayerSaveInfo
check(saved.dataVersion==0 and saved.version==nil and saved.coins==0 and saved.loginDays==1,'reset payload carries native foundation save')
check(C.options[1].destroyed,'successful teleport releases options')
C.fail=true;C.command:Fire({UserId=C.player.UserId})
check(C.options[2].destroyed,'failed teleport also releases options')
manager:Destroy();check(C.command:Count()==0 and C.addCoinsCommand:Count()==0,'command lifecycle disconnects')

-- AddCoins 命令校验：仅限非正式环境 + GM 玩家，支持默认与指定正整数数量
do
	C.Config.GameId = 999
	C.game.GameId = 999
	C.studio = false
	local prodManager = Chat.new()
	prodManager:Init()
	check(C.addCoinsCommand:Count() == 0, 'production environment does not register AddCoinsCommand')
	prodManager:Destroy()

	-- 非正式云端环境 (GameId ~= Config.GameId)
	C.game.GameId = 888
	C.studio = false
	local stagingManager = Chat.new()
	stagingManager:Init()
	check(C.addCoinsCommand:Count() == 1, 'non-production cloud registers AddCoinsCommand')
	table.clear(C.addedCoins)
	C.gm = false
	C.addCoinsCommand:Fire({ UserId = C.player.UserId }, '/AddCoins 500')
	check(#C.addedCoins == 0, 'non-GM cannot add coins')
	C.addCoinsCommand:Fire({ UserId = -1 }, '/AddCoins 800')
	check(#C.addedCoins == 0, 'non-production cloud rejects negative studio test user ids')
	C.gm = true
	C.addCoinsCommand:Fire({ UserId = -999 }, '/AddCoins 500')
	check(#C.addedCoins == 0, 'unresolved player cannot add coins')
	C.addCoinsCommand:Fire({ UserId = C.player.UserId }, '/AddCoins 300')
	check(#C.addedCoins == 1 and C.addedCoins[1].player == C.player and C.addedCoins[1].amount == 300, 'GM can add explicit coins in non-production cloud')
	-- 运行期间切到正式环境也必须拒绝触发
	C.game.GameId = 999
	C.addCoinsCommand:Fire({ UserId = C.player.UserId }, '/AddCoins 300')
	check(#C.addedCoins == 1, 'production trigger guard rejects AddCoinsCommand')
	stagingManager:Destroy()

	-- Studio 环境即使 GameId 等于正式 GameId 也允许测试
	C.studio = true
	C.game.GameId = 999
	local studioManager = Chat.new()
	studioManager:Init()
	check(C.addCoinsCommand:Count() == 1, 'Studio registers AddCoinsCommand')
	table.clear(C.addedCoins)
	C.addCoinsCommand:Fire({ UserId = C.player.UserId }, '/AddCoins')
	check(#C.addedCoins == 1 and C.addedCoins[1].amount == 1000, 'AddCoins defaults to 1000 when no amount argument provided')
	C.addCoinsCommand:Fire({ UserId = C.player.UserId }, '/AddCoins 2500')
	check(#C.addedCoins == 2 and C.addedCoins[2].amount == 2500, 'AddCoins parses positive integer argument')
	for _, invalid in { '/AddCoins -5', '/AddCoins 0', '/AddCoins 1.5', '/AddCoins abc' } do
		C.addCoinsCommand:Fire({ UserId = C.player.UserId }, invalid)
	end
	check(#C.addedCoins == 2, 'AddCoins rejects non-positive, fractional, and non-numeric arguments')
	C.gm = false
	C.addCoinsCommand:Fire({ UserId = C.player.UserId }, '/AddCoins 100')
	check(#C.addedCoins == 2, 'Studio positive non-GM user cannot add coins')
	C.addCoinsCommand:Fire({ UserId = -1 }, '/AddCoins 800')
	check(#C.addedCoins == 3 and C.addedCoins[3].player == C.playersById[-1] and C.addedCoins[3].amount == 800, 'Studio local test client -1 can add explicit coins')
	C.addCoinsCommand:Fire({ UserId = -2 }, '/AddCoins')
	check(#C.addedCoins == 4 and C.addedCoins[4].player == C.playersById[-2] and C.addedCoins[4].amount == 1000, 'Studio local test client -2 defaults to 1000')
	studioManager:Destroy()
	check(C.addCoinsCommand:Count() == 0, 'AddCoinsCommand disconnects on Destroy')
end

print(string.format('PASS: %d foundation reset-command assertions (mock teleport only)',checks))
