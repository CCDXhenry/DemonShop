-- Play 客户端验收辅助：通过真实网络请求扫涂可见表面，不修改完成度或服务端状态
local Net=require(game.ReplicatedStorage.Scripts.Shared.NetMsg)
local Surface=require(game.ReplicatedStorage.Scripts.Shared.PaintSurface)
local test=_G.GameplayTest
assert(test and test.snapshot and test.snapshot.session,"Begin painting and attach a snapshot listener first")
test.bodyId=test.snapshot.tableId;test.paintTestRunning=true;test.paintResults={}
task.spawn(function()
 local item
 local sequence=1000000 -- 独立辅助命名空间；不得与正常绘制同时运行
 for _,candidate in test.snapshot.items do if candidate.id==test.bodyId then item=candidate end end
 local base=workspace.NeonContractDistrict.RuneBodyTable.BodyPlacementAnchor.CFrame*CFrame.new(0,4,0)
 local origin=(base*CFrame.new(0,1,12)).Position
 for phase=0,44 do
  if not test.snapshot.session then break end
  local yaw,pitch=phase*.18,math.sin(phase*.2)*.85
  local pose=base*CFrame.Angles(pitch,yaw,0)
  local samples={}
  for _,part in item.model:GetChildren() do if part:IsA('BasePart') and Surface.IsBody(part) then
   local cf=pose*part:GetAttribute('RestPose')
   for face=1,6 do if Surface.Allowed(part,face) then
    local n=Surface.Point(Vector3.new(2,2,2),face,.5,.5)
    local world=cf:PointToWorldSpace(Surface.Point(part.Size,face,.5,.5))
    if cf:VectorToWorldSpace(n):Dot((origin-world).Unit)>.1 then
     for x=0,3 do for y=0,3 do table.insert(samples,{part=part.Name,face=face,u=(x+.5)/4,v=(y+.5)/4}) end end
    end
   end end
  end end
  for index=1,#samples,12 do
   if not test.snapshot.session then break end
   local batch={}
   for j=index,math.min(index+11,#samples) do table.insert(batch,samples[j]) end
   sequence+=1
   Net.FireRequest({action='Paint',session=test.snapshot.session,sequence=sequence,samples=batch,yaw=yaw,pitch=pitch})
   task.wait(.09)
  end
  for _,candidate in test.snapshot.items do if candidate.id==test.bodyId then
   table.insert(test.paintResults,{phase=phase,progress=candidate.progress,stage=candidate.stage})
  end end
 end
 test.paintTestRunning=false
end)
return 'Coverage sweep started through GameRequest'
