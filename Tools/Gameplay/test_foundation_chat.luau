-- 执行正式清档命令：验证原生默认存档、配置入口与权限隔离
local C=require('./ChatBoundary')
local Chat=require('./ServerPlayerChatCommandManager')
local checks=0
local function check(v,label)assert(v,label);checks+=1 end
local disabled=Chat.new();C.Config.ClearDataStorePlaceId=0;disabled:Init()
check(C.command:Count()==0,'unconfigured reset target registers no command');disabled:Destroy()
C.Config.ClearDataStorePlaceId=123
local manager=Chat.new();manager:Init();manager:Init()
check(C.command:Count()==1,'configured command registers once')
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
manager:Destroy();check(C.command:Count()==0,'command lifecycle disconnects')
print(string.format('PASS: %d foundation reset-command assertions (mock teleport only)',checks))
