-- 三维阻尼弹簧，保留叠加冲量并在静止时休眠。
--!strict
local Spring = {}
Spring.__index = Spring
export type State = typeof(setmetatable({} :: {
	Position: Vector3, Velocity: Vector3, Target: Vector3, Frequency: number, DampingRatio: number,
	MaximumOffset: number, MaximumVelocity: number, Sleeping: boolean,
}, Spring))
local function Finite(n: number): boolean
	return n == n and math.abs(n) < math.huge
end
function Spring.Limit(v: Vector3, maximum: number): Vector3
	local length = v.Magnitude
	if not Finite(length) or not Finite(maximum) or maximum <= 0 then return Vector3.zero end
	return if length > maximum then v * (maximum/length) else v
end
function Spring.new(hz: number, damping: number, offset: number, speed: number): State
	return setmetatable({Position=Vector3.zero, Velocity=Vector3.zero, Target=Vector3.zero, Frequency=hz,
		DampingRatio=damping, MaximumOffset=offset, MaximumVelocity=speed, Sleeping=true}, Spring)
end
function Spring.Reset(self: State, position: Vector3?)
	self.Position = Spring.Limit(position or Vector3.zero, self.MaximumOffset)
	self.Target, self.Velocity, self.Sleeping = self.Position, Vector3.zero, true
end
function Spring.Impulse(self: State, deltaVelocity: Vector3)
	if not Finite(deltaVelocity.Magnitude) then return end
	self.Velocity = Spring.Limit(self.Velocity + deltaVelocity, self.MaximumVelocity)
	self.Sleeping = false
end
function Spring.Step(self: State, dt: number): Vector3
	if not Finite(dt) or dt <= 0 then return self.Position end
	local target = Spring.Limit(self.Target, self.MaximumOffset)
	if self.Sleeping and self.Position == target then return target end
	local x = Spring.Limit(self.Position,self.MaximumOffset) - target
	local v = Spring.Limit(self.Velocity,self.MaximumVelocity)
	local w = 2*math.pi*math.clamp(if Finite(self.Frequency) then self.Frequency else 5, 0.1, 30)
	local z = math.clamp(if Finite(self.DampingRatio) then self.DampingRatio else 1, 0.1, 3)
	-- 闭式状态转移；长帧最多吸收一秒，过阻尼分支分别求负指数以避免双曲函数溢出。
	local t = math.min(dt,1)
	local a = z*w
	local c, s
	if math.abs(z-1) < 0.00001 then
		c = math.exp(-w*t)
		s = t*c
	elseif z < 1 then
		local b = w*math.sqrt(1-z*z)
		local decay = math.exp(-a*t)
		c, s = decay*math.cos(b*t), decay*math.sin(b*t)/b
	else
		local b = w*math.sqrt(z*z-1)
		local first, second = math.exp((-a+b)*t), math.exp((-a-b)*t)
		c, s = (first+second)/2, (first-second)/(2*b)
	end
	self.Position = Spring.Limit(target + x*(c+a*s) + v*s,self.MaximumOffset)
	self.Velocity = Spring.Limit(v*(c-a*s) - x*(w*w*s),self.MaximumVelocity)
	self.Sleeping = (self.Position-target).Magnitude < 0.0001 and self.Velocity.Magnitude < 0.001
	if self.Sleeping then self:Reset(target) end
	return self.Position
end
return Spring
