-- 通用客户端资产预加载与分级调度器：提取实例树资产、去重、提级与按需等待
--!strict
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local AssetPreloader = {}
AssetPreloader.__index = AssetPreloader

export type AssetKind = "Image" | "Decal" | "Animation" | "Sound" | "Mesh" | "Video" | "Unknown"

export type RegisterOptions = {
	priority: number?,
	groups: { string }?,
	filter: ((Instance) -> boolean)?,
	extractGuiAttributes: boolean?,
	id: string?,
}

export type PriorityStats = {
	total: number,
	completed: number,
	succeeded: number,
	failed: number,
}

export type ProgressSnapshot = {
	total: number,
	completed: number,
	succeeded: number,
	failed: number,
	byPriority: { [number]: PriorityStats },
}

export type PreloaderOptions = {
	batchSize: number?,
	maxRetries: number?,
	yieldBetweenBatches: boolean?,
	onProgress: ((ProgressSnapshot) -> ())?,
	onUriReady: ((uri: string, kind: AssetKind, success: boolean, groups: { [string]: boolean }, priority: number) -> ())?,
	onUnitReady: ((unitId: string, root: Instance?, success: boolean, groups: { [string]: boolean }, priority: number) -> ())?,
}

type DownloadEntry = {
	uri: string,
	primaryKind: AssetKind,
	kinds: { [string]: boolean },
	notifiedKinds: { [string]: boolean },
	meshSource: Instance?,
	priority: number,
	groups: { [string]: boolean },
	attempts: number,
	done: boolean,
	success: boolean,
}

type UnitEntry = {
	id: string,
	root: Instance?,
	priority: number,
	groups: { [string]: boolean },
	dependencies: { [DownloadEntry]: boolean },
	notified: boolean,
}

type Waiter = {
	thread: thread,
	kind: "priority" | "group" | "idle",
	maxPriority: number?,
	group: string?,
	resolved: boolean,
}

type PreloaderState = {
	batchSize: number,
	maxAttempts: number,
	yieldBetweenBatches: boolean,
	onProgress: ((ProgressSnapshot) -> ())?,
	onUriReady: ((uri: string, kind: AssetKind, success: boolean, groups: { [string]: boolean }, priority: number) -> ())?,
	onUnitReady: ((unitId: string, root: Instance?, success: boolean, groups: { [string]: boolean }, priority: number) -> ())?,
	downloads: { DownloadEntry },
	byUri: { [string]: DownloadEntry },
	units: { UnitEntry },
	byUnit: { [string | Instance]: UnitEntry },
	promoted: { [string]: boolean },
	temporary: { [Instance]: boolean },
	waiters: { Waiter },
	started: boolean,
	running: boolean,
	cancelled: boolean,
	generation: number,
}

export type Preloader = typeof(setmetatable({} :: PreloaderState, AssetPreloader))

local DefaultBatchSize = 12
local DefaultMaxRetries = 1
local DefaultPriority = 3
local PixelSize = UDim2.fromOffset(2, 2)
local LogPrefix = "[AssetPreloader]"

local ContentProperties: { [string]: { string } } = {
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	CharacterMesh = { "MeshId", "BaseTextureId", "OverlayTextureId" },
	Shirt = { "ShirtTemplate" },
	Pants = { "PantsTemplate" },
	ShirtGraphic = { "Graphic" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
	Tool = { "TextureId" },
	FileMesh = { "MeshId", "TextureId" },
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" },
}

local function NormalizeUri(uri: string): string
	local id = string.match(uri, "^rbxassetid://(%d+)$")
		or string.match(uri, "^https?://www%.roblox%.com/asset/%?id=(%d+)$")
		or string.match(uri, "^https?://assetdelivery%.roblox%.com/v1/asset/%?id=(%d+)$")
	return if id then "rbxassetid://" .. id else uri
end

local function IsAssetUri(value: unknown): boolean
	if typeof(value) ~= "string" or value == "" then
		return false
	end
	return string.match(value, "^rbxassetid://%d+$") ~= nil
		or string.match(NormalizeUri(value), "^rbxassetid://%d+$") ~= nil
end

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

local function MergeGroups(target: { [string]: boolean }, source: { [string]: boolean }): ()
	for group in source do
		target[group] = true
	end
end

local function TrackTemp(self: Preloader, instance: Instance): Instance
	self.temporary[instance] = true
	return instance
end

local function ReleaseTemp(self: Preloader, instances: { Instance }): ()
	for _, instance in instances do
		if self.temporary[instance] then
			self.temporary[instance] = nil
			instance:Destroy()
		end
	end
end

local function CreateContentInstance(kind: AssetKind, uri: string): Instance?
	if kind == "Image" then
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = PixelSize
		label.Image = uri
		return label
	elseif kind == "Decal" then
		local decal = Instance.new("Decal")
		decal.Texture = uri
		return decal
	elseif kind == "Animation" then
		local animation = Instance.new("Animation")
		animation.AnimationId = uri
		return animation
	elseif kind == "Sound" then
		local sound = Instance.new("Sound")
		sound.SoundId = uri
		sound.Volume = 0
		return sound
	elseif kind == "Video" then
		local video = Instance.new("VideoFrame")
		video.Video = uri
		video.Volume = 0
		return video
	end
	return nil
end

local function CreateDownloadInstance(entry: DownloadEntry): Instance?
	local source = entry.meshSource
	if source and source:IsA("MeshPart") and source.Archivable then
		-- MeshPart.MeshId 运行时只读；克隆并剥离子节点与纹理后提交给 ContentProvider。
		local mesh = source:Clone()
		mesh:ClearAllChildren()
		mesh.TextureID = ""
		return mesh
	elseif source then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = entry.uri
		return mesh
	end
	return CreateContentInstance(entry.primaryKind, entry.uri)
end

local function ComputeSnapshot(self: Preloader): ProgressSnapshot
	local total = #self.downloads
	local completed = 0
	local succeeded = 0
	local failed = 0
	local byPriority: { [number]: PriorityStats } = {}
	for _, entry in self.downloads do
		local bucket = byPriority[entry.priority]
		if not bucket then
			bucket = { total = 0, completed = 0, succeeded = 0, failed = 0 }
			byPriority[entry.priority] = bucket
		end
		bucket.total += 1
		if entry.done then
			completed += 1
			bucket.completed += 1
			if entry.success then
				succeeded += 1
				bucket.succeeded += 1
			else
				failed += 1
				bucket.failed += 1
			end
		end
	end
	return {
		total = total,
		completed = completed,
		succeeded = succeeded,
		failed = failed,
		byPriority = byPriority,
	}
end

local function NotifyProgress(self: Preloader): ()
	if self.onProgress and not self.cancelled then
		self.onProgress(ComputeSnapshot(self))
	end
end

local function NotifySingleKind(
	callback: (string, AssetKind, boolean, { [string]: boolean }, number) -> (),
	entry: DownloadEntry,
	kind: AssetKind
): ()
	if entry.kinds[kind] and not entry.notifiedKinds[kind] then
		entry.notifiedKinds[kind] = true
		callback(entry.uri, kind, entry.success, table.clone(entry.groups), entry.priority)
	end
end

local function NotifyUriKinds(self: Preloader, entry: DownloadEntry, generation: number): ()
	local callback = self.onUriReady
	if not callback or self.cancelled or self.generation ~= generation then
		return
	end
	NotifySingleKind(callback, entry, "Image")
	if self.cancelled or self.generation ~= generation then return end
	NotifySingleKind(callback, entry, "Decal")
	if self.cancelled or self.generation ~= generation then return end
	NotifySingleKind(callback, entry, "Animation")
	if self.cancelled or self.generation ~= generation then return end
	NotifySingleKind(callback, entry, "Sound")
	if self.cancelled or self.generation ~= generation then return end
	NotifySingleKind(callback, entry, "Video")
end

local function NotifyReadyUnits(self: Preloader, generation: number): ()
	local callback = self.onUnitReady
	if not callback then
		return
	end
	for _, unit in self.units do
		if self.cancelled or self.generation ~= generation then
			return
		end
		if unit.notified then
			continue
		end
		local ready = true
		local allSucceeded = true
		for dependency in unit.dependencies do
			if not dependency.done then
				ready = false
				break
			end
			if not dependency.success then
				allSucceeded = false
			end
		end
		if ready then
			unit.notified = true
			callback(unit.id, unit.root, allSucceeded, table.clone(unit.groups), unit.priority)
		end
	end
end

local function IsPriorityDone(self: Preloader, maxPriority: number): boolean
	for _, entry in self.downloads do
		if entry.priority <= maxPriority and not entry.done then
			return false
		end
	end
	return true
end

local function IsGroupDone(self: Preloader, group: string): boolean
	for _, entry in self.downloads do
		if entry.groups[group] and not entry.done then
			return false
		end
	end
	return true
end

local function HasPendingDownloads(self: Preloader): boolean
	for _, entry in self.downloads do
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

local function FlushWaiters(self: Preloader, forceFail: boolean): ()
	local remaining: { Waiter } = {}
	for _, waiter in self.waiters do
		if waiter.resolved then
			continue
		end
		if forceFail then
			ResolveWaiter(waiter, false)
			continue
		end
		local satisfied = false
		if waiter.kind == "priority" and waiter.maxPriority then
			satisfied = IsPriorityDone(self, waiter.maxPriority)
		elseif waiter.kind == "group" and waiter.group then
			satisfied = IsGroupDone(self, waiter.group)
		elseif waiter.kind == "idle" then
			satisfied = not self.running and not HasPendingDownloads(self)
		end
		if satisfied then
			ResolveWaiter(waiter, true)
		else
			table.insert(remaining, waiter)
		end
	end
	self.waiters = remaining
end

local function EffectiveRank(self: Preloader, entry: DownloadEntry): number
	if entry.attempts > 0 then
		return math.huge
	end
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

local function FindNextRank(self: Preloader): number?
	local best: number? = nil
	for _, entry in self.downloads do
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

local function RegisterDownload(
	self: Preloader,
	uri: string,
	kind: AssetKind,
	priority: number,
	groups: { [string]: boolean },
	meshSource: Instance?
): DownloadEntry?
	local trimmed = string.gsub(uri, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end
	local key = NormalizeUri(trimmed)
	local existing = self.byUri[key]
	if existing then
		if priority < existing.priority then
			existing.priority = priority
		end
		MergeGroups(existing.groups, groups)
		existing.kinds[kind] = true
		if existing.primaryKind == "Unknown" and kind ~= "Unknown" then
			existing.primaryKind = kind
		end
		if existing.meshSource == nil and meshSource ~= nil then
			existing.meshSource = meshSource
		end
		if existing.done and self.started and not self.cancelled then
			NotifyUriKinds(self, existing, self.generation)
		end
		return existing
	end
	local entry: DownloadEntry = {
		uri = key,
		primaryKind = kind,
		kinds = { [kind] = true },
		notifiedKinds = {},
		meshSource = meshSource,
		priority = priority,
		groups = table.clone(groups),
		attempts = 0,
		done = false,
		success = false,
	}
	self.byUri[key] = entry
	table.insert(self.downloads, entry)
	return entry
end

local function CollectNode(
	self: Preloader,
	node: Instance,
	priority: number,
	groups: { [string]: boolean },
	extractGuiAttributes: boolean,
	dependencies: { [DownloadEntry]: boolean }
): ()
	local function Add(uri: string, kind: AssetKind, meshSource: Instance?)
		local entry = RegisterDownload(self, uri, kind, priority, groups, meshSource)
		if entry then
			dependencies[entry] = true
		end
	end

	if node:IsA("ImageLabel") or node:IsA("ImageButton") then
		Add(node.Image, "Image", nil)
		if node:IsA("ImageButton") then
			Add(node.HoverImage, "Image", nil)
			Add(node.PressedImage, "Image", nil)
		end
	elseif node:IsA("ScrollingFrame") then
		Add(node.TopImage, "Image", nil)
		Add(node.MidImage, "Image", nil)
		Add(node.BottomImage, "Image", nil)
	elseif node:IsA("Decal") then
		Add(node.Texture, "Decal", nil)
	elseif node:IsA("Sound") then
		Add(node.SoundId, "Sound", nil)
	elseif node:IsA("Animation") then
		Add(node.AnimationId, "Animation", nil)
	elseif node:IsA("VideoFrame") and node.Video ~= "" then
		Add(node.Video, "Video", nil)
	end

	local properties = ContentProperties[node.ClassName]
	if properties then
		for _, property in properties do
			local value: unknown = (node :: any)[property]
			local uri = if typeof(value) == "string"
				then value
				elseif typeof(value) == "number" and value > 0 then "rbxassetid://" .. tostring(value)
				else ""
			if uri == "" then
				continue
			end
			if property == "MeshId" then
				Add(uri, "Mesh", node)
			elseif node:IsA("Tool") or (node:IsA("Sky") and (property == "SunTextureId" or property == "MoonTextureId")) then
				Add(uri, "Image", nil)
			else
				-- 网格与特效的贴图由各自模型/特效模板预热，这里仅下载内容不额外生成 2D 图片预热。
				Add(uri, "Unknown", nil)
			end
		end
	end

	if extractGuiAttributes and (node:IsA("GuiObject") or node:IsA("LayerCollector")) then
		for _, value in node:GetAttributes() do
			if IsAssetUri(value) then
				Add(value :: string, "Image", nil)
			end
		end
	end
end

local function DownloadBatch(self: Preloader, rank: number, generation: number): ()
	local entries: { DownloadEntry } = {}
	local temporary: { Instance } = {}
	local targets: { Instance | string } = {}
	local results: { [string]: boolean } = {}
	for _, entry in self.downloads do
		if entry.done or EffectiveRank(self, entry) ~= rank then
			continue
		end
		local target = CreateDownloadInstance(entry)
		if target then
			table.insert(temporary, TrackTemp(self, target))
		end
		table.insert(targets, target or entry.uri)
		table.insert(entries, entry)
		if #entries >= self.batchSize then
			break
		end
	end
	if #entries == 0 then
		return
	end

	local function OnAssetFetched(uri: string, status: Enum.AssetFetchStatus)
		if not self.cancelled and self.generation == generation then
			results[NormalizeUri(uri)] = status == Enum.AssetFetchStatus.Success
		end
	end

	AssetPreloader.PreloadAsync(targets, OnAssetFetched)
	ReleaseTemp(self, temporary)
	if self.cancelled or self.generation ~= generation then
		return
	end

	for _, entry in entries do
		entry.attempts += 1
		local success = results[entry.uri] == true
		if success then
			entry.success = true
			entry.done = true
			NotifyUriKinds(self, entry, generation)
		elseif entry.attempts >= self.maxAttempts then
			entry.success = false
			entry.done = true
			warn(LogPrefix, "下载失败", entry.uri)
			NotifyUriKinds(self, entry, generation)
		end
	end

	NotifyReadyUnits(self, generation)
	NotifyProgress(self)
	FlushWaiters(self, false)
end

local function EnsureWorker(self: Preloader): ()
	if self.cancelled or not self.started or self.running then
		return
	end
	if not HasPendingDownloads(self) then
		NotifyReadyUnits(self, self.generation)
		FlushWaiters(self, false)
		return
	end
	self.running = true
	local generation = self.generation
	task.spawn(function()
		while not self.cancelled and self.generation == generation do
			local rank = FindNextRank(self)
			if not rank then
				break
			end
			DownloadBatch(self, rank, generation)
			if not self.cancelled and self.generation == generation and self.yieldBetweenBatches and HasPendingDownloads(self) then
				RunService.Heartbeat:Wait()
			end
		end
		if self.generation == generation then
			self.running = false
			if not self.cancelled then
				NotifyReadyUnits(self, generation)
				FlushWaiters(self, false)
			end
		end
	end)
end

local function WaitWithCondition(
	self: Preloader,
	kind: "priority" | "group" | "idle",
	maxPriority: number?,
	group: string?,
	timeout: number?
): boolean
	if self.cancelled then
		return false
	end
	if kind == "priority" and maxPriority and IsPriorityDone(self, maxPriority) then
		return true
	elseif kind == "group" and group and IsGroupDone(self, group) then
		return true
	elseif kind == "idle" and not self.running and not HasPendingDownloads(self) then
		return true
	end

	local waiter: Waiter = {
		thread = coroutine.running(),
		kind = kind,
		maxPriority = maxPriority,
		group = group,
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

function AssetPreloader.PreloadAsync(targets: { Instance | string }, onAssetFetched: ((string, Enum.AssetFetchStatus) -> ())?): boolean
	if #targets == 0 then
		return true
	end
	local ok, reason = pcall(function()
		ContentProvider:PreloadAsync(targets, onAssetFetched)
	end)
	if not ok then
		warn(LogPrefix, reason)
	end
	return ok
end

function AssetPreloader.new(options: PreloaderOptions?): Preloader
	local opts: PreloaderOptions = options or {}
	local batchSize = if opts.batchSize and opts.batchSize >= 1 then math.floor(opts.batchSize) else DefaultBatchSize
	local maxRetries = if opts.maxRetries and opts.maxRetries >= 0 then math.floor(opts.maxRetries) else DefaultMaxRetries
	local state: PreloaderState = {
		batchSize = batchSize,
		maxAttempts = 1 + maxRetries,
		yieldBetweenBatches = if opts.yieldBetweenBatches == nil then true else opts.yieldBetweenBatches,
		onProgress = opts.onProgress,
		onUriReady = opts.onUriReady,
		onUnitReady = opts.onUnitReady,
		downloads = {},
		byUri = {},
		units = {},
		byUnit = {},
		promoted = {},
		temporary = {},
		waiters = {},
		started = false,
		running = false,
		cancelled = false,
		generation = 1,
	}
	return setmetatable(state, AssetPreloader)
end

function AssetPreloader.AddUri(self: Preloader, uri: string, kind: AssetKind?, options: RegisterOptions?): string?
	if self.cancelled then
		return nil
	end
	local opts: RegisterOptions = options or {}
	local priority = NormalizePriority(opts.priority)
	local groups = BuildGroupsMap(opts.groups)
	local entry = RegisterDownload(self, uri, kind or "Unknown", priority, groups, nil)
	if not entry then
		return nil
	end
	if self.started then
		EnsureWorker(self)
	end
	return entry.uri
end

function AssetPreloader.AddTree(self: Preloader, root: Instance, options: RegisterOptions?): string?
	if self.cancelled or not root.Archivable then
		return nil
	end
	local opts: RegisterOptions = options or {}
	if opts.filter and not opts.filter(root) then
		return nil
	end
	local priority = NormalizePriority(opts.priority)
	local groups = BuildGroupsMap(opts.groups)
	local extractGuiAttributes = if opts.extractGuiAttributes == nil then true else opts.extractGuiAttributes
	local dependencies: { [DownloadEntry]: boolean } = {}

	local function Visit(node: Instance)
		if not node.Archivable then
			return
		end
		if opts.filter and not opts.filter(node) then
			return
		end
		CollectNode(self, node, priority, groups, extractGuiAttributes, dependencies)
		for _, child in node:GetChildren() do
			Visit(child)
		end
	end
	Visit(root)

	local unitKey: string | Instance = opts.id or root
	local unitId = opts.id or root.Name
	local existingUnit = self.byUnit[unitKey]
	if existingUnit then
		if priority < existingUnit.priority then
			existingUnit.priority = priority
		end
		MergeGroups(existingUnit.groups, groups)
		for dependency in dependencies do
			existingUnit.dependencies[dependency] = true
			if not dependency.done then
				existingUnit.notified = false
			end
		end
	else
		local unit: UnitEntry = {
			id = unitId,
			root = root,
			priority = priority,
			groups = groups,
			dependencies = dependencies,
			notified = false,
		}
		self.byUnit[unitKey] = unit
		table.insert(self.units, unit)
	end

	if self.started then
		NotifyReadyUnits(self, self.generation)
		EnsureWorker(self)
	end
	return unitId
end

function AssetPreloader.Promote(self: Preloader, group: string): ()
	if group ~= "" then
		self.promoted[group] = true
	end
end

function AssetPreloader.Start(self: Preloader): ()
	if self.cancelled then
		return
	end
	self.started = true
	NotifyReadyUnits(self, self.generation)
	EnsureWorker(self)
end

function AssetPreloader.WaitForPriority(self: Preloader, maxPriority: number, timeout: number?): boolean
	return WaitWithCondition(self, "priority", maxPriority, nil, timeout)
end

function AssetPreloader.WaitForGroup(self: Preloader, group: string, timeout: number?, autoPromote: boolean?): boolean
	if autoPromote ~= false then
		self:Promote(group)
	end
	return WaitWithCondition(self, "group", nil, group, timeout)
end

function AssetPreloader.WaitForIdle(self: Preloader, timeout: number?): boolean
	return WaitWithCondition(self, "idle", nil, nil, timeout)
end

function AssetPreloader.GetProgress(self: Preloader): ProgressSnapshot
	return ComputeSnapshot(self)
end

function AssetPreloader.Cancel(self: Preloader): ()
	if self.cancelled then
		return
	end
	self.cancelled = true
	self.running = false
	self.generation += 1
	for instance in self.temporary do
		instance:Destroy()
	end
	table.clear(self.temporary)
	FlushWaiters(self, true)
end

function AssetPreloader.Destroy(self: Preloader): ()
	self:Cancel()
	table.clear(self.downloads)
	table.clear(self.byUri)
	table.clear(self.units)
	table.clear(self.byUnit)
	table.clear(self.promoted)
end

return AssetPreloader
