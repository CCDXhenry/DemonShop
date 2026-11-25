-- 绘画悬挂姿态回归：真实 R15 模板的骨架闭合、越界拒绝、权威重建及动态上传收尾
local fs=require('@lune/fs')
local R=require('@lune/roblox')
local Pose=require('./PaintBodyPose')
local Upload=require('./VisualUpload')
local Net=require('./VisualNet')
local model=R.deserializeModel(fs.readFile('Assets/Models/GameModels.rbxm'))[1].Characters.WhiteR15
local checks=0
local function check(value,message) assert(value,message);checks+=1 end
local motors={}
for _,v in model:GetDescendants() do
 if v:IsA('Motor6D') then
  table.insert(motors,v)
  if v.Name~='Root' and v.Name~='RootJoint' then
   local a,b=R.Instance.new('Attachment'),R.Instance.new('Attachment')
   a.CFrame,a.Parent=v.C0,v.Part0
   b.CFrame,b.Parent=v.C1,v.Part1
   local joint=R.Instance.new('BallSocketConstraint')
   joint.Name,joint.Attachment0,joint.Attachment1,joint.UpperAngle,joint.Parent=v.Name,a,b,75,model
  end
 end
end
for _=1,8 do for _,motor in motors do motor.Part1.CFrame=motor.Part0.CFrame*motor.C0*motor.C1:Inverse() end end
local frames=Pose.Capture(model)
check(Pose.ValidateWire(frames),'captured body is a bounded wire pose')
check(Pose.Validate(model,frames),'closed real R15 template passes joint validation')
local bent=table.clone(frames)
local neck
for _,motor in motors do if motor.Name=='Neck' then neck=motor end end
local head=neck.Part0.CFrame*neck.C0*R.CFrame.Angles(.2,0,0)*neck.C1:Inverse()
bent.Head=model.UpperTorso.CFrame:ToObjectSpace(head)
check(Pose.Validate(model,bent),'head can physically tilt around the neck')
local invalid=table.clone(frames);invalid.Head=invalid.Head+R.Vector3.new(2,0,0)
check(not Pose.Validate(model,invalid),'detached head rejected')
invalid=table.clone(frames);invalid.Head=nil
check(not Pose.Validate(model,invalid),'missing limb rejected')
invalid=table.clone(frames);invalid.UpperTorso=R.CFrame.new(0,.1,0)
check(not Pose.Validate(model,invalid),'support torso cannot move')
invalid=table.clone(frames);invalid.UnknownPart=R.CFrame.identity
check(not Pose.ValidateWire(invalid),'extra body parts rejected')
check(not Pose.IsFiniteFrame(R.CFrame.new(0/0,0,0)),'NaN frame rejected')
check(not Pose.IsFiniteFrame(R.CFrame.new(20,0,0)),'far-away frame rejected')
check(not Pose.Changed(frames,table.clone(frames)),'identical pose does not upload')
check(Pose.Changed(frames,bent),'joint rotation uploads without camera rotation')
local base=R.CFrame.new(10,4,-2)*R.CFrame.Angles(.3,.5,0)
model.UpperTorso:SetAttribute('RestPose',R.CFrame.new(0,.2,0))
Pose.Apply(model,base,bent)
for name,frame in bent do
 local expected=base*R.CFrame.new(0,.2,0)*frame
 check((model[name].CFrame.Position-expected.Position).Magnitude<.0001,'authoritative reconstruction '..name)
end
table.clear(Net.requests)
local upload=Upload.new();upload:Begin('pose-session')
upload:Update({},.1,1,false,frames)
check(#Net.requests==1 and #Net.requests[1].segments==0 and Net.requests[1].bodyPose~=nil,'idle limb motion uses existing reliable visual stream')
upload:Update({},.11,1,false,bent)
check(#Net.requests==1,'joint motion obeys paint upload interval')
upload:Ack(1);upload.closing=true
upload:Update({},.2,1,true,bent)
check(Net.requests[2].action=='EndPaint','continued limb swing cannot prevent intentional exit')
model:Destroy()
print('PASS: '..checks..' hanging paint pose assertions (production R15 template, validator, reconstruction and upload queue)')
