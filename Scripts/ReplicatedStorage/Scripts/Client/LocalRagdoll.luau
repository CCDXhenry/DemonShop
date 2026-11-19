-- 从上一帧可见骨架交接到六条以内的本地物理链，落地后冻结求解后的相对姿态。
--!strict
local Shared = script.Parent.Parent.Shared
local Physics = require(Shared.PhysicsConfig)
local Types = require(Shared.GameTypes)
local Adapter = require(script.Parent.JointAdapter)
local Spring = require(script.Parent.Spring)
local Fall = {}
local chains={"LeftShoulder","RightShoulder","LeftHip","RightHip","LeftKnee","RightKnee"}
export type History = {[string]: CFrame}
export type State = {
	root: BasePart, origin: CFrame, target: CFrame, elapsed: number, tip: number, duration: number,
	mask: {[string]: boolean}, sockets: {BallSocketConstraint}, parts: {BasePart}, active: boolean, deadline: number,
	sleepPose: {[BasePart]: CFrame}?, base: {[string]: CFrame}, velocity: Vector3,
}
function Fall.Sample(joints: Adapter.Map, history: History)
	for name,joint in joints do history[name]=joint.child.CFrame end
end
local function Relative(joint: Adapter.Joint): CFrame
	return (joint.parent.CFrame*joint.c0):ToObjectSpace(joint.child.CFrame*joint.c1)
end
local bend: {[string]:number}={LeftKnee=.26,RightKnee=.43,LeftShoulder=-.15,RightShoulder=.21}
local function SetDrive(joint: Adapter.Joint,enabled: boolean)
	local drive=joint.drive
	if drive:IsA("Motor6D") then drive.Enabled=enabled else drive.IsKinematic=true;drive.Enabled=enabled end
end
local function Open(joint: Adapter.Joint, state: State, previous: CFrame?, dt: number)
	local limit=assert(joint.limit)
	local a,b=Instance.new("Attachment"),Instance.new("Attachment")
	a.CFrame,a.Parent=joint.c0,joint.parent
	b.CFrame,b.Parent=joint.c1,joint.child
	local socket=Instance.new("BallSocketConstraint")
	socket.Attachment0,socket.Attachment1=a,b
	socket.LimitsEnabled,socket.TwistLimitsEnabled=true,true
	socket.UpperAngle,socket.TwistLowerAngle,socket.TwistUpperAngle=limit.cone,limit.lower,limit.upper
	socket.MaxFrictionTorque=limit.friction*.52
	socket.Parent=joint.child
	SetDrive(joint,false)
	state.mask[joint.name]=true
	table.insert(state.sockets,socket)
	local part=joint.child
	part.Massless=false
	local linear,angular=Vector3.zero,Vector3.zero
	if previous and dt>0 and dt<=.15 then
		linear=(part.Position-previous.Position)/dt
		local axis,angle=(part.CFrame.Rotation*previous.Rotation:Inverse()):ToAxisAngle()
		angular=axis*(angle/dt)
	end
	part.AssemblyLinearVelocity=Spring.Limit(linear+state.velocity,Physics.DropMaximumSpeed)
	part.AssemblyAngularVelocity=Spring.Limit(angular,Physics.MaximumAngularSpeed)
end
function Fall.Begin(root: BasePart,joints: Adapter.Map,fall: Types.GroundFall,history: History,dt: number,
	cfg: Physics.Presentation,physics: boolean,late: boolean): State
	local state: State={root=root,origin=root.CFrame,target=fall.target,elapsed=0,tip=cfg.Fall.TipSeconds,
		duration=cfg.Fall.PhysicsSeconds,deadline=os.clock()+cfg.Fall.PhysicsSeconds,mask={},sockets={},parts={root},active=false,base={},velocity=fall.velocity}
	for name,joint in joints do
		local transform=Relative(joint)
		state.base[name]=transform
		Adapter.Write(joint,transform)
		joint.applied=nil
		table.insert(state.parts,joint.child)
	end
	if physics and not late and state.duration>0 then
		for i,name in chains do
			if i>math.floor(cfg.Fall.JointLimit) then break end
			local joint=joints[name]
			Open(joint,state,history[name],dt)
		end
		state.active=#state.sockets>0
		if state.active then state.tip=math.min(state.tip,state.duration) end
		for name,joint in joints do
			local side=string.match(name,"^(Left)") or string.match(name,"^(Right)")
			local limb=side and (string.find(name,"Arm") or string.find(name,"Elbow") or string.find(name,"Wrist") or string.find(name,"Shoulder"))
			local part=joint.child
			if side and state.mask[side..(if limb then "Shoulder" else "Hip")] then
				part.CollisionGroup=Physics.FallGroup
				part.CanTouch,part.CanQuery=false,false
				part.CanCollide=true
			end
		end
	end
	if late then
		-- 流入/远景从权威落点直接构建同向曲肢姿态；不依赖锚定部件间的约束求解。
		local byChild: {[BasePart]: Adapter.Joint}={}
		local pose: {[BasePart]: CFrame}={[root]=CFrame.identity}
		for _,joint in joints do
			byChild[joint.child]=joint
			joint.child.Anchored=true
			SetDrive(joint,false)
		end
		local function Frame(part: BasePart): CFrame
			if pose[part] then return pose[part] end
			local joint=byChild[part]
			local relative=Frame(joint.parent)*joint.c0*CFrame.Angles(bend[joint.name] or 0,0,0)*joint.c1:Inverse()
			pose[part]=relative
			return relative
		end
		for _,part in state.parts do part.CFrame=fall.target*Frame(part) end
		state.sleepPose=pose
	end
	return state
end
function Fall.StopPhysics(state: State,joints: Adapter.Map)
	if not state.active then return end
	for name in state.mask do
		local joint=joints[name]
		local relative=Relative(joint)
		state.base[name]=relative
		Adapter.Write(joint,relative)
		SetDrive(joint,true)
	end
	for _,part in state.parts do part.CanCollide=false end
	for _,socket in state.sockets do
		local a,b=socket.Attachment0,socket.Attachment1
		socket:Destroy()
		if a then a:Destroy() end
		if b then b:Destroy() end
	end
	table.clear(state.sockets)
	table.clear(state.mask)
	state.active=false
end
function Fall.Step(state: State,joints: Adapter.Map,dt: number)
	if state.sleepPose then return end
	-- 先读上一物理步已解算的最终姿态，再冻结；避免 Transform 延迟应用产生一帧回弹。
	if state.elapsed>=math.max(state.tip,if state.active then state.duration else 0) then
		local pose: {[BasePart]: CFrame}={}
		for _,part in state.parts do pose[part]=state.root.CFrame:ToObjectSpace(part.CFrame) end
		for _,part in state.parts do part.Anchored=true end
		Fall.StopPhysics(state,joints)
		for _,joint in joints do SetDrive(joint,false) end
		for part,relative in pose do part.CFrame=state.target*relative end
		state.sleepPose=pose
		return
	end
	if state.active and os.clock()>=state.deadline then Fall.StopPhysics(state,joints) end
	state.elapsed+=dt
	local t=math.clamp(state.elapsed/state.tip,0,1)
	local u=t*t*(3-2*t)
	local frame=state.origin:Lerp(state.target,u)
	local initial=Spring.Limit(state.velocity,Physics.DropMaximumSpeed)*state.tip*t*(1-t)^2
	state.root.CFrame=frame+initial
	-- 支撑链在接地前逐渐对齐权威躯干；入场腰部的后仰不会随根额外翻进地面。
	local settle=math.clamp((t-.18)/.82,0,1)
	settle=settle*settle*(3-2*settle)
	for _,name in {"Root","Waist","Neck"} do
		Adapter.Write(joints[name],state.base[name]:Lerp(CFrame.identity,settle))
	end
	if not state.active then
		for name,angle in bend do
			Adapter.Write(joints[name],state.base[name]*CFrame.Angles(angle*u,0,0))
		end
	end
end
return Fall
