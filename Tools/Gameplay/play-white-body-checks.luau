-- 获授权 Play 隔离验收：走停、受击、无碰撞肩扛、跳跃、释放及重复拾放清理
assert(game:GetService("RunService"):IsRunning(),"Play server required")
local NPC=require(game.ServerStorage.Scripts.NPC)
local Carry=require(game.ServerStorage.Scripts.Carry)
local Scene=require(game.ServerStorage.Scripts.Scene)
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
	 if item.carryTarget then
	  local distance=(item.model.UpperTorso.Position-item.carryTarget.WorldPosition).Magnitude
	  results.maximumShoulderError=math.max(results.maximumShoulderError or 0,distance)
	 end
  NPC.Update(item,workspace:GetServerTimeNow())
  Carry.Update(item,workspace:GetServerTimeNow())
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
 local before=root.Position
 NPC.Hit(item,Vector3.xAxis)
 updateFor(.3)
 results.hitDisplacement=(root.Position-before).Magnitude
 check(results.hitDisplacement>.2,"visibleHitRecoil")
 updateFor(.6)
 check(item.motionState~="Hit","staggerRecovers")
 NPC.Hit(item,Vector3.xAxis)
 NPC.Hit(item,Vector3.xAxis)
 check(model:GetAttribute("PhysicsMode")=="Loose","thirdHitRagdoll")
 character:PivotTo(CFrame.new(root.Position+Vector3.new(3,1,0)))
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
