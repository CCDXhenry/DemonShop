-- 白膜受击表现：本地关节叠加、有限命中特效池及可撤销的相机冲击
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Rules = require(ReplicatedStorage.Scripts.Shared.HitFeedbackRules)
local GameData = require(ReplicatedStorage.Scripts.Shared.GameData)
local ModelTemplates = require(ReplicatedStorage.Scripts.Shared.ModelTemplates)
local TweenService = game:GetService("TweenService")
local Presentation = {}
Presentation.__index = Presentation
type Pose = { model: Model, joints: {Motor6D}, started: number, direction: Vector3, hits: number }
type JointOffset = { base: CFrame, applied: CFrame, offset: CFrame }
type JointCache = {model: Model, joints: {Motor6D}}
type Effect = { id: string, model: Folder, parts: {BasePart}, started: number, frame: CFrame, final: boolean, flashSeconds: number, active: boolean }
type AuthoredPart = { part: BasePart, relative: CFrame, size: Vector3, transparency: number }
type WeaponSlot = {
	model: Model,
	parts: { AuthoredPart },
	active: boolean,
	token: number,
	driver: NumberValue?,
	connection: RBXScriptConnection?,
	tween: Tween?,
}
export type Presentation = typeof(setmetatable({} :: {
	poses: {[string]: Pose}, cache: {[string]: JointCache}, offsets: {[Motor6D]: JointOffset}, pool: {Effect},
	weaponPools: { [string]: { WeaponSlot } },
	managed: ((string, Model) -> boolean)?,
	camera: Camera?, cameraOffset: CFrame, cameraApplied: CFrame?, shakeStarted: number?, shakeFinal: boolean,
}, Presentation))
local WeaponPoolSize = 3
local SweepStart = 0.45
local SweepSeconds = 0.32
local function CreatePart(parent: Folder, name: string, color: Color3): Part
	local part = Instance.new("Part")
	part.Name, part.Color, part.Material = name, color, Enum.Material.Neon
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.CastShadow, part.Transparency = false, 1
	part.Size = Vector3.one * Config.HitEffectThickness
	part.Parent = parent
	return part
end
function Presentation.new(): Presentation
	return setmetatable({poses={},cache={},offsets={},pool={},weaponPools={},camera=nil,cameraOffset=CFrame.identity,cameraApplied=nil,shakeStarted=nil,shakeFinal=false}, Presentation)
end
function Presentation.Restore(self: Presentation): ()
	for joint, offset in self.offsets do
		if joint.Parent then joint.Transform = if joint.Transform==offset.applied then offset.base else joint.Transform end
	end
	table.clear(self.offsets)
end
function Presentation.Remove(self: Presentation, id: string, retainCache: boolean?): ()
	local pose = self.poses[id]
	if pose then
		for _, joint in pose.joints do
			local offset = self.offsets[joint]
			if offset and joint.Parent then joint.Transform = if joint.Transform==offset.applied then offset.base else joint.Transform end
			self.offsets[joint] = nil
		end
	end
	self.poses[id] = nil
	if not retainCache then self.cache[id]=nil end
end
function Presentation.Play(self: Presentation, id: string, model: Model, hits: number, direction: Vector3, started: number): ()
	local pose: Pose? = self.poses[id]
	if pose and pose.model ~= model then self:Remove(id); pose=nil end
	if not pose then
		local cached=self.cache[id]
		if not cached or cached.model~=model then
			local joints: {Motor6D} = {}
			for _, joint in model:GetDescendants() do
				if joint:IsA("Motor6D") and (joint.Name=="Waist" or joint.Name=="Neck" or string.find(joint.Name,"Shoulder")) then
					table.insert(joints,joint)
				end
			end
			local created: JointCache={model=model,joints=joints}
			self.cache[id]=created
			cached=created
		end
		if not cached then return end
		local joints=cached.joints
		pose={model=model,joints=joints,started=started,direction=direction,hits=hits}
		self.poses[id]=pose
	end
	if pose then pose.started,pose.direction,pose.hits=started,direction,hits end
end
-- 兼容包络只计算偏移；接管的展示关节由管理器一次提交。
function Presentation.Sample(self: Presentation, id: string, name: string, now: number): CFrame?
	local pose = self.poses[id]
	if not pose or (name ~= "Waist" and name ~= "Neck" and not string.find(name,"Shoulder")) then return nil end
	local root = pose.model.PrimaryPart
	if not root then return nil end
	local age = now-pose.started
	local duration = if pose.hits==1 then Config.HitPoseSeconds else Config.HitSecondPoseSeconds
	if age < 0 or age >= duration then return nil end
	local direction=root.CFrame:VectorToObjectSpace(pose.direction)
	local angle=if pose.hits==1 then Config.HitPoseAngle else Config.HitSecondPoseAngle
	local side=if pose.hits%2==1 then 1 else -1
	local limb=name~="Waist"
	local amount=Rules.Envelope(age-(if limb then Config.HitLimbDelay else 0),duration,Config.HitPosePeakSeconds)
	local scale=if name=="Neck" then -Config.HitHeadScale elseif limb then -Config.HitArmScale else 1
	return CFrame.Angles(direction.Z*angle*amount*scale,Config.HitTwistAngle*side*amount*scale,-direction.X*angle*amount*scale)
end
function Presentation.Apply(self: Presentation, now: number): ()
	for id, pose in self.poses do
		local root=pose.model.PrimaryPart
		local duration=if pose.hits==1 then Config.HitPoseSeconds else Config.HitSecondPoseSeconds
		local age=now-pose.started
		if not root or not pose.model.Parent or age>=duration or pose.model:GetAttribute("MotionState")=="Down" then
			self:Remove(id,pose.model.Parent~=nil and age>=duration); continue
		end
		if self.managed and self.managed(id, pose.model) then continue end
		for _, joint in pose.joints do
			if not joint.Parent or not joint.Enabled then continue end
			local offset = self:Sample(id, joint.Name, now)
			if not offset then continue end
			local base=joint.Transform
			local applied=offset*base
			joint.Transform=applied
			self.offsets[joint]={base=base,applied=joint.Transform,offset=offset}
		end
	end
end
function Presentation.Burst(self: Presentation, id: string, position: Vector3, direction: Vector3, final: boolean, started: number): ()
	local camera=workspace.CurrentCamera
	if not camera or (camera.CFrame.Position-position).Magnitude>Config.HitEffectDistance then return end
	local effect: Effect? = nil
	for _, candidate in self.pool do if not candidate.active then effect=candidate; break end end
	if not effect and #self.pool<Config.HitEffectPoolSize then
		local model=Instance.new("Folder")
		model.Name="LocalHitBurst"
		local flash=CreatePart(model,"Flash",Config.HitFlashColor)
		flash.Shape=Enum.PartType.Ball
		local parts: {BasePart}={flash}
		for index=1,Config.HitEffectRayCount+Config.HitEffectRingSegments do
			table.insert(parts,CreatePart(model,"Ray"..index,Config.HitRayColor))
		end
		model.Parent=workspace
		local created: Effect={id=id,model=model,parts=parts,started=started,frame=CFrame.identity,final=final,flashSeconds=Config.HitEffectSeconds,active=false}
		table.insert(self.pool,created)
		effect=created
	end
	if not effect then
		local oldest: Effect?=nil
		for _, candidate in self.pool do if not oldest or candidate.started<oldest.started then oldest=candidate end end
		effect=oldest
	end
	if not effect then return end
	local normal=if direction.Magnitude>0.01 then direction.Unit else Vector3.zAxis
	local up=if math.abs(normal:Dot(Vector3.yAxis))>0.95 then Vector3.xAxis else Vector3.yAxis
	effect.flashSeconds=if final then Config.HitFinalEffectSeconds else Config.HitEffectSeconds
	effect.id=id
	effect.started,effect.frame,effect.final,effect.active=started,CFrame.lookAt(position,position+normal,up),final,true
end
function Presentation.UpgradeBurst(self: Presentation, id: string): ()
	for _, effect in self.pool do
		if effect.active and effect.id==id then effect.final=true end
	end
end
function Presentation.UpdateEffects(self: Presentation, now: number): ()
	for _, effect in self.pool do
		if not effect.active then continue end
		local duration=if effect.final then Config.HitFinalEffectSeconds else Config.HitEffectSeconds
		local t=math.clamp((now-effect.started)/duration,0,1)
		local radius=Config.HitEffectRadius*(if effect.final then Config.HitFinalEffectScale else 1)
		local thickness=Config.HitEffectThickness
		for index, part in effect.parts do
			part.Transparency=t
			if index==1 then
				local flashT=math.clamp((now-effect.started)/effect.flashSeconds,0,1)
				part.Transparency=flashT
				part.Size=Vector3.one*math.max(thickness,radius*(1-flashT)^2)
				part.CFrame=effect.frame
			elseif index<=Config.HitEffectRayCount+1 then
				local angle=(index-2)/Config.HitEffectRayCount*math.pi*2
				part.Size=Vector3.new(thickness,math.max(thickness,radius*(1-t)*Config.HitRayLengthScale),thickness)
				part.CFrame=effect.frame*CFrame.Angles(0,0,angle)*CFrame.new(0,radius*(Config.HitRayStartRadius+t),0)
			else
				local angle=(index-Config.HitEffectRayCount-2)/Config.HitEffectRingSegments*math.pi*2
				local ringRadius=radius*(Config.HitRingStartRadius+t)
				part.Size=Vector3.new(math.max(thickness,ringRadius*2*math.sin(math.pi/Config.HitEffectRingSegments)),thickness,thickness)
				part.CFrame=effect.frame*CFrame.Angles(0,0,angle)*CFrame.new(0,ringRadius,0)
			end
		end
		if t>=1 then effect.active=false end
	end
end
function Presentation.RestoreCamera(self: Presentation): ()
	local camera=self.camera
	-- Only undo our own last pose; a different camera owner may already have replaced it.
	if camera and self.cameraApplied and camera.CFrame==self.cameraApplied then camera.CFrame=camera.CFrame*self.cameraOffset:Inverse() end
	self.camera,self.cameraApplied,self.cameraOffset=nil,nil,CFrame.identity
end
function Presentation.Shake(self: Presentation, now: number, final: boolean, upgrade: boolean): ()
	if upgrade and self.shakeStarted then
		self.shakeFinal=final
		return
	end
	self.shakeStarted,self.shakeFinal=now,final
end
function Presentation.UpdateCamera(self: Presentation, now: number, enabled: boolean): ()
	if not enabled then self:ResetCamera(); return end
	local started=self.shakeStarted
	local camera=workspace.CurrentCamera
	if not started or not camera then return end
	local duration=if self.shakeFinal then Config.HitFinalCameraSeconds else Config.HitCameraSeconds
	local age=now-started
	if age<0 or age>=duration then self.shakeStarted=nil; return end
	local pulse=math.cos(age*Config.HitCameraFrequency)*(1-age/duration)^2
	local angle=(if self.shakeFinal then Config.HitFinalCameraAngle else Config.HitCameraAngle)*pulse
	local offset=(if self.shakeFinal then Config.HitFinalCameraOffset else Config.HitCameraOffset)*pulse
	self.cameraOffset=CFrame.new(offset,offset*Config.HitCameraVerticalScale,0)*CFrame.Angles(-angle,0,angle*Config.HitCameraRollScale)
	self.camera=camera
	camera.CFrame=camera.CFrame*self.cameraOffset
	self.cameraApplied=camera.CFrame
end
function Presentation.ResetCamera(self: Presentation): ()
	self:RestoreCamera()
	self.shakeStarted=nil
end
local function StopWeaponSlot(slot: WeaponSlot): ()
	if slot.connection then
		slot.connection:Disconnect()
		slot.connection = nil
	end
	if slot.tween then
		slot.tween:Cancel()
		slot.tween = nil
	end
	if slot.driver then
		slot.driver:Destroy()
		slot.driver = nil
	end
end
local function ApplyWeaponSlot(slot: WeaponSlot, scaleX: number, scaleY: number, scaleZ: number, amount: number): ()
	local pivot = slot.model:GetPivot()
	local fade = math.clamp((amount - SweepStart) / (1 - SweepStart), 0, 1)
	for _, item in slot.parts do
		local pos = Vector3.new(item.relative.Position.X * scaleX, item.relative.Position.Y * scaleY, item.relative.Position.Z * scaleZ) * amount
		local size = Vector3.new(item.size.X * scaleX * amount, item.size.Y * scaleY * amount, item.size.Z * scaleZ * amount)
		item.part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
		item.part.CFrame = pivot:ToWorldSpace(CFrame.new(pos) * item.relative.Rotation)
		item.part.Transparency = item.transparency + (1 - item.transparency) * fade
	end
end
local function ResetWeaponSlot(slot: WeaponSlot): ()
	StopWeaponSlot(slot)
	local pivot = slot.model:GetPivot()
	for _, item in slot.parts do
		item.part.Size = item.size
		item.part.Transparency = item.transparency
		item.part.CFrame = pivot:ToWorldSpace(item.relative)
	end
	slot.model.Parent = nil
	slot.active = false
end
local function CreateWeaponSlot(template: Model): WeaponSlot
	local clone = template:Clone()
	local pivot = clone:GetPivot()
	local parts: { AuthoredPart } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			table.insert(parts, {
				part = descendant,
				relative = pivot:ToObjectSpace(descendant.CFrame),
				size = descendant.Size,
				transparency = descendant.Transparency,
			})
		end
	end
	return { model = clone, parts = parts, active = false, token = 0, driver = nil, connection = nil, tween = nil }
end
local function EnsureWeaponPool(self: Presentation, modelName: string): { WeaponSlot }?
	local template = ModelTemplates.FindEffect(modelName)
	if not template then
		return nil
	end
	local pool = self.weaponPools[modelName]
	if not pool then
		pool = {}
		self.weaponPools[modelName] = pool
	end
	while #pool < WeaponPoolSize do
		table.insert(pool, CreateWeaponSlot(template))
	end
	return pool
end
function Presentation.PrepareWeaponEffects(self: Presentation): ()
	for _, weapon in GameData.GetAllWeapons() do
		EnsureWeaponPool(self, weapon.model)
	end
end
function Presentation.WeaponEffect(self: Presentation, modelName: string, pose: CFrame, range: number, width: number?): ()
	local template = ModelTemplates.FindEffect(modelName)
	if not template then
		return
	end
	local designRange = template:GetAttribute("DesignRange")
	if typeof(designRange) ~= "number" or designRange <= 0 or range <= 0 then
		return
	end
	local pool = EnsureWeaponPool(self, modelName)
	if not pool then
		return
	end
	local scale = range / designRange
	local scaleX, scaleY, scaleZ = scale, scale, scale
	local designWidth = template:GetAttribute("DesignWidth")
	if typeof(designWidth) == "number" and designWidth > 0 then
		local lane = if width and width > 0 then width else designWidth
		scaleX = scale * (lane / designWidth)
	end
	local slot: WeaponSlot? = nil
	for _, candidate in pool do
		if not candidate.active then
			slot = candidate
			break
		end
	end
	local playing = slot or pool[1]
	if not playing then
		return
	end
	if playing.active then
		ResetWeaponSlot(playing)
	end
	StopWeaponSlot(playing)
	playing.active = true
	playing.token += 1
	local token = playing.token
	playing.model:PivotTo(pose * CFrame.new(0, -1.5, 0))
	playing.model.Parent = workspace
	ApplyWeaponSlot(playing, scaleX, scaleY, scaleZ, SweepStart)
	local driver = Instance.new("NumberValue")
	driver.Name = "Sweep"
	driver.Value = SweepStart
	driver.Parent = playing.model
	playing.driver = driver
	playing.connection = driver.Changed:Connect(function(value: number)
		if playing.token ~= token then
			return
		end
		ApplyWeaponSlot(playing, scaleX, scaleY, scaleZ, value)
	end)
	local tween = TweenService:Create(driver, TweenInfo.new(SweepSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	playing.tween = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if playing.token ~= token or state ~= Enum.PlaybackState.Completed then
			return
		end
		ResetWeaponSlot(playing)
	end)
	tween:Play()
end
function Presentation.Clear(self: Presentation): ()
	self:Restore()
	table.clear(self.poses)
	table.clear(self.cache)
	self:ResetCamera()
	for _, effect in self.pool do effect.model:Destroy() end
	table.clear(self.pool)
	for _, slots in self.weaponPools do
		for _, slot in slots do
			StopWeaponSlot(slot)
			slot.model:Destroy()
		end
	end
	table.clear(self.weaponPools)
end
return Presentation
