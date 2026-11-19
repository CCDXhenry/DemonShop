-- 工作台展示：仰卧静止姿态、观察者插值，以及原实体可见性恢复
--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Pose=require(ReplicatedStorage.Scripts.Shared.PaintBodyPose)
local Config=require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Types=require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Presentation={}
Presentation.__index=Presentation
export type Presentation=typeof(setmetatable({} :: {
	model: Model?,parts: {[string]: BasePart},
	yaw: number,pitch: number,targetYaw: number,targetPitch: number,
	dynamic: boolean,rest: CFrame,targetBodyPose: Types.BodyPose?,
},Presentation))
function Presentation.new(): Presentation
	return setmetatable({model=nil,parts={},yaw=0,pitch=0,targetYaw=0,targetPitch=0,dynamic=false,rest=CFrame.identity,targetBodyPose=nil},Presentation)
end
function Presentation.Clear(self: Presentation): ()
	table.clear(self.parts)
	self.model,self.targetBodyPose=nil,nil
	self.dynamic=false
end
-- 副本及可见性交接由白膜管理器独占；此控制器只持有当前工位姿态。
function Presentation.Attach(self: Presentation,source: Model,model: Model,rootDrive: Instance,receivedPose: Types.BodyPose?)
	self:Clear()
	self.model=model
	local torso=model:FindFirstChild("UpperTorso")
	assert(torso and torso:IsA("BasePart"),"Painting body requires UpperTorso")
	local rest=torso:GetAttribute("RestPose")
	self.rest=if typeof(rest)=="CFrame" then rest else model:GetPivot():ToObjectSpace(torso.CFrame)
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
	self.yaw,self.pitch=0,0
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
	if not self.model then return end
	-- 工作台保持锚定的静止仰卧，不打开球窝，四肢不因重力垂落。
	self.dynamic=false
	local support=pose*CFrame.Angles(self.pitch,self.yaw,0)*self.rest
	local torso=self.parts.UpperTorso
	if torso then torso.CFrame=if immediate then support else torso.CFrame:Lerp(support,alpha) end
	for name,frame in pairs(self.targetBodyPose or {}) do
		local part=self.parts[name]
		if part and name~="UpperTorso" then
			local goal=support*frame
			part.CFrame=if immediate then goal else part.CFrame:Lerp(goal,alpha)
		end
	end
end
return Presentation
