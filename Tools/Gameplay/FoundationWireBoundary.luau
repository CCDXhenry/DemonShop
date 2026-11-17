-- 网络测试边界：真实具名协议和适配器共享同一组 Remote 信号
local B=require('./FoundationBoundary')
local W={events={}}
W.folder={WaitForChild=function(_,name)
 if not W.events[name] then
  local event={OnServerEvent=B.Signal(),OnClientEvent=B.Signal(),fires=0}
  function event:FireServer(...) self.fires+=1;self.OnServerEvent:Fire(B.player,...) end
  function event:FireClient(player,...) self.fires+=1;self.OnClientEvent:Fire(...) end
  function event:FireAllClients(...) self.fires+=1;self.OnClientEvent:Fire(...) end
  W.events[name]=event
 end
 return W.events[name]
end}
W.Processing={Validate=function()return true end,FireRequest=function()end,ConnectRequest=function()end,FireNotify=function()end,Broadcast=function()end,ConnectNotify=function()end}
return W
