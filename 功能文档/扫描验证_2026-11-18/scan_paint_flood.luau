local M=require('./ScanProcessingManager')
local Protocol=require('./VisualProtocol')
local B=require('./ScanPaintBoundary')
local player={}
local session={player=player,id="body",token="token",sequence=1,last=100,yaw=0,pitch=0}
local manager=setmetatable({players={[player]={}},data={IsActive=function() return true end},paint=session,items={body={stage="Painting",progress=0}},Root=function() return {} end},M)
for index=1,1000 do
 local request={action="Paint",session="token",sequence=index+1,samples={}}
 assert(Protocol.Validate(request),"request must pass real wire validation")
 manager:OnRequest(player,request)
end
assert(B.count==1000)
assert(session.last==100)
print("PASS diagnostic: 1000 valid Paint requests at fixed time; 0 accepted coverage updates, "..B.count.." PaintPose broadcasts")
