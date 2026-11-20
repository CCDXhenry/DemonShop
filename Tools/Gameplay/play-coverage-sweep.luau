-- Play 客户端验收辅助：通过真实网络请求扫涂可见表面，不修改完成度或服务端状态
local Net=require(game.ReplicatedStorage.Scripts.Shared.NetMsg)
local Surface=require(game.ReplicatedStorage.Scripts.Shared.PaintSurface)
local Curve=require(game.ReplicatedStorage.Scripts.Shared.CurvedSurface)
local Rotation=require(game.ReplicatedStorage.Scripts.Shared.PaintRotation)
local BodyPose=require(game.ReplicatedStorage.Scripts.Shared.PaintBodyPose)
local test=_G.GameplayTest
assert(test and test.snapshot and test.snapshot.session,"Begin painting and attach a snapshot listener first")
test.bodyId=test.snapshot.tableId;test.paintTestRunning=true;test.paintResults={}
task.spawn(function()
 local item
 local sequence=1000000 -- 独立辅助命名空间；不得与正常绘制同时运行
 for _,candidate in test.snapshot.items do if candidate.id==test.bodyId then item=candidate end end
 local placement=workspace.NeonContractDistrict.RuneBodyTable.BodyPlacementAnchor.Position
 local base,origin=Rotation.TablePose(placement),Rotation.CameraPose(placement).Position
 local frames=test.snapshot.bodyPose or BodyPose.Capture(item.model)
 local geometry=Rotation.Create(item.model,frames)
 for phase=0,44 do
  if not test.snapshot.session then break end
  local orientation=CFrame.Angles(math.sin(phase*.2)*.85,phase*.18,0)
  local pose=Rotation.Pose(base,geometry,orientation)
  local samples={}
  for _,part in item.model:GetChildren() do if part:IsA('BasePart') and Surface.IsBody(part) then
   local cf=pose*geometry.rest*frames[part.Name]
   if Curve.IsPart(part) then
    for triangleIndex,triangle in Curve.Geometry(part).triangles do
     local point=cf:PointToWorldSpace((triangle.a+triangle.b+triangle.c)/3)
     if triangle.allowed and (triangleIndex+phase)%8==0 and cf:VectorToWorldSpace(triangle.normal):Dot((origin-point).Unit)>.1 then
      table.insert(samples,{part=part.Name,face=1,triangle=triangleIndex,surfaceVersion=Curve.Version,u=1/3,v=1/3})
     end
    end
    continue
   end
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
   Net.FireRequest({action='Paint',session=test.snapshot.session,sequence=sequence,samples=batch,orientation=orientation})
   task.wait(.09)
  end
  for _,candidate in test.snapshot.items do if candidate.id==test.bodyId then
   table.insert(test.paintResults,{phase=phase,progress=candidate.progress,stage=candidate.stage})
  end end
 end
 test.paintTestRunning=false
end)
return 'Coverage sweep started through GameRequest'
