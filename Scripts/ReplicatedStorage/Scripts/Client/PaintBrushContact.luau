-- 椭圆体区域画笔与 3D 旋转横截面采样：画笔在近似椭圆体投影区域内平滑移动，旋转时沿切平面直接求交绘制完整横截面（含凹处）。
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local Curve = require(Shared.CurvedSurface)
local Rotation = require(Shared.PaintRotation)
local Surface = require(Shared.PaintSurface)
local Types = require(Shared.GameTypes)

local Brush = {}
local RayLength = 100
local EdgeRefinements = 5
local MaxSlicesPerFrame = 6
local TwoPi = math.pi * 2

export type Contact = {
	point: Vector2,
	sample: Types.Sample,
	localPoint: Vector3,
	worldPoint: Vector3?,
}
export type Frame = {
	orientation: CFrame,
	pointer: Vector2,
	tip: Vector2,
	contact: Contact?,
	clamped: boolean,
	planeNormal: Vector3?,
	planeOffset: number?,
	brushAzimuth: number?,
	brushWorld: Vector3?,
}
export type Resolver = {
	cast: (CFrame, Vector2) -> Contact?,
	ellipsoidPoint: ((CFrame, Vector2) -> (Vector2, Vector3, boolean))?,
	slice: ((CFrame, Vector3, number, Vector3, Vector3, number, number, number) -> { Types.Sample })?,
	worldToScreen: ((Vector3) -> Vector2?)?,
	axisWorld: ((CFrame, CFrame) -> Vector3?)?,
	pivotWorld: Vector3?,
	cameraLook: Vector3?,
}

local function WrapPi(angle: number): number
	local wrapped = (angle + math.pi) % TwoPi - math.pi
	if wrapped <= -math.pi then
		return wrapped + TwoPi
	end
	return wrapped
end

local function SameContinuousSurface(a: Contact?, b: Contact?): boolean
	return a ~= nil and b ~= nil and a.sample.part == b.sample.part and a.sample.face == b.sample.face
end

-- 将屏幕射线解析投影到旋转 3D 椭圆体表面：内部 1:1 跟随指针，外部精确贴合椭圆体轮廓地平线。
function Brush.ProjectToEllipsoid(
	ellipsoidFrame: CFrame,
	radii: Vector3,
	rayOrigin: Vector3,
	rayDir: Vector3,
	pointer: Vector2,
	cameraPos: Vector3?,
	worldToScreen: ((Vector3) -> Vector2?)?
): (Vector2, Vector3, boolean)
	local rx = math.max(radii.X, 0.05)
	local ry = math.max(radii.Y, 0.05)
	local rz = math.max(radii.Z, 0.05)
	local safeRadii = Vector3.new(rx, ry, rz)
	local invR = Vector3.new(1 / rx, 1 / ry, 1 / rz)

	local localO = ellipsoidFrame:PointToObjectSpace(rayOrigin) * invR
	local localD = ellipsoidFrame:VectorToObjectSpace(rayDir) * invR
	local a = localD:Dot(localD)
	if a < 1e-12 then
		return pointer, ellipsoidFrame.Position, false
	end
	local b = localO:Dot(localD)
	local c = localO:Dot(localO) - 1
	local disc = b * b - a * c

	if disc >= 0 then
		local sqrtDisc = math.sqrt(disc)
		local t = (-b - sqrtDisc) / a
		if t < 0 then
			t = (-b + sqrtDisc) / a
		end
		local qUnit = localO + localD * math.max(0, t)
		local brushWorld = ellipsoidFrame:PointToWorldSpace(qUnit * safeRadii)
		return pointer, brushWorld, false
	end

	local tClosest = -b / a
	local q = localO + localD * tClosest
	local unitDir = if rayDir.Magnitude > 1e-6 then rayDir.Unit else Vector3.zAxis
	local isPerspective = cameraPos ~= nil
		and (rayOrigin - cameraPos):Cross(unitDir).Magnitude < 0.05
		and (cameraPos - ellipsoidFrame.Position).Magnitude > 0.1

	local hUnit: Vector3
	if isPerspective and cameraPos then
		local eyeUnit = ellipsoidFrame:PointToObjectSpace(cameraPos) * invR
		local eyeLen = eyeUnit.Magnitude
		if eyeLen > 1.0001 then
			local e1 = eyeUnit / eyeLen
			local qPerp = q - e1 * q:Dot(e1)
			if qPerp.Magnitude > 1e-6 then
				local e2 = qPerp.Unit
				local cosH = 1 / eyeLen
				local sinH = math.sqrt(math.max(0, 1 - cosH * cosH))
				hUnit = e1 * cosH + e2 * sinH
			else
				hUnit = e1
			end
		else
			hUnit = if q.Magnitude > 1e-6 then q.Unit else Vector3.yAxis
		end
	else
		hUnit = if q.Magnitude > 1e-6 then q.Unit else Vector3.yAxis
	end

	local brushWorld = ellipsoidFrame:PointToWorldSpace(hUnit * safeRadii)
	local projected = if worldToScreen then worldToScreen(brushWorld) else nil
	return projected or pointer, brushWorld, true
end

function Brush.Resolver(
	model: Model,
	camera: Camera,
	base: CFrame,
	geometry: Rotation.Geometry,
	orientation: CFrame
): Resolver
	local displayed = Rotation.Pose(base, geometry, orientation)
	local pivotWorld = base:PointToWorldSpace(geometry.center)
	local radii = Rotation.EllipsoidRadii(geometry)
	local cameraFrame = camera.CFrame
	local cameraPos: Vector3? = if typeof(cameraFrame) == "CFrame" then cameraFrame.Position else nil
	local cameraLook = if typeof(cameraFrame) == "CFrame" then cameraFrame.LookVector else Vector3.zAxis
	local parts = Curve.BodyMesh(model)
	local partMap: { [string]: BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and Surface.IsBody(child) then
			partMap[child.Name] = child
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }

	local function WorldToScreen(worldPoint: Vector3): Vector2?
		local projected = camera:WorldToScreenPoint(worldPoint)
		if projected.Z <= 0 then
			return nil
		end
		return Vector2.new(projected.X, projected.Y)
	end

	local function CastAt(pose: CFrame, point: Vector2): Contact?
		local ray = camera:ScreenPointToRay(point.X, point.Y)
		local poseFrame = Rotation.Pose(base, geometry, pose)
		local correction = displayed * poseFrame:Inverse()
		local origin = correction:PointToWorldSpace(ray.Origin)
		local direction = correction:VectorToWorldSpace(ray.Direction)
		if #parts > 0 then
			local sample = Curve.FirstHit(parts, origin, direction, RayLength)
			if not sample then
				return nil
			end
			local part = partMap[sample.part]
			if not part then
				return nil
			end
			local localPoint = Curve.Point(part, sample)
			local displayedWorld = part.CFrame:PointToWorldSpace(localPoint)
			local worldPoint = poseFrame:PointToWorldSpace(displayed:PointToObjectSpace(displayedWorld))
			return { point = point, sample = sample, localPoint = localPoint, worldPoint = worldPoint }
		end
		local hit = workspace:Raycast(origin, direction * RayLength, params)
		if not hit or not hit.Instance:IsA("BasePart") or partMap[hit.Instance.Name] ~= hit.Instance then
			return nil
		end
		local sample = Surface.Project(hit.Instance, hit.Position, hit.Normal)
		if not Surface.IsPaintSample(hit.Instance, sample) then
			return nil
		end
		local worldPoint = poseFrame:PointToWorldSpace(displayed:PointToObjectSpace(hit.Position))
		return {
			point = point,
			sample = sample,
			localPoint = hit.Instance.CFrame:PointToObjectSpace(hit.Position),
			worldPoint = worldPoint,
		}
	end

	local function EllipsoidPoint(pose: CFrame, point: Vector2): (Vector2, Vector3, boolean)
		local ray = camera:ScreenPointToRay(point.X, point.Y)
		local ellipsoidFrame = CFrame.new(pivotWorld) * base.Rotation * pose.Rotation
		return Brush.ProjectToEllipsoid(ellipsoidFrame, radii, ray.Origin, ray.Direction, point, cameraPos, WorldToScreen)
	end

	local sliceFn: ((CFrame, Vector3, number, Vector3, Vector3, number, number, number) -> { Types.Sample })? = nil
	if #parts > 0 then
		sliceFn = function(
			pose: CFrame,
			planeNormal: Vector3,
			planeOffset: number,
			towardCamera: Vector3,
			tangent: Vector3,
			brushAzimuthStart: number,
			brushAzimuthEnd: number,
			deltaAngle: number
		): { Types.Sample }
			local poseFrame = Rotation.Pose(base, geometry, pose)
			local correction = displayed * poseFrame:Inverse()
			local adjPivot = correction:PointToWorldSpace(pivotWorld)
			local adjNormal = correction:VectorToWorldSpace(planeNormal).Unit
			local adjToward = correction:VectorToWorldSpace(towardCamera).Unit
			local adjTangent = correction:VectorToWorldSpace(tangent).Unit
			local sliced = Curve.SliceCrossSection(
				parts,
				adjPivot,
				adjNormal,
				planeOffset,
				adjToward,
				adjTangent,
				brushAzimuthStart,
				brushAzimuthEnd,
				deltaAngle,
				Config.BrushRadius * 0.5
			)
			if not cameraPos or #sliced == 0 then
				return sliced
			end
			-- 与服务端 Painting.Apply 保持同一镜头侧半球过滤，避免客户端提前记录服务端会拒收的背面切片点。
			local adjCamPos = correction:PointToWorldSpace(cameraPos)
			local toCameraVec = adjCamPos - adjPivot
			local toCamera = if toCameraVec.Magnitude > 0.001 then toCameraVec.Unit else Vector3.yAxis
			local minDot = Config.PaintSliceHemisphereMinDot
			local filtered: { Types.Sample } = {}
			local broke = false
			local cachedPartName: string? = nil
			local cachedPart: BasePart? = nil
			local cachedTris: typeof(Curve.Geometry(nil :: any).triangles)? = nil
			for _, sample in sliced do
				if sample.part ~= cachedPartName then
					cachedPartName = sample.part
					cachedPart = partMap[sample.part]
					cachedTris = if cachedPart then Curve.Geometry(cachedPart).triangles else nil
				end
				local tri = if cachedTris and sample.triangle then cachedTris[sample.triangle] else nil
				if cachedPart and tri then
					local localPoint = tri.a + (tri.b - tri.a) * sample.u + (tri.c - tri.a) * sample.v
					local worldPoint = cachedPart.CFrame:PointToWorldSpace(localPoint)
					if (worldPoint - adjPivot):Dot(toCamera) >= minDot then
						if broke then
							sample.breakBefore = true
							broke = false
						end
						table.insert(filtered, sample)
					else
						broke = true
					end
				else
					broke = true
				end
			end
			return filtered
		end
	end

	local function AxisWorld(fromPose: CFrame, toPose: CFrame): Vector3?
		local delta = toPose * fromPose:Inverse()
		local localAxis, deltaAngle = delta:ToAxisAngle()
		if math.abs(deltaAngle) < 1e-6 or localAxis.Magnitude < 1e-6 then
			return nil
		end
		local worldAxis = base:VectorToWorldSpace(localAxis)
		if worldAxis.Magnitude < 1e-6 then
			return nil
		end
		return worldAxis.Unit
	end

	return {
		cast = CastAt,
		ellipsoidPoint = EllipsoidPoint,
		slice = sliceFn,
		worldToScreen = WorldToScreen,
		axisWorld = AxisWorld,
		pivotWorld = pivotWorld,
		cameraLook = cameraLook,
	}
end

local function SliceBasis(planeNormal: Vector3, cameraLook: Vector3): (Vector3?, Vector3?)
	local towardRaw = -cameraLook - planeNormal * (-cameraLook):Dot(planeNormal)
	if towardRaw.Magnitude < 1e-5 then
		return nil, nil
	end
	local towardCamera = towardRaw.Unit
	local tangentRaw = planeNormal:Cross(towardCamera)
	if tangentRaw.Magnitude < 1e-5 then
		return nil, nil
	end
	return towardCamera, tangentRaw.Unit
end

local function OffsetAndAzimuth(
	worldPoint: Vector3,
	pivotWorld: Vector3,
	planeNormal: Vector3,
	towardCamera: Vector3,
	tangent: Vector3
): (number, number)
	local rel = worldPoint - pivotWorld
	local offset = rel:Dot(planeNormal)
	local inPlane = rel - planeNormal * offset
	local azimuth = if inPlane.Magnitude > 1e-5
		then math.atan2(inPlane:Dot(tangent), inPlane:Dot(towardCamera))
		else 0
	return offset, azimuth
end

function Brush.SamplePath(
	previous: Frame?,
	pointer: Vector2,
	orientation: CFrame,
	radius: number,
	resolver: Resolver,
	viewport: Vector2,
	rotationAxis: Vector3?
): ({ Types.Sample }, Frame)
	local samples: { Types.Sample } = {}
	local stepLength = Config.BrushRadius * 0.5
	local shortSide = math.max(1, math.min(viewport.X, viewport.Y))
	local samplePixels = math.max(1, Config.PaintVisualSamplePixels * shortSide / 1080)

	local tip = pointer
	local brushWorld: Vector3? = nil
	local clamped = false
	if resolver.ellipsoidPoint then
		tip, brushWorld, clamped = resolver.ellipsoidPoint(orientation, pointer)
	end

	local startPose = if previous then previous.orientation else orientation
	local angle = if previous then Rotation.Distance(startPose, orientation) else 0
	local derivedAxis = if previous and angle >= 1e-7 and resolver.axisWorld
		then resolver.axisWorld(startPose, orientation)
		else nil
	local activeAxis: Vector3? = nil
	if derivedAxis then
		activeAxis = derivedAxis
	elseif rotationAxis and rotationAxis.Magnitude > 1e-6 then
		activeAxis = rotationAxis.Unit
	end

	local pivotWorld = resolver.pivotWorld
	local cameraLook = resolver.cameraLook

	local function Emit(contact: Contact, pose: CFrame, breakBefore: boolean): ()
		contact.sample.orientation = pose
		contact.sample.breakBefore = breakBefore
		table.insert(samples, contact.sample)
	end

	-- 旋转绘画态：取消真实网格寻点，画笔严格按椭圆体区域移动，并沿切平面直接求交绘制完整横截面（含凹处）。
	if previous and angle >= 1e-7 and activeAxis and resolver.slice and pivotWorld and cameraLook and brushWorld then
		local towardCamera, tangent = SliceBasis(activeAxis, cameraLook)
		if towardCamera and tangent then
			local offsetB, phiB = OffsetAndAzimuth(brushWorld, pivotWorld, activeAxis, towardCamera, tangent)
			local axisChanged = not previous.planeNormal or math.abs(previous.planeNormal:Dot(activeAxis)) < 0.999
			local offsetA, phiA = offsetB, phiB
			if not axisChanged and previous.planeOffset ~= nil and previous.brushAzimuth ~= nil then
				offsetA = previous.planeOffset
				phiA = previous.brushAzimuth
			elseif previous.brushWorld then
				offsetA, phiA = OffsetAndAzimuth(previous.brushWorld, pivotWorld, activeAxis, towardCamera, tangent)
			end

			local deltaOffset = offsetB - offsetA
			local deltaPhi = WrapPi(phiB - phiA)
			local sliceCount = math.clamp(math.ceil(math.abs(deltaOffset) / stepLength), 1, MaxSlicesPerFrame)

			for k = 1, sliceCount do
				local t0 = (k - 1) / sliceCount
				local t1 = k / sliceCount
				local poseK = if k == sliceCount then orientation else startPose:Lerp(orientation, t1)
				local offsetK = if sliceCount == 1 then offsetB else offsetA + deltaOffset * ((t0 + t1) * 0.5)
				local subPhiA = phiA + deltaPhi * t0
				local subPhiB = phiA + deltaPhi * t1
				local subAngle = angle / sliceCount
				local sliced = resolver.slice(poseK, activeAxis, offsetK, towardCamera, tangent, subPhiA, subPhiB, subAngle)
				for _, sample in sliced do
					sample.orientation = poseK
					sample.slice = true
					table.insert(samples, sample)
				end
			end

			return samples, {
				orientation = orientation,
				pointer = pointer,
				tip = tip,
				contact = nil,
				clamped = clamped,
				planeNormal = activeAxis,
				planeOffset = offsetB,
				brushAzimuth = phiB,
				brushWorld = brushWorld,
			}
		end
	end

	-- 按下首笔：画笔位于椭圆体限制区域内，若直接落在白膜表面则落下一笔。
	if not previous then
		local hit = resolver.cast(orientation, tip)
		local planeOffset: number? = nil
		local brushAzimuth: number? = nil
		if activeAxis and pivotWorld and cameraLook and brushWorld then
			local towardCamera, tangent = SliceBasis(activeAxis, cameraLook)
			if towardCamera and tangent then
				planeOffset, brushAzimuth = OffsetAndAzimuth(brushWorld, pivotWorld, activeAxis, towardCamera, tangent)
			end
		end
		if hit then
			Emit(hit, orientation, true)
		end
		return samples, {
			orientation = orientation,
			pointer = pointer,
			tip = tip,
			contact = hit,
			clamped = clamped,
			planeNormal = activeAxis,
			planeOffset = planeOffset,
			brushAzimuth = brushAzimuth,
			brushWorld = brushWorld,
		}
	end

	local tipMove = (tip - previous.tip).Magnitude
	if angle < 1e-7 and tipMove < 1e-4 then
		return samples, {
			orientation = orientation,
			pointer = pointer,
			tip = tip,
			contact = previous.contact,
			clamped = clamped,
			planeNormal = previous.planeNormal,
			planeOffset = previous.planeOffset,
			brushAzimuth = previous.brushAzimuth,
			brushWorld = brushWorld or previous.brushWorld,
		}
	end

	-- 静止手绘（未拖出死区）或非曲面旧模型回退路径：沿椭圆体限制后的笔尖轨迹采样。
	local last: Contact? = previous.contact
	local startTip = previous.tip

	local function AppendSegment(poseA: CFrame, poseB: CFrame, tipA: Vector2, tipB: Vector2, hitB: Contact?, depth: number): ()
		if not hitB then
			last = nil
			return
		end
		local same = SameContinuousSurface(last, hitB)
		local distance = if same then (hitB.localPoint - (last :: Contact).localPoint).Magnitude else 0
		if depth < 5 and same and distance > stepLength then
			local midPose = poseA:Lerp(poseB, 0.5)
			local midTip = tipA:Lerp(tipB, 0.5)
			local midHit = resolver.cast(midPose, midTip)
			AppendSegment(poseA, midPose, tipA, midTip, midHit, depth + 1)
			AppendSegment(midPose, poseB, midTip, tipB, hitB, depth + 1)
			return
		end
		if not last then
			Emit(hitB, poseB, true)
			last = hitB
		elseif not same or distance > 1e-5 then
			Emit(hitB, poseB, not same or distance > stepLength * 2)
			last = hitB
		end
	end

	local rotSteps = if angle >= 1e-7 then math.ceil(radius * angle / stepLength) else 0
	local moveSteps = if tipMove >= 1e-4 then math.ceil(tipMove / samplePixels) else 0
	local steps = math.clamp(math.max(rotSteps, moveSteps, 1), 1, Config.PaintVisualSamplesPerFrame)

	local prevPose = startPose
	local prevTip = startTip
	for index = 1, steps do
		local alpha = index / steps
		local nextPose = if index == steps then orientation else startPose:Lerp(orientation, alpha)
		local nextTip = if index == steps then tip else startTip:Lerp(tip, alpha)
		local hit = resolver.cast(nextPose, nextTip)
		if last and hit then
			AppendSegment(prevPose, nextPose, prevTip, nextTip, hit, 0)
		elseif last and not hit then
			local hitT, missT = 0, 1
			local edgeHit: Contact? = nil
			local edgePose = prevPose
			local edgeTip = prevTip
			for _ = 1, EdgeRefinements do
				local midT = (hitT + missT) * 0.5
				local midPose = prevPose:Lerp(nextPose, midT)
				local midTip = prevTip:Lerp(nextTip, midT)
				local found = resolver.cast(midPose, midTip)
				if found and SameContinuousSurface(last, found) then
					hitT, edgeHit, edgePose, edgeTip = midT, found, midPose, midTip
				else
					missT = midT
				end
			end
			if edgeHit then
				AppendSegment(prevPose, edgePose, prevTip, edgeTip, edgeHit, 0)
			end
			last = nil
		elseif not last and hit then
			local missT, hitT = 0, 1
			local edgeHit: Contact = hit
			local edgePose = nextPose
			local edgeTip = nextTip
			for _ = 1, EdgeRefinements do
				local midT = (missT + hitT) * 0.5
				local midPose = prevPose:Lerp(nextPose, midT)
				local midTip = prevTip:Lerp(nextTip, midT)
				local found = resolver.cast(midPose, midTip)
				if found and SameContinuousSurface(hit, found) then
					hitT, edgeHit, edgePose, edgeTip = midT, found, midPose, midTip
				else
					missT = midT
				end
			end
			Emit(edgeHit, edgePose, true)
			last = edgeHit
			if edgeHit ~= hit then
				AppendSegment(edgePose, nextPose, edgeTip, nextTip, hit, 0)
			end
		end
		prevPose = nextPose
		prevTip = nextTip
	end

	local planeOffset = previous.planeOffset
	local brushAzimuth = previous.brushAzimuth
	if activeAxis and pivotWorld and cameraLook and brushWorld then
		local towardCamera, tangent = SliceBasis(activeAxis, cameraLook)
		if towardCamera and tangent then
			planeOffset, brushAzimuth = OffsetAndAzimuth(brushWorld, pivotWorld, activeAxis, towardCamera, tangent)
		end
	end

	return samples, {
		orientation = orientation,
		pointer = pointer,
		tip = tip,
		contact = last,
		clamped = clamped,
		planeNormal = activeAxis or previous.planeNormal,
		planeOffset = planeOffset,
		brushAzimuth = brushAzimuth,
		brushWorld = brushWorld or previous.brushWorld,
	}
end

return Brush
