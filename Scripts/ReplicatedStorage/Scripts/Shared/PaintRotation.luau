-- 白膜双轴旋转：固定工位摆位、输入角速度和旋转枢轴，由客户端和服务端共用。
--!strict
local Config = require(script.Parent.GameConfig)
local Types = require(script.Parent.GameTypes)

local Rotation = {}
local FullSpeedRadius = 0.45 -- 视口短边的比例
export type Geometry = { center: Vector3, rest: CFrame, radius: number, halfExtents: Vector3? }

Rotation.FlipOrientation = CFrame.Angles(0, math.pi, 0)

function Rotation.FlatOrientation(flipped: boolean): CFrame
	return if flipped then Rotation.FlipOrientation else CFrame.identity
end

function Rotation.IsFlipped(orientation: CFrame?): boolean
	if not orientation then
		return false
	end
	return Rotation.Distance(orientation, Rotation.FlipOrientation) < 0.1
end

function Rotation.FlipFrame(alpha: number): (CFrame, number)
	local t = math.clamp(alpha, 0, 1)
	local eased = if t < 0.5 then 2 * t * t else 1 - ((-2 * t + 2) ^ 2) / 2
	local rot = CFrame.Angles(0, math.pi * eased, 0)
	local lift = Config.PaintFlipLiftHeight * math.sin(math.pi * t)
	return rot, lift
end

function Rotation.TablePose(position: Vector3): CFrame
	-- 头朝东（台面圆圈、画面左侧），脚朝西（腿线），胸口朝上。
	return CFrame.fromMatrix(position, -Vector3.zAxis, Vector3.xAxis)
end

function Rotation.CameraPose(position: Vector3): CFrame
	-- 正上方。画面右侧朝世界 -X，画面上方朝世界 +Z（台子远处、牌子在画面下方）。
	local eye = position + Vector3.yAxis * Config.PaintCameraHeight
	return CFrame.fromMatrix(eye, -Vector3.xAxis, Vector3.zAxis)
end

function Rotation.Distance(from: CFrame, to: CFrame): number
	local _, angle = from:ToObjectSpace(to):ToAxisAngle()
	return math.abs(angle)
end

function Rotation.Velocity(offset: Vector2, viewport: Vector2): Vector2
	local radius = offset.Magnitude
	local shortSide = math.max(1, math.min(viewport.X, viewport.Y))
	local deadzone = Config.PaintDeadzonePixels * shortSide / 1080
	if radius <= deadzone then return Vector2.zero end
	local weight = math.min(1, (radius - deadzone) / math.max(1, shortSide * FullSpeedRadius - deadzone))
	return Vector2.new(offset.Y, offset.X) * (weight * Config.PaintAngularSpeed / radius)
end

function Rotation.Step(orientation: CFrame, speed: number, target: Vector2, dt: number): (CFrame, number)
	local targetSpeed = target.Magnitude
	if targetSpeed == 0 then return orientation, 0 end
	dt = math.clamp(dt, 0, 0.1)
	local decay = math.exp(-Config.PaintRotationResponse * dt)
	local nextSpeed = targetSpeed + (speed - targetSpeed) * decay
	local angle = targetSpeed * dt + (speed - targetSpeed) * ((1 - decay) / Config.PaintRotationResponse)
	-- 工位局部 X/Y 与俯视镜头的两条翻转轴对齐，左乘使轴独立于白膜当前朝向。
	local axis = Vector3.new(target.Y, target.X, 0) / targetSpeed
	return (CFrame.fromAxisAngle(axis, math.max(0, angle)) * orientation):Orthonormalize(), nextSpeed
end

local function Extent(frame: CFrame, half: Vector3, direction: Vector3): number
	return math.abs(frame.XVector:Dot(direction)) * half.X
		+ math.abs(frame.YVector:Dot(direction)) * half.Y
		+ math.abs(frame.ZVector:Dot(direction)) * half.Z
end

function Rotation.Create(model: Model, frames: Types.BodyPose): Geometry
	local torso = model:FindFirstChild("UpperTorso")
	local rest = CFrame.identity
	if torso and torso:IsA("BasePart") then
		local configuredRest = torso:GetAttribute("RestPose")
		rest = if typeof(configuredRest) == "CFrame" then configuredRest else model:GetPivot():ToObjectSpace(torso.CFrame)
	end
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum
	for name, frame in frames do
		local part = model:FindFirstChild(name)
		if not part or not part:IsA("BasePart") then continue end
		local localFrame, half = rest * frame, part.Size * 0.5
		local extent = Vector3.new(Extent(localFrame, half, Vector3.xAxis), Extent(localFrame, half, Vector3.yAxis), Extent(localFrame, half, Vector3.zAxis))
		minimum = minimum:Min(localFrame.Position - extent)
		maximum = maximum:Max(localFrame.Position + extent)
	end
	if minimum.X == math.huge then
		return { center = Vector3.zero, rest = rest, radius = 0, halfExtents = Vector3.new(0.1, 0.1, 0.1) }
	end
	local halfExtents = (maximum - minimum) * 0.5
	halfExtents = Vector3.new(math.max(0.1, halfExtents.X), math.max(0.1, halfExtents.Y), math.max(0.1, halfExtents.Z))
	return { center = (minimum + maximum) * 0.5, rest = rest, radius = halfExtents.Magnitude, halfExtents = halfExtents }
end

function Rotation.EllipsoidRadii(geometry: Geometry): Vector3
	local scale = Config.PaintEllipsoidScale
	local half = geometry.halfExtents
	if half then
		return Vector3.new(math.max(0.1, half.X * scale), math.max(0.1, half.Y * scale), math.max(0.1, half.Z * scale))
	end
	local fallback = math.max(0.1, geometry.radius * scale)
	return Vector3.new(fallback, fallback, fallback)
end

function Rotation.Pose(base: CFrame, geometry: Geometry?, orientation: CFrame): CFrame
	local center = if geometry and geometry.center then geometry.center else Vector3.zero
	return base * CFrame.new(center) * orientation * CFrame.new(-center)
end

return Rotation
