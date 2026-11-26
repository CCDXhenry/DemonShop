-- 符文落印几何规则：切平面正向基、笔势转角与边缘等比缩放/跳过判定
--!strict
local Config = require(script.Parent.GameConfig)
local Surface = require(script.Parent.PaintSurface)
local Curve = require(script.Parent.CurvedSurface)

local Rules = {}

local NormalDotThreshold = 0.25
local PlaneDepthFactor = 0.95
local TangentReachFactor = 1.45
local ScaleSteps = { 1, 0.75, 0.5, 0.38 }
local CardinalProbes = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
}
local DiagonalProbes = {
	{ 0.7071, 0.7071 },
	{ -0.7071, 0.7071 },
	{ 0.7071, -0.7071 },
	{ -0.7071, -0.7071 },
}
local ProbeOffsets = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
	{ 0.7071, 0.7071 },
	{ -0.7071, 0.7071 },
	{ 0.7071, -0.7071 },
	{ -0.7071, -0.7071 },
}

-- 由局部法线构造稳定右手切平面基 (right, up)：默认 +Y 为部位正向，极区回退至 -Z。
function Rules.Basis(normal: Vector3): (Vector3, Vector3)
	local n = if normal.Magnitude > 1e-5 then normal.Unit else Vector3.yAxis
	local ref = if math.abs(n.Y) < 0.95 then Vector3.yAxis else -Vector3.zAxis
	local right = ref:Cross(n)
	if right.Magnitude < 1e-5 then
		right = Vector3.xAxis:Cross(n)
	end
	right = right.Unit
	local up = n:Cross(right).Unit
	return right, up
end

-- 将表面笔势方向换算为相对部位正向的顺时针弧度角 [-pi, pi]；与 SurfaceGui ImageLabel.Rotation 一致。
function Rules.AngleFromDirection(direction: Vector3, right: Vector3, up: Vector3): number
	local dx = direction:Dot(right)
	local dy = direction:Dot(up)
	if dx * dx + dy * dy < 1e-10 then
		return 0
	end
	return math.atan2(dx, dy)
end

-- 构造旋转后的切平面图像轴 (glyphRight, glyphDown)，使 angle=0 时字形顶端指向 +up。
function Rules.Axes(normal: Vector3, angle: number): (Vector3, Vector3)
	local right, up = Rules.Basis(normal)
	local cosine, sine = math.cos(angle), math.sin(angle)
	local glyphRight = right * cosine - up * sine
	local glyphUp = right * sine + up * cosine
	return glyphRight, -glyphUp
end

type CurvedGeometry = typeof(Curve.Geometry(nil :: any))

local function ProbeFitsPart(
	part: BasePart,
	geometry: CurvedGeometry,
	probe: Vector3,
	center: Vector3,
	normal: Vector3,
	maxDepth: number,
	maxReachSq: number,
	limX: number,
	limY: number,
	limZ: number,
	flatSide: number?
): boolean
	if math.abs(probe.X) > limX or math.abs(probe.Y) > limY or math.abs(probe.Z) > limZ then
		return false
	end
	local projected = Curve.ProjectLocal(part, probe)
	local triIndex = projected.triangle
	if not triIndex then
		return false
	end
	local triangle = geometry.triangles[triIndex]
	if not triangle or not triangle.allowed then
		return false
	end
	if triangle.normal:Dot(normal) < NormalDotThreshold then
		return false
	end
	if flatSide ~= nil and Curve.FlatSideDot(triangle.normal, flatSide) < Curve.FlatVisualClipMinDot then
		return false
	end
	local surfacePoint = Curve.Point(part, projected)
	local diff = surfacePoint - probe
	if math.abs(diff:Dot(normal)) > maxDepth then
		return false
	end
	local radial = surfacePoint - center
	return radial:Dot(radial) <= maxReachSq
end

local function CheckProbeList(
	part: BasePart,
	geometry: CurvedGeometry,
	center: Vector3,
	normal: Vector3,
	glyphRight: Vector3,
	glyphDown: Vector3,
	half: number,
	maxDepth: number,
	maxReachSq: number,
	limX: number,
	limY: number,
	limZ: number,
	probes: { { number } },
	model: Model?,
	flatSide: number?
): boolean
	local margin = maxDepth + 0.08
	local neighbors = if model then Curve.Neighbors[part.Name] else nil
	for _, offset in ipairs(probes) do
		local probe = center + glyphRight * (offset[1] * half) + glyphDown * (offset[2] * half)
		if ProbeFitsPart(part, geometry, probe, center, normal, maxDepth, maxReachSq, limX, limY, limZ, flatSide) then
			continue
		end
		local matchedNeighbor = false
		if model and neighbors then
			for _, neighborName in ipairs(neighbors) do
				local shift = Curve.RestOffset(part.Name, neighborName)
				local neighbor = if shift then model:FindFirstChild(neighborName) else nil
				if neighbor and neighbor:IsA("BasePart") and Curve.IsPart(neighbor) and shift then
					local nHalf = neighbor.Size * 0.5
					if ProbeFitsPart(
						neighbor,
						Curve.Geometry(neighbor),
						probe + shift,
						center + shift,
						normal,
						maxDepth,
						maxReachSq,
						nHalf.X + margin,
						nHalf.Y + margin,
						nHalf.Z + margin,
						flatSide
					) then
						matchedNeighbor = true
						break
					end
				end
			end
		end
		if not matchedNeighbor then
			return false
		end
	end
	return true
end

local function ProbesFitCurved(
	part: BasePart,
	geometry: CurvedGeometry,
	center: Vector3,
	normal: Vector3,
	glyphRight: Vector3,
	glyphDown: Vector3,
	half: number,
	model: Model?,
	flatSide: number?
): boolean
	local maxDepth = half * PlaneDepthFactor
	local maxReach = half * TangentReachFactor
	local maxReachSq = maxReach * maxReach
	local halfSize = part.Size * 0.5
	local margin = maxDepth + 0.08
	local limX, limY, limZ = halfSize.X + margin, halfSize.Y + margin, halfSize.Z + margin
	if not CheckProbeList(part, geometry, center, normal, glyphRight, glyphDown, half, maxDepth, maxReachSq, limX, limY, limZ, CardinalProbes, model, flatSide) then
		return false
	end
	local edgeMargin = half * 1.45
	local nearEdge = math.abs(center.X) + edgeMargin >= halfSize.X
		or math.abs(center.Y) + edgeMargin >= halfSize.Y
		or math.abs(center.Z) + edgeMargin >= halfSize.Z
	if not nearEdge then
		return true
	end
	return CheckProbeList(part, geometry, center, normal, glyphRight, glyphDown, half, maxDepth, maxReachSq, limX, limY, limZ, DiagonalProbes, model, flatSide)
end

-- 曲面部位边缘适配：允许等比缩至 Config.RuneMinScale，仍放不下完整字形时返回 nil 跳过；跨直连关节时可落到邻接部件表面。
function Rules.FitCurvedScale(part: BasePart, center: Vector3, normal: Vector3, angle: number, model: Model?, flatSide: number?): number?
	local geometry = Curve.Geometry(part)
	local glyphRight, glyphDown = Rules.Axes(normal, angle)
	local baseHalf = Config.RuneStampSize * 0.5
	for _, scale in ipairs(ScaleSteps) do
		if scale < Config.RuneMinScale then
			break
		end
		if ProbesFitCurved(part, geometry, center, normal, glyphRight, glyphDown, baseHalf * scale, model, flatSide) then
			return scale
		end
	end
	return nil
end

-- 旧平面部位边缘适配：根据到面边缘距离及 PaintMask 遮罩计算最大完整缩放，低于下限时返回 nil 跳过。
function Rules.FitFlatScale(part: BasePart, face: number, u: number, v: number, dimensions: Vector2): number?
	local cx, cy = u * dimensions.X, v * dimensions.Y
	local minEdge = math.min(cx, dimensions.X - cx, cy, dimensions.Y - cy)
	local baseHalf = Config.RuneStampSize * 0.5
	if baseHalf <= 1e-6 then
		return 1
	end
	local fit = math.min(1, minEdge / baseHalf)
	if fit < Config.RuneMinScale then
		return nil
	end
	local grid = Config.PaintGrid
	local mask = part:GetAttribute("PaintMask" .. tostring(face))
	if typeof(mask) == "string" then
		for _, scale in ipairs(ScaleSteps) do
			local candidate = math.min(fit, scale)
			if candidate < Config.RuneMinScale then
				break
			end
			local half = baseHalf * candidate
			local ok = true
			for _, offset in ipairs(ProbeOffsets) do
				local pu = math.clamp((cx + offset[1] * half) / dimensions.X, 0, 0.999999)
				local pv = math.clamp((cy + offset[2] * half) / dimensions.Y, 0, 0.999999)
				local gx = math.floor(pu * grid)
				local gy = math.floor(pv * grid)
				if not Surface.CellAllowed(part, face, gx, gy) then
					ok = false
					break
				end
			end
			if ok then
				return candidate
			end
		end
		return nil
	end
	return fit
end

return Rules
