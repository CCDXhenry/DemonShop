-- 固定视角工具 FixedCamera、PaintCamera 与 Scene.CameraPose 精简自动化单测
local B = require('./FixedCameraBoundary')
local R = B.R
local Instance = R.Instance
local CFrame = R.CFrame
local Vector3 = R.Vector3
local Enum = R.Enum

local FixedCamera = require('./FixedCamera')
local PaintCamera = require('./PaintCamera')
local PaintRotation = require('./PaintRotation')

local count = 0
local function check(cond: boolean, msg: string)
	assert(cond, msg)
	count += 1
end

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-4)
end

local function nearVec(a: Vector3, b: Vector3, eps: number?): boolean
	return (a - b).Magnitude <= (eps or 1e-4)
end

local function nearCF(a: CFrame, b: CFrame, eps: number?): boolean
	local tol = eps or 1e-4
	return (a.Position - b.Position).Magnitude <= tol
		and (a.LookVector - b.LookVector).Magnitude <= tol
		and (a.UpVector - b.UpVector).Magnitude <= tol
end

-- 1. FixedCamera：IsMarker、FindMarker（自定义命名与默认名）、ReadSettings 防御、GetPose/GetCFrame、HideMarker
do
	local station = Instance.new('Model')
	station.Name = 'RuneBodyTable'

	local customNamed = Instance.new('Part')
	customNamed.Name = 'TableCamView'
	customNamed:SetAttribute('CameraMarker', true)
	customNamed:SetAttribute('FOV', 45)
	customNamed:SetAttribute('TransitionDuration', 0.22)
	customNamed.Transparency = 0.5
	customNamed.CanCollide = true
	customNamed.CanTouch = true
	customNamed.CanQuery = true
	customNamed.CastShadow = true
	local markerCF = CFrame.lookAt(Vector3.new(-16, 13, 9), Vector3.new(-16, 4.5, 15))
	customNamed.CFrame = markerCF
	customNamed.Parent = station

	check(FixedCamera.IsMarker(customNamed), 'IsMarker recognizes Part with CameraMarker=true regardless of Name')
	check(FixedCamera.FindMarker(station) == customNamed, 'FindMarker prioritizes CameraMarker=true inside container')

	local defaultNamed = Instance.new('Part')
	defaultNamed.Name = 'CameraMarker'
	check(FixedCamera.IsMarker(defaultNamed), 'IsMarker recognizes Part named CameraMarker even without attribute')

	local settings = FixedCamera.ReadSettings(customNamed)
	check(near(settings.FOV, 45) and near(settings.TransitionDuration, 0.22),
		'ReadSettings reads direct FOV and TransitionDuration attributes')

	customNamed:SetAttribute('FOV', 0 / 0)
	customNamed:SetAttribute('TransitionDuration', -2)
	local sanitized = FixedCamera.ReadSettings(customNamed, 50, 0.3)
	check(near(sanitized.FOV, 50) and near(sanitized.TransitionDuration, 0),
		'ReadSettings sanitizes NaN FOV and clamps negative duration')

	customNamed:SetAttribute('FOV', 45)
	customNamed:SetAttribute('TransitionDuration', 0.22)
	local pose, fov, dur, found = FixedCamera.GetPose(station)
	check(found == customNamed and pose ~= nil and nearCF(pose :: CFrame, markerCF) and near(fov, 45) and near(dur, 0.22),
		'GetPose returns marker CFrame, FOV, TransitionDuration, and marker ref')

	local fallbackCF = CFrame.new(1, 2, 3)
	local emptyModel = Instance.new('Model')
	local fbPose, fbFov, fbDur, fbMarker = FixedCamera.GetPose(emptyModel, fallbackCF, 48, 0.4)
	check(fbMarker == nil and fbPose ~= nil and nearCF(fbPose :: CFrame, fallbackCF) and near(fbFov, 48) and near(fbDur, 0.4),
		'GetPose falls back cleanly when marker is absent')

	FixedCamera.HideInContainer(station)
	check(customNamed.Transparency == 1 and not customNamed.CanCollide and not customNamed.CanTouch
		and not customNamed.CanQuery and not customNamed.CastShadow,
		'HideInContainer hides marker and disables collision/query/shadow')

	local district = Instance.new('Folder')
	local sub = Instance.new('Model')
	sub.Parent = district
	local extraMarker = Instance.new('Part')
	extraMarker.Name = 'CameraMarker'
	extraMarker.Transparency = 0.5
	extraMarker.CanCollide = true
	extraMarker.Parent = sub
	local hiddenCount = FixedCamera.HideAll(district)
	check(hiddenCount == 1 and extraMarker.Transparency == 1 and not extraMarker.CanCollide,
		'HideAll hides all markers in subtree')

	local streamedSignal = B.CreateSignal()
	local watchHost = {
		DescendantAdded = streamedSignal,
		GetDescendants = function() return {} end,
		IsA = function() return false end,
		GetAttribute = function() return nil end,
	}
	local stopWatch = FixedCamera.WatchAndHide(watchHost :: any)
	local lateMarker = Instance.new('Part')
	lateMarker.Name = 'LateMarker'
	lateMarker:SetAttribute('CameraMarker', true)
	lateMarker.Transparency = 0.5
	lateMarker.CanQuery = true
	streamedSignal:Fire(lateMarker)
	check(lateMarker.Transparency == 1 and not lateMarker.CanQuery,
		'WatchAndHide automatically hides markers streamed in after init')
	stopWatch()
	check(streamedSignal:ActiveCount() == 0, 'WatchAndHide cleanup disconnects DescendantAdded listener')
end

-- 2. PaintCamera：EnterMarker、Play 热调 CFrame/FOV、FollowToss 暂停热调、退出与回退
do
	local camObj = {
		CFrame = CFrame.new(0, 10, 20),
		FieldOfView = 70,
		CameraType = Enum.CameraType.Custom,
		CameraSubject = B.LocalHumanoid,
	}
	B.SetCurrentCamera(camObj)

	local tableModel = Instance.new('Model')
	tableModel.Name = 'RuneBodyTable'
	local rawMarker = Instance.new('Part')
	rawMarker.Name = 'CameraMarker'
	rawMarker:SetAttribute('CameraMarker', true)
	rawMarker:SetAttribute('FOV', 45)
	rawMarker:SetAttribute('TransitionDuration', 0.22)
	rawMarker.Transparency = 0.5
	local targetCF = CFrame.lookAt(Vector3.new(-16, 13, 9), Vector3.new(-16, 4.5, 15))
	rawMarker.CFrame = targetCF
	rawMarker.Parent = tableModel

	local paintCam = PaintCamera.new()
	local fallbackPose = CFrame.new(5, 6, 7)
	paintCam:EnterMarker(tableModel, fallbackPose, 45)
	check(paintCam.saved ~= nil and camObj.CameraType == Enum.CameraType.Scriptable and rawMarker.Transparency == 1,
		'PaintCamera:EnterMarker saves camera state, sets Scriptable, and hides CameraMarker')
	check(not paintCam.ready, 'PaintCamera is not ready before tween finishes')
	B.CompletePendingTweens()
	check(paintCam.ready and nearCF(camObj.CFrame, targetCF) and near(camObj.FieldOfView, 45),
		'PaintCamera completes transition to CameraMarker.CFrame and FOV')

	paintCam:Exit(true)
	check(paintCam.saved == nil and not paintCam.ready and camObj.CameraType == Enum.CameraType.Custom
		and near(camObj.FieldOfView, 70) and nearCF(camObj.CFrame, CFrame.new(0, 10, 20)),
		'PaintCamera:Exit(true) restores original camera pose, FOV, subject, and CameraType')

	-- 使用信号代理验证 Play 下热调与 FollowToss 暂停热调
	local wrappedMarker, propSignals, attrSignals = B.WrapSignalHost(rawMarker)
	local fakeContainer = {
		IsA = function(_s, cls) return cls == 'Model' end,
		GetChildren = function() return { wrappedMarker } end,
		GetDescendants = function() return { wrappedMarker } end,
		FindFirstChild = function(_s, name)
			if name == 'CameraMarker' then return wrappedMarker end
			return nil
		end,
	}

	local hotCtrl = PaintCamera.new()
	hotCtrl:EnterMarker(fakeContainer :: any, fallbackPose, 45)
	B.CompletePendingTweens()
	check(hotCtrl.ready, 'Hot-reload controller reaches ready state')

	local movedCF = CFrame.lookAt(Vector3.new(-14, 15, 7), Vector3.new(-16, 4.5, 15))
	wrappedMarker.CFrame = movedCF
	check(nearCF(camObj.CFrame, movedCF), 'Hot-reload updates live camera CFrame when CameraMarker moves')

	rawMarker:SetAttribute('FOV', 52)
	attrSignals['FOV']:Fire()
	check(near(camObj.FieldOfView, 52), 'Hot-reload updates live camera FOV when FOV attribute changes')

	B.SetServerTime(100)
	hotCtrl:FollowToss(101, function() return Vector3.new(0, 4, 0) end)
	check(hotCtrl.follow ~= nil and not hotCtrl.ready, 'FollowToss suspends ready state')
	wrappedMarker.CFrame = CFrame.lookAt(Vector3.new(-99, 99, 99), Vector3.zero)
	check(nearCF(camObj.CFrame, movedCF), 'FollowToss suspends hot-reload so marker changes do not hijack toss camera')

	hotCtrl:StepToss(100.5, 0.016)
	check(camObj.CFrame.Position.Y <= 15.8 + 1e-4, 'StepToss enforces safe ceiling height')
	hotCtrl:StepToss(101.1, 0.016)
	check(hotCtrl.saved == nil and hotCtrl.follow == nil and camObj.CameraType == Enum.CameraType.Custom,
		'Completing FollowToss restores camera and clears state')
	check(propSignals['CFrame']:ActiveCount() == 0 and attrSignals['FOV']:ActiveCount() == 0,
		'Restoring camera disconnects all hot-reload signals')

	local emptyModel = Instance.new('Model')
	hotCtrl:EnterMarker(emptyModel, fallbackPose, 48)
	B.CompletePendingTweens()
	check(hotCtrl.ready and nearCF(camObj.CFrame, fallbackPose) and near(camObj.FieldOfView, 48),
		'EnterMarker falls back cleanly when CameraMarker is absent')
	hotCtrl:Destroy()
	check(hotCtrl.saved == nil and camObj.CameraType == Enum.CameraType.Custom,
		'Destroy restores camera cleanly')
end

-- 3. 服务端 Scene.CameraPose 一致性与缺失回退
do
	local SB = require('./StationPotionBoundary')
	local station = SB.workspace:FindFirstChild('NeonContractDistrict'):FindFirstChild('RuneBodyTable')
	local anchor = station:FindFirstChild('BodyPlacementAnchor') :: BasePart
	local Scene = require('./CameraScene')
	local marker = station:FindFirstChild('CameraMarker') :: BasePart

	check(marker.Transparency == 1, 'Server Scene hides CameraMarker on boot')
	check(nearCF(Scene.CameraPose(1), marker.CFrame) and nearCF(Scene.CameraPose(5), marker.CFrame),
		'Scene.CameraPose locks both single and batch (5) bodies to CameraMarker.CFrame')
	marker:Destroy()
	local fallback = PaintRotation.CameraPose(anchor.Position, 1)
	check(nearVec(Scene.CameraPose(1).Position, fallback.Position) and nearVec(Scene.CameraPose(5).Position, fallback.Position),
		'Scene.CameraPose falls back to single-body PaintRotation.CameraPose when marker is absent')
end

print(string.format('PASS: %d FixedCamera, PaintCamera, and Scene.CameraPose tests', count))
