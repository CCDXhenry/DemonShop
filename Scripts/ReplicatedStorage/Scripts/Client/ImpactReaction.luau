-- 将独立的预测或权威冲击按力臂分配到躯干、支撑腿及延迟响应的末端。
--!strict
local Physics = require(script.Parent.Parent.Shared.PhysicsConfig)
local GameConfig = require(script.Parent.Parent.Shared.GameConfig)
local Adapter = require(script.Parent.JointAdapter)
local Spring = require(script.Parent.Spring)
local Impact = {}
type Pulse = {
	age: number, gain: number, final: boolean, rejected: boolean, confirmed: boolean, point: Vector3,
	axes: {[string]: Vector3}, desired: {[string]: Vector3}, shift: Vector3, desiredShift: Vector3,
	channels: {Spring.State}, delays: {number}, started: number,
}
export type State = {[string]: Pulse}
local groups = {Root=1, Waist=1, Hip=2, Shoulder=2, Neck=2, Knee=3, Elbow=3, Wrist=4, Ankle=4}
local function Family(name: string): string
	return (name:gsub("^Left",""):gsub("^Right",""))
end
function Impact.Input(state: State, key: string, joints: Adapter.Map, frame: CFrame, position: Vector3,
	direction: Vector3, hits: number, started: number, confirmed: boolean, allowNew: boolean, cfg: Physics.Presentation)
	local pulse = state[key]
	if not pulse and not allowNew then return end
	local point = frame:PointToObjectSpace(position)
	local dir = frame:VectorToObjectSpace(direction)
	dir = Spring.Limit(Vector3.new(dir.X,0,dir.Z),1)
	local bend = Vector3.yAxis:Cross(dir)
	local amplitude = math.rad(if hits==1 then cfg.Hit.FirstDegrees else cfg.Hit.SecondDegrees)
	local axes: {[string]: Vector3} = {}
	for name,joint in joints do
		local pivot = frame:PointToObjectSpace((joint.parent.CFrame*joint.c0).Position)
		local torque = Spring.Limit((point-pivot):Cross(dir),1)
		local family = Family(name)
		local side = if name:sub(1,4)=="Left" then -1 else 1
		local balance = if hits>=2 then 1 else 0.4
		local axis = bend
		if family=="Waist" then axis=bend*0.85+torque*0.35
		elseif family=="Root" then axis=bend*(if hits==1 then 0.14 else 0.38)
		elseif family=="Hip" then axis=-bend*0.32+Vector3.xAxis*0.16*balance
		elseif family=="Knee" then axis=Vector3.xAxis*(0.22+0.36*balance)
		elseif family=="Shoulder" then axis=-bend*0.55+Vector3.zAxis*side*(0.3+balance*0.55)
		elseif family=="Neck" then axis=-bend*0.52+torque*0.12
		elseif family=="Elbow" then axis=-Vector3.xAxis*0.53*balance
		elseif family=="Wrist" or family=="Ankle" then axis=-bend*0.18 end
		axes[name] = axis*amplitude
	end
	local shift = dir*(if hits==1 then 0.035 else 0.08) - Vector3.yAxis*(if hits==1 then 0.04 else 0.10)
	if pulse then
		if confirmed and not pulse.confirmed then
			pulse.confirmed, pulse.rejected = true, false
			pulse.desired, pulse.desiredShift, pulse.point = axes, shift, point
		end
		return
	end
	local channels: {Spring.State} = {}
	local delays = {0,cfg.Hit.DelaySeconds,cfg.Hit.DelaySeconds*1.6,cfg.Hit.DelaySeconds*2}
	for _ in delays do
		local spring = Spring.new(cfg.Hit.FrequencyHz,cfg.Hit.DampingRatio,1.4,300)
		-- 单位临界阻尼脉冲的峰值为一；关节幅值由独立影响向量决定。
		spring:Impulse(Vector3.xAxis*(2*math.pi*cfg.Hit.FrequencyHz*math.exp(1)))
		table.insert(channels,spring)
	end
	state[key]={age=0,gain=1,final=hits>=GameConfig.StunHits,rejected=false,confirmed=confirmed,axes=axes,desired=axes,shift=shift,desiredShift=shift,
		point=point,channels=channels,delays=delays,started=started}
end
function Impact.Reject(state: State, key: string)
	local pulse=state[key]
	if pulse and not pulse.confirmed then pulse.rejected=true end
end
-- 末击峰段短暂保姿，等状态包承接；拒绝时仍由该令牌的 gain 衰减。
local function SpringAge(t: number,delay: number,final: boolean,cfg: Physics.Presentation): number
	local age=math.max(0,t-delay)
	if final then
		local peak=1/(2*math.pi*cfg.Hit.FrequencyHz)
		age-=math.clamp(age-peak,0,cfg.Fall.HoldSeconds)
	end
	return age
end
function Impact.Step(state: State, now: number, cfg: Physics.Presentation): ({[string]: Vector3}, Vector3)
	local rotations: {[string]: Vector3} = {}
	local translation=Vector3.zero
	for key,pulse in state do
		local age=math.max(pulse.age,now-pulse.started)
		local dt=age-pulse.age
		local blend=1-math.exp(-24*dt)
		if pulse.rejected then pulse.gain *= math.exp(-28*dt) end
		local awake=false
		for index,spring in pulse.channels do
			local delay=pulse.delays[index]
			spring.Frequency,spring.DampingRatio=cfg.Hit.FrequencyHz,cfg.Hit.DampingRatio
			spring:Step(SpringAge(age,delay,pulse.final,cfg)-SpringAge(pulse.age,delay,pulse.final,cfg))
			awake=awake or not spring.Sleeping
		end
		pulse.age=age
		if not awake or pulse.gain<0.001 or age>2 then state[key]=nil; continue end
		for name,axis in pulse.axes do
			local corrected=axis:Lerp(pulse.desired[name],blend)
			pulse.axes[name]=corrected
			local channel=pulse.channels[groups[Family(name)]]
			rotations[name]=(rotations[name] or Vector3.zero)+corrected*(channel.Position.X*pulse.gain)
		end
		pulse.shift=pulse.shift:Lerp(pulse.desiredShift,blend)
		translation+=pulse.shift*(pulse.channels[1].Position.X*pulse.gain)
	end
	return rotations,translation
end
return Impact
