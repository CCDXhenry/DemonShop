-- 获授权 Play 隔离验收：走停、受击、无碰撞肩扛、跳跃、释放及重复拾放清理
assert(game:GetService("RunService"):IsRunning(),"Play server required")
local NPC=require(game.ServerStorage.Scripts.NPC)
local Carry=require(game.ServerStorage.Scripts.Carry)
local Scene=require(game.ServerStorage.Scripts.Scene)
local Physics=require(game.ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Config=require(game.ReplicatedStorage.Scripts.Shared.GameConfig)
local player=game.Players:GetPlayers()[1]
assert(player and player.Character,"A live player is required")
local character=player.Character
local original=character:GetPivot()
local folder=Instance.new("Folder")
folder.Name="WhiteBodyIsolatedChecks"
folder.Parent=workspace
local results={}
local item
local function check(value,name)
 assert(value,name)
 results[name]=true
end
local function updateFor(seconds)
 local deadline=os.clock()+seconds
 repeat
  local now=workspace:GetServerTimeNow()
  Carry.AdvanceTransition(item,now)
	 if item.carryTarget then
	  local distance=(item.model.UpperTorso.Position-item.carryTarget.WorldPosition).Magnitude
	  results.maximumShoulderError=math.max(results.maximumShoulderError or 0,distance)
	 end
  NPC.Update(item,now)
  Carry.Update(item,now)
  task.wait(.04)
 until os.clock()>=deadline
end
local ok,reason=xpcall(function()
 item=NPC.Spawn(folder,{})
 assert(item)
 local model=item.model
 local root=model.PrimaryPart
 item.nextWalk=workspace:GetServerTimeNow()+100
 model.Humanoid:MoveTo(root.Position)
 updateFor(.4)
 check(item.motionState=="Idle" and not item.walkTrack.IsPlaying,"stopExitsWalk")
 model.Humanoid:MoveTo(root.Position+Vector3.new(5,0,0))
 updateFor(.4)
 check(item.motionState=="Walking" and item.walkTrack.IsPlaying,"walkStarts")
 check(math.abs(model.Humanoid.WalkSpeed-Config.NpcStrollSpeed)<.01,"streetStrollSpeed")
 check(Scene.IsInStreetWalkZones(root.Position,1),"streetSpawnInZone")
 local attackFrom=root.Position-Vector3.xAxis*6
 NPC.Hit(item,Vector3.xAxis,nil,nil,attackFrom)
 check(item.motionState=="Hit" and model.Humanoid.WalkSpeed==0,"shortHitStop")
 updateFor(.17)
 check(item.motionState=="Fleeing" and model.Humanoid.WalkSpeed==Config.NpcFleeSpeed,"startsFlee")
 local firstDeadline=item.fleeUntil
 NPC.Hit(item,Vector3.xAxis,nil,nil,attackFrom)
 check(item.fleeUntil>firstDeadline,"repeatHitExtendsFlee")
 updateFor(Config.NpcFleeDuration+.12)
 check(item.motionState~="Fleeing" and model.Humanoid.WalkSpeed==Config.NpcStrollSpeed,"fleeRecovers")
 check(Scene.IsInStreetWalkZones(root.Position,1),"fleeStaysInStreet")
 NPC.Hit(item,Vector3.xAxis)
 check(item.motionState=="Down" and item.fleeUntil==nil,"stunCancelsFlee")
 check(model:GetAttribute("PhysicsMode")== (if Physics.GroundRootEnabled then "GroundRoot" else "Loose"),"thirdHitRagdoll")
 -- 沿用玩家当前的网络所有权，把隔离样本移到玩家身边再测肩扛。
 model:PivotTo(CFrame.new(character.PrimaryPart.Position+Vector3.new(2,0,0))*root.CFrame.Rotation)
 check((character.PrimaryPart.Position-root.Position).Magnitude<4,"carryFixtureInReach")
 check(Carry.Take(item,player),"takeBody")
 updateFor(.6)
 for _,part in model:GetDescendants() do
  if part:IsA("BasePart") then check(not part.CanCollide,"carriedCollision_"..part.Name) end
 end
 local humanoid=character.Humanoid
 humanoid.Jump=true
 updateFor(.5)
 check(item.location=="Carried","survivesJump")
 updateFor(1)
 results.shoulderError=(model.UpperTorso.Position-item.carryTarget.WorldPosition).Magnitude
 check(results.shoulderError<.5,"boundedShoulderError")
 local pose=model:GetPivot()
 Carry.Drop(item,root.Position)
 results.releaseDisplacement=(model:GetPivot().Position-pose.Position).Magnitude
 check(item.carryTarget==nil and item.carryResources==nil,"releaseClearsSupport")
 updateFor(.7)
 for index=1,20 do
  check(Carry.Take(item,player),"repeatTake"..index)
  Carry.Static(item,CFrame.new(Scene.StreetPoint(Random.new(index))+Vector3.new(0,3.2,0)))
 end
 check(character:FindFirstChild("WhiteBodyShoulder",true)==nil,"shoulderAttachmentsCleared")
 check(model:FindFirstChild("CarryAnchor",true)==nil,"bodyAttachmentsCleared")
 check(model:FindFirstChild("CarryResources")==nil,"supportResourcesCleared")
end,debug.traceback)
if item then Carry.Detach(item) end
folder:Destroy()
if character.Parent then character:PivotTo(original) end
_G.WhiteBodyCheckResults=results
assert(ok,tostring(reason).." | "..game:GetService("HttpService"):JSONEncode(results))
return results
