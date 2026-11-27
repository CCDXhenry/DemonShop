-- 固定视角机位工具（单 Part + 直接 Attribute：识别、运行期隐藏、平滑聚焦、Play 热调与安全归还）
--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

export type MarkerSettings = {
	FOV: number,
	TransitionDuration: number,
}

export type SavedCameraState = {
	camera: Camera,
	kind: Enum.CameraType,
	subject: Instance?,
	pose: CFrame,
	fov: number,
}

export type ControllerOptions = {
	defaultFov: number?,
	defaultDuration: number?,
	markerName: string?,
	enableHotReload: boolean?,
	onReadyChanged: ((ready: boolean) -> ())?,
	onRestored: (() -> ())?,
}

export type Controller = {
	saved: SavedCameraState?,
	ready: boolean,
	marker: BasePart?,
	suspended: boolean,
	EnterPose: (self: Controller, pose: CFrame, fov: number?, duration: number?) -> (),
	Enter: (
		self: Controller,
		target: Instance?,
		fallbackPose: CFrame?,
		fallbackFov: number?,
		fallbackDuration: number?
	) -> (),
	Suspend: (self: Controller) -> (),
	Resume: (self: Controller) -> (),
	Cancel: (self: Controller) -> (),
	Exit: (self: Controller, immediate: boolean?, duration: number?) -> (),
	Restore: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local DEFAULT_MARKER_NAME = "CameraMarker"
local MARKER_ATTRIBUTE = "CameraMarker"

local FixedCamera = {}

FixedCamera.Defaults = {
	MarkerName = DEFAULT_MARKER_NAME,
	MarkerAttribute = MARKER_ATTRIBUTE,
	FOV = 70,
	TransitionDuration = 0.25,
}

local function IsFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

function FixedCamera.IsMarker(instance: Instance?): boolean
	if instance == nil or not instance:IsA("BasePart") then
		return false
	end
	return instance:GetAttribute(MARKER_ATTRIBUTE) == true or instance.Name == DEFAULT_MARKER_NAME
end

local function FindByAttribute(root: Instance, recursive: boolean): BasePart?
	local list: { Instance }
	if recursive then
		list = root:GetDescendants()
	else
		list = root:GetChildren()
	end
	for _, child in list do
		if child:IsA("BasePart") and child:GetAttribute(MARKER_ATTRIBUTE) == true then
			return child
		end
	end
	return nil
end

local function FindByName(root: Instance, name: string, recursive: boolean): BasePart?
	local found = root:FindFirstChild(name, recursive)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

function FixedCamera.FindMarker(target: Instance?, markerName: string?): BasePart?
	if target == nil then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if markerName and markerName ~= "" then
		return FindByName(target, markerName, false) or FindByName(target, markerName, true)
	end
	return FindByAttribute(target, false)
		or FindByName(target, DEFAULT_MARKER_NAME, false)
		or FindByAttribute(target, true)
		or FindByName(target, DEFAULT_MARKER_NAME, true)
end

function FixedCamera.ReadSettings(
	marker: BasePart?,
	fallbackFov: number?,
	fallbackDuration: number?
): MarkerSettings
	local fov = if fallbackFov ~= nil and IsFiniteNumber(fallbackFov)
		then math.clamp(fallbackFov :: number, 1, 120)
		else FixedCamera.Defaults.FOV
	local duration = if fallbackDuration ~= nil and IsFiniteNumber(fallbackDuration)
		then math.max(0, fallbackDuration :: number)
		else FixedCamera.Defaults.TransitionDuration

	if marker then
		local rawFov = marker:GetAttribute("FOV")
		if IsFiniteNumber(rawFov) then
			fov = math.clamp(rawFov :: number, 1, 120)
		end
		local rawDuration = marker:GetAttribute("TransitionDuration")
		if IsFiniteNumber(rawDuration) then
			duration = math.max(0, rawDuration :: number)
		end
	end

	return {
		FOV = fov,
		TransitionDuration = duration,
	}
end

function FixedCamera.GetPose(
	target: Instance?,
	fallbackCFrame: CFrame?,
	fallbackFov: number?,
	fallbackDuration: number?,
	markerName: string?
): (CFrame?, number, number, BasePart?)
	local marker = FixedCamera.FindMarker(target, markerName)
	local settings = FixedCamera.ReadSettings(marker, fallbackFov, fallbackDuration)
	local pose = if marker then marker.CFrame else fallbackCFrame
	return pose, settings.FOV, settings.TransitionDuration, marker
end

function FixedCamera.GetCFrame(target: Instance?, fallbackCFrame: CFrame?, markerName: string?): CFrame?
	local marker = FixedCamera.FindMarker(target, markerName)
	if marker then
		return marker.CFrame
	end
	return fallbackCFrame
end

function FixedCamera.HideMarker(marker: BasePart?): ()
	if marker == nil then
		return
	end
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
end

function FixedCamera.HideInContainer(container: Instance?, markerName: string?): BasePart?
	local marker = FixedCamera.FindMarker(container, markerName)
	FixedCamera.HideMarker(marker)
	return marker
end

function FixedCamera.HideAll(root: Instance?): number
	local target = root or Workspace
	local hiddenCount = 0
	if FixedCamera.IsMarker(target) then
		FixedCamera.HideMarker(target :: BasePart)
		hiddenCount += 1
	end
	for _, desc in target:GetDescendants() do
		if FixedCamera.IsMarker(desc) then
			FixedCamera.HideMarker(desc :: BasePart)
			hiddenCount += 1
		end
	end
	return hiddenCount
end

local function ConnectOptionalSignal(instance: Instance, methodName: string, key: string, callback: () -> ()): RBXScriptConnection?
	local okGetter, getter = pcall(function(): any
		return (instance :: any)[methodName]
	end)
	if not okGetter or typeof(getter) ~= "function" then
		return nil
	end
	local ok, signal = pcall(getter, instance, key)
	if not ok or not signal or typeof(signal.Connect) ~= "function" then
		return nil
	end
	local connected, connection = pcall(signal.Connect, signal, callback)
	if connected then
		return connection
	end
	return nil
end

local function ConnectOptionalEvent(instance: Instance, eventName: string, callback: (...any) -> ()): RBXScriptConnection?
	local okEvent, signal = pcall(function(): any
		return (instance :: any)[eventName]
	end)
	if not okEvent or not signal or typeof(signal.Connect) ~= "function" then
		return nil
	end
	local connected, connection = pcall(signal.Connect, signal, callback)
	if connected then
		return connection
	end
	return nil
end

function FixedCamera.WatchAndHide(root: Instance?): () -> ()
	local target = root or Workspace
	FixedCamera.HideAll(target)
	local conn = ConnectOptionalEvent(target, "DescendantAdded", function(desc: Instance): ()
		if FixedCamera.IsMarker(desc) then
			FixedCamera.HideMarker(desc :: BasePart)
		end
	end)
	local cleaned = false
	return function(): ()
		if cleaned then
			return
		end
		cleaned = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
end

function FixedCamera.CreateController(options: ControllerOptions?): Controller
	local defaultFov = if options and IsFiniteNumber(options.defaultFov)
		then math.clamp(options.defaultFov :: number, 1, 120)
		else FixedCamera.Defaults.FOV
	local defaultDuration = if options and IsFiniteNumber(options.defaultDuration)
		then math.max(0, options.defaultDuration :: number)
		else FixedCamera.Defaults.TransitionDuration
	local markerName = if options then options.markerName else nil
	local enableHotReload = if options and options.enableHotReload ~= nil then options.enableHotReload else true
	local onReadyChanged = if options then options.onReadyChanged else nil
	local onRestored = if options then options.onRestored else nil

	local currentTween: Tween? = nil
	local tweenCompletedConn: RBXScriptConnection? = nil
	local hotReloadConns: { RBXScriptConnection } = {}
	local activeDuration = defaultDuration

	local controller = {
		saved = nil :: SavedCameraState?,
		ready = false,
		marker = nil :: BasePart?,
		suspended = false,
	}

	local function SetReady(nextReady: boolean): ()
		if controller.ready == nextReady then
			return
		end
		controller.ready = nextReady
		if onReadyChanged then
			onReadyChanged(nextReady)
		end
	end

	local function ClearHotReload(): ()
		for _, conn in hotReloadConns do
			conn:Disconnect()
		end
		table.clear(hotReloadConns)
	end

	local function ClearTween(): ()
		if tweenCompletedConn then
			tweenCompletedConn:Disconnect()
			tweenCompletedConn = nil
		end
		if currentTween then
			currentTween:Cancel()
			currentTween:Destroy()
			currentTween = nil
		end
	end

	local function ApplyHotReload(marker: BasePart): ()
		if controller.suspended or not controller.ready or not marker.Parent then
			return
		end
		local saved = controller.saved
		if not saved or Workspace.CurrentCamera ~= saved.camera then
			return
		end
		saved.camera.CFrame = marker.CFrame
		local rawFov = marker:GetAttribute("FOV")
		if IsFiniteNumber(rawFov) then
			saved.camera.FieldOfView = math.clamp(rawFov :: number, 1, 120)
		end
	end

	local function BindHotReload(marker: BasePart): ()
		ClearHotReload()
		if not enableHotReload then
			return
		end
		local cframeConn = ConnectOptionalSignal(marker, "GetPropertyChangedSignal", "CFrame", function(): ()
			ApplyHotReload(marker)
		end)
		if cframeConn then
			table.insert(hotReloadConns, cframeConn)
		end
		local fovConn = ConnectOptionalSignal(marker, "GetAttributeChangedSignal", "FOV", function(): ()
			ApplyHotReload(marker)
		end)
		if fovConn then
			table.insert(hotReloadConns, fovConn)
		end
	end

	function controller.Cancel(_self: Controller): ()
		ClearTween()
	end

	function controller.Suspend(self: Controller): ()
		self.suspended = true
		ClearTween()
		SetReady(false)
	end

	function controller.Resume(self: Controller): ()
		self.suspended = false
	end

	function controller.Restore(self: Controller): ()
		ClearHotReload()
		ClearTween()
		local saved = self.saved
		self.saved = nil
		self.marker = nil
		self.suspended = false
		SetReady(false)
		if onRestored then
			onRestored()
		end
		if not saved or Workspace.CurrentCamera ~= saved.camera then
			return
		end
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		saved.camera.CFrame = saved.pose
		saved.camera.FieldOfView = saved.fov
		saved.camera.CameraSubject = humanoid or saved.subject
		saved.camera.CameraType = saved.kind
	end

	local function BeginEnter(pose: CFrame, fov: number, duration: number, marker: BasePart?): ()
		controller:Restore()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		controller.saved = {
			camera = camera,
			kind = camera.CameraType,
			subject = camera.CameraSubject,
			pose = camera.CFrame,
			fov = camera.FieldOfView,
		}
		controller.marker = marker
		controller.suspended = false
		activeDuration = math.max(0, duration)
		camera.CameraType = Enum.CameraType.Scriptable

		if marker then
			FixedCamera.HideMarker(marker)
			BindHotReload(marker)
		end

		if activeDuration <= 0 then
			camera.CFrame = pose
			camera.FieldOfView = fov
			SetReady(true)
			return
		end

		local tween = TweenService:Create(
			camera,
			TweenInfo.new(activeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = pose, FieldOfView = fov }
		)
		currentTween = tween
		tweenCompletedConn = tween.Completed:Connect(function(state: Enum.PlaybackState): ()
			ClearTween()
			if state == Enum.PlaybackState.Completed then
				SetReady(true)
			end
		end)
		tween:Play()
	end

	function controller.EnterPose(_self: Controller, pose: CFrame, fov: number?, duration: number?): ()
		local resolvedFov = if fov ~= nil and IsFiniteNumber(fov)
			then math.clamp(fov :: number, 1, 120)
			else defaultFov
		local resolvedDuration = if duration ~= nil and IsFiniteNumber(duration)
			then math.max(0, duration :: number)
			else defaultDuration
		BeginEnter(pose, resolvedFov, resolvedDuration, nil)
	end

	function controller.Enter(
		_self: Controller,
		target: Instance?,
		fallbackPose: CFrame?,
		fallbackFov: number?,
		fallbackDuration: number?
	): ()
		local resolvedFallbackFov = if fallbackFov ~= nil and IsFiniteNumber(fallbackFov) then fallbackFov else defaultFov
		local resolvedFallbackDuration = if fallbackDuration ~= nil and IsFiniteNumber(fallbackDuration)
			then fallbackDuration
			else defaultDuration
		local pose, fov, duration, marker = FixedCamera.GetPose(
			target,
			fallbackPose,
			resolvedFallbackFov,
			resolvedFallbackDuration,
			markerName
		)
		if not pose then
			return
		end
		BeginEnter(pose, fov, duration, marker)
	end

	function controller.Exit(self: Controller, immediate: boolean?, duration: number?): ()
		ClearHotReload()
		ClearTween()
		self.suspended = false
		SetReady(false)
		local saved = self.saved
		if not saved then
			return
		end
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if immediate or not humanoid or humanoid.Health <= 0 or Workspace.CurrentCamera ~= saved.camera then
			self:Restore()
			return
		end
		local exitDuration = if duration ~= nil and IsFiniteNumber(duration)
			then math.max(0, duration :: number)
			elseif self.marker then FixedCamera.ReadSettings(self.marker, defaultFov, activeDuration).TransitionDuration
			else activeDuration
		if exitDuration <= 0 then
			self:Restore()
			return
		end
		local tween = TweenService:Create(
			saved.camera,
			TweenInfo.new(exitDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = saved.pose, FieldOfView = saved.fov }
		)
		currentTween = tween
		tweenCompletedConn = tween.Completed:Connect(function(state: Enum.PlaybackState): ()
			if state == Enum.PlaybackState.Completed then
				self:Restore()
			end
		end)
		tween:Play()
	end

	function controller.Destroy(self: Controller): ()
		self:Restore()
	end

	return controller :: Controller
end

return FixedCamera
