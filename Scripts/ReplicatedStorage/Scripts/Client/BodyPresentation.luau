-- 工作台展示：躯干固定的本地物理悬挂、观察者姿态平滑和原实体可见性恢复
--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Pose=require(ReplicatedStorage.Scripts.Shared.PaintBodyPose)
local Config=require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Types=require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Presentation={}
Presentation.__index=Presentation
export type Presentation=typeof(setmetatable({} :: {
	source: Model?,model: Model?,hidden: {[BasePart]: number},parts: {[string]: BasePart},
	yaw: number,pitch: number,targetYaw: number,targetPitch: number,
	dynamic: boolean,rest: CFrame,targetBodyPose: Types.BodyPose?,
},Presentation))
function Presentation.new(): Presentation
	return setmetatable({source=nil,model=nil,hidden={},parts={},yaw=0,pitch=0,targetYaw=0,targetPitch=0,dynamic=false,rest=CFrame.identity,targetBodyPose=nil},Presentation)
end
function Presentation.Clear(self: Presentation): ()
	if self.model then self.model:Destroy() end
	for part,transparency in self.hidden do if part.Parent then part.LocalTransparencyModifier=transparency end end
	table.clear(self.hidden);table.clear(self.parts)
	self.model,self.source,self.targetBodyPose=nil,nil,nil
	self.dynamic=false
end
function Presentation.Bind(self: Presentation,source: Model,receivedPose: Types.BodyPose?): Model
	if self.source==source and self.model then return self.model end
	self:Clear()
	local model=source:Clone()
	model.Name="LocalRuneBody"
	local torso=model:FindFirstChild("UpperTorso")
	assert(torso and torso:IsA("BasePart"),"Painting body requires UpperTorso")
	local rest=torso:GetAttribute("RestPose")
	self.rest=if typeof(rest)=="CFrame" then rest else model:GetPivot():ToObjectSpace(torso.CFrame)
	for _,instance in model:GetDescendants() do
		if instance:IsA("LuaSourceContainer") or instance:IsA("Humanoid") then instance:Destroy()
		elseif instance:IsA("Motor6D") then
			instance.Enabled=instance.Name=="Root" or instance.Name=="RootJoint"
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
	for _,instance in source:GetDescendants() do
		if instance:IsA("BasePart") then self.hidden[instance]=instance.LocalTransparencyModifier;instance.LocalTransparencyModifier=1 end
	end
	self.targetBodyPose=receivedPose or Pose.Capture(source)
	model.Parent=workspace
	self.source,self.model=source,model
	self.yaw,self.pitch=0,0
	return model
end
function Presentation.CapturePose(self: Presentation): Types.BodyPose?
	if not self.dynamic or not self.model then return nil end
	return Pose.Capture(self.model)
end
function Presentation.Update(self: Presentation,pose: CFrame,dt: number,immediate: boolean): ()
	local alpha=if immediate then 1 else 1-math.exp(-Config.TableObserverResponse*dt)
	local yawDelta=(self.targetYaw-self.yaw+math.pi)%(2*math.pi)-math.pi
	self.yaw+=yawDelta*alpha
	self.pitch+=(self.targetPitch-self.pitch)*alpha
	local model=self.model
	if not model then return end
	if self.dynamic~=immediate then
		self.dynamic=immediate
		for name,part in self.parts do part.Anchored=not immediate or name=="UpperTorso" end
		for _,joint in model:GetDescendants() do if joint:IsA("BallSocketConstraint") then joint.Enabled=immediate end end
	end
	local support=pose*CFrame.Angles(self.pitch,self.yaw,0)*self.rest
	local torso=self.parts.UpperTorso
	if torso then torso.CFrame=support end
	if immediate then
		for _,part in self.parts do
			if part.Anchored then continue end
			local velocity,angular=part.AssemblyLinearVelocity,part.AssemblyAngularVelocity
			if velocity.Magnitude>Config.MaximumLinearSpeed then part.AssemblyLinearVelocity=velocity.Unit*Config.MaximumLinearSpeed end
			if angular.Magnitude>Config.MaximumAngularSpeed then part.AssemblyAngularVelocity=angular.Unit*Config.MaximumAngularSpeed end
		end
	else
		for name,frame in pairs(self.targetBodyPose or {}) do
			local part=self.parts[name]
			if part and name~="UpperTorso" then part.CFrame=part.CFrame:Lerp(support*frame,alpha) end
		end
	end
end
return Presentation
