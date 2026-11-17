-- 基础框架回归：正式存档、资料、设置、商城与双端装配，边界服务使用替身
local R=require('@lune/roblox')
local task=require('@lune/task')
local B=require('./FoundationBoundary')
local Save=require('./SaveRules')
local Rules=require('./PlayerProfileRules')
local Store=require('./ServerPlayerSaveStore')
local Info=require('./ServerGameInfo')
local Server=require('./ServerGameManager')
local Client=require('./ClientGameManager')
local ClientInfo=require('./ClientGameInfo')
local Market=require('./ServerMarketplaceManager')
local Protocol=require('./FoundationProtocol')
local checks=0
local function check(v,label) assert(v,label);checks+=1 end
local old={version=1,coins=123}
local migrated=Save.Migrate(old,100000)
check(migrated and migrated.version==2 and migrated.coins==123,'v1 coins preserved')
check(old.version==1 and old.settingInfo==nil,'migration does not mutate input')
check(migrated.settingInfo.bgmVolume==1 and migrated.settingInfo.soundEffectVolume==1 and migrated.settingInfo.vibrationOn,'setting defaults')
check(migrated.firstEnterTime==100000 and migrated.gameTime==0 and #migrated.ownedGamePassList==0,'statistics defaults')
check(Save.Migrate({dataVersion=1,farm={}})==nil,'farm profile not silently converted')
check(Save.Migrate({version=99,coins=0})==nil,'future version rejected')
for _,coins in {-1,.5,math.huge,0/0} do check(Save.Migrate({version=1,coins=coins})==nil,'invalid old coins rejected') end
local clone=Save.Copy(migrated);clone.settingInfo.bgmVolume=.2;table.insert(clone.ownedGamePassList,10)
check(migrated.settingInfo.bgmVolume==1 and #migrated.ownedGamePassList==0,'snapshots own nested tables')
Rules.Login(migrated,100000);Rules.Login(migrated,100100)
check(migrated.loginDays==1 and migrated.lastOnlineDateUTC==86400,'same UTC date counted once')
Rules.Login(migrated,172800);check(migrated.loginDays==2,'next UTC day counted')
Rules.Login(migrated,100000);check(migrated.loginDays==2,'clock rollback cannot double count')
Rules.AddTime(migrated,1.5);Rules.AddTime(migrated,2.25)
check(migrated.gameTime==3.75,'online time accumulates fractions')
check(not Rules.AddTime(migrated,math.huge) and not Rules.AddTime(migrated,-1),'invalid elapsed time rejected')
check(Rules.Setting(migrated,'bgmVolume',.3),'valid setting applied')
check(not Rules.Setting(migrated,'soundEffectVolume',2) and not Rules.Setting(migrated,'vibrationOn',0),'setting types and range')
check(Rules.GrantPass(migrated,42) and not Rules.GrantPass(migrated,42),'pass grant idempotent')
for _,request in {{action='SetBGMVolume',value=0/0},{action='SetSoundEffectVolume',value=math.huge},{action='SetVibrationsOnOffState',value='true'},{action='unknown'}} do
 check(not Protocol.Validate(request),'network rejects invalid settings')
end
check(Protocol.Validate({action='SetBGMVolume',value=.5}) and Protocol.Validate({action='RequestPlayerInfoInit'}),'network accepts valid requests')
check(Market.ProcessReceipt({PlayerId=1001,ProductId=1,PurchaseId='x'})==R.Enum.ProductPurchaseDecision.NotProcessedYet,'unconfigured receipt never granted')
B.db.values['1001']={version=1,coins=321}
local server=Server.new();server:Init();server:Init()
check(B.processingStarts==1 and B.Players.PlayerAdded:Count()==1 and B.RunService.Heartbeat:Count()==1 and B.binds==1,'server Init is idempotent')
server:AddPlayer(B.player);server:AddPlayer(B.player)
check(B.processingAdds==1 and B.player.attributes.GameReady and Info.GetPlayerInfo(B.player).profile.coins==321,'single load and processing attach')
local client=Client.new();client:Init();client:Init()
check(B.clientStarts==1 and B.uiStarts==1 and B.soundStarts==1,'client starts after profile exactly once')
Info.SendPlayerInfo(B.player)
check(B.clientStarts==1 and B.uiStarts==1,'profile replay cannot restart client')
check(B.bgm==1 and B.sfx==1 and B.vibration==true,'loaded settings applied')
B.request:Fire(B.player,{action='SetBGMVolume',value=.4})
check(Info.GetPlayerInfo(B.player).profile.settingInfo.bgmVolume==1,'rate limit blocks immediate repeat')
-- Exercise actual setting handler after the clock boundary advances.
local Settings=require('./ServerPlayerSettingManager')
local settings=server.settings;settings.lastRequest[B.player]=-math.huge
B.request:Fire(B.player,{action='SetBGMVolume',value=.4})
check(B.bgm==.4 and Info.GetPlayerInfo(B.player).profile.settingInfo.bgmVolume==.4,'server setting update and client application')
check(Info.AddCoins(B.player,100) and Info.GetPlayerInfo(B.player).profile.coins==421,'reward uses shared data owner')
Info.Tick(B.player,2.5)
check(Info.GetPlayerInfo(B.player).profile.gameTime==2.5,'foundation owns online statistics')
check(Info.SetPlayerGamePassAcquired(B.player,42) and not Info.SetPlayerGamePassAcquired(B.player,42),'server pass notification idempotent')
check(B.grants==1 and table.find(ClientInfo.GetLocalPlayerInfo().ownedGamePassList,42),'client pass cache receives one grant')
check(Info.GetPlayerInfo(B.player).coins==421 and Info.GetPlayerInfo(B.player).dataVersion==2,'reference player view aliases authoritative profile')
check(Info.GetPlayerInfo(B.player).ownedGamePassMap[42] and ClientInfo.GetLocalPlayerInfo().ownedGamePassMap[42],'reference pass maps built on both peers')
local publicSave=Info.CreatePlayerSaveInfoByPlayerInfo(Info.GetPlayerInfo(B.player))
check(publicSave.version==nil and publicSave.dataVersion==2 and rawget(publicSave,'dataVersion')==2,'reference save snapshot uses native dataVersion field')
check(B.notices[#B.notices].notice.localInfo.firstEnterTime==nil and B.notices[#B.notices].notice.localInfo.version==nil,'local sync excludes server private profile fields')
ClientInfo.InitOtherPlayerInfo(2002,{})
check(ClientInfo.GetOtherPlayerInfo(2002)~=nil and B.lastOther==2002,'other player init message and cache restored')
B.Net.FireNotifyPlayerLeft(2002)
check(ClientInfo.GetOtherPlayerInfo(2002)==nil,'other player leave clears client cache')
local second=B.Player(2002);server:AddPlayer(second)
Info.SendPlayerInfo(B.player)
check(B.notices[#B.notices].notice.otherPlayers['2002']~=nil,'profile replay includes connected other players')
server:RemovePlayer(second)
check(ClientInfo.GetOtherPlayerInfo(2002)==nil,'server departure reaches client cleanup')
local snapshot=Save.Copy(Info.GetPlayerInfo(B.player).profile)
Info.UpdateSetting(B.player,'vibrationOn',false)
check(snapshot.settingInfo.vibrationOn==true,'pending snapshot does not change during new edits')
check(Info.Save(B.player),'latest profile saved')
local revision=Info.GetPlayerInfo(B.player).revision
check(server.store:Save(1001,snapshot,revision-1),'older revision safely superseded')
check(B.db.values['1001'].settingInfo.vibrationOn==false,'stale snapshot cannot roll back setting')
local stranger=B.Player(3003);settings.lastRequest[stranger]=-math.huge
B.request:Fire(stranger,{action='SetBGMVolume',value=.1})
check(Info.GetPlayerInfo(stranger)==nil,'unloaded player cannot modify settings')
server:RemovePlayer(B.player);server:RemovePlayer(B.player)
check(B.processingRemoves==2 and Info.GetPlayerInfo(B.player)==nil and B.player.attributes.GameReady==false,'exit freezes and detaches exactly once')
server:AddPlayer(B.player)
check(Info.GetPlayerInfo(B.player).profile.coins==421 and not Info.GetPlayerInfo(B.player).profile.settingInfo.vibrationOn,'rejoin restores coins and settings')
check(Info.GetPlayerInfo(B.player).profile.loginDays==1,'same UTC day rejoin keeps login count')
-- 保存失败不能污染已存数据；异步旧快照不能覆盖保存期间的新金币。
local Mock=require('./Mock')
B.db.fail=true
Info.AddCoins(B.player,10)
check(not Info.Save(B.player) and B.db.values['1001'].coins==421,'failed storage leaves durable snapshot untouched')
B.db.fail=false
local previousUpdate=Mock.DataStoreTool.SafeUpdate
local delayNext=true
Mock.DataStoreTool.SafeUpdate=function(...)
 if delayNext then delayNext=false;task.wait(.02) end
 return previousUpdate(...)
end
local saved=false
task.spawn(function() saved=Info.Save(B.player) end)
task.wait(.005)
Info.AddCoins(B.player,10)
check(Info.Save(B.player),'new revision saves after pending write')
check(saved and B.db.values['1001'].coins==441,'pending old snapshot cannot erase concurrent coin change')
Mock.DataStoreTool.SafeUpdate=previousUpdate
local leaving=B.Player(5005)
Mock.DataStoreTool.SafeUpdate=function(...)
 task.wait(.02)
 return previousUpdate(...)
end
local addsBefore=B.processingAdds
task.spawn(function()server:AddPlayer(leaving)end)
task.wait(.005);leaving.Parent=nil
task.wait(.06)
Mock.DataStoreTool.SafeUpdate=previousUpdate
check(Info.GetPlayerInfo(leaving)==nil and not server.loading[leaving] and B.processingAdds==addsBefore,'leaving during data acquisition never attaches gameplay')
local Lease=require('./PlayerSaveLeaseRules')
check(B.db.metadata['5005'][Lease.MetadataKeys.SessionId]==nil,'leaving during acquire releases acquired lease')
local expiredPlayer=B.Player(6006);server:AddPlayer(expiredPlayer)
server.store.records[6006].expiresAt=0
local coinsBefore=Info.GetPlayerInfo(expiredPlayer).coins
check(not Info.AddCoins(expiredPlayer,100) and Info.GetPlayerInfo(expiredPlayer).coins==coinsBefore,'expired lease cannot award coins')
server:RemovePlayer(expiredPlayer)
check(Info.GetPlayerInfo(expiredPlayer)==nil,'expired player cleans up owner record')
client:Destroy();server:Destroy();task.wait()
check(B.request:Count()==0 and B.notify:Count()==0 and B.Players.PlayerAdded:Count()==0 and B.RunService.Heartbeat:Count()==0,'destroy disconnects lifecycle hooks')
check(Info.GetPlayerInfo(B.player)==nil,'shutdown releases sole data owner')
local cold=Client.new();cold:Init();check(not cold.started,'client waits for profile rather than starting early');cold:Destroy()
print(string.format('PASS: %d foundation assertions (production data and managers; engine boundaries mocked)',checks))
