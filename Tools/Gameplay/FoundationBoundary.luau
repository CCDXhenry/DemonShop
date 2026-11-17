-- 基础框架离线边界：信号、服务与业务替身；正式资料、保存和管理器照常执行
local R=require('@lune/roblox')
local Mock=require('./Mock')
local B={Enum=R.Enum,db=Mock.NewStore(),processingStarts=0,processingAdds=0,processingRemoves=0,clientStarts=0,uiStarts=0,soundStarts=0,notices={},clock=100,binds=0}
function B.Signal()
 local s={listeners={}}
 function s:Connect(callback)
  local c={Connected=true};function c:Disconnect() self.Connected=false end
  table.insert(self.listeners,{callback=callback,connection=c});return c
 end
 function s:Fire(...) for _,v in table.clone(self.listeners) do if v.connection.Connected then v.callback(...) end end end
 function s:Count() local n=0;for _,v in self.listeners do if v.connection.Connected then n+=1 end end;return n end
 return s
end
B.request=B.Signal();B.notify=B.Signal()
B.Net={ConnectRequest=function(cb) return B.request:Connect(cb) end,ConnectNotify=function(cb) return B.notify:Connect(cb) end,
 FireNotify=function(player,notice) table.insert(B.notices,{player=player,notice=notice});B.notify:Fire(notice) end,
 RequestPlayerInfoInit=function() B.request:Fire(B.player,{action='RequestPlayerInfoInit'}) end}
for _,name in {'SetBGMVolume','SetSoundEffectVolume','SetVibrationsOnOffState','PlayerInfoInit'} do
 B.Net['ConnectRequest'..name]=function(callback)
  return B.request:Connect(function(player,request)
   if request.action==name or (name=='PlayerInfoInit' and request.action=='RequestPlayerInfoInit') then callback(player,request.value) end
  end)
 end
end
B.Net.FireRequestPlayerInfoInit=B.Net.RequestPlayerInfoInit
B.Net.FireNotifyPlayerInfoInit=function(player,info,others,config)
 table.insert(B.notices,{player=player,notice={kind='PlayerInfoInit',localInfo=info,otherPlayers=others,playerConfigInfo=config}})
 B.notify:Fire('PlayerInfoInit',info,others,config)
end
B.Net.FireNotifyPlayersOtherPlayerInfoInit=function(id,info) B.otherNotices=(B.otherNotices or 0)+1;B.notify:Fire('OtherPlayerInfoInit',id,info) end
B.Net.FireNotifyPlayerAcquiredGamePass=function(player,id) B.notify:Fire('GamePassAcquired',id) end
B.Net.FireNotifyPlayerLeft=function(id) B.notify:Fire('PlayerLeft',id) end
for name,kind in {NotifyPlayerInfoInit='PlayerInfoInit',NotifyPlayersOtherPlayerInfoInit='OtherPlayerInfoInit',NotifyPlayerAcquiredGamePass='GamePassAcquired',NotifyPlayerLeft='PlayerLeft'} do
 B.Net['Connect'..name]=function(callback)
  return B.notify:Connect(function(received,...) if received==kind then callback(...) end end)
 end
end
B.Context={Get=function()return 'unknown',{} end,ResolveConfig=function()return {} end}
B.Players={PlayerAdded=B.Signal(),PlayerRemoving=B.Signal(),GetPlayers=function() return {} end}
B.RunService={Heartbeat=B.Signal(),IsStudio=function() return true end}
B.DataStoreService={GetDataStore=function() return B.db end}
B.game={BindToClose=function() B.binds+=1 end}
B.Processing={new=function() return {
 Init=function() B.processingStarts+=1 end,AddPlayer=function() B.processingAdds+=1 end,
 RemovePlayer=function() B.processingRemoves+=1 end,Destroy=function() end,
} end}
B.ClientProcessing={new=function() return {gui={},Init=function() B.clientStarts+=1 end,Destroy=function() end} end}
B.UI={CreateGameScreenGui=function() B.uiStarts+=1;return {} end,Destroy=function() end}
B.Sound={Init=function() B.soundStarts+=1 end,PlayBGM=function() end,SetBGMVolume=function(v) B.bgm=v end,
 SetSoundEffectVolume=function(v) B.sfx=v end,SetVibrationsOnOffState=function(v) B.vibration=v end,Destroy=function() end}
B.MarketplaceService={PromptGamePassPurchaseFinished=B.Signal(),UserOwnsGamePassAsync=function() return false end}
B.Analytics={Init=function() end,Destroy=function() end,AddPlayerEnterGameEvent=function() end,AddPlayerLeaveGameEvent=function() end,AddPassPurchaseEvent=function() end}
B.Chat={new=function() return {Init=function() end,Destroy=function() end} end}
B.serverInit=B.Signal()
B.ServerMsg={FirePlayerInfoInit=function(player) B.serverInit:Fire(player) end}
B.ClientMsg={FireOtherPlayerInfoInit=function(id) B.lastOther=id end,FireLocalPlayerInfoInit=function() end,FireLocalPlayerAcquiredGamePass=function() B.grants=(B.grants or 0)+1 end}
function B.Player(id)
 local p={UserId=id,Parent=true,attributes={}}
 function p:SetAttribute(key,value) self.attributes[key]=value end
 function p:Kick(message) self.kicked=message;self.Parent=nil end
 function p:IsA(name) return name=='Player' end
 return p
end
B.Analytics.Flush=function()return true end
B.Analytics.Close=function()return true end
B.StarterGui={SetCoreGuiEnabled=function(_,kind,enabled) B.backpackCalls=(B.backpackCalls or 0)+1;B.backpackEnabled=enabled;B.backpackKind=kind end}
B.Analytics.AddPlayer=B.Analytics.AddPlayerEnterGameEvent
B.Analytics.RemovePlayer=B.Analytics.AddPlayerLeaveGameEvent
B.Players.LocalPlayer=B.Player(1001)
B.player=B.Players.LocalPlayer
return B
