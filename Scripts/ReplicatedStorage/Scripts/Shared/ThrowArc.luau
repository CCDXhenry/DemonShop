-- 手动丢置弹道：斜抛初速、采样、体积扫掠时刻与 Beam 曲线拟合
--!strict
local Physics = require(script.Parent.PhysicsConfig)
local Config = Physics.ManualThrow
local Arc = {}
export type Cast = (CFrame, Vector3, Vector3) -> RaycastResult?

function Arc.IsFinite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function Arc.IsFiniteVector(value: Vector3): boolean
	return Arc.IsFinite(value.X) and Arc.IsFinite(value.Y) and Arc.IsFinite(value.Z)
end

function Arc.Horizontal(direction: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if Arc.IsFiniteVector(flat) and flat.Magnitude > 0.001 then
		return flat.Unit
	end
	local safe = Vector3.new(fallback.X, 0, fallback.Z)
	return if safe.Magnitude > 0.001 then safe.Unit else Vector3.zAxis
end

-- 以平地落回出手高度为基准，由水平距离和仰角求初速度。实际落点另由扫掠决定。
function Arc.LaunchVelocity(direction: Vector3, gravity: number): Vector3
	local horizontal = Arc.Horizontal(direction, Vector3.zAxis)
	local angle = math.rad(Config.AngleDegrees)
	local sine = math.sin(angle * 2)
	local speed = if sine > 0.001 and gravity > 0 then math.sqrt(Config.RangeStuds * gravity / sine) else 0
	return horizontal * (speed * math.cos(angle)) + Vector3.yAxis * (speed * math.sin(angle))
end

function Arc.Origin(shoulder: CFrame, direction: Vector3): Vector3
	local horizontal = Arc.Horizontal(direction, shoulder.LookVector)
	return shoulder.Position + horizontal * Config.ForwardStuds + Vector3.yAxis * Config.HeightStuds
end

function Arc.Position(origin: Vector3, velocity: Vector3, gravity: number, time: number): Vector3
	return origin + velocity * time - Vector3.yAxis * gravity * time * time / 2
end

function Arc.Velocity(velocity: Vector3, gravity: number, time: number): Vector3
	return velocity - Vector3.yAxis * gravity * time
end

-- 圆柱轴向为局部 X。把轴向对准表面法线后，落点圈贴在真实命中面上。
function Arc.RingCFrame(position: Vector3, normal: Vector3): CFrame
	local axis = if normal.Magnitude > 0.001 then normal.Unit else Vector3.yAxis
	local reference = if math.abs(axis:Dot(Vector3.yAxis)) < 0.999 then Vector3.yAxis else Vector3.xAxis
	local yVector = axis:Cross(reference).Unit
	local zVector = axis:Cross(yVector).Unit
	return CFrame.fromMatrix(position + axis * Config.RingLiftStuds, axis, yVector, zVector)
end

-- 交出物理前削掉朝地面的速度，避免刚体速度把白膜打穿地板。
function Arc.LimitDrop(velocity: Vector3): Vector3
	local drop = Config.SettleDropSpeed
	if velocity.Y >= -drop then
		return velocity
	end
	return Vector3.new(velocity.X, -drop, velocity.Z)
end

-- 以枢轴为中心、包住当前姿态的轴对齐扫掠盒。盒底贴到最低的可碰撞部件。
function Arc.SweepBox(model: Model): Vector3
	local pivot = model:GetPivot().Position
	local reach = Vector3.zero
	local found = false
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
			local cf = inst.CFrame
			local half = inst.Size * 0.5
			local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
			local extent = Vector3.new(
				math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
				math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
				math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
			)
			local offset = cf.Position - pivot
			local corner = Vector3.new(math.abs(offset.X) + extent.X, math.abs(offset.Y) + extent.Y, math.abs(offset.Z) + extent.Z)
			if found then
				reach = Vector3.new(math.max(reach.X, corner.X), math.max(reach.Y, corner.Y), math.max(reach.Z, corner.Z))
			else
				reach = corner
				found = true
			end
		end
	end
	if not found then
		return Config.SweepSize
	end
	return Vector3.new(math.max(reach.X * 2, Config.SweepSize.X), math.max(reach.Y * 2, Config.SweepSize.Y), math.max(reach.Z * 2, Config.SweepSize.Z))
end

-- 第三个返回值是表面命中点，第四个是该点的法线。弧长或时长用尽仍未命中时两者为空。
function Arc.Sweep(origin: Vector3, velocity: Vector3, gravity: number, step: number, limit: number, size: Vector3, cast: Cast, maxLength: number?): (number, Vector3, Vector3?, Vector3?)
	local cap = if maxLength and maxLength > 0 then maxLength else Config.MaxArcStuds
	local last = origin
	local elapsed = 0
	local traveled = 0
	local stride = math.max(step, 1 / 240)
	while elapsed < limit - 1e-5 and traveled < cap - 1e-4 do
		local time = math.min(elapsed + stride, limit)
		local point = Arc.Position(origin, velocity, gravity, time)
		local delta = point - last
		local segment = delta.Magnitude
		if segment > 1e-5 then
			local remain = cap - traveled
			local used = math.min(segment, remain)
			local probe = if used < segment - 1e-5 then delta.Unit * used else delta
			local hit = cast(CFrame.new(last), size, probe)
			if hit then
				local alpha = math.clamp(hit.Distance / used, 0, 1)
				local axis = hit.Normal
				local lift = if axis.Magnitude > 0.001 then axis.Unit else Vector3.yAxis
				local portion = used / segment
				return elapsed + (time - elapsed) * portion * alpha, last + probe * alpha + lift * Config.GroundGapStuds, hit.Position, lift
			end
			traveled += used
			if used < segment - 1e-5 then
				return elapsed + (time - elapsed) * (used / segment), last + probe, nil
			end
		end
		last = point
		elapsed = time
	end
	return elapsed, last, nil
end

-- 屏幕上方为镜头水平前方。死区内返回空，由调用方决定轻点或取消。
function Arc.StickDirection(vector: Vector2, forward: Vector3): Vector3?
	if vector.Magnitude <= Config.StickDeadzone then
		return nil
	end
	local look = Arc.Horizontal(forward, Vector3.zAxis)
	return (look * vector.Y + look:Cross(Vector3.yAxis) * vector.X).Unit
end

local function TangentFrame(position: Vector3, tangent: Vector3): CFrame
	local right = if tangent.Magnitude > 0 then tangent.Unit else Vector3.xAxis
	local up = if math.abs(right:Dot(Vector3.yAxis)) > 0.999 then Vector3.zAxis else Vector3.yAxis
	local back = right:Cross(up).Unit
	return CFrame.fromMatrix(position, right, back:Cross(right).Unit, back)
end

function Arc.BeamCurve(origin: Vector3, velocity: Vector3, gravity: number, duration: number): (CFrame, CFrame, number, number)
	local span = math.max(duration, 0)
	local finish = origin + velocity * span - Vector3.yAxis * gravity * span * span / 2
	local endVelocity = velocity - Vector3.yAxis * gravity * span
	return TangentFrame(origin, velocity), TangentFrame(finish, endVelocity), velocity.Magnitude * span / 3, endVelocity.Magnitude * span / 3
end

-- 存放池水平范围不含外扩边距，高度只到围墙顶。
function Arc.InsidePoolStrict(floor: CFrame, floorSize: Vector3, position: Vector3, wallHeight: number): boolean
	local localPosition = floor:PointToObjectSpace(position)
	local half = floorSize * 0.5
	return math.abs(localPosition.X) <= half.X
		and math.abs(localPosition.Z) <= half.Z
		and localPosition.Y >= -half.Y
		and localPosition.Y <= half.Y + wallHeight
end

-- 第二个返回值表示需要向抛掷者提示池已满。
function Arc.Landing(inStrict: boolean, painted: boolean, count: number, capacity: number): (string, boolean)
	if inStrict and not painted and count < capacity then
		return "Pool", false
	end
	if inStrict and not painted then
		return "Ground", true
	end
	return "Ground", false
end

return Arc
