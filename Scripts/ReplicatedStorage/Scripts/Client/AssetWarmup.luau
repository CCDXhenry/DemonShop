-- 通用客户端渲染与解码预热器：常驻复用舞台、帧预算控制与可插拔扩展
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AssetWarmup = {}
AssetWarmup.__index = AssetWarmup

export type WarmupTask = {
	key: string | Instance,
	kind: string,
	uri: string?,
	source: Instance?,
	priority: number?,
	groups: { string }?,
	payload: any?,
}

export type WarmupContext = {
	slot: Frame,
	animator: Animator,
	track: (Instance) -> Instance,
	stageViewport: (GuiObject, Model) -> ViewportFrame,
	prepareVisualClone: (Instance) -> (),
}

export type WarmupHandler = (task: WarmupTask, context: WarmupContext) -> ()

export type PriorityWarmupStats = {
	queued: number,
	warmed: number,
	failed: number,
}

export type WarmupStats = {
	queued: number,
	warmed: number,
	failed: number,
	byPriority: { [number]: PriorityWarmupStats },
}

export type WarmupOptions = {
	batchSize: number?,
	heavyPerBatch: number?,
	holdFrames: number?,
	heavyKinds: { [string]: boolean }?,
	stageName: string?,
	onTaskDone: ((key: string | Instance, kind: string, success: boolean) -> ())?,
}

type WarmupEntry = {
	key: string | Instance,
	kind: string,
	uri: string?,
	source: Instance?,
	payload: any?,
	priority: number,
	groups: { [string]: boolean },
	done: boolean,
}

type Waiter = {
	thread: thread,
	resolved: boolean,
}

type WarmupState = {
	batchSize: number,
	heavyPerBatch: number,
	holdFrames: number,
	heavyKinds: { [string]: boolean },
	stageName: string,
	onTaskDone: ((key: string | Instance, kind: string, success: boolean) -> ())?,
	handlers: { [string]: WarmupHandler },
	entries: { WarmupEntry },
	byKey: { [string | Instance]: WarmupEntry },
	promoted: { [string]: boolean },
	temporary: { [Instance]: boolean },
	stageGui: ScreenGui?,
	stageWorld: Folder?,
	animator: Animator?,
	waiters: { Waiter },
	statsByPriority: { [number]: PriorityWarmupStats },
	totalQueued: number,
	totalWarmed: number,
	totalFailed: number,
	started: boolean,
	running: boolean,
	cancelled: boolean,
	generation: number,
}

export type Warmup = typeof(setmetatable({} :: WarmupState, AssetWarmup))

local DefaultBatchSize = 12
local DefaultHeavyPerBatch = 2
local DefaultHoldFrames = 2
local DefaultPriority = 3
local WarmupDisplayOrder = -100
local WarmupTransparency = 0.98
local AnimationWeight = 0.0001
local FallbackEffectPosition = Vector3.new(0, 5000, 0)
local PixelSize = UDim2.fromOffset(2, 2)
local LogPrefix = "[AssetWarmup]"

local function NormalizePriority(priority: number?): number
	if priority == nil or priority ~= priority then
		return DefaultPriority
	end
	local rounded = math.floor(priority)
	return if rounded < 1 then 1 else rounded
end

local function BuildGroupsMap(groups: { string }?): { [string]: boolean }
	local map: { [string]: boolean } = {}
	if groups then
		for _, group in groups do
			if group ~= "" then
				map[group] = true
			end
		end
	end
	return map
end

local function EnsurePriorityStats(self: Warmup, priority: number): PriorityWarmupStats
	local bucket = self.statsByPriority[priority]
	if not bucket then
		bucket = { queued = 0, warmed = 0, failed = 0 }
		self.statsByPriority[priority] = bucket
	end
	return bucket
end

local function TrackInstance(self: Warmup, instance: Instance): Instance
	self.temporary[instance] = true
	return instance
end

local function ReleaseInstances(self: Warmup, instances: { Instance }): ()
	for _, instance in instances do
		if self.temporary[instance] then
			self.temporary[instance] = nil
			instance:Destroy()
		end
	end
end

local function ReleaseStage(self: Warmup): ()
	if self.stageGui then
		self.temporary[self.stageGui] = nil
		self.stageGui:Destroy()
		self.stageGui = nil
	end
	if self.stageWorld then
		self.temporary[self.stageWorld] = nil
		self.stageWorld:Destroy()
		self.stageWorld = nil
	end
	self.animator = nil
end

local function EnsureStage(self: Warmup, playerGui: Instance): (ScreenGui, Animator)
	if self.stageGui and self.stageGui.Parent == playerGui and self.stageWorld and self.stageWorld.Parent == workspace and self.animator then
		return self.stageGui, self.animator
	end
	ReleaseStage(self)

	local screen = Instance.new("ScreenGui")
	screen.Name = self.stageName
	screen.ResetOnSpawn = false
	screen.DisplayOrder = WarmupDisplayOrder
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui
	self.stageGui = screen
	self.temporary[screen] = true

	local world = Instance.new("Folder")
	world.Name = "AssetWarmupWorld"
	world.Parent = workspace
	local controller = Instance.new("AnimationController")
	local animator = Instance.new("Animator")
	animator.Parent = controller
	controller.Parent = world
	self.stageWorld = world
	self.animator = animator
	self.temporary[world] = true

	return screen, animator
end

local function PrepareVisualClone(clone: Instance): ()
	local function PrepareNode(node: Instance)
		if node:IsA("BaseScript") or node:IsA("ProximityPrompt") or node:IsA("Sound") then
			node:Destroy()
		elseif node:IsA("ParticleEmitter") then
			node.Enabled = false
		elseif node:IsA("BasePart") then
			node.Anchored = true
			node.CanCollide = false
			node.CanTouch = false
			node.CanQuery = false
			node.CastShadow = false
		end
	end
	PrepareNode(clone)
	for _, node in clone:GetDescendants() do
		PrepareNode(node)
	end
end

local function StageViewport(slot: GuiObject, model: Model): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = PixelSize
	viewport.BackgroundTransparency = 1
	viewport.ImageTransparency = WarmupTransparency
	viewport.Parent = slot
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model.Parent = world
	local pose, size = model:GetBoundingBox()
	local distance = math.max(size.Magnitude, 1)
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(pose.Position + Vector3.new(0, 0, -distance), pose.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function ResolveEffectCFrame(): CFrame
	local camera = workspace.CurrentCamera
	if camera then
		-- 置于当前视锥前方微距可见位置，避免高空被视锥/距离剔除而未触发 GPU 编译。
		return camera.CFrame * CFrame.new(0, 0, -10)
	end
	return CFrame.new(FallbackEffectPosition)
end

local function StageEffectClone(clone: Instance, context: WarmupContext): ()
	local anchor = context.track(Instance.new("Part")) :: Part
	anchor.Name = "PreloadEffectAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	local targetPose = ResolveEffectCFrame()
	anchor.CFrame = targetPose
	clone.Parent = anchor
	if clone:IsA("Model") then
		clone:PivotTo(targetPose)
	elseif clone:IsA("BasePart") then
		clone.CFrame = targetPose
	end
	anchor.Parent = workspace
	for _, node in anchor:GetDescendants() do
		if node:IsA("ParticleEmitter") then
			node:Emit(1)
		elseif node:IsA("Beam") then
			node.Enabled = true
		elseif node:IsA("Trail") then
			node.Enabled = true
		end
	end
end

local function BuildDefaultHandlers(): { [string]: WarmupHandler }
	local handlers: { [string]: WarmupHandler } = {}

	handlers.Image = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.uri or taskItem.uri == "" then
			return
		end
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = PixelSize
		label.ImageTransparency = WarmupTransparency
		label.Image = taskItem.uri
		label.Parent = context.slot
	end

	handlers.Decal = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.uri or taskItem.uri == "" then
			return
		end
		local model = Instance.new("Model")
		model.Name = "PreloadFace"
		local part = Instance.new("Part")
		part.Anchored = true
		part.Parent = model
		local decal = Instance.new("Decal")
		decal.Texture = taskItem.uri
		decal.Parent = part
		context.stageViewport(context.slot, model)
	end

	handlers.Animation = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.uri or taskItem.uri == "" then
			return
		end
		local animation = context.track(Instance.new("Animation")) :: Animation
		animation.AnimationId = taskItem.uri
		local track = context.track(context.animator:LoadAnimation(animation)) :: AnimationTrack
		track:Play(0, AnimationWeight, 0)
	end

	handlers.Sound = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.uri or taskItem.uri == "" then
			return
		end
		local sound = context.track(Instance.new("Sound")) :: Sound
		sound.SoundId = taskItem.uri
		sound.Volume = 0
		sound.Parent = context.slot
		sound:Play()
	end

	handlers.Video = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.uri or taskItem.uri == "" then
			return
		end
		local frame = Instance.new("CanvasGroup")
		frame.Size = PixelSize
		frame.BackgroundTransparency = 1
		frame.GroupTransparency = WarmupTransparency
		frame.Parent = context.slot
		local video = Instance.new("VideoFrame")
		video.Size = PixelSize
		video.Volume = 0
		video.Video = taskItem.uri
		video.Parent = frame
		video:Play()
	end

	handlers.Model = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.source then
			return
		end
		local clone = context.track(taskItem.source:Clone())
		context.prepareVisualClone(clone)
		local model = Instance.new("Model")
		model.Name = "PreloadModel"
		clone.Parent = model
		context.stageViewport(context.slot, model)
	end

	handlers.Effect = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.source then
			return
		end
		local clone = context.track(taskItem.source:Clone())
		context.prepareVisualClone(clone)
		StageEffectClone(clone, context)
	end

	handlers.Sky = function(taskItem: WarmupTask, context: WarmupContext)
		if not taskItem.source or not taskItem.source:IsA("Sky") then
			return
		end
		local clone = context.track(taskItem.source:Clone())
		local model = Instance.new("Model")
		local probe = Instance.new("Part")
		probe.Material = Enum.Material.Metal
		probe.Reflectance = 1
		probe.Parent = model
		clone.Parent = context.stageViewport(context.slot, model)
	end

	return handlers
end

local function EffectiveRank(self: Warmup, entry: WarmupEntry): number
	if entry.priority <= 1 then
		return 1
	end
	for group in entry.groups do
		if self.promoted[group] then
			return 2
		end
	end
	return entry.priority + 1
end

local function FindNextRank(self: Warmup): number?
	local best: number? = nil
	for _, entry in self.entries do
		if entry.done then
			continue
		end
		local candidate = EffectiveRank(self, entry)
		if not best or candidate < best then
			best = candidate
		end
	end
	return best
end

local function HasPendingWarmups(self: Warmup): boolean
	for _, entry in self.entries do
		if not entry.done then
			return true
		end
	end
	return false
end

local function ResolveWaiter(waiter: Waiter, result: boolean): ()
	if waiter.resolved then
		return
	end
	waiter.resolved = true
	if coroutine.status(waiter.thread) == "suspended" then
		task.spawn(waiter.thread, result)
	end
end

local function FlushIdleWaiters(self: Warmup, result: boolean): ()
	if result and (self.running or HasPendingWarmups(self)) then
		return
	end
	local waiters = self.waiters
	self.waiters = {}
	for _, waiter in waiters do
		ResolveWaiter(waiter, result)
	end
end

local function RunWarmupBatch(self: Warmup, rank: number, playerGui: Instance, generation: number): boolean
	local batch: { WarmupEntry } = {}
	local heavyCount = 0
	for _, entry in self.entries do
		if entry.done or EffectiveRank(self, entry) ~= rank then
			continue
		end
		if self.heavyKinds[entry.kind] then
			if heavyCount >= self.heavyPerBatch then
				continue
			end
			heavyCount += 1
		end
		table.insert(batch, entry)
		if #batch >= self.batchSize then
			break
		end
	end
	if #batch == 0 then
		return false
	end

	local screen, animator = EnsureStage(self, playerGui)
	local batchOwned: { Instance } = {}
	local function TrackBatch(instance: Instance): Instance
		TrackInstance(self, instance)
		table.insert(batchOwned, instance)
		return instance
	end

	local startedEntries: { WarmupEntry } = {}
	for index, entry in batch do
		entry.done = true
		local handler = self.handlers[entry.kind]
		if not handler then
			self.totalFailed += 1
			EnsurePriorityStats(self, entry.priority).failed += 1
			warn(LogPrefix, "未注册预热处理器", entry.kind)
			if self.onTaskDone then
				self.onTaskDone(entry.key, entry.kind, false)
			end
			continue
		end

		local slot = Instance.new("Frame")
		slot.Size = PixelSize
		slot.Position = UDim2.new(0, (index - 1) * PixelSize.X.Offset, 1, -PixelSize.Y.Offset)
		slot.BackgroundTransparency = 1
		slot.Parent = screen
		TrackBatch(slot)

		local taskItem: WarmupTask = {
			key = entry.key,
			kind = entry.kind,
			uri = entry.uri,
			source = entry.source,
			priority = entry.priority,
			groups = nil,
			payload = entry.payload,
		}
		local context: WarmupContext = {
			slot = slot,
			animator = animator,
			track = TrackBatch,
			stageViewport = StageViewport,
			prepareVisualClone = PrepareVisualClone,
		}
		local ok, reason = pcall(function()
			handler(taskItem, context)
			return true
		end)
		if ok then
			table.insert(startedEntries, entry)
		else
			self.totalFailed += 1
			EnsurePriorityStats(self, entry.priority).failed += 1
			warn(LogPrefix, "预热失败", entry.uri or entry.kind, reason)
			if self.onTaskDone then
				self.onTaskDone(entry.key, entry.kind, false)
			end
		end
	end

	for _ = 1, self.holdFrames do
		RunService.PreRender:Wait()
		if self.cancelled or self.generation ~= generation then
			return false
		end
	end

	ReleaseInstances(self, batchOwned)
	for _, entry in startedEntries do
		self.totalWarmed += 1
		EnsurePriorityStats(self, entry.priority).warmed += 1
		if self.onTaskDone then
			self.onTaskDone(entry.key, entry.kind, true)
		end
	end
	return true
end

local function EnsureWorker(self: Warmup): ()
	if self.cancelled or not self.started or self.running then
		return
	end
	if not HasPendingWarmups(self) then
		ReleaseStage(self)
		FlushIdleWaiters(self, true)
		return
	end
	self.running = true
	local generation = self.generation
	task.spawn(function()
		while not self.cancelled and self.generation == generation do
			if not HasPendingWarmups(self) then
				break
			end
			local localPlayer = Players.LocalPlayer
			local playerGui = if localPlayer then localPlayer:FindFirstChild("PlayerGui") else nil
			if not playerGui then
				RunService.Heartbeat:Wait()
				continue
			end
			local rank = FindNextRank(self)
			if not rank then
				break
			end
			RunWarmupBatch(self, rank, playerGui, generation)
		end
		if self.generation == generation then
			self.running = false
			ReleaseStage(self)
			if not self.cancelled then
				FlushIdleWaiters(self, true)
			end
		end
	end)
end

function AssetWarmup.new(options: WarmupOptions?): Warmup
	local opts: WarmupOptions = options or {}
	local heavyKinds = opts.heavyKinds or { Model = true, Effect = true, Sky = true }
	local state: WarmupState = {
		batchSize = if opts.batchSize and opts.batchSize >= 1 then math.floor(opts.batchSize) else DefaultBatchSize,
		heavyPerBatch = if opts.heavyPerBatch and opts.heavyPerBatch >= 1 then math.floor(opts.heavyPerBatch) else DefaultHeavyPerBatch,
		holdFrames = if opts.holdFrames and opts.holdFrames >= 1 then math.floor(opts.holdFrames) else DefaultHoldFrames,
		heavyKinds = heavyKinds,
		stageName = opts.stageName or "PreloadImageWarmup",
		onTaskDone = opts.onTaskDone,
		handlers = BuildDefaultHandlers(),
		entries = {},
		byKey = {},
		promoted = {},
		temporary = {},
		stageGui = nil,
		stageWorld = nil,
		animator = nil,
		waiters = {},
		statsByPriority = {},
		totalQueued = 0,
		totalWarmed = 0,
		totalFailed = 0,
		started = false,
		running = false,
		cancelled = false,
		generation = 1,
	}
	return setmetatable(state, AssetWarmup)
end

function AssetWarmup.RegisterHandler(self: Warmup, kind: string, handler: WarmupHandler): ()
	self.handlers[kind] = handler
end

function AssetWarmup.Enqueue(self: Warmup, taskItem: WarmupTask): ()
	if self.cancelled then
		return
	end
	local priority = NormalizePriority(taskItem.priority)
	local groups = BuildGroupsMap(taskItem.groups)
	local existing = self.byKey[taskItem.key]
	if existing then
		if not existing.done then
			if priority < existing.priority then
				EnsurePriorityStats(self, existing.priority).queued -= 1
				existing.priority = priority
				EnsurePriorityStats(self, priority).queued += 1
			end
			for group in groups do
				existing.groups[group] = true
			end
		end
		return
	end

	local entry: WarmupEntry = {
		key = taskItem.key,
		kind = taskItem.kind,
		uri = taskItem.uri,
		source = taskItem.source,
		payload = taskItem.payload,
		priority = priority,
		groups = groups,
		done = false,
	}
	self.byKey[taskItem.key] = entry
	table.insert(self.entries, entry)
	self.totalQueued += 1
	EnsurePriorityStats(self, priority).queued += 1

	if self.started then
		EnsureWorker(self)
	end
end

function AssetWarmup.Promote(self: Warmup, group: string): ()
	if group ~= "" then
		self.promoted[group] = true
	end
end

function AssetWarmup.Start(self: Warmup): ()
	if self.cancelled then
		return
	end
	self.started = true
	EnsureWorker(self)
end

function AssetWarmup.WaitForIdle(self: Warmup, timeout: number?): boolean
	if self.cancelled then
		return false
	end
	if not self.running and not HasPendingWarmups(self) then
		return true
	end
	local waiter: Waiter = {
		thread = coroutine.running(),
		resolved = false,
	}
	table.insert(self.waiters, waiter)
	if timeout and timeout > 0 then
		task.delay(timeout, function()
			ResolveWaiter(waiter, false)
		end)
	end
	return coroutine.yield() :: boolean
end

function AssetWarmup.GetStats(self: Warmup): WarmupStats
	local copy: { [number]: PriorityWarmupStats } = {}
	for priority, bucket in self.statsByPriority do
		copy[priority] = table.clone(bucket)
	end
	return {
		queued = self.totalQueued,
		warmed = self.totalWarmed,
		failed = self.totalFailed,
		byPriority = copy,
	}
end

function AssetWarmup.Cancel(self: Warmup): ()
	if self.cancelled then
		return
	end
	self.cancelled = true
	self.running = false
	self.generation += 1
	ReleaseStage(self)
	for instance in self.temporary do
		instance:Destroy()
	end
	table.clear(self.temporary)
	FlushIdleWaiters(self, false)
end

function AssetWarmup.Destroy(self: Warmup): ()
	self:Cancel()
	table.clear(self.entries)
	table.clear(self.byKey)
	table.clear(self.promoted)
	table.clear(self.statsByPriority)
end

return AssetWarmup
