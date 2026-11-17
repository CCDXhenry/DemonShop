-- 执行正式具名网络与旧适配器，防止双传输路径、参数漂移与连接泄漏
local B=require('./FoundationBoundary')
local W=require('./FoundationWireBoundary')
local Net=require('./FoundationWire')
local Adapter=require('./FoundationAdapter')
local Version=require('./PlayerSaveInfoVersionUpdateTool')
local Context=require('./PlayerContextTool')
local Config=require('./GameConfig')
local checks=0
local function check(v,label)assert(v,label);checks+=1 end
local received={}
local connections={}
for _,name in {'SetBGMVolume','SetSoundEffectVolume','SetVibrationsOnOffState'} do
 local seen={}
 table.insert(connections,Net['ConnectRequest'..name](function(player,value)table.insert(seen,{player,value})end))
 local valid=if name=='SetVibrationsOnOffState' then false else .25
 Net['FireRequest'..name](valid)
 check(#seen==1 and seen[1][1]==B.player and seen[1][2]==valid,'named request preserves sender and payload')
 local event=W.events['Request'..name]
 for _,invalid in {0/0,math.huge,-1,2,'invalid',{}} do event:FireServer(invalid) end
 check(#seen==1,'actual wire rejects invalid values')
end
local requests=0
local requestConnection=Adapter.ConnectRequest(function()requests+=1 end)
Adapter.RequestPlayerInfoInit();Adapter.RequestSetBGMVolume(.5);Adapter.RequestSetSoundEffectVolume(.5);Adapter.RequestSetVibrationsOnOffState(true)
check(requests==4,'adapter receives each named request once')
W.events.FoundationRequest:FireServer({action='SetBGMVolume',value=.5})
check(requests==4,'handshake cannot carry settings')
local notices={}
local noticeConnection=Adapter.ConnectNotify(function(notice)table.insert(notices,notice)end)
local localInfo={coins=12,settingInfo={bgmVolume=1,soundEffectVolume=1,vibrationOn=true},ownedGamePassList={}}
Net.FireNotifyPlayerInfoInit(B.player,localInfo,{['2002']={}},{feature=true})
check(#notices==1 and notices[1].localInfo==localInfo and notices[1].otherPlayers['2002'] and notices[1].playerConfigInfo.feature,'three argument reference init is adapted without full profile')
Net.FireNotifyPlayersOtherPlayerInfoInit(2002,{})
Net.FireNotifyPlayerAcquiredGamePass(B.player,42)
Net.FireNotifyPlayerLeft(2002)
check(#notices==4 and notices[2].playerId==2002 and notices[3].gamePassId==42 and notices[4].kind=='PlayerLeft','reference broadcasts and leave extension')
check(W.events.FoundationNotify==nil,'retired notification transport never accessed')
requestConnection:Disconnect();requestConnection:Disconnect();noticeConnection:Disconnect()
Net.FireNotifyPlayerAcquiredGamePass(B.player,43);Adapter.RequestPlayerInfoInit()
check(requests==4 and #notices==4 and not requestConnection.Connected,'composite connection disconnect is complete and idempotent')
for _,connection in connections do connection:Disconnect() end
for _,event in W.events do check(event.OnServerEvent:Count()==0 and event.OnClientEvent:Count()==0,'all network connections released') end
local initial=Config.CreateDefaultPlayerSaveInfo(100000)
check(Version.Update(initial)==initial and initial.dataVersion==0 and initial.coins==0,'reserved framework entry leaves current initial save unchanged')
for _,unsupported in {1,2,99} do
 local value=Config.CreateDefaultPlayerSaveInfo();value.dataVersion=unsupported
 check(Version.Update(value)==nil and value.dataVersion==unsupported,'unregistered versions are rejected without migration')
end
local corrupt=Config.CreateDefaultPlayerSaveInfo();corrupt.coins=nil
check(Version.Update(corrupt)==nil and corrupt.coins==nil,'missing fields are not repaired as legacy data')
check(Version.Update({version=1,coins=77})==nil,'old alternate shape is not converted')
local region,config=Context.Get(B.player)
check(region=='unknown' and next(config)==nil,'country lookup failure falls back without blocking')
check(next(Context.ResolveConfig(B.player,'1.0.0'))==nil,'disabled remote configuration uses local defaults')
check(Config.CreateDefaultPlayerSaveInfo().dataVersion==0,'default factory exposes native reference version')
local native=Config.CreateDefaultPlayerSaveInfo(100000)
check(rawget(native,'dataVersion')==0 and native.version==nil and getmetatable(native)==nil,'foundation save is a plain native table')
check(native.loginDays==1 and native.lastOnlineDateUTC==86400 and native.firstEnterTime==100000,'foundation defaults retain reference login and UTC semantics')
local Save=require('./SaveRules')
local durable=Save.Copy(native)
check(durable.dataVersion==0 and durable.version==nil and Save.Validate(durable),'native save is stored directly without an alternate version field')
durable.settingInfo.bgmVolume=.2
check(native.settingInfo.bgmVolume==1,'save snapshot owns nested settings')
print(string.format('PASS: %d foundation wire/context assertions (production protocols, adapter and initial schema)',checks))
