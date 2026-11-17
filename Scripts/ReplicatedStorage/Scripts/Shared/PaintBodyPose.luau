-- 绘画悬挂姿态契约：躯干局部坐标、关节限位校验与服务端可见表面重建
--!strict
local Types=require(script.Parent.GameTypes)
local Config=require(script.Parent.PhysicsConfig)
local Pose={}
local MaximumParts=15
local MaximumExtent=12
function Pose.IsFiniteFrame(value: unknown): boolean
	if typeof(value)~="CFrame" then return false end
	local frame=value :: CFrame
	for _,n in {frame:GetComponents()} do if n~=n or math.abs(n)==math.huge then return false end end
	if frame.Position.Magnitude>MaximumExtent then return false end
	local x,y,z=frame.XVector,frame.YVector,frame.ZVector
	return math.abs(x.Magnitude-1)<.001 and math.abs(y.Magnitude-1)<.001 and math.abs(z.Magnitude-1)<.001 and math.abs(x:Dot(y))<.001 and (x:Cross(y)-z).Magnitude<.001
end
function Pose.ValidateWire(value: unknown): boolean
	if typeof(value)~="table" then return false end
	local count=0
	for name,frame in value :: {[unknown]: unknown} do
		count+=1
		if count>MaximumParts or typeof(name)~="string" or #name>32 or not Pose.IsFiniteFrame(frame) then return false end
	end
	return count>0
end
function Pose.Capture(model: Model): Types.BodyPose
	local torso=model:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then return {} end
	local result: Types.BodyPose={}
	for _,part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Paintable")==true then result[part.Name]=torso.CFrame:ToObjectSpace(part.CFrame) end
	end
	return result
end
function Pose.Validate(model: Model,frames: Types.BodyPose): boolean
	if not Pose.ValidateWire(frames) then return false end
	local count=0
	for _,part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Paintable")==true then
			count+=1
			if not frames[part.Name] then return false end
		end
	end
	local received=0
	for _ in frames do received+=1 end
	if count~=received then return false end
	local torso=frames.UpperTorso
	if not torso or torso.Position.Magnitude>.001 or (torso.XVector-Vector3.xAxis).Magnitude>.001 or (torso.YVector-Vector3.yAxis).Magnitude>.001 then return false end
	local joints=0
	for _,joint in model:GetDescendants() do
		if not joint:IsA("BallSocketConstraint") then continue end
		local a,b=joint.Attachment0,joint.Attachment1
		local p0,p1=if a then a.Parent else nil,if b then b.Parent else nil
		if not a or not b or not p0 or not p1 or not p0:IsA("BasePart") or not p1:IsA("BasePart") then continue end
		local f0,f1=frames[p0.Name],frames[p1.Name]
		if not f0 or not f1 then continue end
		joints+=1
		local world0,world1=f0*a.CFrame,f1*b.CFrame
		if (world0.Position-world1.Position).Magnitude>Config.TableJointPositionTolerance then return false end
		local limit=if string.find(joint.Name,"Neck") then Config.TableNeckAngle else joint.UpperAngle
		local angle=math.acos(math.clamp(world0.XVector:Dot(world1.XVector),-1,1))
		if angle>math.rad(limit)+Config.TableJointAngleTolerance then return false end
	end
	return joints>=14
end
function Pose.Apply(model: Model,base: CFrame,frames: Types.BodyPose?): ()
	if not frames then model:PivotTo(base);return end
	local torso=model:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then return end
	local rest=torso:GetAttribute("RestPose")
	local support=base*(if typeof(rest)=="CFrame" then rest else CFrame.identity)
	for _,part in model:GetChildren() do
		local frame=frames[part.Name]
		if frame and part:IsA("BasePart") then part.CFrame=support*frame end
	end
	for _,joint in model:GetDescendants() do
		if joint:IsA("Motor6D") and (joint.Name=="Root" or joint.Name=="RootJoint") and joint.Part0 and joint.Part1 then joint.Part0.CFrame=joint.Part1.CFrame*joint.C1*joint.C0:Inverse() end
	end
end
function Pose.Changed(a: Types.BodyPose?,b: Types.BodyPose?): boolean
	if not a or not b then return a~=b end
	for name,frame in b do
		local old=a[name]
		if not old or (old.Position-frame.Position).Magnitude>.005 or (old.XVector-frame.XVector).Magnitude>.01 or (old.YVector-frame.YVector).Magnitude>.01 then return true end
	end
	return false
end
return Pose
