-- 曲面白膜 Edit 模板安装器：保留 R15 关节契约，仅替换可视身体，不覆写脚本
assert(game.PlaceId==110812537538556 and not game:GetService("RunService"):IsRunning(),"Place1 Edit required")
local rs=game:GetService("ReplicatedStorage")
local models=rs:WaitForChild("Models")
local function CompleteRig(rig)
 rig.HumanoidRootPart.CanQuery=false
 if not rig:GetAttribute("RigRetargeted") then
  rig.Humanoid.AutomaticScalingEnabled=false
  for _,side in {"Left","Right"} do
   local sign=if side=="Left" then 1 else -1
   local torso=rig.UpperTorso[side.."ShoulderRigAttachment"]
   local arm=rig[side.."UpperArm"][side.."ShoulderRigAttachment"]
   torso.CFrame=torso.CFrame+Vector3.new(sign*.15,0,0)
   arm.CFrame=arm.CFrame-Vector3.new(sign*.15,0,0)
  end
  rig:SetAttribute("RigRetargeted",true)
 end
 local links={{"Root","HumanoidRootPart","LowerTorso"},{"Waist","LowerTorso","UpperTorso"},{"Neck","UpperTorso","Head"}}
 for _,side in {"Left","Right"} do
  for _,link in {{"Shoulder","UpperTorso",side.."UpperArm"},{"Elbow",side.."UpperArm",side.."LowerArm"},{"Wrist",side.."LowerArm",side.."Hand"},{"Hip","LowerTorso",side.."UpperLeg"},{"Knee",side.."UpperLeg",side.."LowerLeg"},{"Ankle",side.."LowerLeg",side.."Foot"}} do
   table.insert(links,{side..link[1],link[2],link[3]})
  end
 end
 for _,link in links do
  local p0,p1=rig[link[2]],rig[link[3]]
  if not p1:FindFirstChild(link[1]) then
   local name=link[1].."RigAttachment"
   local a,b=p0[name],p1[name]
   local motor=Instance.new("Motor6D")
   motor.Name,motor.Part0,motor.Part1=link[1],p0,p1
   motor.C0,motor.C1,motor.Parent=a.CFrame,b.CFrame,p1
  end
 end
end
local existing=rs.Models.WhiteR15
if existing:GetAttribute("SurfaceVersion")==1 then CompleteRig(existing);return "Already installed; rig verified" end
local source=models:FindFirstChild("WhiteBodyImport")
if not source then source=game:GetService("InsertService"):LoadAsset(84781021841961);source.Name="WhiteBodyImport";source.Parent=models end
local previous=models.WhiteR15
local backup=models:FindFirstChild("WhiteR15Legacy")
if not backup then backup=previous:Clone();backup.Name="WhiteR15Legacy";backup.Parent=models end
local rig=previous:Clone()
rig.Name="WhiteR15CurvedStaging"
local replacements={}
local joints={}
for _,joint in rig:GetDescendants() do
 if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
  table.insert(joints,{joint=joint,part0=joint.Part0,part1=joint.Part1,world0=joint.Part0.CFrame*joint.C0,world1=joint.Part1.CFrame*joint.C1})
 end
end
for _,old in rig:GetChildren() do
 if old:IsA("BasePart") and old.Name~="HumanoidRootPart" then
  local imported=source:FindFirstChild(old.Name,true)
  assert(imported and imported:IsA("MeshPart"),"Missing mesh "..old.Name)
  local part=imported:Clone()
  for _,v in part:GetChildren() do v:Destroy() end
  part.Name=old.Name
  part.Size=imported.Size/100
  local arm=string.find(old.Name,"Arm") or string.find(old.Name,"Hand")
  local shift=if arm then Vector3.new(if string.sub(old.Name,1,4)=="Left" then .3 else -.3,0,0) else Vector3.zero
  part.CFrame=old.CFrame+shift
  part.Color=Color3.fromRGB(220,220,231)
  part.Material=Enum.Material.SmoothPlastic
  part.TextureID=""
  part.Anchored,part.CanCollide,part.CanTouch,part.Massless=false,false,false,false
  part.CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition
  part:SetAttribute("Paintable",true)
  part:SetAttribute("SurfaceVersion",1)
  for _,child in old:GetChildren() do child.Parent=part end
  part.Parent=rig
  replacements[old]=part
 end
end
for _,record in joints do
 local joint=record.joint
 local p0=replacements[record.part0] or record.part0
 local p1=replacements[record.part1] or record.part1
 local arm=string.find(p1.Name,"Arm") or string.find(p1.Name,"Hand")
 local shoulder=string.find(joint.Name,"Shoulder")
 local amount=if shoulder then .15 elseif arm then .3 else 0
 local shift=Vector3.new(if string.sub(p1.Name,1,4)=="Left" then amount else -amount,0,0)
 joint.Part0,joint.Part1=p0,p1
 joint.C0=p0.CFrame:ToObjectSpace(record.world0+shift)
 joint.C1=p1.CFrame:ToObjectSpace(record.world1+shift)
end
for _,joint in rig:GetDescendants() do
 if joint:IsA("AnimationConstraint") then
  -- Existing attachment positions are retargeted from the original part frames.
  for _,attachment in {joint.Attachment0,joint.Attachment1} do
   if attachment then
    local part=attachment.Parent
    if part and part:IsA("BasePart") then
     for old,replacement in replacements do
      if replacement==part then attachment.CFrame=part.CFrame:ToObjectSpace(old.CFrame*attachment.CFrame) end
     end
    end
   end
  end
 end
end
for old in replacements do old:Destroy() end
rig.PrimaryPart=rig.HumanoidRootPart
rig:SetAttribute("SurfaceVersion",1)
rig:SetAttribute("MeshModelAsset",84781021841961)
rig.Parent=models
previous:Destroy()
rig.Name="WhiteR15"
CompleteRig(rig)
source:Destroy()
return {path=rig:GetFullName(),parts=15,surfaceVersion=1}
