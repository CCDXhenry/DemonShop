-- 以已绑定街道躯干和角色躯干的相对扫掠驱动有滞回的柔性让位。
--!strict
local Physics = require(script.Parent.Parent.Shared.PhysicsConfig)
local Spring = require(script.Parent.Spring)
local Contact = {}
export type Actor = {part: BasePart, previous: Vector3, radius: number}
export type Body = {id: string, torso: BasePart, root: BasePart, previous: Vector3}
type Touch = {normal: Vector3, speed: number, strength: number, phase: string}
type Pending = {remaining: number, velocity: Vector3}
export type State = {pending: {[string]: Pending}, touches: {[BasePart]: Touch}, springs: {[string]: Spring.State}, phase: string}
type Candidate = {body: Body, actor: Actor, start: Vector3, finish: Vector3, score: number}
type Inputs = {delay: {[string]: number}, target: {[string]: Vector3}, impulse: {[string]: Vector3}}
function Contact.New(): State
	return {pending={},touches={},springs={},phase="Exit"}
end
-- 相对线段与膨胀的定向盒求交。初始重叠从最近的水平面退出。
function Contact.Sweep(a: Vector3, b: Vector3, half: Vector3): (Vector3?, Vector3?)
	local t0,t1=0,1
	local normal=Vector3.zero
	local delta=b-a
	for _,axis in {Vector3.xAxis,Vector3.yAxis,Vector3.zAxis} do
		local start, speed, extent=a:Dot(axis),delta:Dot(axis),half:Dot(axis)
		if math.abs(speed)<0.00001 then
			if math.abs(start)>extent then return nil,nil end
		else
			local first,last=(-extent-start)/speed,(extent-start)/speed
			if first>last then first,last=last,first end
			if first>t0 then t0,normal=first,axis*math.sign(speed) end
			t1=math.min(t1,last)
			if t0>t1 then return nil,nil end
		end
	end
	if normal.Magnitude==0 or normal.Y~=0 then
		if half.X-math.abs(a.X)<half.Z-math.abs(a.Z) then
			normal=Vector3.xAxis*(if a.X>=0 then -1 else 1)
		else
			normal=Vector3.zAxis*(if a.Z>=0 then -1 else 1)
		end
	end
	return normal,a+delta*t0
end
local function Accumulate(inputs: Inputs, normal: Vector3, point: Vector3, speed: number, enter: boolean, cfg: Physics.Presentation)
	local bend=Vector3.yAxis:Cross(normal)
	local twist=math.clamp(point:Cross(normal).Y,-1,1)
	local strength=math.clamp(speed/14,0,1)
	local waist=math.rad(cfg.Contact.WaistDegrees)
	local onLeft=point.X<0
	local function Add(name: string, axis: Vector3, delay: number)
		inputs.target[name]=(inputs.target[name] or Vector3.zero)+axis*waist
		if enter then
			inputs.impulse[name]=(inputs.impulse[name] or Vector3.zero)+axis*(math.rad(cfg.Contact.StrongDegrees)*strength*cfg.Contact.FrequencyHz*12)
			inputs.delay[name]=math.min(inputs.delay[name] or delay,delay)
		end
	end
	local sideContact=math.abs(normal.X)>math.abs(normal.Z)
	local delay=cfg.Contact.DelaySeconds
	Add("Waist",bend+Vector3.yAxis*(twist*0.48+normal.X*0.3),if sideContact then delay else 0)
	Add("Neck",-bend*0.42,delay*1.6)
	for _,side in {"Left","Right"} do
		local weight=if (side=="Left")==onLeft then 1 else 0.36
		Add(side.."Shoulder",(bend*0.56+Vector3.yAxis*normal.X*0.65)*weight,if sideContact and weight==1 then 0 else delay)
		Add(side.."Hip",-bend*(0.28*weight),delay)
		Add(side.."Elbow",-bend*(0.18*weight),delay*1.8)
		Add(side.."Knee",Vector3.xAxis*(0.16*weight),delay*1.8)
	end
end
function Contact.Update(bodies: {Body}, actors: {Actor}, states: {[string]: State}, dt: number, cfg: Physics.Presentation): number
	local candidates: {Candidate}={}
	for _,body in bodies do
		local frame=body.torso.CFrame
		for _,actor in actors do
			if actor.part.Parent==body.torso.Parent then continue end
			local a=frame:VectorToObjectSpace(actor.previous-body.previous)
			local b=frame:PointToObjectSpace(actor.part.Position)
			local delta=b-a
			if delta.Magnitude>16 then a=b; delta=Vector3.zero end
			local closest=a+delta*math.clamp(-a:Dot(delta)/math.max(delta:Dot(delta),0.00001),0,1)
			if closest.Magnitude<=body.torso.Size.Magnitude/2+actor.radius+0.8 then
				local active=states[body.id] and states[body.id].touches[actor.part]
				table.insert(candidates,{body=body,actor=actor,start=a,finish=b,score=closest.Magnitude-(if active then 8 else 0)})
			end
		end
	end
	table.sort(candidates,function(a,b) return a.score<b.score end)
	local used,counts=0,{} :: {[string]: number}
	local current: {[string]: {[BasePart]: Touch}}={}
	local inputs: {[string]: Inputs}={}
	for _,pair in candidates do
		local body,actor=pair.body,pair.actor
		local id=body.id
		if used>=12 then break end
		if (counts[id] or 0)>=3 then continue end
		used+=1
		counts[id]=(counts[id] or 0)+1
		local old=states[id] and states[id].touches[actor.part]
		local pad=actor.radius+(if old then cfg.Contact.ExitPad else cfg.Contact.EnterPad)
		local half=body.torso.Size/2+Vector3.new(pad,actor.part.Size.Y/2,pad)
		local normal,center=Contact.Sweep(pair.start,pair.finish,half)
		if not normal or not center then continue end
		local world=body.torso.CFrame:VectorToWorldSpace(normal)
		local relative=actor.part.AssemblyLinearVelocity-body.torso.AssemblyLinearVelocity
		local speed=math.max(0,relative:Dot(world),(pair.finish-pair.start):Dot(normal)/math.max(dt,1/120))
		local rootNormal=body.root.CFrame:VectorToObjectSpace(world)
		local extent=body.torso.Size*0.5
		local surface=Vector3.new(math.clamp(center.X,-extent.X,extent.X),math.clamp(center.Y,-extent.Y,extent.Y),math.clamp(center.Z,-extent.Z,extent.Z))
		local position=body.root.CFrame:PointToObjectSpace(body.torso.CFrame:PointToWorldSpace(surface))
		if not inputs[id] then inputs[id]={target={},impulse={},delay={}}; current[id]={} end
		current[id][actor.part]={normal=world,speed=speed,strength=math.clamp(speed/14,0,1),phase=if old then "Stay" else "Enter"}
		Accumulate(inputs[id],rootNormal,position,speed,not old,cfg)
	end
	for id in current do if not states[id] then states[id]=Contact.New() end end
	for id,state in states do
		local input=inputs[id]
		state.touches=current[id] or {}
		state.phase=if input then "Stay" else "Exit"
		for _,touch in state.touches do if touch.phase=="Enter" then state.phase="Enter" end end
		if input then
			for name in input.target do
				if not state.springs[name] then state.springs[name]=Spring.new(5,0.85,1,20) end
			end
		end
		for name,spring in state.springs do
			local secondary=name=="Neck" or name:find("Knee") or name:find("Elbow")
			spring.Frequency=cfg.Contact.FrequencyHz*(if secondary then 0.72 else 1)
			spring.DampingRatio=cfg.Contact.DampingRatio
			spring.MaximumOffset=math.rad(cfg.Contact.StrongDegrees)
			local target=Spring.Limit(if input then input.target[name] or Vector3.zero else Vector3.zero,math.rad(cfg.Contact.WaistDegrees))
			local impulse=input and input.impulse[name]
			local pending=state.pending[name]
			if impulse and input then
				local delay=input.delay[name] or 0
				if pending then
					pending.remaining=math.min(pending.remaining,delay)
					pending.velocity=Spring.Limit(pending.velocity+impulse,spring.MaximumVelocity)
				else
					pending={remaining=delay,velocity=impulse}
					state.pending[name]=pending
				end
			end
			local remaining=dt
			if pending then
				local waitTime=math.min(remaining,pending.remaining)
				spring:Step(waitTime)
				pending.remaining-=waitTime
				remaining-=waitTime
				if pending.remaining>0 then continue end
				spring:Impulse(pending.velocity)
				state.pending[name]=nil
			end
			spring.Target=target
			spring:Step(remaining)
			if not input and spring.Sleeping then state.springs[name]=nil end
		end
		if not input and not next(state.springs) then states[id]=nil end
	end
	return used
end
return Contact
