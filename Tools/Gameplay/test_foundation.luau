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
local Config=require('./GameConfig')
local checks=0
local function check(v,label) assert(v,label);checks+=1 end
local initial=Save.New(100000)
check(initial.dataVersion==0 and initial.version==nil and initial.coins==0,'first-release save uses original version zero and native fields')
check(initial.settingInfo.bgmVolume==1 and initial.settingInfo.soundEffectVolume==1 and initial.settingInfo.vibrationOn,'setting defaults')
check(initial.firstEnterTime==100000 and initial.gameTime==0 and #initial.ownedGamePassList==0,'statistics defaults')
check(not Save.Validate({version=1,coins=123}),'coin-only shape is rejected without conversion')
local future=Save.New();future.dataVersion=99
check(not Save.Validate(future),'unsupported version is rejected without conversion')
for _,coins in {-1,.5,math.huge,0/0} do
 local invalid=Save.New();invalid.coins=coins
 check(not Save.Validate(invalid),'invalid current coins rejected')
end
local clone=Save.Copy(initial);clone.settingInfo.bgmVolume=.2;table.insert(clone.ownedGamePassList,10)
check(initial.settingInfo.bgmVolume==1 and #initial.ownedGamePassList==0,'snapshots own nested tables')
Rules.Login(initial,100000);Rules.Login(initial,100100)
check(initial.loginDays==1 and initial.lastOnlineDateUTC==86400,'same UTC date counted once')
Rules.Login(initial,172800);check(initial.loginDays==2,'next UTC day counted')
Rules.Login(initial,100000);check(initial.loginDays==2,'clock rollback cannot double count')
Rules.AddTime(initial,1.5);Rules.AddTime(initial,2.25)
check(initial.gameTime==3.75,'online time accumulates fractions')
check(not Rules.AddTime(initial,math.huge) and not Rules.AddTime(initial,-1),'invalid elapsed time rejected')
check(Rules.Setting(initial,'bgmVolume',.3),'valid setting applied')
check(not Rules.Setting(initial,'soundEffectVolume',2) and not Rules.Setting(initial,'vibrationOn',0),'setting types and range')
check(Rules.GrantPass(initial,42) and not Rules.GrantPass(initial,42),'pass grant idempotent')
for _,request in {{action='SetBGMVolume',value=0/0},{action='SetSoundEffectVolume',value=math.huge},{action='SetVibrationsOnOffState',value='true'},{action='unknown'}} do
 check(not Protocol.Validate(request),'network rejects invalid settings')
end
check(Protocol.Validate({action='SetBGMVolume',value=.5}) and Protocol.Validate({action='RequestPlayerInfoInit'}),'network accepts valid requests')
check(Market.ProcessReceipt({PlayerId=1001,ProductId=1,PurchaseId='x'})==R.Enum.ProductPurchaseDecision.NotProcessedYet,'unconfigured receipt never granted')
check(Config.SessionOnlyEconomy == true,'SessionOnlyEconomy defaults to true for M1')
Config.SessionOnlyEconomy = false
B.db.values['1001']=Save.New();B.db.values['1001'].coins=321
local server=Server.new();server:Init();server:Init()
check(B.processingStarts==1 and B.Players.PlayerAdded:Count()==1 and B.RunService.Heartbeat:Count()==1 and B.binds==1,'server Init is idempotent')
local initCount=0
local initConnection=B.serverInit:Connect(function(player)
 initCount+=1
 local info=Info.GetPlayerInfo(player)
 check(info~=nil and info.playerConfigInfo.final==true,'server initialization listeners see final resolved config')
 check(player.attributes.GameReady==false,'business remains gated at initialization signal')
end)
B.Context.ResolveConfig=function()return {final=true}end
server:AddPlayer(B.player);server:AddPlayer(B.player)
check(B.processingAdds==1 and B.player.attributes.GameReady and Info.GetPlayerInfo(B.player).coins==321,'single load and processing attach')
check(initCount==1 and #B.notices==1 and B.otherNotices==1,'native initialization emits each notification once')
initConnection:Disconnect()
local client=Client.new();client:Init();client:Init()
check(B.backpackCalls==1 and B.backpackEnabled==false and B.backpackKind==R.Enum.CoreGuiType.Backpack,'foundation disables native backpack exactly once')
check(B.clientStarts==1 and B.uiStarts==1 and B.soundStarts==1,'client starts after profile exactly once')
Info.SendPlayerInfo(B.player)
check(B.clientStarts==1 and B.uiStarts==1 and B.backpackCalls==1,'profile replay cannot restart client or reset backpack')
check(B.bgm==1 and B.sfx==1 and B.vibration==true,'loaded settings applied')
B.request:Fire(B.player,{action='SetBGMVolume',value=.4})
check(Info.GetPlayerInfo(B.player).settingInfo.bgmVolume==1,'rate limit blocks immediate repeat')
-- Exercise actual setting handler after the clock boundary advances.
local Settings=require('./ServerPlayerSettingManager')
local settings=server.settings;settings.lastRequest[B.player]=-math.huge
B.request:Fire(B.player,{action='SetBGMVolume',value=.4})
check(B.bgm==.4 and Info.GetPlayerInfo(B.player).settingInfo.bgmVolume==.4,'server setting update and client application')
check(Info.AddCoins(B.player,100) and Info.GetPlayerInfo(B.player).coins==421,'reward uses shared data owner')
Info.Tick(B.player,2.5)
check(Info.GetPlayerInfo(B.player).gameTime==2.5,'foundation owns online statistics')
check(Info.SetPlayerGamePassAcquired(B.player,42) and not Info.SetPlayerGamePassAcquired(B.player,42),'server pass notification idempotent')
check(B.grants==1 and table.find(ClientInfo.GetLocalPlayerInfo().ownedGamePassList,42),'client pass cache receives one grant')
check(Info.GetPlayerInfo(B.player).coins==421 and Info.GetPlayerInfo(B.player).dataVersion==0,'reference fields live directly on PlayerInfo')
check(Info.GetPlayerInfo(B.player).ownedGamePassMap[42] and ClientInfo.GetLocalPlayerInfo().ownedGamePassMap[42],'reference pass maps built on both peers')
local publicSave=Info.CreatePlayerSaveInfoByPlayerInfo(Info.GetPlayerInfo(B.player))
check(publicSave.version==nil and publicSave.dataVersion==0 and rawget(publicSave,'dataVersion')==0,'reference save snapshot uses native dataVersion field')
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
local info=Info.GetPlayerInfo(B.player)
check(getmetatable(info)==nil and rawget(info,'coins')==421 and rawget(info,'dataVersion')==0,'public PlayerInfo is a plain native table')
check(info.profile==nil and info.revision==nil and info.savedRevision==nil and info.closing==nil,'session internals are not public fields')
local nativeClone=table.clone(info);nativeClone.coins=1
check(info.coins==421,'cloned scalar does not mutate authoritative coins')
info.playerInfoChanged=false;check(info.playerInfoChanged==false,'native dirty flag can be cleared')
info.playerInfoChanged=true;check(info.playerInfoChanged==true,'native dirty flag can be set')
local snapshot=Info.CreatePlayerSaveInfoByPlayerInfo(Info.GetPlayerInfo(B.player))
Info.UpdateSetting(B.player,'vibrationOn',false)
check(snapshot.settingInfo.vibrationOn==true,'pending snapshot does not change during new edits')
check(Info.Save(B.player),'latest profile saved')
check(not Info.GetPlayerInfo(B.player).playerInfoChanged,'successful unchanged snapshot clears native dirty flag')
local stranger=B.Player(3003);settings.lastRequest[stranger]=-math.huge
B.request:Fire(stranger,{action='SetBGMVolume',value=.1})
check(Info.GetPlayerInfo(stranger)==nil,'unloaded player cannot modify settings')
server:RemovePlayer(B.player);server:RemovePlayer(B.player)
check(B.processingRemoves==2 and Info.GetPlayerInfo(B.player)==nil and B.player.attributes.GameReady==false,'exit freezes and detaches exactly once')
server:AddPlayer(B.player)
check(Info.GetPlayerInfo(B.player).coins==421 and not Info.GetPlayerInfo(B.player).settingInfo.vibrationOn,'rejoin restores coins and settings')
check(Info.GetPlayerInfo(B.player).loginDays==1,'same UTC day rejoin keeps login count')
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
-- 普通表直接写入也必须在保存期间保留脏状态，随后快照使用最新字段。
local current=Info.GetPlayerInfo(B.player)
local savedCoins=current.coins
Mock.DataStoreTool.SafeUpdate=function(...)task.wait(.02);return previousUpdate(...)end
local firstDone=false
task.spawn(function()Info.Save(B.player);firstDone=true end)
task.wait(.005)
current.coins+=7;current.settingInfo.bgmVolume=.7;current.playerInfoChanged=true
task.wait(.03)
check(firstDone and current.playerInfoChanged,'direct native writes during save remain dirty')
check(B.db.values['1001'].coins==savedCoins,'pending snapshot owns scalar fields')
check(Info.Save(B.player) and B.db.values['1001'].coins==savedCoins+7 and not current.playerInfoChanged,'follow-up save persists direct writes and clears only current snapshot')
Mock.DataStoreTool.SafeUpdate=previousUpdate
Config.SessionOnlyEconomy = true
local interrupted=B.Player(4004)
local baseResolve=B.Context.ResolveConfig
B.Context.ResolveConfig=function()task.wait(.02);return {final=true}end
local noticeCount=#B.notices
task.spawn(function()server:AddPlayer(interrupted)end)
task.wait(.005);interrupted.Parent=nil
server:RemovePlayer(interrupted)
check(not server.store:IsActive(interrupted.UserId),'disconnect releases lease before slow config resolver finishes')
task.wait(.04)
B.Context.ResolveConfig=baseResolve
check(Info.GetPlayerInfo(interrupted)==nil and #B.notices==noticeCount and not server.loading[interrupted],'departure during config resolution never publishes native info')
local Lease=require('./PlayerSaveLeaseRules')
check(B.db.metadata['4004'][Lease.MetadataKeys.SessionId]==nil,'config cancellation releases acquired lease')
local leaving=B.Player(5005)
Mock.DataStoreTool.SafeUpdate=function(...)
 task.wait(.02)
 return previousUpdate(...)
end
local addsBefore=B.processingAdds
task.spawn(function()server:AddPlayer(leaving)end)
task.wait(.005);leaving.Parent=nil
task.spawn(function()server:RemovePlayer(leaving)end)
task.wait(.07)
Mock.DataStoreTool.SafeUpdate=previousUpdate
check(Info.GetPlayerInfo(leaving)==nil and not server.loading[leaving] and B.processingAdds==addsBefore,'leaving during data acquisition never attaches gameplay')
check((not B.db.metadata['5005']) or B.db.metadata['5005'][Lease.MetadataKeys.SessionId]==nil,'leaving during acquire releases acquired lease')
local expiredPlayer=B.Player(6006);server:AddPlayer(expiredPlayer)
server.store.records[6006].expiresAt=0
local coinsBefore=Info.GetPlayerInfo(expiredPlayer).coins
check(not Info.AddCoins(expiredPlayer,100) and Info.GetPlayerInfo(expiredPlayer).coins==coinsBefore,'expired lease cannot award coins')
server:RemovePlayer(expiredPlayer)
check(Info.GetPlayerInfo(expiredPlayer)==nil,'expired player cleans up owner record')
-- 串联首次创建、原生初始化及直接保存，始终保持同一初始版本。
local NativeConfig=require('./GameConfig')
local Version=require('./PlayerSaveInfoVersionUpdateTool')
local pipelinePlayer=B.Player(9009)
local beforeAcquire=#B.notices
local acquired=Info.AcquirePlayerSaveInfo(pipelinePlayer)
check(acquired and acquired.dataVersion==0 and Info.GetPlayerInfo(pipelinePlayer)==nil and #B.notices==beforeAcquire,'acquisition holds lease without publishing PlayerInfo')
local initialNative=NativeConfig.CreateDefaultPlayerSaveInfo(100000)
check(Version.Update(initialNative)==initialNative and initialNative.dataVersion==0,'reserved entry validates initial save without migration')
Info.InitPlayerInfo(pipelinePlayer,initialNative,'unknown',{final=true})
check(#B.notices==beforeAcquire+1 and Info.GetPlayerInfo(pipelinePlayer).dataVersion==0,'native InitPlayerInfo publishes local notice without root compensation')
local nativeSnapshot=Info.CreatePlayerSaveInfoByPlayerInfo(Info.GetPlayerInfo(pipelinePlayer))
check(nativeSnapshot.version==nil and nativeSnapshot.dataVersion==0 and Save.Validate(nativeSnapshot),'native snapshot is directly valid at storage boundary')
check(Info.Save(pipelinePlayer) and B.db.values['9009'].version==nil and B.db.values['9009'].dataVersion==0,'new save pipeline stores native initial version directly')
Info.RemovePlayerInfo(pipelinePlayer)
do
	-- M1 本局化经济验证：进服金币归零，运行期可累加，保存时固定写入 0 且保留设置与统计。
	local sessionPlayer = B.Player(7007)
	B.db.values['7007'] = Save.New(100000)
	B.db.values['7007'].coins = 321
	B.db.values['7007'].settingInfo.bgmVolume = 0.8
	server:AddPlayer(sessionPlayer)
	local sInfo = Info.GetPlayerInfo(sessionPlayer)
	check(sInfo ~= nil and sInfo.coins == 0 and sessionPlayer.attributes.Coins == 0, 'SessionOnlyEconomy zeroes pre-existing DB coins on join')
	check(Info.AddCoins(sessionPlayer, 250) and sInfo.coins == 250 and sessionPlayer.attributes.Coins == 250, 'SessionOnlyEconomy allows runtime coin gains')
	check(Info.UpdateSetting(sessionPlayer, 'bgmVolume', 0.25), 'SessionOnlyEconomy allows setting updates')
	Info.Tick(sessionPlayer, 3.5)
	local sessionSnap = Info.CreatePlayerSaveInfoByPlayerInfo(sInfo)
	check(sessionSnap.coins == 0 and sessionSnap.settingInfo.bgmVolume == 0.25 and sessionSnap.gameTime == 3.5, 'CreatePlayerSaveInfoByPlayerInfo zeroes coins while preserving settings and statistics')
	check(Info.Save(sessionPlayer), 'SessionOnlyEconomy save succeeds')
	check(B.db.values['7007'].coins == 0 and B.db.values['7007'].settingInfo.bgmVolume == 0.25 and B.db.values['7007'].gameTime == 3.5, 'SessionOnlyEconomy writes coins=0 while persisting settings and gameTime')
	server:RemovePlayer(sessionPlayer)
	check(B.db.values['7007'].coins == 0, 'RemovePlayer persists coins=0 under SessionOnlyEconomy')
	server:AddPlayer(sessionPlayer)
	local rejoined = Info.GetPlayerInfo(sessionPlayer)
	check(rejoined ~= nil and rejoined.coins == 0 and rejoined.settingInfo.bgmVolume == 0.25 and rejoined.gameTime == 3.5, 'rejoin under SessionOnlyEconomy starts with coins=0 and restores settings')
	server:RemovePlayer(sessionPlayer)
end
local closingLoad=B.Player(8008)
local beforeCloseNotices=#B.notices
B.Context.ResolveConfig=function()task.wait(.03);return {final=true}end
task.spawn(function()server:AddPlayer(closingLoad)end)
task.wait(.005)
server:Close()
B.Context.ResolveConfig=baseResolve
check(Info.GetPlayerInfo(closingLoad)==nil and #B.notices==beforeCloseNotices,'shutdown during config resolution never publishes half initialized player')
check(not server.store:IsActive(closingLoad.UserId) and not server.loading[closingLoad],'shutdown releases loading lease and waits within common deadline')
client:Destroy();server:Destroy();task.wait()
check(B.request:Count()==0 and B.notify:Count()==0 and B.Players.PlayerAdded:Count()==0 and B.RunService.Heartbeat:Count()==0,'destroy disconnects lifecycle hooks')
check(Info.GetPlayerInfo(B.player)==nil,'shutdown releases sole data owner')
local cold=Client.new();cold:Init();check(not cold.started,'client waits for profile rather than starting early');cold:Destroy()
print(string.format('PASS: %d foundation assertions (production data and managers; engine boundaries mocked)',checks))
