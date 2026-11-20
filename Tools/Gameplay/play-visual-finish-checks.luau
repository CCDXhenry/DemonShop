-- 隔离 Play 收尾回归：捕获网络边界且不写存档，不参与正常玩家流程验收
assert(game.PlaceId==110812537538556 and game:GetService("RunService"):IsServer(),"target server required")
local rs=game.ReplicatedStorage
local Manager=require(game.ServerStorage.Scripts.ProcessingManager)
local Scene=require(game.ServerStorage.Scripts.Scene)
local Net=require(rs.Scripts.Shared.NetMsg)
local Lifecycle=require(rs.Scripts.Shared.LifecycleTool)
local player=game.Players:FindFirstChild("Player3") or game.Players:GetPlayers()[1]
assert(player and player.Character,"test player required")
local hum=player.Character:FindFirstChildOfClass("Humanoid")
local root=player.Character.HumanoidRootPart
local backup={painting=player:GetAttribute("Painting"),walk=hum.WalkSpeed,jump=hum.JumpPower,height=hum.JumpHeight,anchored=root.Anchored}
local originalBroadcast,originalNotify=Net.Broadcast,Net.FireNotify
local notices={}
local manager=Manager.new({IsActive=function()return true end,CanAddCoins=function()return false end,AddCoins=function()return false end})
local model=Instance.new("Model");model.Name="VisualFinishFixture"
local part=Instance.new("Part");part.Name="UpperTorso";part.Size=Vector3.new(2,2,1);part.Anchored=true;part.CanCollide=false;part:SetAttribute("Paintable",true);part.Parent=model
model.PrimaryPart=part;model:PivotTo(Scene.TablePose());model.Parent=workspace
local scope=Lifecycle.new()
local checks=0
local function check(v,m)assert(v,m);checks+=1 end
local ok,err=xpcall(function()
 Net.Broadcast=function(n)table.insert(notices,n)end
 Net.FireNotify=function(_,n)table.insert(notices,n)end
 manager.players[player]={scope=scope,lastAttack=0,lastRequest=0,lastSync=0,closing=false}
 local item={id="visual-finish-fixture",kind="Body",stage="Painting",location="Table",version=1,model=model,hits=3,covered={},strokes={},strokePoints=0,area=0,totalArea=.001,progress=0,paintSeconds=0,streetSlot=false,nextWalk=0}
 manager.items[item.id]=item;manager.tableId=item.id
 local now=workspace:GetServerTimeNow()
 local session={player=player,id=item.id,token="fixture-session",sequence=0,last=now-1,orientation=CFrame.identity,walkSpeed=backup.walk,jumpPower=backup.jump,jumpHeight=backup.height}
 manager.paint=session
 local segment={key="fixture-session:1:1",version=1,gesture=1,part="UpperTorso",face=1,u0=.1,v0=.2,u1=.7,v1=.6}
 manager:OnRequest(player,{action="PaintVisual",session=session.token,sequence=1,segments={segment},started=now})
 check(item.visualState and item.visualState.count==1,"visual stored independently of coverage")
 manager:Paint(player,{action="Paint",session=session.token,sequence=1,samples={{part="UpperTorso",face=1,u=.5,v=.5}},orientation=CFrame.identity})
 check(item.progress==1 and session.finishing,"coverage completion enters finishing phase")
 check(manager.paint==session and item.stage=="Painting","completion does not release before final upload")
 local finishNotice=false
 for _,n in notices do if n.kind=="FinishPaint"then finishNotice=true end end
 check(finishNotice,"client receives final flush request")
 manager:OnRequest(player,{action="EndPaint",session=session.token,sequence=0})
 check(manager.paint==session,"unacknowledged end sequence cannot release ownership")
 local final=table.clone(segment);final.version=2;final.u1=.9
 manager:OnRequest(player,{action="PaintVisual",session=session.token,sequence=2,segments={final},started=now})
 check(item.visualState.segments[segment.key].version==2,"final extension accepted while finishing")
 manager:OnRequest(player,{action="EndPaint",session=session.token,sequence=2})
 check(manager.paint==nil and item.stage=="Painted","confirmed final sequence completes body and releases lock")
 check(item.visualState.count==1 and item.visualState.segments[segment.key].u1==.9,"completed body retains exact final geometry")
 manager:PaintVisual(player,{action="PaintVisual",session=session.token,sequence=3,segments={segment}})
 check(item.visualState.segments[segment.key].version==2,"closed session cannot overwrite final geometry")
 item.progress=.4;item.stage="Painting";manager.paint=session
 manager:ReleasePlayer(player)
 check(manager.paint==nil and item.stage=="Painting" and item.visualState.count==1,"death or disconnect release retains confirmed partial paint")
end,debug.traceback)
Net.Broadcast,Net.FireNotify=originalBroadcast,originalNotify
hum.WalkSpeed,hum.JumpPower,hum.JumpHeight=backup.walk,backup.jump,backup.height
root.Anchored=backup.anchored;player:SetAttribute("Painting",backup.painting)
model:Destroy();manager.runtime:Destroy();scope:Destroy();manager.scope:Destroy()
assert(ok,err)
return {passed=checks,kind="isolated finishing checks",dataStoreWrites=false}
