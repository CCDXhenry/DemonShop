-- 统计离线边界：内存 HTTP、可控时间与真实任务调度，不访问网络
local task=require('@lune/task')
local serde=require('@lune/serde')
local B=require('./FoundationBoundary')
local A={clock=100,requests={},delay=0,fail=false,started=0,finished=0,warnings={}}
A.Config=table.clone(require('./GameConfig'))
A.Config.AnalyticsEnabled=false
A.Config.AnalyticsEndpoint='https://statistics.test.invalid/events'
A.Config.AnalyticsProjectId='offline-test'
A.Config.GameAnalyticsEnabled=false
A.Heartbeat=B.Signal()
A.RunService={IsStudio=function()return false end,Heartbeat=A.Heartbeat}
A.os={clock=function()return A.clock end,time=os.time}
A.task={wait=function(seconds)A.clock+=seconds or .001;task.wait(.001)end}
A.HttpService={JSONEncode=function(_,value)return serde.encode('json',value)end,GenerateGUID=function()return 'offline-purchase' end,
 RequestAsync=function(_,request)
  A.started+=1;table.insert(A.requests,serde.decode('json',request.Body))
  if A.delay>0 then task.wait(A.delay) end
  A.finished+=1
  return {Success=not A.fail}
 end}
A.Info={GetPlayerInfo=function()return {firstEnterTime=10,firstEnterVersion='1.0.0',countryRegion='unknown',gameTime=12,timeOfThisLogin=os.time()-5}end}
A.GameAnalytics={}
A.ServerConfig={GoogleAnalyticsGameKey='',GoogleAnalyticsSecretKey=''}
A.warn=function(...)table.insert(A.warnings,{...})end
A.player=B.Player(7007)
return A
