-- 工作台展示：双轴白膜零重力甩动物理、停转回正与旁观者插值。
--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local GameConfig=require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Pose=require(ReplicatedStorage.Scripts.Shared.PaintBodyPose)
local Config=require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Types=require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Rotation=require(ReplicatedStorage.Scripts.Shared.PaintRotation)
local Presentation={}
Presentation.__index=Presentation
export type Presentation=typeof(setmetatable({} :: {
	model: Model?,parts: {[string]: BasePart},
	sockets: {BallSocketConstraint},baseFriction: {[BallSocketConstraint]: number},
	antiGravity: {[BasePart]: VectorForce},aligners: {[BasePart]: AlignOrientation},
	orientation: CFrame,targetOrientation: CFrame,
	dynamic: boolean,spinning: boolean,
	targetBodyPose: Types.BodyPose?,restBodyPose: Types.BodyPose?,
	geometry: Rotation.Geometry?, center: Vector3?,
},Presentation))
function Presentation.new(): Presentation
	return setmetatable({
		model=nil,parts={},sockets={},baseFriction={},antiGravity={},aligners={},
		orientation=CFrame.identity,targetOrientation=CFrame.identity,
		dynamic=false,spinning=false,targetBodyPose=nil,restBodyPose=nil,
	},Presentation)
end
function Presentation.Clear(self: Presentation): ()
	for _,socket in self.sockets do
		if socket.Parent then socket.Enabled=false end
	end
	for _,align in self.aligners do
		if align.Parent then align.Enabled=false; align:Destroy() end
	end
	for _,force in self.antiGravity do
		if force.Parent then force.Enabled=false end
		local attachment=force.Attachment0
		if attachment and attachment.Parent then attachment:Destroy() end
		if force.Parent then force:Destroy() end
	end
	table.clear(self.sockets)
	table.clear(self.baseFriction)
	table.clear(self.aligners)
	table.clear(self.antiGravity)
	table.clear(self.parts)
	self.model,self.targetBodyPose,self.restBodyPose=nil,nil,nil
	self.geometry,self.center=nil,nil
	self.dynamic,self.spinning=false,false
end
local function ApplySocketFriction(self: Presentation,scale: number): ()
	for _,socket in self.sockets do
		local base=self.baseFriction[socket]
		if base then socket.MaxFrictionTorque=base*scale end
	end
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
			self.baseFriction[instance]=instance.MaxFrictionTorque
			instance.MaxFrictionTorque*=Config.TableRecoverFrictionScale
			if string.find(instance.Name,"Neck") then instance.UpperAngle=Config.TableNeckAngle end
			table.insert(self.sockets,instance)
		elseif instance:IsA("Constraint") then
			if not instance:IsA("NoCollisionConstraint") then instance:Destroy() end
		elseif instance:IsA("Attachment") and instance.Name=="TableZeroGravityAttachment" then
			instance:Destroy()
		elseif instance:IsA("BasePart") then
			instance.Anchored=true
			instance.CanCollide,instance.CanTouch=false,false
			instance.CanQuery=instance.Name~="HumanoidRootPart" and instance:GetAttribute("Paintable")==true
			instance.Massless=instance.Name=="HumanoidRootPart"
			instance.LocalTransparencyModifier=0
			instance.AssemblyLinearVelocity,instance.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
			self.parts[instance.Name]=instance
			if instance.Name~="UpperTorso" and instance.Name~="HumanoidRootPart" then
				local attachment=Instance.new("Attachment")
				attachment.Name="TableZeroGravityAttachment"
				attachment.Parent=instance
				local force=Instance.new("VectorForce")
				force.Name="TableZeroGravityForce"
				force.Attachment0=attachment
				force.RelativeTo=Enum.ActuatorRelativeTo.World
				force.ApplyAtCenterOfMass=true
				force.Force=Vector3.zero
				force.Enabled=false
				force.Parent=instance
				self.antiGravity[instance]=force
				local align=Instance.new("AlignOrientation")
				align.Name="TablePoseAlign"
				align.Mode=Enum.OrientationAlignmentMode.OneAttachment
				align.Attachment0=attachment
				align.RigidityEnabled=false
				align.MaxAngularVelocity=Config.TableRecoverMaxAngularVelocity
				align.Responsiveness=Config.TableRecoverResponsiveness
				align.MaxTorque=0
				align.CFrame=CFrame.identity
				align.Enabled=false
				align.Parent=instance
				self.aligners[instance]=align
			end
		end
	end
	local initialPose=receivedPose or Pose.Capture(source)
	self.targetBodyPose=initialPose
	self.restBodyPose=table.clone(initialPose)
	self.orientation=CFrame.identity
end
function Presentation.CapturePose(self: Presentation): Types.BodyPose?
	if not self.dynamic or not self.model then return nil end
	return Pose.Capture(self.model)
end
function Presentation.Update(self: Presentation,pose: CFrame,dt: number,immediate: boolean): ()
	if not GameConfig.PaintRotationEnabled then
		self.targetOrientation=CFrame.identity
		self.orientation=CFrame.identity
	end
	local prevOrientation=self.orientation
	local alpha=if immediate then 1 else 1-math.exp(-Config.TableObserverResponse*dt)
	self.orientation=if immediate then self.targetOrientation else self.orientation:Lerp(self.targetOrientation,alpha)
	local model,frames=self.model,self.targetBodyPose
	if not model or not frames then return end
	local hadGeometry=self.geometry~=nil
	local geometry=self.geometry
	if not geometry then
		local created=Rotation.Create(model,frames)
		self.geometry=created
		geometry=created
	end
	if not geometry then return end
	local rotated=Rotation.Pose(pose,geometry,self.orientation)
	local pivotWorld=rotated:PointToWorldSpace(geometry.center)
	self.center=pivotWorld
	local support=rotated*geometry.rest

	local wantDynamic=immediate and GameConfig.PaintPhysicsEnabled==true
	local delta=self.orientation*prevOrientation:Inverse()
	local localAxis,deltaAngle=delta:ToAxisAngle()
	local absAngle=math.abs(deltaAngle)
	local isJump=absAngle>Config.TableSpinResetAngle
	local angularSpeed=if dt>1e-4 and not isJump then math.min(absAngle/dt,Config.MaximumAngularSpeed*2) else 0
	local isSpinning=wantDynamic and GameConfig.PaintRotationEnabled==true and angularSpeed>Config.TableSpinThreshold and localAxis.Magnitude>1e-4

	if self.dynamic~=wantDynamic then
		if wantDynamic then
			for name,frame in frames do
				local part=self.parts[name]
				if part then
					part.CFrame=support*frame
					part.AssemblyLinearVelocity,part.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
				end
			end
			local rootPart=self.parts.HumanoidRootPart
			if rootPart then rootPart.AssemblyLinearVelocity,rootPart.AssemblyAngularVelocity=Vector3.zero,Vector3.zero end
			self.dynamic=true
			self.spinning=isSpinning
			ApplySocketFriction(self,if isSpinning then Config.TableSpinFrictionScale else Config.TableRecoverFrictionScale)
			for _,socket in self.sockets do socket.Enabled=true end
			for name,part in self.parts do part.Anchored=name=="UpperTorso" end
			local gravity=workspace.Gravity
			for part,force in self.antiGravity do
				force.Force=Vector3.new(0,part.AssemblyMass*gravity,0)
				force.Enabled=true
			end
		else
			local captured=Pose.Capture(model)
			if next(captured)~=nil then
				self.targetBodyPose=captured
				frames=captured
			end
			self.dynamic=false
			self.spinning=false
			for _,align in self.aligners do
				align.Enabled=false
				align.MaxTorque=0
			end
			for _,force in self.antiGravity do
				force.Enabled=false
				force.Force=Vector3.zero
			end
			for _,socket in self.sockets do socket.Enabled=false end
			for _,part in self.parts do
				part.Anchored=true
				part.AssemblyLinearVelocity,part.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
			end
		end
	end
	local torso=self.parts.UpperTorso
	if torso then torso.CFrame=support end
	if wantDynamic then
		if self.spinning~=isSpinning then
			self.spinning=isSpinning
			ApplySocketFriction(self,if isSpinning then Config.TableSpinFrictionScale else Config.TableRecoverFrictionScale)
		end
		local worldAxis: Vector3?=nil
		if isSpinning then
			local axis=pose:VectorToWorldSpace(localAxis)
			if axis.Magnitude>1e-4 then worldAxis=axis.Unit end
		end
		local gravity=workspace.Gravity
		for part,force in self.antiGravity do
			local mass=part.AssemblyMass
			local totalForce=Vector3.new(0,mass*gravity,0)
			if isSpinning and worldAxis then
				local rel=part.CFrame.Position-pivotWorld
				local radial=rel-worldAxis*rel:Dot(worldAxis)
				local radialMag=radial.Magnitude
				if radialMag>1e-4 then
					local accel=math.min(angularSpeed*angularSpeed*radialMag*Config.TableCentrifugalBoost,Config.TableMaxCentrifugalAccel)
					totalForce+=radial/radialMag*(mass*accel)
				end
			end
			force.Force=totalForce
		end
		local restFrames=self.restBodyPose or frames
		local torquePerMass=if isSpinning then Config.TableSpinAlignTorquePerMass else Config.TableRecoverTorquePerMass
		local responsiveness=if isSpinning then Config.TableSpinAlignResponsiveness else Config.TableRecoverResponsiveness
		for part,align in self.aligners do
			local restFrame=restFrames[part.Name]
			if restFrame then
				align.CFrame=(support*restFrame).Rotation
				align.MaxTorque=math.max(part.AssemblyMass,0.05)*torquePerMass
				align.Responsiveness=responsiveness
				align.Enabled=true
			end
		end
		for _,part in self.parts do
			if part.Anchored then continue end
			local velocity,angular=part.AssemblyLinearVelocity,part.AssemblyAngularVelocity
			if velocity.Magnitude>Config.MaximumLinearSpeed then part.AssemblyLinearVelocity=velocity.Unit*Config.MaximumLinearSpeed end
			if angular.Magnitude>Config.MaximumAngularSpeed then part.AssemblyAngularVelocity=angular.Unit*Config.MaximumAngularSpeed end
		end
	else
		for name,frame in frames do
			local part=self.parts[name]
			if part and name~="UpperTorso" then
				local target=support*frame
				part.CFrame=if not hadGeometry or immediate then target else part.CFrame:Lerp(target,alpha)
			end
		end
	end
end
return Presentation
