-- 双轴旋转、3D 椭圆体画笔限制区域、凹处完整横截面求交与服务端进度同步离线回归。
local R = require('@lune/roblox')
local Config = require('./GameConfig')
local Rotation = require('./PaintRotation')
local Brush = require('./PaintBrushContact')
local Presentation = require('./BodyPresentation')
local Curve = require('./CurvedSurface')
local Data = require('./BodySurfaceData')
local Surface = require('./PaintSurface')
local Painting = require('./Painting')
local V, V3, C = R.Vector2, R.Vector3, R.CFrame
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end

-- 1. 双轴角速度、步进与枢轴中心验证。
local viewport = V.new(1920, 1080)
check(Rotation.Velocity(V.new(1, 0), viewport) == V.zero, 'offset inside the press-point deadzone stops rotation')
local near = Rotation.Velocity(V.new(20, 0), viewport)
local far = Rotation.Velocity(V.new(200, 0), viewport)
check(near.X == 0 and near.Y > 0 and far.Magnitude > near.Magnitude, 'horizontal input controls pitch at radial speed')
check(Rotation.Velocity(V.new(0, -200), viewport).X < 0, 'vertical input controls the other axis')
check((far - Rotation.Velocity(V.new(100, 0), viewport * 0.5)).Magnitude < 1e-6, 'speed scales with the viewport')
check(math.abs(Rotation.Velocity(V.new(900, 900), viewport).Magnitude - Config.PaintAngularSpeed) < 1e-5, 'diagonal input respects the total speed cap')
local target = V.new(3, -3)
local initial = C.Angles(1.7, 0.4, -1.5)
local turned, speed = Rotation.Step(initial, 0, target, 0.08)
local first, firstSpeed = Rotation.Step(initial, 0, target, 0.04)
local second = Rotation.Step(first, firstSpeed, target, 0.04)
check(Rotation.Distance(turned, second) < 1e-5, 'equal elapsed time gives the same motion across frame rates')
local stopped, stoppedSpeed = Rotation.Step(turned, speed, V.zero, 0.08)
check(stopped == turned and stoppedSpeed == 0, 'release or press-point deadzone stops without coasting')
local expectedAxis = V3.new(target.Y, target.X, 0).Unit
local orientation = C.identity
for _ = 1, 50 do
	local nextPose = Rotation.Step(orientation, target.Magnitude, target, 0.06)
	local axis = (nextPose * orientation:Inverse()):ToAxisAngle()
	check(axis:Dot(expectedAxis) > 0.9999, 'the world rotation direction stays fixed over more than a full turn')
	orientation = nextPose
end
local reversed = Rotation.Step(orientation, speed, -target, 0.02)
local axis = (reversed * orientation:Inverse()):ToAxisAngle()
check(axis:Dot(-expectedAxis) > 0.9999, 'new input direction takes effect without smoothing through the opposite direction')

-- 2. 工位枢轴、椭圆体半尺寸与旁观者同步验证。
local torso = R.Instance.new('Part')
torso.Name, torso.Size = 'UpperTorso', V3.new(2, 4, 1)
torso:SetAttribute('RestPose', C.new(1, 0, 0))
local mockModel = { FindFirstChild = function(_, name) return if name == 'UpperTorso' then torso else nil end }
local mockFrames = { UpperTorso = C.identity }
local placement = V3.new(-31, 6.9, -9)
local base = Rotation.TablePose(placement)
local geometry = Rotation.Create(mockModel, mockFrames)
check(geometry.halfExtents ~= nil and math.abs(geometry.halfExtents.X - 1) < 1e-5 and math.abs(geometry.halfExtents.Y - 2) < 1e-5 and math.abs(geometry.halfExtents.Z - 0.5) < 1e-5,
	'Rotation.Create captures exact body local halfExtents for ellipsoid bounds')
local radii = Rotation.EllipsoidRadii(geometry)
check(math.abs(radii.X - Config.PaintEllipsoidScale) < 1e-5 and math.abs(radii.Y - 2 * Config.PaintEllipsoidScale) < 1e-5,
	'EllipsoidRadii scales halfExtents by PaintEllipsoidScale')
local neutralCenter = base:PointToWorldSpace(geometry.center)
check(base.Position == placement and (Rotation.CameraPose(placement).Position - placement - V3.yAxis * Config.PaintCameraHeight).Magnitude < 1e-5,
	'table and camera use the workspace placement anchor')
local flatAtOrigin = Rotation.TablePose(V3.zero)
check((flatAtOrigin.UpVector - V3.xAxis).Magnitude < 1e-5 and (flatAtOrigin.LookVector - V3.yAxis).Magnitude < 1e-5,
	'table pose points the head east and the chest upward')
local overhead = Rotation.CameraPose(V3.zero)
check((overhead.UpVector - V3.zAxis).Magnitude < 1e-5 and (overhead.Position - V3.yAxis * Config.PaintCameraHeight).Magnitude < 1e-5,
	'paint camera sits overhead with the far side at the top of the screen')
check(Config.PaintCameraHeight == 10.5 and Config.BrushRadius == 0.18,
	'paint camera height clears overhead slab and brush radius matches rune stamp size')
for _, angles in { V.new(0, math.pi / 2), V.new(math.pi / 2, 0), V.new(-2.4, 1.8), V.new(math.pi, math.pi) } do
	local turnedPose = Rotation.Pose(base, geometry, C.Angles(angles.Y, angles.X, 0.4))
	check((turnedPose:PointToWorldSpace(geometry.center) - neutralCenter).Magnitude < 1e-5,
		'whole-body pivot keeps the same world position during rotation')
end
local viewer = Presentation.new()
viewer.model, viewer.parts.UpperTorso, viewer.targetBodyPose = mockModel, torso, mockFrames
check(Config.PaintRotationEnabled == false and Config.PaintPhysicsEnabled == false,
	'rotation and physics switches default to false so body lies flat and fixed')
viewer.orientation = C.Angles(0, math.pi - 0.02, 0)
viewer.targetOrientation = C.Angles(0, -math.pi + 0.02, 0)
viewer:Update(base, 0.01, true)
check(viewer.orientation == C.identity and viewer.targetOrientation == C.identity,
	'disabled rotation switch locks table orientation to neutral flat pose')
Config.PaintRotationEnabled = true
viewer.orientation = C.Angles(0, math.pi - 0.02, 0)
viewer.targetOrientation = C.Angles(0, -math.pi + 0.02, 0)
viewer:Update(base, 0.01, false)
check(Rotation.Distance(viewer.orientation, viewer.targetOrientation) < 0.04, 'observer interpolates across the short arc')
viewer:Update(base, 0.01, true)
local expected = Rotation.Pose(base, geometry, viewer.targetOrientation) * geometry.rest
check((torso.CFrame.Position - expected.Position).Magnitude < 1e-5, 'observers and operators use the same rigid transform')
Config.PaintRotationEnabled = false
torso:Destroy()

-- 3. 3D 椭圆体解析投影验证（内部 1:1 跟随，外部严格贴合透视地平线，旋转窄侧面平滑收窄无跳动）。
local camPos = Rotation.CameraPose(V3.zero).Position
local perspCam = {
	CFrame = Rotation.CameraPose(V3.zero),
	ViewportSize = viewport,
	WorldToScreenPoint = function(_, p)
		local rel = p - camPos
		local depth = -rel.Y
		if depth <= 0.01 then return V3.new(0, 0, -1) end
		local focal = 1080 / (2 * math.tan(math.rad(45) * 0.5))
		return V3.new(960 - rel.X * focal / depth, 540 - rel.Z * focal / depth, depth)
	end,
	ScreenPointToRay = function(_, sx, sy)
		local focal = 1080 / (2 * math.tan(math.rad(45) * 0.5))
		local dir = V3.new(-(sx - 960) / focal, -1, -(sy - 540) / focal).Unit
		return { Origin = camPos + dir * 0.1, Direction = dir }
	end,
}
local function projectToScreen(p)
	local s = perspCam:WorldToScreenPoint(p)
	return if s.Z > 0 then V.new(s.X, s.Y) else nil
end
local testRadii = V3.new(1.5, 2.5, 0.6) -- TablePose 下 X=竖直宽(±1.5)，Y=水平长(±2.5)，Z=厚度(±0.6)
local flatBase = Rotation.TablePose(V3.zero)
local flatEllipsoid = C.new(V3.zero) * flatBase.Rotation
-- 内部指针：1:1 跟随，clamped=false，且 brushWorld 严格落在椭圆体前表面。
local insidePtr = V.new(1020, 580)
local insideRay = perspCam:ScreenPointToRay(insidePtr.X, insidePtr.Y)
local inTip, inWorld, inClamped = Brush.ProjectToEllipsoid(flatEllipsoid, testRadii, insideRay.Origin, insideRay.Direction, insidePtr, camPos, projectToScreen)
local inLocal = flatEllipsoid:PointToObjectSpace(inWorld)
local inNorm = (inLocal.X / testRadii.X) ^ 2 + (inLocal.Y / testRadii.Y) ^ 2 + (inLocal.Z / testRadii.Z) ^ 2
check(not inClamped and inTip == insidePtr and math.abs(inNorm - 1) < 1e-4 and inWorld.Y > 0,
	'pointer inside ellipsoid keeps exact screen tip and lies on front ellipsoid surface')
-- 外部指针：严格贴合透视轮廓地平线，clamped=true，旋转 90° 侧视时垂直范围平滑收窄。
local outerPtr = V.new(960, 980)
local outerRay = perspCam:ScreenPointToRay(outerPtr.X, outerPtr.Y)
local outTipFlat, outWorldFlat, outClampedFlat = Brush.ProjectToEllipsoid(flatEllipsoid, testRadii, outerRay.Origin, outerRay.Direction, outerPtr, camPos, projectToScreen)
local outLocalFlat = flatEllipsoid:PointToObjectSpace(outWorldFlat)
local outNormFlat = (outLocalFlat.X / testRadii.X) ^ 2 + (outLocalFlat.Y / testRadii.Y) ^ 2 + (outLocalFlat.Z / testRadii.Z) ^ 2
check(outClampedFlat and math.abs(outNormFlat - 1) < 1e-4 and outTipFlat.Y > 540 and outTipFlat.Y < outerPtr.Y,
	'pointer outside ellipsoid clamps onto exact projected ellipsoid boundary')
local sideEllipsoid = C.new(V3.zero) * flatBase.Rotation * C.Angles(0, math.pi / 2, 0)
local outTipSide, _, outClampedSide = Brush.ProjectToEllipsoid(sideEllipsoid, testRadii, outerRay.Origin, outerRay.Direction, outerPtr, camPos, projectToScreen)
check(outClampedSide and (outTipSide.Y - 540) < (outTipFlat.Y - 540) * 0.6,
	'rotating body onto its narrow side smoothly narrows the ellipsoid brush region')

-- 4. 历史射线兼容验证（旧平面回退）。
local world = require('./PaintingWorld')
local displayed = R.Instance.new('Model')
local flatPart = R.Instance.new('Part')
flatPart.Name, flatPart.Size = 'UpperTorso', V3.new(2, 2, 0.5)
flatPart:SetAttribute('Paintable', true)
local backPose = C.Angles(0, math.pi, 0)
flatPart.CFrame = backPose
flatPart.Parent = displayed
world.part = flatPart
local orthoCam = {
	CFrame = C.identity,
	ViewportSize = viewport,
	WorldToScreenPoint = function(_, p) return V3.new(p.X, p.Y, 10) end,
	ScreenPointToRay = function(_, x, y) return { Origin = V3.new(x, y, -10), Direction = V3.zAxis } end,
}
local histResolve = Brush.Resolver(displayed, orthoCam, C.identity, { center = V3.zero, rest = C.identity, radius = 2 }, backPose)
local frontHit, backHit = histResolve.cast(C.identity, V.zero), histResolve.cast(backPose, V.zero)
check(frontHit and backHit and frontHit.sample.face == 1 and backHit.sample.face == 2,
	'historical rays use their original orientation while casting against the current displayed model')
displayed:Destroy()

-- 5. 多部件带凹处白膜（躯干 + 双臂 + 头 + 下躯干 + 双腿）完整横截面旋转 + 服务端进度同步验证！
local bodyModel = R.Instance.new('Model')
local offsets = {
	UpperTorso = V3.new(0, 0.2, 0),
	LowerTorso = V3.new(0, -0.75, 0),
	Head = V3.new(0, 1.55, 0),
	LeftUpperArm = V3.new(-1.18, 0.35, 0),
	RightUpperArm = V3.new(1.18, 0.35, 0),
	LeftLowerArm = V3.new(-1.25, -0.55, 0),
	RightLowerArm = V3.new(1.25, -0.55, 0),
	LeftUpperLeg = V3.new(-0.42, -1.55, 0),
	RightUpperLeg = V3.new(0.42, -1.55, 0),
	LeftLowerLeg = V3.new(-0.42, -2.55, 0),
	RightLowerLeg = V3.new(0.42, -2.55, 0),
}
local bodyParts, bodyFrames = {}, {}
local meshFacing = C.Angles(0, math.pi, 0)
for name, off in offsets do
	local p = R.Instance.new('Part')
	p.Name = name
	p.Size = Data.Parts[name].size
	p:SetAttribute('Paintable', true)
	p:SetAttribute('SurfaceVersion', Curve.Version)
	p:SetAttribute('RestPose', C.new(off) * meshFacing)
	p.CFrame = flatBase * C.new(off) * meshFacing
	p.Parent = bodyModel
	bodyParts[name] = p
	bodyFrames[name] = C.new(meshFacing:VectorToObjectSpace(off - offsets.UpperTorso))
end
local bodyGeometry = Rotation.Create(bodyModel, bodyFrames)
local function setBodyPose(ori)
	local rotated = Rotation.Pose(flatBase, bodyGeometry, ori)
	local support = rotated * bodyGeometry.rest
	for name, f in bodyFrames do
		bodyParts[name].CFrame = support * f
	end
end
local serverBody = {
	FindFirstChild = function(_, n) return bodyModel:FindFirstChild(n) end,
	GetChildren = function(_) return bodyModel:GetChildren() end,
	PivotTo = function(_, cf)
		local support = cf * bodyGeometry.rest
		for name, f in bodyFrames do
			bodyParts[name].CFrame = support * f
		end
	end,
}
local totalBodyArea = Surface.Total(bodyModel)
local interiorCovered = {}
local excludedArea = Curve.ExcludeInterior(bodyModel, interiorCovered)
local effectiveArea = totalBodyArea - excludedArea

-- 5a. 绕长轴（头-脚）旋转 360°：胸部/腋下横截面必须完整覆盖手臂外侧、手臂内侧以及被手臂遮挡的躯干左右侧面！
Config.PaintRotationEnabled = true
local function runRoll(fps, pointer)
	local curFrame = nil
	local collected = {}
	for tick = 0, fps do
		local ori = C.Angles(0, 2 * math.pi * tick / fps, 0)
		setBodyPose(ori)
		local res = Brush.Resolver(bodyModel, perspCam, flatBase, bodyGeometry, ori)
		local samples, nextF = Brush.SamplePath(curFrame, pointer, ori, bodyGeometry.radius, res, viewport, V3.new(-1, 0, 0))
		curFrame = nextF
		for _, s in samples do table.insert(collected, s) end
	end
	return collected
end

-- 指针拖到外侧 (960, 880) 加速绕长轴旋转，且横截面穿过胸口与双上臂（把指针 X 放在胸口中心上方）。
local chestScreen = projectToScreen(flatBase:PointToWorldSpace(V3.new(0, 0.35, 0)))
assert(chestScreen, 'chest projection fixture')
local rollSamples60 = runRoll(60, V.new(chestScreen.X, chestScreen.Y + 320))
local rollSamples30 = runRoll(30, V.new(chestScreen.X, chestScreen.Y + 320))

-- 检查是否真的画到了被手臂遮挡的躯干左侧/右侧凹处以及左右上臂内侧！
local sawTorsoLeftConcave, sawTorsoRightConcave = false, false
local sawLeftArmInner, sawRightArmInner = false, false
for _, s in rollSamples60 do
	local p = bodyParts[s.part]
	local lp = meshFacing:VectorToWorldSpace(Curve.Point(p, s))
	if s.part == 'UpperTorso' then
		if lp.X < -p.Size.X * 0.42 then sawTorsoLeftConcave = true end
		if lp.X > p.Size.X * 0.42 then sawTorsoRightConcave = true end
	elseif s.part == 'LeftUpperArm' then
		if lp.X > p.Size.X * 0.35 then sawLeftArmInner = true end
	elseif s.part == 'RightUpperArm' then
		if lp.X < -p.Size.X * 0.35 then sawRightArmInner = true end
	end
end
check(sawTorsoLeftConcave and sawTorsoRightConcave, 'roll cross-section paints both concave torso sides hidden behind arms')
check(sawLeftArmInner and sawRightArmInner, 'roll cross-section paints inner surfaces of both arms facing the torso')

-- 对比 30 FPS 与 60 FPS 覆盖一致性，以及服务端 Painting.Apply 100% 接收率与进度准确性。
local function stampOnServer(sampleList)
	setBodyPose(C.identity)
	local session = { token = 's', sequence = 0, last = 0, orientation = C.identity, geometry = bodyGeometry }
	local item = { model = serverBody, covered = table.clone(interiorCovered), area = 0, totalArea = effectiveArea, paintSeconds = 0, progress = 0, strokes = {}, strokePoints = 0 }
	local seq = 0
	for i = 1, #sampleList, Config.PaintCoverageBatchSize do
		local batch = {}
		for j = i, math.min(#sampleList, i + Config.PaintCoverageBatchSize - 1) do
			table.insert(batch, sampleList[j])
		end
		seq += 1
		local lastOri = batch[#batch].orientation or C.identity
		Painting.Apply(session, item, { sequence = seq, orientation = lastOri, samples = batch }, flatBase, camPos, seq * 0.1)
	end
	return item.area, item.covered
end

local rollArea60 = stampOnServer(rollSamples60)
local rollArea30 = stampOnServer(rollSamples30)
check(rollArea60 > 1.2 and math.abs(rollArea60 - rollArea30) / rollArea60 < 0.08,
	'30/60 FPS roll cross-sections agree closely and cover full chest+arms perimeter')

-- 5b. 绕横轴（左右肩）前后翻滚 360°：头部 + 脖颈凹处 + 躯干 + 下躯干完整闭合覆盖，且服务端覆盖与理想覆盖一致。
local pitchFrame = nil
local pitchSamples = {}
for tick = 0, 72 do
	local ori = C.Angles(2 * math.pi * tick / 72, 0, 0)
	setBodyPose(ori)
	local res = Brush.Resolver(bodyModel, perspCam, flatBase, bodyGeometry, ori)
	local samples, nextF = Brush.SamplePath(pitchFrame, V.new(960, 540), ori, bodyGeometry.radius, res, viewport, V3.new(0, 0, 1))
	pitchFrame = nextF
	for _, s in samples do table.insert(pitchSamples, s) end
end
local pitchArea = stampOnServer(pitchSamples)
local idealPitchCovered = table.clone(interiorCovered)
local idealPitchArea = 0
for _, s in pitchSamples do
	local _, a = Surface.Stamp(bodyParts[s.part], s, idealPitchCovered)
	idealPitchArea += a
end
check(pitchArea > 1.2, 'pitch 360 cross-section covers head, neck hollow, torso and pelvis completely (was only 0.78 before)')
check(pitchArea >= idealPitchArea * 0.98, 'server records full cross-section progress without dropping concave samples')

-- 5c. 仅旋转 12° 时，背面绝不会提前被画到。
local smallFrame = nil
local smallSamples = {}
for tick = 0, 2 do
	local ori = C.Angles(0, math.rad(6 * tick), 0)
	setBodyPose(ori)
	local res = Brush.Resolver(bodyModel, perspCam, flatBase, bodyGeometry, ori)
	local samples, nextF = Brush.SamplePath(smallFrame, V.new(chestScreen.X, chestScreen.Y), ori, bodyGeometry.radius, res, viewport, V3.new(-1, 0, 0))
	smallFrame = nextF
	for _, s in samples do table.insert(smallSamples, s) end
end
setBodyPose(C.Angles(0, math.rad(12), 0))
local pivotW = flatBase:PointToWorldSpace(bodyGeometry.center)
for _, s in smallSamples do
	local wp = bodyParts[s.part].CFrame:PointToWorldSpace(Curve.Point(bodyParts[s.part], s))
	check((wp - pivotW).Y > -0.25, 'small front rotation never paints the opposite back side prematurely')
end

-- 5d. 旋转同时沿转轴移动画笔（从头滑到脚），扫出连续多片横截面覆盖头、躯干、双腿。
local spiralFrame = nil
local spiralParts = {}
for tick = 0, 36 do
	local ori = C.Angles(0, 2 * math.pi * tick / 36, 0)
	setBodyPose(ori)
	local res = Brush.Resolver(bodyModel, perspCam, flatBase, bodyGeometry, ori)
	local sx = 680 + (1240 - 680) * (tick / 36)
	local samples, nextF = Brush.SamplePath(spiralFrame, V.new(sx, 540), ori, bodyGeometry.radius, res, viewport, V3.new(-1, 0, 0))
	spiralFrame = nextF
	for _, s in samples do spiralParts[s.part] = true end
end
check(spiralParts.Head and spiralParts.UpperTorso and (spiralParts.LeftUpperLeg or spiralParts.RightUpperLeg),
	'sliding brush along the rotation axis inside the ellipsoid paints continuously from head through torso to legs')

Config.PaintRotationEnabled = false
-- 5e. 非旋转模式关闭椭圆体钳制（解除头部/脚部/上臂 0.96 盲区）且不附带 sample.orientation；动态切换开关即刻生效。
do
	setBodyPose(C.identity)
	local flatRes = Brush.Resolver(bodyModel, perspCam, flatBase, bodyGeometry, C.identity)
	local headEdgeWorld = bodyParts.Head.CFrame:PointToWorldSpace(V3.new(0, bodyParts.Head.Size.Y * 0.4, bodyParts.Head.Size.Z * 0.42))
	local headEdgePtr = projectToScreen(headEdgeWorld)
	assert(headEdgePtr, 'head edge projection fixture')
	local _, _, wouldClamp = flatRes.ellipsoidPoint(C.identity, headEdgePtr)
	check(wouldClamp and flatRes.cast(C.identity, headEdgePtr) ~= nil,
		'fixture point on head edge lies outside 0.96 ellipsoid while still hitting head mesh')

	local flatSamples, flatFrame = Brush.SamplePath(nil, headEdgePtr, C.identity, bodyGeometry.radius, flatRes, viewport, nil)
	check(not flatFrame.clamped and flatFrame.tip == headEdgePtr and flatFrame.brushWorld == nil,
		'PaintRotationEnabled == false never clamps pointer outside ellipsoid')
	check(#flatSamples == 1 and flatSamples[1].part == 'Head' and flatSamples[1].orientation == nil,
		'flat mode hits blind-spot head area and omits redundant sample.orientation')

	local headDragPtr = V.new(headEdgePtr.X + 8, headEdgePtr.Y)
	local flatDragSamples, flatDragFrame = Brush.SamplePath(flatFrame, headDragPtr, C.identity, bodyGeometry.radius, flatRes, viewport, nil)
	check(not flatDragFrame.clamped and flatDragFrame.tip == headDragPtr and #flatDragSamples > 0,
		'flat mode drag continues un-clamped across mesh')
	for _, sample in flatDragSamples do
		check(sample.orientation == nil, 'flat mode drag samples omit sample.orientation')
	end

	local _, outerFlatFrame = Brush.SamplePath(nil, outerPtr, C.identity, bodyGeometry.radius, flatRes, viewport, nil)
	check(not outerFlatFrame.clamped and outerFlatFrame.tip == outerPtr,
		'far outer pointer stays un-clamped when PaintRotationEnabled == false')

	-- 动态开启旋转：不重加载模块，同一点立刻被椭圆体钳制并携带 sample.orientation。
	Config.PaintRotationEnabled = true
	local rotSamples, rotFrame = Brush.SamplePath(nil, headEdgePtr, C.identity, bodyGeometry.radius, flatRes, viewport, nil)
	check(rotFrame.clamped and (rotFrame.tip - headEdgePtr).Magnitude > 1 and rotFrame.brushWorld ~= nil,
		'PaintRotationEnabled == true dynamically restores ellipsoid clamping')
	check(#rotSamples == 1 and rotSamples[1].orientation == C.identity,
		'PaintRotationEnabled == true attaches sample.orientation on first hit')

	local insideBodyPtr = V.new(chestScreen.X, chestScreen.Y)
	local _, insideStartFrame = Brush.SamplePath(nil, insideBodyPtr, C.identity, bodyGeometry.radius, flatRes, viewport, nil)
	local turnedPose = C.Angles(0, 0.08, 0)
	setBodyPose(turnedPose)
	local turnedRes = Brush.Resolver(bodyModel, perspCam, flatBase, bodyGeometry, turnedPose)
	local rotDragSamples, rotDragFrame = Brush.SamplePath(insideStartFrame, insideBodyPtr + V.new(0, 24), turnedPose, bodyGeometry.radius, turnedRes, viewport, V3.new(-1, 0, 0))
	check(not rotDragFrame.clamped and #rotDragSamples > 0, 'rotated drag produces samples')
	for _, sample in rotDragSamples do
		check(sample.orientation ~= nil, 'PaintRotationEnabled == true attaches sample.orientation on drag/slice samples')
	end
	Config.PaintRotationEnabled = false
end
bodyModel:Destroy()

-- 6. 工作台零重力物理生命周期与服务端动态姿态重建校验。
do
	local fs = require('@lune/fs')
	local Pose = require('./PaintBodyPose')
	local source = R.deserializeModel(fs.readFile('Assets/Models/GameModels.rbxm'))[1].Characters.WhiteR15
	local motors = {}
	local rootDrive = nil
	for _, node in source:GetDescendants() do
		if node:IsA('Motor6D') then
			table.insert(motors, node)
			if node.Name == 'Root' or node.Name == 'RootJoint' then
				rootDrive = node
			else
				local a, b = R.Instance.new('Attachment'), R.Instance.new('Attachment')
				a.CFrame, a.Parent = node.C0, node.Part0
				b.CFrame, b.Parent = node.C1, node.Part1
				local socket = R.Instance.new('BallSocketConstraint')
				socket.Name, socket.Attachment0, socket.Attachment1, socket.UpperAngle, socket.MaxFrictionTorque, socket.Parent = node.Name, a, b, 75, 20, source
			end
		end
	end
	for _ = 1, 8 do
		for _, motor in motors do
			motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
		end
	end
	source.UpperTorso:SetAttribute('RestPose', C.new(0, 0.2, 0))
	local clone = source:Clone()
	local cloneRootDrive = nil
	for _, node in clone:GetDescendants() do
		if node:IsA('Motor6D') and (node.Name == 'Root' or node.Name == 'RootJoint') then
			cloneRootDrive = node
		elseif node:IsA('BasePart') then
			node.Massless = true
			node.AssemblyMass = node.Size.X * node.Size.Y * node.Size.Z
		end
	end
	assert(rootDrive and cloneRootDrive, 'R15 template requires Root Motor6D')
	local Physics = require('./PhysicsConfig')
	local tableView = Presentation.new()
	tableView:Attach(source, clone, cloneRootDrive, nil)
	check(#tableView.sockets == 14, 'Attach caches all 14 BallSocketConstraints')
	local forceCount = 0
	local alignCount = 0
	for part, force in tableView.antiGravity do
		forceCount += 1
		check(force:IsA('VectorForce') and force.ApplyAtCenterOfMass and force.RelativeTo == R.Enum.ActuatorRelativeTo.World and not force.Enabled,
			'each dynamic limb gets a disabled world center-of-mass VectorForce before activation')
		check(not part.Massless and part.Anchored, 'limb restores real mass and starts anchored')
		local align = tableView.aligners[part]
		if align then
			alignCount += 1
			check(align:IsA('AlignOrientation') and align.Mode == R.Enum.OrientationAlignmentMode.OneAttachment and not align.RigidityEnabled and not align.Enabled,
				'each dynamic limb gets a soft OneAttachment AlignOrientation before activation')
		end
	end
	check(forceCount == 14 and alignCount == 14, 'all 14 non-torso limbs receive anti-gravity forces and pose aligners')
	check(tableView.parts.HumanoidRootPart.Massless and tableView.parts.UpperTorso.Anchored, 'HumanoidRootPart stays massless and UpperTorso stays anchored')

	-- 默认物理与旋转均关闭：操作者更新仍保持全身锚定躺平，不启用球窝或零重力约束。
	tableView.targetOrientation = C.Angles(0, 0.5, 0)
	tableView:Update(flatBase, 0.016, true)
	check(not tableView.dynamic and not tableView.spinning and tableView.orientation == C.identity and tableView:CapturePose() == nil,
		'disabled physics and rotation switches keep table body static and flat during operator painting')
	for _, part in tableView.parts do
		check(part.Anchored, 'all body parts remain anchored when PaintPhysicsEnabled is false: ' .. part.Name)
	end
	for _, socket in tableView.sockets do
		check(not socket.Enabled, 'BallSocketConstraints stay disabled when PaintPhysicsEnabled is false')
	end
	for _, force in tableView.antiGravity do
		check(not force.Enabled, 'VectorForces stay disabled when PaintPhysicsEnabled is false')
	end

	-- 开启旋转与物理开关后验证完整零重力物理生命周期。
	Config.PaintRotationEnabled = true
	Config.PaintPhysicsEnabled = true

	-- 静止切入动态模式：仅 UpperTorso 锚定，纯零重力，处于恢复态。
	tableView.targetOrientation = C.identity
	tableView:Update(flatBase, 0.016, true)
	check(tableView.dynamic and not tableView.spinning, 'stationary operator update enters non-spinning dynamic mode')
	check(tableView.parts.UpperTorso.Anchored, 'UpperTorso remains anchored as rotation pivot')
	for name, part in tableView.parts do
		if name ~= 'UpperTorso' then
			check(not part.Anchored, 'dynamic limb is unanchored: ' .. name)
		end
	end
	for _, socket in tableView.sockets do
		check(socket.Enabled and math.abs(socket.MaxFrictionTorque - 20 * Physics.TableRecoverFrictionScale) < 1e-4,
			'BallSocketConstraint enabled with recover friction when stationary')
	end
	for part, force in tableView.antiGravity do
		check(force.Enabled, 'VectorForce enabled in dynamic mode')
		local expectedY = part.AssemblyMass * 196.2
		check(math.abs(force.Force.X) < 1e-5 and math.abs(force.Force.Z) < 1e-5 and math.abs(force.Force.Y - expectedY) < 1e-3,
			'VectorForce exactly cancels world gravity when stationary for ' .. part.Name)
	end
	local captured = tableView:CapturePose()
	check(captured ~= nil and Pose.Validate(source, captured), 'CapturePose produces a valid dynamic BodyPose')

	-- 连续旋转步进：切入甩动态（极低摩擦 + 径向离心外甩力 + 柔顺回中）。
	local spinOrientation = C.Angles(0, 0.14, 0)
	tableView.targetOrientation = spinOrientation
	tableView:Update(flatBase, 0.016, true)
	check(tableView.spinning, 'active rotation enters spinning fling state')
	for _, socket in tableView.sockets do
		check(math.abs(socket.MaxFrictionTorque - 20 * Physics.TableSpinFrictionScale) < 1e-4,
			'spinning lowers joint friction so limbs fling freely')
	end
	local centrifugalCount = 0
	for part, force in tableView.antiGravity do
		local expectedY = part.AssemblyMass * 196.2
		local extra = force.Force - V3.new(0, expectedY, 0)
		if extra.Magnitude > 1e-3 then
			centrifugalCount += 1
		end
		local align = tableView.aligners[part]
		check(align.Enabled and align.Responsiveness == Physics.TableSpinAlignResponsiveness,
			'spinning relaxes AlignOrientation responsiveness')
	end
	check(centrifugalCount >= 8, 'spinning applies radial centrifugal fling force to off-axis limbs')

	-- 停止旋转：立即切回恢复态（撤除离心力、恢复纯零重力、提高回中刚度并指向当前朝向的端正姿态）。
	tableView:Update(flatBase, 0.016, true)
	check(not tableView.spinning, 'stopping rotation leaves spinning state immediately')
	for _, socket in tableView.sockets do
		check(math.abs(socket.MaxFrictionTorque - 20 * Physics.TableRecoverFrictionScale) < 1e-4,
			'stopping rotation restores recover damping friction')
	end
	local supportAtStop = Rotation.Pose(flatBase, tableView.geometry, spinOrientation) * tableView.geometry.rest
	for part, force in tableView.antiGravity do
		local expectedY = part.AssemblyMass * 196.2
		check((force.Force - V3.new(0, expectedY, 0)).Magnitude < 1e-3,
			'stopping rotation removes centrifugal force and restores pure zero gravity')
		local align = tableView.aligners[part]
		local expectedRot = (supportAtStop * tableView.restBodyPose[part.Name]).Rotation
		check(align.Enabled and align.Responsiveness == Physics.TableRecoverResponsiveness
			and Rotation.Distance(align.CFrame, expectedRot) < 1e-4,
			'stopping rotation drives AlignOrientation toward rest pose at current orientation')
	end

	-- 单帧大角度重置跳变不触发甩动。
	tableView.targetOrientation = C.Angles(0, math.pi, 0)
	tableView:Update(flatBase, 0.016, true)
	check(not tableView.spinning, 'large single-frame reset jump does not trigger centrifugal fling')

	-- 切回旁观/静态模式与 Clear 后：零重力、回中约束与球窝全部关闭/清理。
	tableView:Update(flatBase, 0.016, false)
	check(not tableView.dynamic and not tableView.spinning, 'observer update returns to anchored static mode')
	for _, socket in tableView.sockets do
		check(not socket.Enabled, 'BallSocketConstraint disabled when leaving dynamic mode')
	end
	for _, force in tableView.antiGravity do
		check(not force.Enabled and force.Force == V3.zero, 'VectorForce disabled when leaving dynamic mode')
	end
	for _, align in tableView.aligners do
		check(not align.Enabled and align.MaxTorque == 0, 'AlignOrientation disabled when leaving dynamic mode')
	end
	for _, part in tableView.parts do
		check(part.Anchored, 'all parts re-anchored when leaving dynamic mode')
	end
	tableView:Clear()
	check(clone:FindFirstChild('TableZeroGravityForce', true) == nil
		and clone:FindFirstChild('TableZeroGravityAttachment', true) == nil
		and clone:FindFirstChild('TablePoseAlign', true) == nil,
		'Clear destroys temporary anti-gravity and pose align instances cleanly')

	-- 服务端 Painting.Apply 校验并重建动态 bodyPose，拒绝非法拆解姿态。
	local neck = nil
	for _, motor in motors do
		if motor.Name == 'Neck' then neck = motor end
	end
	local initialFrames = Pose.Capture(source)
	local bentFrames = table.clone(initialFrames)
	local tiltedHead = neck.Part0.CFrame * neck.C0 * C.Angles(0.25, 0, 0) * neck.C1:Inverse()
	bentFrames.Head = source.UpperTorso.CFrame:ToObjectSpace(tiltedHead)
	check(Pose.Validate(source, bentFrames), 'tilted head pose passes validation')
	local physSession = {
		player = {}, id = 'phys-body', token = 'phys', last = 0, sequence = 0,
		orientation = C.identity, walkSpeed = 16, jumpPower = 50, jumpHeight = 7.2,
		geometry = Rotation.Create(source, initialFrames),
	}
	local physItem = {
		id = 'phys-body', kind = 'Body', stage = 'Painting', location = 'Table', version = 1,
		model = source, covered = {}, area = 0, totalArea = 100, paintSeconds = 0,
		progress = 0, strokes = {}, strokePoints = 0, poseBody = initialFrames,
	}
	local applied = Painting.Apply(physSession, physItem, {
		action = 'Paint', session = 'phys', sequence = 1, samples = {},
		orientation = C.identity, bodyPose = bentFrames,
	}, flatBase, camPos, 1)
	check(applied ~= nil and physItem.poseBody ~= nil and (physItem.poseBody.Head.Position - bentFrames.Head.Position).Magnitude < 1e-5,
		'Painting.Apply accepts and stores valid dynamic bodyPose')
	local expectedHead = Rotation.Pose(flatBase, physSession.geometry, C.identity) * physSession.geometry.rest * bentFrames.Head
	check((source.Head.CFrame.Position - expectedHead.Position).Magnitude < 1e-4,
		'Painting.Apply reconstructs authoritative server limb CFrame from dynamic bodyPose')
	local badFrames = table.clone(bentFrames)
	badFrames.Head = badFrames.Head + V3.new(3, 0, 0)
	Painting.Apply(physSession, physItem, {
		action = 'Paint', session = 'phys', sequence = 2, samples = {},
		orientation = C.identity, bodyPose = badFrames,
	}, flatBase, camPos, 2)
	check((physItem.poseBody.Head.Position - bentFrames.Head.Position).Magnitude < 1e-5,
		'Painting.Apply rejects detached invalid bodyPose and keeps previous valid pose')

	Config.PaintRotationEnabled = false
	Config.PaintPhysicsEnabled = false
	local furtherTilted = neck.Part0.CFrame * neck.C0 * C.Angles(0.45, 0, 0) * neck.C1:Inverse()
	local ignoredFrames = table.clone(initialFrames)
	ignoredFrames.Head = source.UpperTorso.CFrame:ToObjectSpace(furtherTilted)
	Painting.Apply(physSession, physItem, {
		action = 'Paint', session = 'phys', sequence = 3, samples = {},
		orientation = C.Angles(0, 0.8, 0), bodyPose = ignoredFrames,
	}, flatBase, camPos, 3)
	check(physSession.orientation == C.identity and (physItem.poseBody.Head.Position - bentFrames.Head.Position).Magnitude < 1e-5,
		'disabled PaintRotationEnabled and PaintPhysicsEnabled ignore incoming rotation and bodyPose on server')

	clone:Destroy()
	source:Destroy()
end

print('PASS: ' .. checks .. ' paint rotation, 3D ellipsoid region, concave cross-section, zero-gravity table physics and server sync assertions')
