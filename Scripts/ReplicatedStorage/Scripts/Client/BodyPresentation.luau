-- 工作台展示：双轴白膜姿态、旋转中心与旁观者插值。
--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Pose=require(ReplicatedStorage.Scripts.Shared.PaintBodyPose)
local Config=require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Types=require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Rotation=require(ReplicatedStorage.Scripts.Shared.PaintRotation)
local Presentation={}
Presentation.__index=Presentation
export type Presentation=typeof(setmetatable({} :: {
	model: Model?,parts: {[string]: BasePart},
	orientation: CFrame,targetOrientation: CFrame,
	dynamic: boolean,targetBodyPose: Types.BodyPose?,
	geometry: Rotation.Geometry?, geometryFrames: Types.BodyPose?, center: Vector3?,
},Presentation))
function Presentation.new(): Presentation
	return setmetatable({model=nil,parts={},orientation=CFrame.identity,targetOrientation=CFrame.identity,dynamic=false,targetBodyPose=nil},Presentation)
end
function Presentation.Clear(self: Presentation): ()
	table.clear(self.parts)
	self.model,self.targetBodyPose=nil,nil
	self.geometry,self.geometryFrames,self.center=nil,nil,nil
	self.dynamic=false
end
-- 副本及可见性交接由白膜管理器独占；此控制器只持有当前工位姿态。
function Presentation.Attach(self: Presentation,source: Model,model: Model,rootDrive: Instance,receivedPose: Types.BodyPose?)
	self:Clear()
	self.model=model
	local torso=model:FindFirstChild("UpperTorso")
	assert(torso and torso:IsA("BasePart"),"Painting body requires UpperTorso")
	for _,instance in model:GetDescendants() do
		if instance:IsA("LuaSourceContainer") or instance:IsA("Humanoid") then instance:Destroy()
		elseif instance:IsA("Motor6D") then
			instance.Enabled=instance==rootDrive
			instance.Transform=CFrame.identity
		elseif instance:IsA("AnimationConstraint") then
			instance.Enabled=instance==rootDrive
			instance.IsKinematic=true
			instance.Transform=CFrame.identity
		elseif instance:IsA("BallSocketConstraint") then
			instance.Enabled=false
			instance.MaxFrictionTorque*=Config.TableJointFrictionScale
			if string.find(instance.Name,"Neck") then instance.UpperAngle=Config.TableNeckAngle end
		elseif instance:IsA("Constraint") then
			if not instance:IsA("NoCollisionConstraint") then instance:Destroy() end
		elseif instance:IsA("BasePart") then
			instance.Anchored=true
			instance.CanCollide,instance.CanTouch=false,false
			instance.CanQuery=instance.Name~="HumanoidRootPart" and instance:GetAttribute("Paintable")==true
			instance.LocalTransparencyModifier=0
			instance.AssemblyLinearVelocity,instance.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
			self.parts[instance.Name]=instance
		end
	end
	self.targetBodyPose=receivedPose or Pose.Capture(source)
	self.orientation=CFrame.identity
end
function Presentation.Update(self: Presentation,pose: CFrame,dt: number,immediate: boolean): ()
	local alpha=if immediate then 1 else 1-math.exp(-Config.TableObserverResponse*dt)
	self.orientation=if immediate then self.targetOrientation else self.orientation:Lerp(self.targetOrientation,alpha)
	local model,frames=self.model,self.targetBodyPose
	if not model or not frames then return end
	local geometry=self.geometry
	if not geometry or self.geometryFrames~=frames then
		local created=Rotation.Create(model,frames)
		self.geometry,self.geometryFrames=created,frames
		geometry=created
	end
	if not geometry then return end
	local rotated=Rotation.Pose(pose,geometry,self.orientation)
	self.center=rotated:PointToWorldSpace(geometry.center)
	local support=rotated*geometry.rest
	for name,frame in frames do
		local part=self.parts[name]
		if part then part.CFrame=support*frame end
	end
end
return Presentation
