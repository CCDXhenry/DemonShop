-- 搬运模块：无碰撞柔性肩扛、有限惯性释放及资源回收
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Ragdoll = require(script.Parent.Ragdoll)
local NPC = require(script.Parent.NPC)
local Scene = require(script.Parent.Scene)
local Config = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Carry = {}
local function SetOwner(model: Model, owner: Player?): ()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then pcall(function(): () part:SetNetworkOwner(owner) end) end
	end
end
local function ClearRelease(item: Types.Item): ()
	local contacts = item.model:FindFirstChild("ReleaseContacts")
	if contacts then contacts:Destroy() end
	item.releaseUntil, item.releaseCharacter = nil, nil
end
function Carry.Detach(item: Types.Item): ()
	if item.carryTween then item.carryTween:Cancel(); item.carryTween:Destroy(); item.carryTween = nil end
	if item.carryWeld then item.carryWeld:Destroy(); item.carryWeld = nil end
	if item.carryResources then
		local reference=item.carryResources:FindFirstChild("Anchor")
		if reference and reference:IsA("ObjectValue") and reference.Value then reference.Value:Destroy() end
		item.carryResources:Destroy(); item.carryResources = nil
	end
	if item.carryTarget then item.carryTarget:Destroy(); item.carryTarget = nil end
	item.carryErrorSince=nil
	item.carryBaseOffset,item.carryVelocity,item.carryUpdated,item.carrySway=nil,nil,nil,nil
	local contacts = item.model:FindFirstChild("CarryContacts")
	if contacts then contacts:Destroy() end
	ClearRelease(item)
	SetOwner(item.model, nil)
	local owner = item.holder
	item.holder = nil
	local humanoid = owner and owner.Character and owner.Character:FindFirstChildOfClass("Humanoid")
	local backpack = owner and owner:FindFirstChild("Backpack")
	local club = backpack and backpack:FindFirstChild("Club")
	if humanoid and humanoid.Health > 0 and club and club:IsA("Tool") then humanoid:EquipTool(club) end
end
function Carry.Static(item: Types.Item, pose: CFrame): ()
	Carry.Detach(item)
	NPC.StopMotion(item)
	item.model:SetAttribute("MotionState", "Static")
	if item.kind == "Body" then Ragdoll.SetMode(item.model, "Static") else
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored,part.CanCollide=true,false end
		end
	end
	item.model:PivotTo(pose)
end
function Carry.Take(item: Types.Item, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local primary = item.model.PrimaryPart
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or not primary then return false end
	Carry.Detach(item)
	NPC.StopMotion(item)
	if item.kind == "Body" then
		local torso = item.model:FindFirstChild("UpperTorso")
		if not torso or not torso:IsA("BasePart") then return false end
		Ragdoll.SetMode(item.model,"Static")
		local shoulder = character:FindFirstChild("UpperTorso")
		local support = if shoulder and shoulder:IsA("BasePart") then shoulder else root
		local scale = support.Size / Vector3.new(2,1.6,1)
		local offset = CFrame.new(Config.ShoulderOffset * scale) * Config.ShoulderRotation
		local relative = item.model:GetPivot():ToObjectSpace(torso.CFrame)
		item.model:PivotTo(support.CFrame * offset * relative:Inverse())
		Ragdoll.SetMode(item.model,"Carried")
		local resources = Instance.new("Folder")
		resources.Name,resources.Parent="CarryResources",item.model
		item.carryResources=resources
		local target = Instance.new("Attachment")
		target.Name,target.CFrame,target.Parent="WhiteBodyShoulder",offset,support
		item.carryTarget=target
		item.carryBaseOffset,item.carryVelocity,item.carryUpdated,item.carrySway=offset,support.AssemblyLinearVelocity,workspace:GetServerTimeNow(),Vector2.zero
		local anchor = Instance.new("Attachment")
		anchor.Name,anchor.Parent="CarryAnchor",torso
		local reference=Instance.new("ObjectValue")
		reference.Name,reference.Value,reference.Parent="Anchor",anchor,resources
		local align=Instance.new("AlignPosition")
		align.Attachment0,align.Attachment1=anchor,target
		align.ApplyAtCenterOfMass,align.ReactionForceEnabled,align.RigidityEnabled=true,false,false
		align.MaxForce=math.max(torso.AssemblyMass,1)*Config.CarryForcePerMass
		align.MaxVelocity,align.Responsiveness=Config.CarryMaxVelocity,Config.CarryResponsiveness
		align.Parent=resources
		local orientation=Instance.new("AlignOrientation")
		orientation.Attachment0,orientation.Attachment1=anchor,target
		orientation.ReactionTorqueEnabled,orientation.RigidityEnabled=false,false
		orientation.MaxTorque=math.max(torso.AssemblyMass,1)*Config.CarryTorquePerMass
		orientation.MaxAngularVelocity,orientation.Responsiveness=Config.CarryMaxAngularVelocity,Config.CarryOrientationResponsiveness
		orientation.Parent=resources
		SetOwner(item.model,player)
	else
		item.model:PivotTo(root.CFrame*CFrame.new(1,-.1,-1.3))
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored,part.CanCollide,part.CanTouch,part.Massless=false,false,false,true end
		end
		local weld=Instance.new("Weld")
		weld.Name,weld.Part0,weld.Part1="CarryWeld",root,primary
		weld.C0,weld.Parent=root.CFrame:ToObjectSpace(primary.CFrame),primary
		item.carryWeld=weld
	end
	humanoid:UnequipTools()
	item.holder,item.location,item.motionState=player,"Carried","Carried"
	item.model:SetAttribute("MotionState","Carried")
	item.streetSlot=false
	item.version+=1
	return true
end
local function ReleaseContacts(item: Types.Item, character: Model): ()
	local folder=Instance.new("Folder")
	folder.Name,folder.Parent="ReleaseContacts",item.model
	for _, body in item.model:GetDescendants() do
		if body:IsA("BasePart") then
			for _, playerPart in character:GetDescendants() do
				if playerPart:IsA("BasePart") then
					local contact=Instance.new("NoCollisionConstraint")
					contact.Part0,contact.Part1,contact.Parent=body,playerPart,folder
				end
			end
		end
	end
	item.releaseCharacter=character
	item.releaseUntil=workspace:GetServerTimeNow()+Config.ReleaseGraceSeconds
end
function Carry.Drop(item: Types.Item, position: Vector3): ()
	local owner=item.holder
	local character=owner and owner.Character
	local primary=item.model.PrimaryPart
	local velocity=if primary then primary.AssemblyLinearVelocity else Vector3.zero
	local pose=item.model:GetPivot()
	Carry.Detach(item)
	local ignored: {Instance}={item.model}
	if character then table.insert(ignored,character) end
	local fallback=if item.kind=="Body" then Scene.PoolPickup.Position else Scene.Shelf.Position
	local safePose=Scene.SafePose(position,fallback,ignored)
	if item.kind=="Body" then
		local params=OverlapParams.new()
		params.FilterType,params.FilterDescendantsInstances=Enum.RaycastFilterType.Exclude,ignored
		params.RespectCanCollide=true
		local frame,size=item.model:GetBoundingBox()
		local blocked=#workspace:GetPartBoundsInBox(frame,size*0.85,params)>0
		if not owner or blocked or pose.Position.Y < -35 then
			item.model:PivotTo(pose + (safePose.Position-pose.Position))
		end
		Ragdoll.SetMode(item.model,"Loose")
		if velocity.Magnitude>Config.DropMaximumSpeed then velocity=velocity.Unit*Config.DropMaximumSpeed end
		for _,part in item.model:GetDescendants() do
			if part:IsA("BasePart") then part.AssemblyLinearVelocity=velocity end
		end
		if character then ReleaseContacts(item,character) end
	else
		item.model:PivotTo(safePose)
		for _,part in item.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored,part.CanCollide,part.CanTouch,part.Massless=false,true,true,false
				part.AssemblyLinearVelocity,part.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
			end
		end
	end
	item.location,item.motionState="Ground","Down"
	item.model:SetAttribute("MotionState","Down")
	item.version+=1
end
function Carry.Update(item: Types.Item, now: number): boolean
	if item.releaseUntil and now>=item.releaseUntil then
		local character=item.releaseCharacter
		local overlapping=false
		if character and character.Parent then
			local params=OverlapParams.new()
			params.FilterType,params.FilterDescendantsInstances=Enum.RaycastFilterType.Include,{character}
			for _,part in item.model:GetChildren() do
				if part:IsA("BasePart") and part.CanCollide and #workspace:GetPartsInPart(part,params)>0 then overlapping=true;break end
			end
		end
		if overlapping then item.releaseUntil=now+.15 else ClearRelease(item) end
	end
	local target=item.carryTarget
	local torso=item.model:FindFirstChild("UpperTorso")
	if item.holder and target and torso and torso:IsA("BasePart") then
		if not target.Parent or not item.holder.Character then Carry.Drop(item,torso.Position);return true end
		local support=target.Parent
		local base=item.carryBaseOffset
		if support:IsA("BasePart") and base then
			local dt=math.clamp(now-(item.carryUpdated or now),.01,.2)
			local velocity=support.AssemblyLinearVelocity
			local acceleration=support.CFrame:VectorToObjectSpace((velocity-(item.carryVelocity or velocity))/dt)
			local limit=Config.CarrySwayRadians
			local desired=Vector2.new(math.clamp(acceleration.Z*Config.CarrySwayAccelerationScale,-limit,limit),math.clamp(-acceleration.X*Config.CarrySwayAccelerationScale,-limit,limit))
			local sway=(item.carrySway or Vector2.zero):Lerp(desired,1-math.exp(-Config.CarrySwayResponse*dt))
			target.CFrame=base*CFrame.Angles(sway.X,0,sway.Y)
			item.carrySway,item.carryVelocity,item.carryUpdated=sway,velocity,now
		end
		if (torso.Position-target.WorldPosition).Magnitude>Config.CarryRecoveryDistance then
			-- 两套客户端装配可能在不同复制帧到达，连续超限才按脱肩处理。
			local since=item.carryErrorSince or now
			item.carryErrorSince=since
			if now-since>=Config.CarryRecoveryGraceSeconds then Carry.Drop(item,torso.Position);return true end
		else item.carryErrorSince=nil end
	end
	return false
end
return Carry
