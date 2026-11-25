-- 加工业务管理器：共享工位、搬运、权威画符和奖励；玩家生命周期由基础入口装配
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local GameData = require(Shared.GameData)
local GameTexts = require(Shared.GameTexts)
local Types = require(Shared.GameTypes)
local Net = require(Shared.ProcessingNet)
local Lifecycle = require(Shared.LifecycleTool)
local Info = require(script.Parent.ServerGameInfo)
local Scene = require(script.Parent.Scene)
local NPC = require(script.Parent.NPC)
local Carry = require(script.Parent.Carry)
local Ragdoll = require(script.Parent.Ragdoll)
local Ground = require(script.Parent.GroundAuthority)
local Physics = require(Shared.PhysicsConfig)
local Door = require(script.Parent.Door)
local Painting = require(script.Parent.Painting)
local Replication = require(script.Parent.Replication)
local VisualRules = require(Shared.VisualRules)
local Surface = require(Shared.PaintSurface)
local BodyPose = require(Shared.PaintBodyPose)
local PaintRotation = require(Shared.PaintRotation)
local CurvedSurface = require(Shared.CurvedSurface)
local ThrowArc = require(Shared.ThrowArc)
local AutomationRules = require(Shared.AutomationRules)
local AutoRunePattern = require(Shared.AutoRunePattern)
local AutomationAgents = require(script.Parent.AutomationAgents)
local PersonalRules = require(Shared.PersonalUpgradeRules)
local PersonalMovement = require(script.Parent.PersonalMovement)
local ModelTemplates = require(Shared.ModelTemplates)
type PlayerData = {
	IsActive: (Player) -> boolean,
	CanAddCoins: (Player, number) -> boolean,
	AddCoins: (Player, number) -> boolean,
	CanSpendCoins: ((Player, number) -> boolean)?,
	SpendCoins: ((Player, number) -> boolean)?,
	TrySpendCoins: ((Player, number) -> boolean)?,
}
type PaintSession = Painting.Session
type PlayerRecord = {
	scope: Lifecycle.Lifecycle,
	characterScope: Lifecycle.Lifecycle?,
	lastAttack: number,
	lastThrow: number,
	lastRequest: number,
	lastSync: number,
	lastUpgrade: number,
	carryOverflowCount: number,
	levels: PersonalRules.Levels,
	movement: PersonalMovement.State,
	closing: boolean,
}
local PotionReserveName = "PotionReserve"
local Manager = {}
local random = Random.new()
Manager.__index = Manager
export type Manager = typeof(setmetatable(
	{} :: {
		initialized: boolean,
		data: PlayerData,
		replication: Replication.Replication,
		closing: boolean,
		scope: Lifecycle.Lifecycle,
		runtime: Folder,
		items: { [string]: Types.Item },
		players: { [Player]: PlayerRecord },
		removing: { [Player]: boolean },
		pool: { string },
		poolOverflowCount: number,
		shelfCounts: { [number]: number },
		shelfVisible: { [number]: { string } },
		unlockedFacilities: { [number]: boolean },
		unlockLocks: { [number]: boolean },
		chuteVisible: { string },
		chuteOverflowCount: number,
		chuteTakeSerial: number,
		autoPaintedVisible: { string },
		autoPaintedOverflowCount: number,
		autoOutputTakeSerial: number,
		autoRuneItemId: string?,
		autoRuneEnds: number,
		autoRuneSegments: { Types.VisualSegment }?,
		autoRuneCursor: number,
		autoRuneVisualQueue: { { id: string, segments: { Types.VisualSegment }, revision: number } },
		autoSmelterItemId: string?,
		autoSmelterEnds: number,
		autoShelfCount: number,
		autoShelfVisible: { string },
		autoShelfTakeSerial: number,
		agents: AutomationAgents.State?,
		tableId: string?,
		altarId: string?,
		altarEnds: number,
		altarHeld: boolean,
		paint: PaintSession?,
		stationVersions: { [string]: number },
		stationKeys: { [string]: string },
		revision: number,
		nextSpawn: number,
		nextUpdate: number,
		nextToolbarOrder: number,
	},
	Manager
))
function Manager.new(data: PlayerData?): Manager
	local playerData: PlayerData = data or {
		IsActive = Info.IsActive,
		CanAddCoins = Info.CanAddCoins,
		AddCoins = Info.AddCoins,
		CanSpendCoins = Info.CanSpendCoins,
		SpendCoins = Info.SpendCoins,
		TrySpendCoins = Info.TrySpendCoins,
	}
	local runtime = Instance.new("Folder")
	runtime.Name = "GameRuntime"
	return setmetatable({
		initialized = false,
		data = playerData,
		replication = Replication.new(),
		closing = false,
		scope = Lifecycle.new(),
		runtime = runtime,
		items = {},
		players = {},
		removing = {},
		pool = {},
		poolOverflowCount = 0,
		shelfCounts = {},
		shelfVisible = {},
		unlockedFacilities = {},
		unlockLocks = {},
		chuteVisible = {},
		chuteOverflowCount = 0,
		chuteTakeSerial = 0,
		autoPaintedVisible = {},
		autoPaintedOverflowCount = 0,
		autoOutputTakeSerial = 0,
		autoRuneItemId = nil,
		autoRuneEnds = 0,
		autoRuneSegments = nil,
		autoRuneCursor = 0,
		autoRuneVisualQueue = {},
		autoSmelterItemId = nil,
		autoSmelterEnds = 0,
		autoShelfCount = 0,
		autoShelfVisible = {},
		autoShelfTakeSerial = 0,
		agents = nil,
		tableId = nil,
		altarId = nil,
		altarEnds = 0,
		altarHeld = false,
		paint = nil,
		stationVersions = {
			Pool = 1,
			Table = 1,
			Altar = 1,
			Shelf = 1,
			Sigil = 1,
			Chute = 1,
			ChutePickup = 1,
			AutoOutput = 1,
			AutoShelf = 1,
		},
		stationKeys = {},
		revision = 0,
		nextSpawn = 0,
		nextUpdate = 0,
		nextToolbarOrder = 0,
	}, Manager)
end
function Manager.PoolCount(self: Manager): number
	return #self.pool + self.poolOverflowCount
end
function Manager.ChuteCount(self: Manager): number
	return #self.chuteVisible + self.chuteOverflowCount
end
function Manager.AutoPaintedCount(self: Manager): number
	return #self.autoPaintedVisible + self.autoPaintedOverflowCount
end
function Manager.AutoShelfCount(self: Manager): number
	return self.autoShelfCount
end
local function IsAutomationLocation(location: string): boolean
	return location == "Chute" or location == "AutoOutput" or location == "AutoRune" or location == "AutoSmelter" or location == "BruteCarried"
end
local function MarkAutoPaintedAppearance(item: Types.Item): ()
	item.model:SetAttribute("AutoPainted", true)
end
local function QueueAutoRuneSegments(self: Manager, item: Types.Item, segments: { Types.VisualSegment }): ()
	if #segments == 0 then
		return
	end
	local state = item.visualState or VisualRules.New()
	item.visualState = state
	local batch: { Types.VisualSegment } = {}
	local function FlushBatch(): ()
		if #batch == 0 then
			return
		end
		state.revision += 1
		local packet = batch
		batch = {}
		table.insert(self.autoRuneVisualQueue, { id = item.id, segments = packet, revision = state.revision })
	end
	for _, segment in segments do
		if state.segments[segment.key] == nil then
			local stored = table.clone(segment)
			state.segments[stored.key] = stored
			state.count += 1
			table.insert(batch, stored)
			if #batch >= Config.PaintVisualBatchSize then
				FlushBatch()
			end
		end
	end
	FlushBatch()
end
local function AdvanceAutoRuneVisual(self: Manager, now: number): ()
	local id = self.autoRuneItemId
	local item = if id then self.items[id] else nil
	local pattern = self.autoRuneSegments
	if not item or not pattern then
		return
	end
	local duration = math.max(Config.AutoRuneSeconds, 1e-3)
	local alpha = 1
	if now < self.autoRuneEnds then
		alpha = math.clamp((now - (self.autoRuneEnds - duration)) / duration, 0, 1)
	end
	local target = if alpha >= 1 then #pattern else math.floor(alpha * #pattern + 1e-6)
	if target <= self.autoRuneCursor then
		return
	end
	local slice: { Types.VisualSegment } = {}
	for index = self.autoRuneCursor + 1, target do
		table.insert(slice, pattern[index])
	end
	self.autoRuneCursor = target
	QueueAutoRuneSegments(self, item, slice)
end
local function FlushAutoRuneVisuals(self: Manager): ()
	local queue = self.autoRuneVisualQueue
	if #queue == 0 then
		return
	end
	self.autoRuneVisualQueue = {}
	for _, packet in queue do
		if self.items[packet.id] then
			Net.Broadcast({
				kind = "VisualDelta",
				id = packet.id,
				segments = packet.segments,
				visualRevision = packet.revision,
			})
		end
	end
end
local function CreateStationBody(self: Manager, location: string, stage: string, pose: CFrame): Types.Item?
	local template = ModelTemplates.FindCharacter("WhiteR15")
	if not template then
		return nil
	end
	local model = template:Clone()
	local id = HttpService:GenerateGUID(false)
	model.Name = "WhiteNPC"
	model:SetAttribute("ItemId", id)
	model:SetAttribute("GroundPresentation", Physics.GroundRootEnabled)
	model:PivotTo(pose)
	model.Parent = self.runtime
	Ragdoll.Setup(model)
	local item: Types.Item = {
		id = id,
		kind = "Body",
		stage = stage,
		location = location,
		version = 1,
		model = model,
		holder = nil,
		hits = Config.StunHits,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = Surface.Total(model),
		progress = if stage == "Painted" then 1 else 0,
		paintSeconds = 0,
		streetSlot = false,
		nextWalk = 0,
		carryWeld = nil,
		walkTrack = nil,
	}
	self.items[id] = item
	return item
end
function Manager.SpawnPoolBody(self: Manager): Types.Item?
	local item = CreateStationBody(self, "Pool", "Unpainted", Scene.PoolPose(#self.pool + 1))
	if item then
		Carry.RecoverPool(item)
	end
	return item
end
function Manager.ReplenishPoolVisible(self: Manager): ()
	while #self.pool < Config.PoolVisibleLimit and self.poolOverflowCount > 0 do
		local item = self:SpawnPoolBody()
		if not item then
			break
		end
		self.poolOverflowCount -= 1
		table.insert(self.pool, item.id)
	end
end
function Manager.ReleaseChuteBody(self: Manager, item: Types.Item, pose: CFrame, restoreTool: boolean?): ()
	local pile = {}
	for _, id in self.chuteVisible do
		local other = self.items[id]
		if other and other ~= item and other.model.Parent and other.model.PrimaryPart
			and Scene.ChutePileContains(other.model.PrimaryPart.Position)
		then
			table.insert(pile, other.model)
		end
	end
	Carry.ReleaseIntoChute(item, pose, pile, restoreTool)
	item.chuteRecoverAt = workspace:GetServerTimeNow() + Physics.PoolRecoverSeconds
end
function Manager.SpawnChuteBody(self: Manager): Types.Item?
	local pose = Scene.ChuteDropPose(random)
	local item = CreateStationBody(self, "Chute", "Unpainted", pose)
	if item then
		self:ReleaseChuteBody(item, pose, false)
	end
	return item
end
function Manager.SpawnAutoPaintedBody(self: Manager): Types.Item?
	local pose = Scene.AutoOutputPose(#self.autoPaintedVisible + 1)
	local item = CreateStationBody(self, "AutoOutput", "Painted", pose)
	if item then
		MarkAutoPaintedAppearance(item)
		Carry.Static(item, pose, false)
		QueueAutoRuneSegments(self, item, AutoRunePattern.Build(item.model))
	end
	return item
end
function Manager.ReplenishChuteVisible(self: Manager): ()
	for index = #self.chuteVisible, 1, -1 do
		if self.items[self.chuteVisible[index]] == nil then
			table.remove(self.chuteVisible, index)
		end
	end
	while #self.chuteVisible < Config.AutoQueueVisibleLimit and self.chuteOverflowCount > 0 do
		local item = self:SpawnChuteBody()
		if not item then
			break
		end
		self.chuteOverflowCount -= 1
		table.insert(self.chuteVisible, item.id)
	end
end
function Manager.ReplenishAutoPaintedVisible(self: Manager): ()
	for index = #self.autoPaintedVisible, 1, -1 do
		if self.items[self.autoPaintedVisible[index]] == nil then
			table.remove(self.autoPaintedVisible, index)
		end
	end
	while #self.autoPaintedVisible < Config.AutoQueueVisibleLimit and self.autoPaintedOverflowCount > 0 do
		local item = self:SpawnAutoPaintedBody()
		if not item then
			break
		end
		self.autoPaintedOverflowCount -= 1
		table.insert(self.autoPaintedVisible, item.id)
	end
	for index, id in self.autoPaintedVisible do
		local item = self.items[id]
		if item then
			local target = Scene.AutoOutputPose(index)
			if (item.model:GetPivot().Position - target.Position).Magnitude > 0.05 then
				Carry.Static(item, target, false)
				item.version += 1
			end
		end
	end
end
function Manager.SyncAutoShelfVisible(self: Manager): ()
	local target = math.min(self.autoShelfCount, Config.AutoQueueVisibleLimit)
	while #self.autoShelfVisible < target do
		table.insert(self.autoShelfVisible, HttpService:GenerateGUID(false))
	end
	while #self.autoShelfVisible > target do
		table.remove(self.autoShelfVisible)
	end
end
function Manager.AltarSummary(self: Manager): (string?, number, string)
	local now = workspace:GetServerTimeNow()
	local soonestId: string? = nil
	local soonest = math.huge
	local waitingId: string? = nil
	local parts: { string } = {}
	for _, item in self.items do
		if item.kind == "Body" and item.location == "Altar" and item.convertEnds then
			table.insert(parts, item.id .. "@" .. tostring(item.convertEnds))
			if item.convertEnds > now and item.convertEnds < soonest then
				soonestId = item.id
				soonest = item.convertEnds
			elseif now >= item.convertEnds then
				waitingId = waitingId or item.id
			end
		end
	end
	table.sort(parts)
	return soonestId or waitingId, (if soonestId then soonest else 0), table.concat(parts, ",")
end
function Manager.PeekChuteItem(self: Manager): Types.Item?
	while #self.chuteVisible > 0 and self.items[self.chuteVisible[1]] == nil do
		table.remove(self.chuteVisible, 1)
	end
	if #self.chuteVisible == 0 and self.chuteOverflowCount > 0 then
		self:ReplenishChuteVisible()
	end
	local id = self.chuteVisible[1]
	return if id then self.items[id] else nil
end
function Manager.PushChuteItem(self: Manager, item: Types.Item, restoreTool: boolean?, landing: CFrame?): ()
	if #self.chuteVisible < Config.AutoQueueVisibleLimit then
		self:ReleaseChuteBody(item, Scene.ChuteDropPose(random, landing), restoreTool)
		item.location = "Chute"
		item.stage = "Unpainted"
		item.streetSlot = false
		item.version += 1
		table.insert(self.chuteVisible, item.id)
	else
		Carry.Detach(item, restoreTool)
		NPC.StopMotion(item)
		self.items[item.id] = nil
		item.model:Destroy()
		self.chuteOverflowCount += 1
	end
end
function Manager.PeekAutoPaintedItem(self: Manager): Types.Item?
	while #self.autoPaintedVisible > 0 and self.items[self.autoPaintedVisible[1]] == nil do
		table.remove(self.autoPaintedVisible, 1)
	end
	if #self.autoPaintedVisible == 0 and self.autoPaintedOverflowCount > 0 then
		self:ReplenishAutoPaintedVisible()
	end
	local id = self.autoPaintedVisible[1]
	return if id then self.items[id] else nil
end
function Manager.PushAutoPaintedItem(self: Manager, item: Types.Item): ()
	if #self.autoPaintedVisible < Config.AutoQueueVisibleLimit then
		item.location = "AutoOutput"
		item.stage = "Painted"
		item.progress = 1
		item.streetSlot = false
		item.version += 1
		MarkAutoPaintedAppearance(item)
		Carry.Static(item, Scene.AutoOutputPose(#self.autoPaintedVisible + 1), false)
		table.insert(self.autoPaintedVisible, item.id)
	else
		Carry.Detach(item, false)
		NPC.StopMotion(item)
		self.items[item.id] = nil
		item.model:Destroy()
		self.autoPaintedOverflowCount += 1
	end
end
function Manager.IsFacilityUnlocked(self: Manager, facilityId: number): boolean
	return self.unlockedFacilities[facilityId] == true
end
function Manager.IsNearPad(self: Manager, player: Player, facilityId: number): boolean
	local root = self:Root(player)
	local pad = Scene.UnlockPads[facilityId]
	if not root or not pad then
		return false
	end
	local trigger = pad:FindFirstChild("TriggerZone")
	local center = if trigger and trigger:IsA("BasePart") then trigger.Position else pad:GetPivot().Position
	local dx = root.Position.X - center.X
	local dz = root.Position.Z - center.Z
	local dy = math.abs(root.Position.Y - center.Y)
	return (dx * dx + dz * dz) <= Config.UnlockPadTriggerRadius * Config.UnlockPadTriggerRadius
		and dy <= Config.UnlockPadHeightTolerance
end
function Manager.ApplyFacilityWorldState(self: Manager, facilityId: number): ()
	local pad = Scene.UnlockPads[facilityId]
	if pad then
		pad:SetAttribute("Unlocked", true)
		pad:SetAttribute("PadState", "Unlocked")
		for _, descendant in pad:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanTouch = false
				if descendant.Name == "OuterRim" or descendant.Name == "GlowRing" or descendant.Name == "InnerDisc" or descendant.Name == "CenterGlyph" then
					descendant.Transparency = 1
				end
			elseif descendant:IsA("PointLight") then
				descendant.Enabled = false
			elseif descendant:IsA("BillboardGui") then
				descendant.Enabled = false
			end
		end
	end
	local FacilityId = GameData.FacilityId
	if facilityId == FacilityId.FastChute then
		local cover = Scene.FastChuteCover
		if cover then
			cover:SetAttribute("Unlocked", true)
			for _, descendant in cover:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
					descendant.Transparency = 1
				elseif descendant:IsA("BillboardGui") then
					descendant.Enabled = false
				elseif descendant:IsA("SurfaceGui") then
					descendant.Enabled = false
				end
			end
		end
	elseif facilityId == FacilityId.Brute1 or facilityId == FacilityId.Brute2 then
		if Scene.BrutePost then
			Scene.BrutePost:SetAttribute("Unlocked", true)
		end
		local state = self:EnsureAgents()
		AutomationAgents.SyncUnlocked(state, workspace:GetServerTimeNow())
	elseif facilityId == FacilityId.AutoRune then
		if Scene.AutoRuneMachine then
			Scene.AutoRuneMachine:SetAttribute("Unlocked", true)
		end
	elseif facilityId == FacilityId.AutoSmelter then
		if Scene.AutoSmelterMachine then
			Scene.AutoSmelterMachine:SetAttribute("Unlocked", true)
		end
	elseif facilityId == FacilityId.AutoClerk then
		if Scene.AutoClerkStation then
			Scene.AutoClerkStation:SetAttribute("Unlocked", true)
		end
		local state = self:EnsureAgents()
		AutomationAgents.SyncUnlocked(state, workspace:GetServerTimeNow())
	end
end
function Manager.EnsureAgents(self: Manager): AutomationAgents.State
	local state = self.agents
	if state and not state.destroyed then
		return state
	end
	local created = AutomationAgents.New({
		runtime = self.runtime,
		scope = self.scope,
		items = self.items,
		stationVersions = self.stationVersions,
		isUnlocked = function(facilityId: number): boolean
			return self:IsFacilityUnlocked(facilityId)
		end,
		getAutoShelfCount = function(): number
			return self.autoShelfCount
		end,
		takeAutoShelf = function(): number
			local count = self.autoShelfCount
			if count <= 0 then
				return 0
			end
			self.autoShelfCount = 0
			self.autoShelfTakeSerial += 1
			self:SyncAutoShelfVisible()
			return count
		end,
		payPotionSale = function(count: number, warnIfBlocked: boolean): boolean
			return self:PayPotionSale(count, warnIfBlocked)
		end,
		pushChuteItem = function(item: Types.Item): ()
			self:PushChuteItem(item, false)
		end,
		stepAutomation = function(now: number): boolean
			return self:StepAutomation(now)
		end,
		changed = function(): ()
			self:Changed()
		end,
	})
	self.agents = created
	return created
end
function Manager.StepAutomationAgents(self: Manager, now: number): boolean
	local FacilityId = GameData.FacilityId
	if self.agents == nil and not (self:IsFacilityUnlocked(FacilityId.Brute1) or self:IsFacilityUnlocked(FacilityId.Brute2) or self:IsFacilityUnlocked(FacilityId.AutoClerk)) then
		return false
	end
	local state = self:EnsureAgents()
	return AutomationAgents.Step(state, now)
end
function Manager.StepAutomation(self: Manager, now: number): boolean
	local changed = false
	if self:IsFacilityUnlocked(GameData.FacilityId.AutoRune) then
		if self.autoRuneItemId ~= nil and now >= self.autoRuneEnds then
			AdvanceAutoRuneVisual(self, now)
			local doneId = self.autoRuneItemId
			self.autoRuneItemId = nil
			self.autoRuneEnds = 0
			self.autoRuneSegments = nil
			self.autoRuneCursor = 0
			local doneItem = self.items[doneId]
			if doneItem then
				self:PushAutoPaintedItem(doneItem)
			elseif #self.autoPaintedVisible < Config.AutoQueueVisibleLimit then
				local created = self:SpawnAutoPaintedBody()
				if created then
					table.insert(self.autoPaintedVisible, created.id)
				else
					self.autoPaintedOverflowCount += 1
				end
			else
				self.autoPaintedOverflowCount += 1
			end
			changed = true
		elseif self.autoRuneItemId ~= nil then
			AdvanceAutoRuneVisual(self, now)
		end
		if self.autoRuneItemId == nil and self:ChuteCount() > 0 then
			local nextItem = self:PeekChuteItem()
			if nextItem then
				table.remove(self.chuteVisible, 1)
				self:ReplenishChuteVisible()
				self.autoRuneItemId = nextItem.id
				self.autoRuneEnds = now + Config.AutoRuneSeconds
				nextItem.location = "AutoRune"
				nextItem.stage = "Painting"
				nextItem.version += 1
				Carry.Static(nextItem, Scene.AutoRunePose(), false)
				self.autoRuneSegments = AutoRunePattern.Build(nextItem.model)
				self.autoRuneCursor = 0
				AdvanceAutoRuneVisual(self, now)
				changed = true
			elseif self.chuteOverflowCount > 0 then
				self.chuteOverflowCount -= 1
				self.autoRuneItemId = HttpService:GenerateGUID(false)
				self.autoRuneEnds = now + Config.AutoRuneSeconds
				self.autoRuneSegments = nil
				self.autoRuneCursor = 0
				changed = true
			end
		end
	end
	if self:IsFacilityUnlocked(GameData.FacilityId.AutoSmelter) then
		if self.autoSmelterItemId ~= nil and now >= self.autoSmelterEnds then
			local doneId = self.autoSmelterItemId
			self.autoSmelterItemId = nil
			self.autoSmelterEnds = 0
			local doneItem = self.items[doneId]
			if doneItem then
				self.items[doneId] = nil
				doneItem.model:Destroy()
			end
			self.autoShelfCount += 1
			self:SyncAutoShelfVisible()
			changed = true
		end
		if self.autoSmelterItemId == nil and self:AutoPaintedCount() > 0 then
			local nextItem = self:PeekAutoPaintedItem()
			if nextItem then
				table.remove(self.autoPaintedVisible, 1)
				self:ReplenishAutoPaintedVisible()
				self.autoSmelterItemId = nextItem.id
				self.autoSmelterEnds = now + Config.AutoSmelterSeconds
				nextItem.location = "AutoSmelter"
				nextItem.stage = "Converting"
				nextItem.version += 1
				Carry.Static(nextItem, Scene.AutoSmelterPose(), false)
				changed = true
			elseif self.autoPaintedOverflowCount > 0 then
				self.autoPaintedOverflowCount -= 1
				self.autoSmelterItemId = HttpService:GenerateGUID(false)
				self.autoSmelterEnds = now + Config.AutoSmelterSeconds
				changed = true
			end
		end
	end
	return changed
end
function Manager.TryUnlockFacility(self: Manager, player: Player, facilityId: number): boolean
	if self.closing or self.unlockedFacilities[facilityId] or self.unlockLocks[facilityId] then
		return false
	end
	local def = GameData.GetFacility(facilityId)
	if not def then
		return false
	end
	local record = self.players[player]
	if not record or record.closing or not self.data.IsActive(player) then
		return false
	end
	if not AutomationRules.ArePrerequisitesMet(facilityId, self.unlockedFacilities) then
		return false
	end
	if not self:IsNearPad(player, facilityId) then
		return false
	end
	self.unlockLocks[facilityId] = true
	if self.unlockedFacilities[facilityId] then
		self.unlockLocks[facilityId] = nil
		return false
	end
	local canSpend = self.data.CanSpendCoins
	local hasCoins = if canSpend then canSpend(player, def.cost) else Info.CanSpendCoins(player, def.cost)
	if not hasCoins then
		self.unlockLocks[facilityId] = nil
		return false
	end
	local paid = if self.data.TrySpendCoins
		then self.data.TrySpendCoins(player, def.cost)
		elseif self.data.SpendCoins then self.data.SpendCoins(player, def.cost)
		else Info.TrySpendCoins(player, def.cost)
	if not paid then
		self.unlockLocks[facilityId] = nil
		return false
	end
	self.unlockedFacilities[facilityId] = true
	self:ApplyFacilityWorldState(facilityId)
	self.unlockLocks[facilityId] = nil
	local okName, displayName = pcall(function(): string
		return player.DisplayName
	end)
	local actorName = if okName and typeof(displayName) == "string" and displayName ~= "" then displayName else player.Name
	Net.Broadcast({
		kind = "Message",
		textId = "FacilityUnlocked",
		textArgs = { actorName, def.name_t },
	})
	self:StepAutomation(workspace:GetServerTimeNow())
	self:Changed()
	return true
end
function Manager.Snapshot(self: Manager): Types.Snapshot
	local shelfItems: { [string]: CFrame } = {}
	for quality, ids in self.shelfVisible do
		for slot, id in ids do
			shelfItems[id] = Scene.ShelfPose(quality, slot)
		end
	end
	local autoShelfItems: { [string]: CFrame } = {}
	for slot, id in self.autoShelfVisible do
		autoShelfItems[id] = Scene.AutoShelfPose(slot)
	end
	local list: { Types.ItemView } = {}
	for _, item in self.items do
		if item.location == "Shelf" or item.location == "Toolbar" then continue end
		table.insert(list, {
			id = item.id,
			kind = item.kind,
			stage = item.stage,
			location = item.location,
			version = item.version,
			model = item.model,
			hits = item.hits,
			hp = item.hp,
			maxHp = item.maxHp,
			fall = item.fall,
			progress = item.progress,
			holder = if item.holder then item.holder.UserId else nil,
			carryOrder = item.carryOrder,
			paintSlot = item.paintSlot,
			visualCount = if item.visualState then item.visualState.count else 0,
			paintFlipped = item.paintFlipped == true,
			flyEnds = item.flyEnds,
			convertEnds = item.convertEnds,
			toss = if item.poolToss then {
				from = item.poolToss.from,
				target = item.poolToss.target,
				started = item.poolToss.started,
				owner = item.poolToss.owner,
				kind = item.poolToss.kind,
				origin = item.poolToss.origin,
				velocity = item.poolToss.velocity,
				duration = item.poolToss.duration,
				chuteDropFrom = item.poolToss.chuteDropFrom,
				wallStop = item.poolToss.wallStop,
			} else nil,
			altarToss = if item.altarToss then {
				from = item.altarToss.from,
				rest = item.altarToss.rest,
				started = item.altarToss.started,
				flightStarts = item.altarToss.flightStarts,
				landEnds = item.altarToss.landEnds,
			} else nil,
			altarTossStarted = if item.altarToss then item.altarToss.started else nil,
		})
	end
	local body = if self.tableId then self.items[self.tableId] else nil
	local altarId, altarEnds = self:AltarSummary()
	self.altarId, self.altarEnds = altarId, altarEnds
	return {
		revision = self.revision,
		paintOrientation = if body then body.paintOrientation else nil,
		paintFlipped = if body then body.paintFlipped == true else false,
		bodyPose = if body then body.poseBody else nil,
		stationVersions = table.clone(self.stationVersions),
		items = list,
		pool = self:PoolCount(),
		shelf = self:ShelfCount(),
		shelfItems = shelfItems,
		tableId = self.tableId,
		altarId = self.altarId,
		altarEnds = self.altarEnds,
		painter = if self.paint then self.paint.player.UserId else nil,
		session = if self.paint then self.paint.token else nil,
		unlockedFacilities = (function(): { [number]: boolean }
			local copy: { [number]: boolean } = {}
			for _, facility in GameData.GetAllFacilities() do
				copy[facility.id] = self.unlockedFacilities[facility.id] == true
			end
			return copy
		end)(),
		chuteQueue = self:ChuteCount(),
		autoPaintedQueue = self:AutoPaintedCount(),
		autoShelfCount = self:AutoShelfCount(),
		autoShelfItems = autoShelfItems,
		autoRuneEnds = self.autoRuneEnds,
		autoSmelterEnds = self.autoSmelterEnds,
	}
end
function Manager.Changed(self: Manager): ()
	for player, record in self.players do
		player:SetAttribute("CarryBodyCount", self:CarryCount(player, record))
	end
	local _, _, altarKey = self:AltarSummary()
	local keys: { [string]: string } = {
		Pool = table.concat(self.pool, ",") .. "#" .. tostring(self.poolOverflowCount),
		Table = (self.tableId or "") .. (if self.paint then self.paint.token else ""),
		Altar = altarKey,
		Shelf = self:ShelfKey(),
		Chute = if self.unlockedFacilities[GameData.FacilityId.FastChute] then "1" else "0",
		ChutePickup = (if self:ChuteCount() > 0 then "ready:" else "empty:") .. tostring(self.chuteTakeSerial),
		AutoOutput = (if self:AutoPaintedCount() > 0 then "ready:" else "empty:") .. tostring(self.autoOutputTakeSerial),
		AutoShelf = (if self.autoShelfCount > 0 then "ready:" else "empty:") .. tostring(self.autoShelfTakeSerial),
	}
	for name, key in keys do
		if self.stationKeys[name] ~= key then
			self.stationKeys[name] = key
			self.stationVersions[name] += 1
		end
	end
	self.revision += 1
	self.replication:Broadcast(self:Snapshot())
	FlushAutoRuneVisuals(self)
end
function Manager.Tell(_self: Manager, player: Player, textId: GameTexts.TextId, args: {string}?): ()
	Net.FireNotify(player, { kind = "Message", textId = textId, textArgs = args })
end
function Manager.Carried(self: Manager, player: Player): { Types.Item }
	local list: { Types.Item } = {}
	for _, item in self.items do
		if item.holder == player and item.kind == "Body" then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a: Types.Item, b: Types.Item): boolean
		local left, right = a.carryOrder or 0, b.carryOrder or 0
		if left ~= right then
			return left > right
		end
		return a.id < b.id
	end)
	return list
end
function Manager.CarryCount(self: Manager, player: Player, record: PlayerRecord?): number
	local owner = record or self.players[player]
	local count = if owner then owner.carryOverflowCount else 0
	for _, item in self.items do
		if item.holder == player and item.kind == "Body" then count += 1 end
	end
	return count
end
function Manager.TakeBody(self: Manager, player: Player, item: Types.Item): boolean
	local record = self.players[player]
	local stack = self:Carried(player)
	local count = #stack + (if record then record.carryOverflowCount else 0)
	local capacity = PersonalRules.GetCarryTier(if record then record.levels.carryTool else 1).capacity
	if count >= capacity or self:ShoulderOccupied(player) then
		self:Tell(player, "HandsFull")
		return false
	end
	if #stack < Config.CarryVisibleLimit then
		if not Carry.Take(item, player, #stack) then return false end
		self:Restack(player)
		return true
	end
	-- The virtual count represents fresh white bodies. Keep bodies with rune data as entities.
	if not record or item.stage == "Painted" or item.progress > 0 or item.visualState or not self:Root(player) then
		self:Tell(player, "HandsFull")
		return false
	end
	Carry.Detach(item, false)
	NPC.StopMotion(item)
	self.items[item.id] = nil
	item.model:Destroy()
	record.carryOverflowCount += 1
	return true
end
function Manager.Held(self: Manager, player: Player): Types.Item?
	local carried = self:Carried(player)
	if carried[1] then
		return carried[1]
	end
	for _, item in self.items do
		if item.holder == player then
			return item
		end
	end
	return nil
end
function Manager.ShoulderOccupied(self: Manager, player: Player): boolean
	for _, item in self.items do
		if item.holder == player and item.kind ~= "Body" then
			return true
		end
	end
	return false
end
function Manager.HasOtherBodies(self: Manager, player: Player, except: Types.Item): boolean
	local record = self.players[player]
	if record and record.carryOverflowCount > 0 then return true end
	for _, item in self.items do
		if item ~= except and item.holder == player and item.kind == "Body" then
			return true
		end
	end
	return false
end
function Manager.Restack(self: Manager, player: Player): ()
	local stack = self:Carried(player)
	local record = self.players[player]
	local root = self:Root(player)
	if record and root then
		while #stack < Config.CarryVisibleLimit and record.carryOverflowCount > 0 do
			local item = CreateStationBody(self, "Ground", "Unpainted", root.CFrame)
			if not item then break end
			if not Carry.Take(item, player, #stack) then
				self.items[item.id] = nil
				item.model:Destroy()
				break
			end
			record.carryOverflowCount -= 1
			table.insert(stack, 1, item)
		end
	end
	if #stack == 0 then return end
	local bottomUp: { Types.Item } = {}
	for index = #stack, 1, -1 do
		table.insert(bottomUp, stack[index])
	end
	Carry.Restack(bottomUp)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:UnequipTools()
	end
end
function Manager.Root(_self: Manager, player: Player): BasePart?
	local character = player.Character
	local h = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if h and h.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end
function Manager.Near(self: Manager, player: Player, position: Vector3, range: number, target: Model?, ignored: Instance?): boolean
	local root = self:Root(player)
	local char = player.Character
	return root ~= nil and char ~= nil and (root.Position - position).Magnitude <= range and Scene.Visible(char, position, target, ignored)
end
function Manager.ShelfCount(self: Manager): number
	local count = 0
	for _, amount in self.shelfCounts do
		count += amount
	end
	return count
end
function Manager.QualityCount(self: Manager, quality: number): number
	return self.shelfCounts[quality] or 0
end
function Manager.ShelfKey(self: Manager): string
	local qualities: { number } = {}
	for quality, amount in self.shelfCounts do
		if amount > 0 then
			table.insert(qualities, quality)
		end
	end
	table.sort(qualities)
	local parts: { string } = {}
	for _, quality in qualities do
		local count = self.shelfCounts[quality] or 0
		local visible = self.shelfVisible[quality]
		table.insert(parts, tostring(quality) .. ":" .. tostring(count) .. ":" .. (if visible then table.concat(visible, ",") else ""))
	end
	return table.concat(parts, ";")
end
function Manager.LaunchToAltar(self: Manager, item: Types.Item, started: number?): ()
	local layer = 0
	for _, other in self.items do
		if other ~= item and other.kind == "Body" and other.location == "Altar" then layer += 1 end
	end
	local now = started or workspace:GetServerTimeNow()
	local fromTable = item.location == "Table"
	item.stage = "Converting"
	item.location = "Altar"
	item.flyEnds = nil
	item.convertEnds = nil
	item.altarHeld = false
	item.version += 1
	if self.tableId == item.id then self.tableId = nil end
	local holder = item.holder
	local keep = holder ~= nil and self:HasOtherBodies(holder, item)
	Carry.BeginAltarToss(item, layer, fromTable, now, not keep)
	if holder and keep then
		self:Restack(holder)
	end
end
function Manager.SpawnAltarPotion(self: Manager, item: Types.Item): ()
	local quality = Config.DefaultPotionQuality
	item.model:Destroy()
	self.items[item.id] = nil
	self.shelfCounts[quality] = (self.shelfCounts[quality] or 0) + 1
	local visible = self.shelfVisible[quality]
	if not visible then
		visible = {}
		self.shelfVisible[quality] = visible
	end
	if #visible < Config.ShelfVisibleLimit then
		table.insert(visible, HttpService:GenerateGUID(false))
	end
end
local function BatchIds(session: PaintSession): { string }
	local ids = {}
	for _, body in ipairs(session.batch or {}) do
		table.insert(ids, body.id)
	end
	return ids
end

local function SyncBatchPose(session: PaintSession, item: Types.Item): ()
	local frames = item.poseBody
	if not frames then return end
	local pivot = PaintRotation.Pose(Scene.TablePose(), session.geometry, session.orientation)
	for index, body in ipairs(session.batch or {}) do
		if body.model.Parent then
			BodyPose.Apply(body.model, pivot + PaintRotation.BatchOffset(index + 1), frames)
		end
	end
end

local function ReturnBatchBody(self: Manager, body: Types.Item): ()
	body.paintSlot = nil
	body.visualState = nil
	if #self.pool < Config.PoolVisibleLimit then
		body.location, body.stage = "Pool", "Unpainted"
		body.version += 1
		table.insert(self.pool, body.id)
		Carry.RecoverPool(body)
	else
		self.items[body.id] = nil
		body.model:Destroy()
		self.poolOverflowCount += 1
	end
end

local function TakePoolBody(self: Manager, freshOnly: boolean): Types.Item?
	self:ReplenishPoolVisible()
	local index = 1
	while index <= #self.pool do
		local item = self.items[self.pool[index]]
		if not item then
			table.remove(self.pool, index)
			self:ReplenishPoolVisible()
		elseif not freshOnly or (item.progress == 0 and item.visualState == nil and item.stage ~= "Painted") then
			table.remove(self.pool, index)
			self:ReplenishPoolVisible()
			return item
		else
			index += 1
		end
	end
	if self.poolOverflowCount > 0 then
		local item = self:SpawnPoolBody()
		if item then self.poolOverflowCount -= 1 end
		return item
	end
	return nil
end

local function FillPaintBatch(self: Manager, session: PaintSession, center: Types.Item, limit: number): ()
	local batch = session.batch or {}
	session.batch = batch
	if limit <= 1 then return end
	local stack = self:Carried(session.player)
	local function Place(body: Types.Item): ()
		table.insert(batch, body)
		local slot = #batch + 1
		body.paintSlot = slot
		body.visualState = center.visualState
		body.location, body.stage = "Table", "Painting"
		body.streetSlot = false
		body.version += 1
		Carry.Static(body, Scene.TablePose() + PaintRotation.BatchOffset(slot), false)
	end
	for _, body in stack do
		if #batch >= limit - 1 then break end
		if body.progress == 0 and body.visualState == nil and body.stage ~= "Painted" then
			Place(body)
		end
	end
	while #batch < limit - 1 do
		local body = TakePoolBody(self, true)
		if not body then break end
		Place(body)
	end
	SyncBatchPose(session, center)
end

function Manager.EndPaint(self: Manager, player: Player): ()
	local session = self.paint
	if not session or session.player ~= player then
		return
	end
	local item = self.items[session.id]
	local altarToss: Types.AltarTossView? = nil
	local altarTossStarted: number? = nil
	if item and item.progress >= 1 then
		SyncBatchPose(session, item)
		item.stage = "Painted"
		local started = workspace:GetServerTimeNow()
		self:LaunchToAltar(item, started)
		for _, body in ipairs(session.batch or {}) do
			body.paintSlot = nil
			body.stage, body.progress = "Painted", 1
			body.paintFlipped, body.paintOrientation = item.paintFlipped, item.paintOrientation
			body.visualState = item.visualState
			self:LaunchToAltar(body, started)
		end
		if item.altarToss then
			altarTossStarted = item.altarToss.started
			altarToss = {
				from = item.altarToss.from,
				rest = item.altarToss.rest,
				started = item.altarToss.started,
				flightStarts = item.altarToss.flightStarts,
				landEnds = item.altarToss.landEnds,
			}
		end
	elseif item then
		local restOrientation = if Config.PaintRotationEnabled then CFrame.identity else PaintRotation.FlatOrientation(item.paintFlipped == true)
		Painting.SetPose(session, item, Scene.TablePose(), restOrientation)
		item.stage = "Painting"
		item.version += 1
	end
	if not item and self.tableId == session.id then self.tableId = nil end
	if not item or item.progress < 1 then
		for _, body in ipairs(session.batch or {}) do
			ReturnBatchBody(self, body)
		end
	end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if hum then
		local record = self.players[player]
		if record then
			hum.WalkSpeed = PersonalRules.GetMoveTier(record.levels.moveSpeed).walk
			if character then PersonalMovement.Publish(record.movement, character, hum.WalkSpeed, false) end
		end
		hum.JumpPower = session.jumpPower
		hum.JumpHeight = session.jumpHeight
	end
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
	if hum and hum.Health > 0 and #self:Carried(player) == 0 then
		local backpack = player:FindFirstChild("Backpack")
		local weapon = PersonalRules.FindWeapon(backpack)
		if weapon then
			hum:EquipTool(weapon)
		end
	end
	player:SetAttribute("Painting", false)
	self.paint = nil
	Net.FireNotify(player, { kind = "EndPaint", session = session.token, id = session.id, started = altarTossStarted, altarToss = altarToss })
end
function Manager.BeginPaint(self: Manager, player: Player, item: Types.Item): boolean
	if self.paint then
		self:Tell(player, "TableInUse")
		return false
	end
	local character = player.Character
	local root = self:Root(player)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not hum or hum.Health <= 0 then
		return false
	end
	local initialFlipped = not Config.PaintRotationEnabled and item.paintFlipped == true
	local initialOrientation = PaintRotation.FlatOrientation(initialFlipped)
	local session: PaintSession = {
		player = player,
		batch = {},
		id = item.id,
		token = HttpService:GenerateGUID(false),
		last = workspace:GetServerTimeNow(),
		sequence = 0,
		orientation = initialOrientation,
		jumpPower = hum.JumpPower,
		jumpHeight = hum.JumpHeight,
	}
	self.paint = session
	item.paintOrientation = initialOrientation
	item.poseBody=nil
	item.stage, item.location = "Painting", "Table"
	item.streetSlot = false
	item.version += 1
	self.tableId = item.id
	hum:UnequipTools()
	hum.WalkSpeed = 0
	local record = self.players[player]
	if record then
		record.movement.wanted = false
		record.movement.lastPosition = nil
		PersonalMovement.Publish(record.movement, character, 0, false)
	end
	hum.JumpPower = 0
	hum.JumpHeight = 0
	root.Anchored = true
	player:SetAttribute("Painting", true)
	Carry.Static(item, Scene.TablePose(), false)
	local frames = BodyPose.Capture(item.model)
	item.poseBody = frames
	if not item.exteriorMeasured then
		item.totalArea -= CurvedSurface.ExcludeInterior(item.model,item.covered)
		item.exteriorMeasured = true
	end
	session.geometry = PaintRotation.Create(item.model, frames)
	if initialFlipped then
		Painting.SetPose(session, item, Scene.TablePose(), initialOrientation, true)
	end
	FillPaintBatch(self, session, item, if record then PersonalRules.GetRuneBatch(record.levels.runeBatch) else 1)
	self:Restack(player)
	Net.FireNotify(player, { kind = "BeginPaint", id = item.id, session = session.token, paintBatch = BatchIds(session), bodyPose = frames, orientation = initialOrientation, flipped = initialFlipped })
	return true
end
function Manager.Pool(self: Manager, player: Player): boolean
	local stack = self:Carried(player)
	local deposit: { Types.Item } = {}
	for _, item in stack do
		if item.stage ~= "Painted" then table.insert(deposit, item) end
	end
	local record = self.players[player]
	local overflow = if record then record.carryOverflowCount else 0
	if #deposit > 0 or overflow > 0 then
		local keep = #deposit < #stack
		if record then record.carryOverflowCount = 0 end
		for index, item in deposit do
			local restore = index == #deposit and not keep
			if #self.pool < Config.PoolVisibleLimit then
				item.location = "Pool"
				item.version += 1
				table.insert(self.pool, item.id)
				Carry.TossIntoPool(item, restore)
			else
				Carry.Detach(item, restore)
				NPC.StopMotion(item)
				self.items[item.id] = nil
				item.model:Destroy()
				self.poolOverflowCount += 1
			end
		end
		self.poolOverflowCount += overflow
		self:ReplenishPoolVisible()
		if keep then self:Restack(player) end
		return true
	elseif #stack > 0 or self:ShoulderOccupied(player) then
		self:Tell(player, "StoreUnfinished")
		return false
	elseif self:PoolCount() > 0 then
		while #self.pool > 0 and self.items[self.pool[1]] == nil do
			table.remove(self.pool, 1)
		end
		if #self.pool == 0 then
			self:ReplenishPoolVisible()
		end
		local id = self.pool[1]
		local item = if id then self.items[id] else nil
		if item and self:TakeBody(player, item) then
			table.remove(self.pool, 1)
			self:ReplenishPoolVisible()
			return true
		end
		return false
	else
		self:Tell(player, "PoolIsEmpty")
		return false
	end
end
function Manager.Table(self: Manager, player: Player): boolean
	if self.paint then
		self:Tell(player, "TableInUse")
		return false
	end
	local stack = self:Carried(player)
	local occupied = #stack > 0 or self:ShoulderOccupied(player)
	if self.tableId then
		local item = self.items[self.tableId]
		if not item then
			return false
		end
		if item.stage == "Painted" then
			if occupied then
				self:Tell(player, "TableIsOccupied")
				return false
			end
			if self:TakeBody(player, item) then
				self.tableId = nil
				return true
			end
			return false
		else
			return self:BeginPaint(player, item)
		end
	end
	local chosen: Types.Item? = nil
	for _, item in stack do
		if item.stage ~= "Painted" then
			chosen = item
			break
		end
	end
	if not chosen and occupied then
		self:Tell(player, "BringUnfinished")
		return false
	end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not self:Root(player) then return false end
	local item = chosen or TakePoolBody(self, false)
	if not item then
		self:Tell(player, "BringStunned")
		return false
	end
	return self:BeginPaint(player, item)
end
function Manager.Altar(self: Manager, player: Player): boolean
	local chosen: Types.Item? = nil
	for _, item in self:Carried(player) do
		if item.stage == "Painted" then
			chosen = item
			break
		end
	end
	if not chosen then
		self:Tell(player, "AltarNeedsCompleted")
		return false
	end
	self:LaunchToAltar(chosen)
	return true
end
function Manager.OwnedPotion(self: Manager, player: Player, quality: number): Types.Item?
	local valid: Types.Item? = nil
	local stale: { string } = {}
	for id, item in self.items do
		if item.kind == "Potion" and item.owner == player and item.quality == quality and item.location == "Toolbar" then
			if item.model.Parent == nil then
				table.insert(stale, id)
			elseif not valid then
				valid = item
			end
		end
	end
	for _, id in stale do
		self.items[id] = nil
	end
	return valid
end
function Manager.GrantStack(self: Manager, player: Player, quality: number, count: number): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local existing = self:OwnedPotion(player, quality)
	if existing and existing.model:IsA("Tool") then
		if backpack and existing.model.Parent ~= backpack and existing.model.Parent ~= character then
			local ok = pcall(function(): ()
				existing.model.Parent = backpack
			end)
			if not ok or (existing.model.Parent ~= backpack and existing.model.Parent ~= character) then
				return nil
			end
		end
		local nextCount = (existing.stack or 1) + count
		existing.stack = nextCount
		existing.model:SetAttribute("StackCount", nextCount)
		existing.version += 1
		return existing.model
	end
	local template = ModelTemplates.FindItem("Potion")
	if not template then
		return nil
	end
	local tool = template:Clone()
	local id = HttpService:GenerateGUID(false)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	self.nextToolbarOrder += 1
	tool:SetAttribute("ItemId", id)
	tool:SetAttribute("ToolbarOrder", self.nextToolbarOrder)
	tool:SetAttribute("OwnerUserId", player.UserId)
	tool:SetAttribute("StackCount", count)
	tool:SetAttribute("Quality", quality)
	if backpack then
		local ok = pcall(function(): ()
			tool.Parent = backpack
		end)
		if not ok or tool.Parent ~= backpack then
			tool:Destroy()
			return nil
		end
	end
	local potion: Types.Item = {
		id = id,
		kind = "Potion",
		stage = "Ready",
		location = "Toolbar",
		version = 1,
		model = tool,
		holder = nil,
		owner = player,
		quality = quality,
		stack = count,
		hits = 0,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = 0,
		progress = 0,
		paintSeconds = 0,
		streetSlot = false,
		nextWalk = 0,
		carryWeld = nil,
		walkTrack = nil,
	}
	self.items[id] = potion
	return tool
end
function Manager.EquippedPotion(self: Manager, player: Player): Types.Item?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child.Name == "Potion" then
			local id = child:GetAttribute("ItemId")
			local item = if typeof(id) == "string" then self.items[id] else nil
			if item and item.kind == "Potion" and item.owner == player and item.model == child then
				return item
			end
		end
	end
	return nil
end
function Manager.RescuePotions(_self: Manager, player: Player, character: Model): ()
	local reserve = player:FindFirstChild(PotionReserveName)
	if not reserve then
		local folder = Instance.new("Folder")
		folder.Name = PotionReserveName
		folder.Parent = player
		reserve = folder
	end
	local function MovePotions(container: Instance?): ()
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == "Potion" then
				child.Parent = reserve
			end
		end
	end
	MovePotions(character)
	MovePotions(player:FindFirstChildOfClass("Backpack"))
end
function Manager.ReleasePotions(self: Manager, player: Player): ()
	local owned: { Types.Item } = {}
	for _, item in self.items do
		if item.kind == "Potion" and item.owner == player then
			table.insert(owned, item)
		end
	end
	for _, item in owned do
		self.items[item.id] = nil
		item.stage = "Consumed"
		item.model:Destroy()
	end
	local reserve = player:FindFirstChild(PotionReserveName)
	if reserve then
		reserve:Destroy()
	end
end
function Manager.Shelf(self: Manager, player: Player): boolean
	if #self:Carried(player) > 0 then
		self:Tell(player, "HandsFull")
		return false
	end
	if self:ShelfCount() == 0 then
		self:Tell(player, "PotionsNotReady")
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if (self.paint and self.paint.player == player) or not character or not humanoid or humanoid.Health <= 0 or not backpack then
		return false
	end
	local qualities: { number } = {}
	for quality, count in self.shelfCounts do
		if count > 0 then
			table.insert(qualities, quality)
		end
	end
	table.sort(qualities)
	local equip: Tool? = nil
	local granted: { number } = {}
	for _, quality in qualities do
		local count = self.shelfCounts[quality] or 0
		local tool = if count > 0 then self:GrantStack(player, quality, count) else nil
		if tool then
			if tool.Parent ~= backpack and tool.Parent ~= character then
				pcall(function(): ()
					tool.Parent = backpack
				end)
			end
			if tool.Parent == backpack or tool.Parent == character then
				table.insert(granted, quality)
				equip = tool
			end
		end
	end
	if #granted == 0 then
		return false
	end
	for _, quality in granted do
		self.shelfCounts[quality] = nil
		self.shelfVisible[quality] = nil
	end
	if equip then
		humanoid:EquipTool(equip)
	end
	return true
end
function Manager.Chute(self: Manager, player: Player): boolean
	if not self:IsFacilityUnlocked(GameData.FacilityId.FastChute) then
		self:Tell(player, "ChuteLocked")
		return false
	end
	local stack = self:Carried(player)
	local deposit: { Types.Item } = {}
	for _, item in stack do
		if item.stage ~= "Painted" then
			table.insert(deposit, item)
		end
	end
	local record = self.players[player]
	local overflow = if record then record.carryOverflowCount else 0
	if #deposit == 0 and overflow == 0 then
		if #stack > 0 or self:ShoulderOccupied(player) then
			self:Tell(player, "ChuteUnfinishedOnly")
		else
			self:Tell(player, "ChuteNeedsBody")
		end
		return false
	end
	local willHaveRemaining = #deposit < #stack
	for index, item in deposit do
		self:PushChuteItem(item, index == #deposit and not willHaveRemaining)
	end
	if record then record.carryOverflowCount = 0 end
	self.chuteOverflowCount += overflow
	self:ReplenishChuteVisible()
	if willHaveRemaining then
		self:Restack(player)
	end
	self:StepAutomation(workspace:GetServerTimeNow())
	return true
end
function Manager.ChutePickup(self: Manager, player: Player): boolean
	if self:ShoulderOccupied(player) then
		self:Tell(player, "HandsFull")
		return false
	end
	local item = self:PeekChuteItem()
	if not item then
		self:Tell(player, "ChuteEmpty")
		return false
	end
	if self:TakeBody(player, item) then
		table.remove(self.chuteVisible, 1)
		self.chuteTakeSerial += 1
		self:ReplenishChuteVisible()
		return true
	end
	return false
end
function Manager.AutoOutput(self: Manager, player: Player): boolean
	if self:ShoulderOccupied(player) then
		self:Tell(player, "HandsFull")
		return false
	end
	local item = self:PeekAutoPaintedItem()
	if not item then
		self:Tell(player, "AutoOutputEmpty")
		return false
	end
	if self:TakeBody(player, item) then
		table.remove(self.autoPaintedVisible, 1)
		self.autoOutputTakeSerial += 1
		self:ReplenishAutoPaintedVisible()
		return true
	end
	return false
end
function Manager.AutoShelf(self: Manager, player: Player): boolean
	if #self:Carried(player) > 0 then
		self:Tell(player, "HandsFull")
		return false
	end
	if self.autoShelfCount <= 0 then
		self:Tell(player, "NoAutoPotion")
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if (self.paint and self.paint.player == player) or not character or not humanoid or humanoid.Health <= 0 or not backpack then
		return false
	end
	local tool = self:GrantStack(player, Config.DefaultPotionQuality, self.autoShelfCount)
	if not tool then
		return false
	end
	if tool.Parent ~= backpack and tool.Parent ~= character then
		pcall(function(): ()
			tool.Parent = backpack
		end)
	end
	if tool.Parent ~= backpack and tool.Parent ~= character then
		return false
	end
	self.autoShelfCount = 0
	self.autoShelfTakeSerial += 1
	self:SyncAutoShelfVisible()
	humanoid:EquipTool(tool)
	return true
end
function Manager.OwnedPotions(self: Manager, player: Player): ({ Types.Item }, number)
	local list: { Types.Item } = {}
	local seen: { [string]: boolean } = {}
	local totalCount = 0
	local function Scan(container: Instance?): ()
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name == "Potion" then
				local id = child:GetAttribute("ItemId")
				local item = if typeof(id) == "string" then self.items[id] else nil
				if item and not seen[item.id] and item.kind == "Potion" and item.owner == player and item.model == child then
					seen[item.id] = true
					table.insert(list, item)
					totalCount += math.max(1, item.stack or 1)
				end
			end
		end
	end
	Scan(player.Character)
	Scan(player:FindFirstChildOfClass("Backpack"))
	return list, totalCount
end
function Manager.PayPotionSale(self: Manager, count: number, warnIfBlocked: boolean): boolean
	local paid = false
	local blocked: { Player } = {}
	for _, other in Players:GetPlayers() do
		if self.data.IsActive(other) then
			local record = self.players[other]
			local amount = PersonalRules.ComputePlayerPayout(count * Config.PotionReward, if record then record.levels.sellBonus else 1)
			if self.data.CanAddCoins(other, amount) and self.data.AddCoins(other, amount) then
				self:Tell(other, "CoinsAwarded", { tostring(amount) })
				paid = true
			else
				table.insert(blocked, other)
			end
		end
	end
	if paid or warnIfBlocked then
		for _, other in blocked do
			self:Tell(other, "CoinLimit")
		end
	end
	return paid
end
function Manager.Submit(self: Manager, player: Player): boolean
	local record = self.players[player]
	if not record or not self.data.IsActive(player) then
		return false
	end
	local potions, totalCount = self:OwnedPotions(player)
	if totalCount == 0 then
		self:Tell(player, "BringPotionSigil")
		return false
	end
	if not self:PayPotionSale(totalCount, false) then
		self:Tell(player, "CoinLimit")
		return false
	end
	for _, potion in potions do
		self.items[potion.id] = nil
		potion.stage = "Consumed"
		potion.model:Destroy()
	end
	self.stationVersions.Sigil += 1
	return true
end
function Manager.Attack(self: Manager, player: Player, request: Types.Request): ()
	local function OnResult(hit: boolean): ()
		Net.FireNotify(player, {kind = "AttackResult", attackSequence = request.attackSequence, hit = hit})
	end
	local record = self.players[player]
	local root = self:Root(player)
	if not record or record.closing or not root or self:Held(player) or (self.paint and self.paint.player == player) then
		OnResult(false)
		return
	end
	local character = player.Character
	local level = record.levels.weapon
	local tier = PersonalRules.GetWeaponTier(level)
	local weapon = character and character:FindFirstChild(tier.model)
	if not weapon or not weapon:IsA("Tool") then OnResult(false); return end
	local now = workspace:GetServerTimeNow()
	local cooldown = if tier.attackCooldown > 0 then tier.attackCooldown else Config.AttackCooldown
	if now - record.lastAttack < math.max(0, cooldown - Config.AttackCooldownTolerance) then
		OnResult(false)
		return
	end
	record.lastAttack = now
	Net.Broadcast({kind = "Swing", actor = player.UserId, weaponLevel = level, started = now})
	self.scope:Spawn(function(): ()
		task.wait(Config.AttackWindup)
		local currentRoot = self:Root(player)
		if not currentRoot or self.players[player] ~= record or record.closing or self.closing or self:Held(player)
			or (self.paint and self.paint.player == player) or player.Character ~= character or weapon.Parent ~= character
			or record.levels.weapon ~= level then
			OnResult(false)
			return
		end
		local pose = currentRoot.CFrame
		type Candidate = {item: Types.Item, position: Vector3, distance: number}
		local candidates: {Candidate} = {}
		local function Consider(item: Types.Item, range: number): ()
			if item.kind ~= "Body" or item.location ~= "Street" or item.hits >= Config.StunHits then return end
			local part = item.model.PrimaryPart
			if not part then return end
			local position = part.Position
			if tier.shape ~= "Single" and not PersonalRules.InWeaponArea(level, pose, position) then return end
			-- 范围攻击可穿过其他 NPC，仍由场景碰撞件阻挡。
			local ignored = if tier.shape ~= "Single" then self.runtime else nil
			if not self:Near(player, position, range, item.model, ignored) then return end
			table.insert(candidates, {item = item, position = position, distance = (position - pose.Position).Magnitude})
		end
		if tier.shape == "Single" then
			local item = if request.target then self.items[request.target] else nil
			if item and item.version == request.version then Consider(item, Config.AttackServerRange) end
		else
			-- 贯穿带末端的角点也可命中，Near 同时负责检查遮挡。
			local range = if tier.shape == "Line" then math.sqrt(tier.range ^ 2 + ((tier.width or 5) / 2) ^ 2 + 25) + 0.001 else tier.range + 0.001
			for _, item in self.items do Consider(item, range) end
			table.sort(candidates, function(a, b)
				if a.distance == b.distance then return a.item.id < b.item.id end
				return a.distance < b.distance
			end)
			Net.Broadcast({kind = "WeaponEffect", actor = player.UserId, weaponLevel = level, attackPose = pose, started = workspace:GetServerTimeNow()})
		end
		local count = math.min(#candidates, tier.targets)
		for index = 1, count do
			local candidate = candidates[index]
			local item, position = candidate.item, candidate.position
			local direction = pose.LookVector
			local travel: number? = nil
			if tier.shape == "Slam" then
				local delta = pose.Position - position
				local horizontal = Vector3.new(delta.X, 0, delta.Z)
				if horizontal.Magnitude > 0.01 then direction = horizontal.Unit end
				travel = math.max(0, horizontal.Magnitude - 3)
			end
			local torso = item.model:FindFirstChild("UpperTorso")
			if torso and torso:IsA("BasePart") then position = torso.Position - direction * torso.Size.Z * 0.5 end
			NPC.Hit(item, direction, tier.damage, travel)
			Net.Broadcast({kind = "Hit", actor = player.UserId, attackSequence = if index == 1 then request.attackSequence else nil,
				id = item.id, version = item.version, hits = item.hits, hp = item.hp, maxHp = item.maxHp,
				started = workspace:GetServerTimeNow(), direction = direction, position = position})
			if index == 1 then
				if item.hits >= Config.StunHits then
					self:Tell(player, "StunnedCarry")
				else
					self:Tell(player, "HitCount", {tostring(item.hits), tostring(Config.StunHits)})
				end
			end
		end
		OnResult(count > 0)
		if count > 0 then self:Changed() end
	end)
end
function Manager.Paint(self: Manager, player: Player, request: Types.Request): ()
	local session = self.paint
	if not session or session.player ~= player or request.session ~= session.token then
		return
	end
	local item = self.items[session.id]
	if not item or item.stage ~= "Painting" or session.finishing then
		return
	end
	local orientation, frames = session.orientation, item.poseBody
	local result = Painting.Apply(session, item, request, Scene.TablePose(), Scene.CameraPose(1 + #(session.batch or {})).Position, workspace:GetServerTimeNow())
	-- 重复或过快的请求已被规则层拒绝，不再向全服放大广播。
	if not result then
		return
	end
	if session.orientation ~= orientation or item.poseBody ~= frames then SyncBatchPose(session, item) end
	Net.Broadcast({ kind = "PaintPose", id = item.id, session = session.token, sequence = request.sequence, orientation = session.orientation, flipped = item.paintFlipped == true, bodyPose = item.poseBody, progress = item.progress, started=workspace:GetServerTimeNow() })
	if result.complete then
		session.finishing=true
		Net.FireNotify(player,{kind="FinishPaint",session=session.token,id=item.id})
	end
end
function Manager.PaintVisual(self: Manager,player: Player,request: Types.Request): ()
	local session=self.paint
	if not session or session.player~=player or request.session~=session.token then return end
	local item=self.items[session.id]
	local sequence=request.sequence
	if not item or not sequence or not request.segments then return end
	local previous=session.visualSequence or 0
	if sequence<=previous then
		Net.FireNotify(player,{kind="VisualDelta",id=item.id,session=session.token,sequence=previous,segments={}})
		return
	end
	local reason: GameTexts.TextId?=nil
	local now=workspace:GetServerTimeNow()
	if now-(session.visualWindow or 0)>=1 then session.visualWindow=now;session.visualPackets=0 end
	if sequence~=previous+1 then reason="PaintOutOfSequence"
	elseif (session.visualPackets or 0)>=Config.PaintVisualPacketsPerSecond then reason="PaintRateExceeded" end
	for _,segment in request.segments do
		local part=item.model:FindFirstChild(segment.part)
		if not part or not part:IsA("BasePart") or not part:GetAttribute("Paintable") then reason="InvalidPaintPart";break end
		if part:GetAttribute("SurfaceVersion")~=segment.surfaceVersion then reason="PaintVersionMismatch";break end
	end
	local state=item.visualState or VisualRules.New()
	local accepted: {Types.VisualSegment}?=nil
	if not reason then accepted,reason=VisualRules.Apply(state,request.segments,session.token) end
	if reason or not accepted then
		Net.FireNotify(player,{kind="VisualRejected",id=item.id,session=session.token,sequence=previous,textId=reason or "PaintRejected"})
		return
	end
	item.visualState=state
	for _, body in ipairs(session.batch or {}) do
		body.visualState = state
	end
	session.visualSequence=sequence
	session.visualPackets=(session.visualPackets or 0)+1
	if Config.PaintPhysicsEnabled and request.bodyPose and BodyPose.Validate(item.model, request.bodyPose) then
		item.poseBody = table.clone(request.bodyPose)
		Painting.SetPose(session, item, Scene.TablePose(), session.orientation, true)
		SyncBatchPose(session, item)
	end
	-- 操作者本地已即时渲染，只回传轻量序号确认；完整符文增量仅同步给其他旁观者。
	Net.FireNotify(player, { kind = "VisualDelta", id = item.id, session = session.token, sequence = sequence, segments = {}, visualRevision = state.revision })
	local observerNotice: Types.Notice = { kind = "VisualDelta", id = item.id, session = session.token, paintBatch = BatchIds(session), sequence = sequence, segments = accepted, visualRevision = state.revision, bodyPose = item.poseBody }
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.FireNotify(other, observerNotice)
		end
	end
end
function Manager.SettleThrown(self: Manager, item: Types.Item): ()
	if item.location ~= "Thrown" then
		return
	end
	if item.poolToss and item.poolToss.chuteDropFrom then
		self:PushChuteItem(item, false, item.poolToss.target)
		self:StepAutomation(workspace:GetServerTimeNow())
		return
	end
	local torso = item.model:FindFirstChild("UpperTorso")
	local position = if torso and torso:IsA("BasePart") then torso.Position else item.model:GetPivot().Position
	local kind = ThrowArc.CanStoreThrow(
		self:IsFacilityUnlocked(GameData.FacilityId.FastChute),
		Scene.PoolContainsStrict(position),
		Scene.ChuteContains(position),
		item.stage == "Painted",
		self:PoolCount(),
		nil
	)
	if kind == "Pool" then
		if #self.pool < Config.PoolVisibleLimit then
			item.location = "Pool"
			table.insert(self.pool, item.id)
			Carry.FinishPool(item)
		else
			Carry.Detach(item, false)
			NPC.StopMotion(item)
			self.items[item.id] = nil
			item.model:Destroy()
			self.poolOverflowCount += 1
		end
		return
	elseif kind == "Chute" then
		local primary = item.model.PrimaryPart
		local rotation = if primary then primary.CFrame.Rotation else CFrame.identity
		self:PushChuteItem(item, false, CFrame.new(position) * rotation)
		self:StepAutomation(workspace:GetServerTimeNow())
		return
	end
	Carry.FinishGround(item)
end
function Manager.SweepThrow(origin: Vector3, velocity: Vector3, ignored: { Instance }, canEnterChute: boolean): (number, Vector3, Vector3?, boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	local baffleParams: RaycastParams? = nil
	local baffles = Scene.ChuteBaffles
	if canEnterChute and baffles then
		local paramsForBaffles = RaycastParams.new()
		paramsForBaffles.FilterType = Enum.RaycastFilterType.Include
		paramsForBaffles.FilterDescendantsInstances = { baffles }
		baffleParams = paramsForBaffles
	end
	local throwConfig = Physics.ManualThrow
	local function Cast(frame: CFrame, size: Vector3, delta: Vector3): RaycastResult?
		local solid = workspace:Blockcast(frame, size, delta, params)
		local baffle = if baffleParams then workspace:Blockcast(frame, size, delta, baffleParams) else nil
		return ThrowArc.FirstHit(solid, baffle)
	end
	local duration, landing, surface, normal, hit = ThrowArc.Sweep(origin, velocity, workspace.Gravity, throwConfig.PreviewStepSeconds, throwConfig.PreviewDurationSeconds, throwConfig.SweepSize, Cast)
	local opening, dropZone = Scene.FastChuteOpening, Scene.ChuteDropZone
	local chuteWall = canEnterChute and opening ~= nil and surface ~= nil and normal ~= nil
		and ((hit ~= nil and baffles ~= nil and hit:IsDescendantOf(baffles)) or ThrowArc.IsChuteWall(opening.CFrame, opening.Size, surface, normal))
	local wallStop = normal ~= nil and math.abs(normal.Y) <= 0.2
	if normal and wallStop and not chuteWall then
		local function CastFloor(start: Vector3, delta: Vector3): RaycastResult?
			return workspace:Raycast(start, delta, params)
		end
		landing = ThrowArc.WallLanding(landing, normal, CastFloor)
	end
	if canEnterChute and opening and dropZone and (chuteWall or Scene.ChuteContains(landing)) then
		local floorY = dropZone.Position.Y + throwConfig.SweepSize.Y * 0.5
		local dropFrom = if landing.Y > dropZone.Position.Y + Physics.ChuteWallHeight
			then ThrowArc.ChuteDropStart(opening.CFrame, opening.Size, landing)
			else landing
		return duration, Vector3.new(dropFrom.X, floorY, dropFrom.Z), dropFrom, false
	end
	return duration, landing, nil, wallStop
end
function Manager.Throw(self: Manager, player: Player, request: Types.Request): ()
	local record = self.players[player]
	if not record or record.closing then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - record.lastThrow < Physics.ManualThrow.CooldownSeconds then
		return
	end
	if self.paint and self.paint.player == player then
		return
	end
	local root = self:Root(player)
	local character = player.Character
	if not root or not character then
		return
	end
	local stack = self:Carried(player)
	local top = stack[1]
	if not top or top.id ~= request.target or top.version ~= request.version then
		self:Tell(player, "ItemChanged")
		return
	end
	local requested = request.direction
	if not requested or not ThrowArc.IsFiniteVector(requested) then
		return
	end
	local flat = Vector3.new(requested.X, 0, requested.Z)
	if flat.Magnitude < 0.001 then
		return
	end
	local direction = flat.Unit
	local shoulder = character:FindFirstChild("UpperTorso")
	local basis = if shoulder and shoulder:IsA("BasePart") then shoulder.CFrame else root.CFrame
	local origin = ThrowArc.Origin(basis, direction)
	local velocity = ThrowArc.LaunchVelocity(direction, workspace.Gravity)
	if velocity.Magnitude < 0.001 then
		return
	end
	record.lastThrow = now
	local ignored: { Instance } = { character }
	for _, item in stack do table.insert(ignored, item.model) end
	local canEnterChute = top.stage ~= "Painted" and self:IsFacilityUnlocked(GameData.FacilityId.FastChute)
	local duration, landing, dropFrom, wallStop = Manager.SweepThrow(origin, velocity, ignored, canEnterChute)
	local target = CFrame.new(landing) * top.model:GetPivot().Rotation
	local placed = Carry.BeginManualToss(top, origin, velocity, duration, target, player, not self:HasOtherBodies(player, top), dropFrom, wallStop)
	if placed then
		self:SettleThrown(top)
	end
	self:Restack(player)
	self:Changed()
end
local function SyncCarryRig(character: Model, templateName: string): ()
	local mounted = character:FindFirstChild("CarryBackRig")
	if mounted and mounted:GetAttribute("TemplateName") == templateName then return end
	if mounted then mounted:Destroy() end
	if templateName == "" then return end

	local torso = character:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then return end
	local template = ModelTemplates.FindCarryRig(templateName)
	if not template or not template.PrimaryPart then return end
	local offset = template:GetAttribute("MountOffset")
	if typeof(offset) ~= "CFrame" then return end

	local rig = template:Clone()
	local root = rig.PrimaryPart :: BasePart
	rig.Name = "CarryBackRig"
	rig:SetAttribute("TemplateName", templateName)
	rig:PivotTo(torso.CFrame * offset)
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = false end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Name, weld.Part0, weld.Part1 = "TorsoMount", torso, root
	weld.Parent = root
	rig.Parent = character
end
function Manager.SyncPersonal(self: Manager, player: Player, record: PlayerRecord): ()
	local character = player.Character
	local tier = PersonalRules.GetCarryTier(record.levels.carryTool)
	if character then
		SyncCarryRig(character, tier.model)
		for category, level in record.levels do
			character:SetAttribute("Upgrade_" .. category, level)
		end
	end
	player:SetAttribute("CarryCapacity", tier.capacity)
	player:SetAttribute("CarryBodyCount", self:CarryCount(player, record))
	Net.FireNotify(player, { kind = "PersonalUpgrades", personalLevels = table.clone(record.levels) })
end
function Manager.TryPersonalUpgrade(self: Manager, player: Player, record: PlayerRecord, request: Types.Request): ()
	local category, level = request.category, request.expectedNextLevel
	local cost = PersonalRules.GetPurchaseCost(record.levels, category, level)
	local spend = self.data.TrySpendCoins
	if category == "weapon" and level and cost then
		local template = ModelTemplates.FindWeapon(PersonalRules.GetWeaponTier(level).model)
		if not template then
			self:SyncPersonal(player, record)
			return
		end
	end
	if category and level and cost and spend and spend(player, cost) then
		record.levels[category] = level
		if category == "weapon" then self:GiveWeapon(player, level) end
	end
	self:SyncPersonal(player, record)
end
function Manager.OnRequest(self: Manager, player: Player, request: Types.Request): ()
	local record = self.players[player]
	if not record or record.closing or self.closing or not self.data.IsActive(player) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if request.action == "Sync" then
		if now - record.lastSync < 1 then
			return
		end
		record.lastSync = now
		self:SyncPersonal(player, record)
		Net.FireNotify(player, { kind = "State", snapshot = self:Snapshot() })
		local histories: {{id: string,item: Types.Item,revision: number,state: Types.VisualState,segments: {Types.VisualSegment}}}={}
		for _,item in self.items do
			local state=item.visualState
			if state then
				local segments: {Types.VisualSegment}={}
				for _,segment in state.segments do table.insert(segments,segment) end
				table.insert(histories,{id=item.id,item=item,revision=state.revision,state=state,segments=segments})
			end
		end
		self.scope:Spawn(function(): ()
			local packets=0
			for _,history in histories do
				for first=1,#history.segments,Config.PaintVisualBatchSize do
					if self.items[history.id]~=history.item or history.item.visualState~=history.state or self.players[player]~=record or record.closing then break end
					local chunk: {Types.VisualSegment}={}
					for index=first,math.min(first+Config.PaintVisualBatchSize-1,#history.segments) do table.insert(chunk,history.segments[index]) end
					Net.FireNotify(player,{kind="VisualSnapshot",id=history.id,segments=chunk,visualRevision=history.revision})
					packets+=1
					if packets%Config.PaintVisualPacketsPerTick==0 then task.wait() end
				end
			end
			if self.players[player]==record and not record.closing then Net.FireNotify(player,{kind="SyncComplete"}) end
		end)
		return
	end
	if not self:Root(player) then
		return
	end
	local painting = self.paint ~= nil and self.paint.player == player
	if request.action == "Sprint" then
		record.movement.wanted = request.sprint == true and not painting
		return
	end
	if request.action == "PersonalUpgrade" then
		if not painting and now - record.lastUpgrade >= 0.15 then
			record.lastUpgrade = now
			self:TryPersonalUpgrade(player, record, request)
		end
		return
	end
	if request.action == "Paint" then
		self:Paint(player, request)
		return
	end
	if request.action=="PaintVisual" then self:PaintVisual(player,request);return end
	if request.action == "ResetView" then
		local session = self.paint
		local item = session and self.items[session.id]
		if Config.PaintRotationEnabled and session and item and session.player == player and request.session == session.token and not session.finishing
			and session.orientation ~= CFrame.identity then
			Painting.SetPose(session, item, Scene.TablePose(), CFrame.identity)
			SyncBatchPose(session, item)
			Net.Broadcast({ kind = "PaintPose", id = item.id, session = session.token, orientation = CFrame.identity, progress = item.progress, started = now })
		end
		return
	end
	if request.action=="EndPaint" then
		local session=self.paint
		if session and session.player==player and session.token==request.session and (request.sequence or 0)==(session.visualSequence or 0) then
			local complete=session.finishing
			self:EndPaint(player)
			if complete then self:Tell(player,"RuneComplete") end
			self:Changed()
		end
		return
	end
	-- Attack 有独立冷却校验，不参与通用 0.12s 请求节流，避免刚交互/放下后立刻挥棒被静默丢弃。
	if request.action == "Attack" then
		self:Attack(player, request)
		return
	end
	if request.action == "Throw" then
		self:Throw(player, request)
		return
	end
	if now - record.lastRequest < 0.12 then
		return
	end
	record.lastRequest = now
	if self.paint and self.paint.player == player then
		if request.session ~= self.paint.token then
			return
		end
		return
	end
	local target = request.target
	local changed = false
	if request.action == "UnlockFacility" then
		local facilityId = request.facilityId or (if target then tonumber(target) else nil)
		if facilityId and facilityId >= 1 and facilityId % 1 == 0 then
			self:TryUnlockFacility(player, facilityId)
		end
		return
	end
	if request.action == "TakeTable" then
		if not self:Held(player) and not self.paint and self.tableId then
			if not self:Near(player, Scene.TableInteract.Position, Scene.StationRange("Table"), nil) then
				self:Tell(player, "StationTooFar")
				return
			end
			local item = self.items[self.tableId]
			if item and self:TakeBody(player, item) then
				self.tableId = nil
				changed = true
			end
		end
	elseif request.action == "Interact" and target then
		local positions: { [string]: Vector3 } = {
			Pool = Scene.PoolPickup.Position,
			Table = Scene.TableInteract.Position,
			Altar = Scene.Altar.Position,
			Shelf = Scene.Shelf.Position,
			Sigil = Scene.SigilPosition,
		}
		if Scene.ChutePrompt then
			positions.Chute = Scene.ChutePrompt.Position
		end
		if Scene.ChutePickup then
			positions.ChutePickup = Scene.ChutePickup.Position
		end
		if Scene.AutoRuneOutputPrompt then
			positions.AutoOutput = Scene.AutoRuneOutputPrompt.Position
		end
		if Scene.AutoShelfPickup then
			positions.AutoShelf = Scene.AutoShelfPickup.Position
		end
		local position = positions[target]
		if position then
			if request.version ~= self.stationVersions[target] then
				self:Tell(player, "StationChanged")
				return
			end
			if not self:Near(player, position, Scene.StationRange(target), nil) then
				self:Tell(player, "StationTooFar")
				return
			end
			if target == "Pool" then
				changed = self:Pool(player)
			elseif target == "Table" then
				changed = self:Table(player)
			elseif target == "Altar" then
				changed = self:Altar(player)
			elseif target == "Shelf" then
				changed = self:Shelf(player)
			elseif target == "Chute" then
				changed = self:Chute(player)
			elseif target == "ChutePickup" then
				changed = self:ChutePickup(player)
			elseif target == "AutoOutput" then
				changed = self:AutoOutput(player)
			elseif target == "AutoShelf" then
				changed = self:AutoShelf(player)
			else
				changed = self:Submit(player)
			end
		else
			local item = self.items[target]
			if not item or item.version ~= request.version then
				self:Tell(player, "ItemChanged")
			elseif item.kind ~= "Body" and (self:CarryCount(player) > 0 or self:Held(player) ~= nil) then
				self:Tell(player, "HandsFull")
			elseif item.kind == "Body" and self:ShoulderOccupied(player) then
				self:Tell(player, "HandsFull")
			elseif item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits) then
				local root=item.model.PrimaryPart
				if root and self:Near(player,root.Position,Config.InteractionRange,item.model) then
					changed = if item.kind == "Body" then self:TakeBody(player, item) else Carry.Take(item, player)
				else
					self:Tell(player,"ItemUnavailable")
				end
			else
				self:Tell(player, "ItemUnavailable")
			end
		end
	end
	if changed then
		self:Changed()
	end
end
function Manager.ReleasePlayer(self: Manager, player: Player): ()
	self:EndPaint(player)
	local stack = self:Carried(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.Position else Scene.PoolPickup.Position
	local right = if root and root:IsA("BasePart") then root.CFrame.RightVector else Vector3.xAxis
	if #stack == 0 then
		local held = self:Held(player)
		if held then
			local primary = held.model.PrimaryPart
			Carry.Drop(held, if primary then primary.Position else origin)
		end
	else
		for index, item in stack do
			local primary = item.model.PrimaryPart
			local base = if primary then primary.Position else origin
			Carry.Drop(item, base + right * (index - 1) * Physics.CarryReleaseSpacing, index == #stack)
		end
	end
	local record = self.players[player]
	if record then
		for index = 1, record.carryOverflowCount do
			local offset = Vector3.new((index - 1) % 5 - 2, 0, math.floor((index - 1) / 5) + 1)
			local position = origin + offset * Physics.CarryReleaseSpacing
			local body = CreateStationBody(self, "Ground", "Unpainted", CFrame.new(position))
			if body then
				Carry.Drop(body, position, false)
			else
				self.poolOverflowCount += 1
			end
		end
		record.carryOverflowCount = 0
	end
	self:Changed()
end
function Manager.GiveWeapon(self: Manager, player: Player, level: number): ()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChild("Backpack")
	local template = ModelTemplates.FindWeapon(PersonalRules.GetWeaponTier(level).model)
	if not character or not humanoid or humanoid.Health <= 0 or not backpack or not template then return end
	local weapon = template:Clone()
	local containers: {Instance} = {character, backpack}
	for _, container in containers do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and PersonalRules.WeaponLevel(child.Name) then child:Destroy() end
		end
	end
	weapon.Parent = backpack
	if not self:Held(player) and not (self.paint and self.paint.player == player) then humanoid:EquipTool(weapon) end
end
function Manager.OnCharacter(self: Manager, player: Player, character: Model): ()
	local record = self.players[player]
	if not record or not record.scope.alive or record.closing then
		return
	end
	if record.characterScope then
		record.characterScope:Destroy()
		record.characterScope = nil
	end
	self:ReleasePlayer(player)
	local humanoidInst = character:WaitForChild("Humanoid", 10)
	if not record.scope.alive or record.closing or player.Character ~= character then
		return
	end
	if not humanoidInst or not humanoidInst:IsA("Humanoid") then
		return
	end
	local humanoid: Humanoid = humanoidInst
	local rootInst = character:WaitForChild("HumanoidRootPart", 10)
	if not record.scope.alive or record.closing or player.Character ~= character then
		return
	end
	if not rootInst or not rootInst:IsA("BasePart") then
		return
	end
	local root: BasePart = rootInst
	if PersonalRules.GetCarryTier(record.levels.carryTool).model ~= "" then
		character:WaitForChild("UpperTorso", 5)
		if not record.scope.alive or record.closing or player.Character ~= character then return end
	end
	root.CFrame = Scene.Spawn.CFrame * CFrame.new(0, 4, 0)
	record.movement = PersonalMovement.New()
	humanoid.WalkSpeed = PersonalRules.GetMoveTier(record.levels.moveSpeed).walk
	PersonalMovement.Publish(record.movement, character, humanoid.WalkSpeed, false)
	self:SyncPersonal(player, record)
	local backpack = player:WaitForChild("Backpack", 10)
	if not record.scope.alive or record.closing or player.Character ~= character or not backpack then
		return
	end
	if record.characterScope then
		record.characterScope:Destroy()
	end
	local characterScope = Lifecycle.new()
	record.characterScope = characterScope
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and child.Name ~= "Potion" then
			child:Destroy()
		end
	end
	local reserve = player:FindFirstChild(PotionReserveName)
	if reserve then
		for _, child in reserve:GetChildren() do
			if child:IsA("Tool") then
				child.Parent = backpack
			end
		end
	end
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	self:GiveWeapon(player, record.levels.weapon)
	characterScope:Connect(humanoid.Died:Connect(function(): ()
		self:ReleasePlayer(player)
	end))
end
function Manager.AddPlayer(self: Manager, player: Player): ()
	if self.players[player] or self.closing then
		return
	end
	if not self.data.IsActive(player) then return end
	local record: PlayerRecord = {
		scope = Lifecycle.new(), characterScope = nil, lastAttack = 0, lastThrow = 0,
		lastRequest = 0, lastSync = 0, lastUpgrade = -math.huge, closing = false,
		levels = PersonalRules.New(), movement = PersonalMovement.New(), carryOverflowCount = 0,
	}
	self.players[player] = record
	record.scope:Connect(player.CharacterRemoving:Connect(function(character: Model): ()
		record.movement = PersonalMovement.New()
		if record.characterScope then
			record.characterScope:Destroy()
			record.characterScope = nil
		end
		if self:CarryCount(player, record) > 0 then self:ReleasePlayer(player) end
		self:RescuePotions(player, character)
	end))
	record.scope:Connect(player.CharacterAdded:Connect(function(character: Model): ()
		self:OnCharacter(player, character)
	end))
	if player.Character then
		record.scope:Spawn(function(): ()
			local character = player.Character
			if character then
				self:OnCharacter(player, character)
			end
		end)
	end
	self:SyncPersonal(player, record)
	Net.FireNotify(player, { kind = "State", snapshot = self:Snapshot() })
end
function Manager.RemovePlayer(self: Manager, player: Player): ()
	if self.removing[player] then
		return
	end
	local record = self.players[player]
	if not record then
		return
	end
	self.removing[player] = true
	record.closing = true
	self:ReleasePlayer(player)
	self:ReleasePotions(player)
	if record.characterScope then
		record.characterScope:Destroy()
		record.characterScope = nil
	end
	record.scope:Destroy()
	self.players[player] = nil
	self.removing[player] = nil
end
function Manager.Update(self: Manager): ()
	if self.closing then
		return
	end
	local now = workspace:GetServerTimeNow()
	local changedMotion = false
	for _, item in self.items do
		local carrier = item.holder
		if carrier and item.kind == "Body" and item.model.Parent == nil then
			Carry.Detach(item, not self:HasOtherBodies(carrier, item))
			self.items[item.id] = nil
			self:Restack(carrier)
			changedMotion = true
			continue
		end
		if item.carryTransition then Carry.AdvanceTransition(item, now) end
		if item.altarToss then
			if not item.model:IsDescendantOf(workspace) then
				self.items[item.id] = nil
				changedMotion = true
			elseif Carry.AdvanceAltarToss(item, now) then
				item.convertEnds = now + Config.ConversionSeconds
				changedMotion = true
			end
		elseif item.poolToss and item.poolToss.kind == "Manual" then
			local function OnSettled(settled: Types.Item): ()
				self:SettleThrown(settled)
			end
			if Carry.AdvanceManualToss(item, now, OnSettled) then
				changedMotion = true
			end
		elseif item.poolToss and Carry.AdvancePoolToss(item, now) then
			changedMotion = true
		end
	end
	if Manager.StepAutomation and self:StepAutomation(now) then
		changedMotion = true
	end
	if Manager.StepAutomationAgents and self:StepAutomationAgents(now) then
		changedMotion = true
	end
	if now < self.nextUpdate then
		if changedMotion then
			self:Changed()
		else
			FlushAutoRuneVisuals(self)
		end
		return
	end
	self.nextUpdate = now + 0.1
	local changed = changedMotion
	local count, bodies = 0, 0
	for _, item in self.items do
		local carrier = item.holder
		if Carry.Update(item, now) then
			if carrier then
				self:Restack(carrier)
			end
			changed = true
		end
		if item.streetSlot then
			count += 1
		end
		if item.kind == "Body" and item.model.Parent ~= nil and not IsAutomationLocation(item.location) then
			bodies += 1
		end
		if item.kind == "Body" then
			NPC.Update(item, now)
			if item.location == "Pool" and item.poolToss == nil then
				Ragdoll.LimitVelocity(item.model)
			elseif item.hits >= Config.StunHits and not item.fall then
				Ragdoll.LimitVelocity(item.model)
			end
		end
		local primary = if item.location == "Toolbar" or item.model.Parent == nil then nil else item.model.PrimaryPart
		if item.kind == "Body" and item.location == "Pool" and item.poolToss == nil then
			local torso = item.model:FindFirstChild("UpperTorso")
			local outside = torso ~= nil and torso:IsA("BasePart") and not Scene.PoolContains(torso.Position)
			local fallen = primary ~= nil and primary.Position.Y < -40
			if (outside or fallen) and now >= (item.poolRecoverAt or 0) then
				item.poolRecoverAt = now + Physics.PoolRecoverSeconds
				Carry.RecoverPool(item)
				changed = true
			end
		elseif item.location == "Chute" and primary and not Scene.ChutePileContains(primary.Position) then
			if now >= (item.chuteRecoverAt or 0) then
				self:ReleaseChuteBody(item, Scene.ChuteDropPose(random), false)
				changed = true
			end
		elseif item.location ~= "Altar" and not IsAutomationLocation(item.location) and primary and primary.Position.Y < -40 then
			carrier = item.holder
			if carrier then
				self:EndPaint(carrier)
			end
			local keep = carrier ~= nil and self:HasOtherBodies(carrier, item)
			Carry.Drop(item, Vector3.new(0, -100, 0), not keep)
			if carrier and keep then
				self:Restack(carrier)
			end
			item.streetSlot = false
			changed = true
		end
	end
	if count < Config.StreetPopulation and bodies < Config.MaximumBodies and now >= self.nextSpawn then
		local item = NPC.Spawn(self.runtime, self.items)
		if item then
			self.items[item.id] = item
			changed = true
		end
		self.nextSpawn = now + Config.SpawnInterval
	end
	local ready: { Types.Item } = {}
	for _, item in self.items do
		if item.kind == "Body" and item.location == "Altar" and item.convertEnds and now >= item.convertEnds then
			table.insert(ready, item)
		end
	end
	table.sort(ready, function(a: Types.Item, b: Types.Item): boolean
		return (a.convertEnds or 0) < (b.convertEnds or 0)
	end)
	for _, item in ready do
		if self.items[item.id] ~= item then continue end
		self:SpawnAltarPotion(item)
		changed = true
	end
	if self.paint and not self:Root(self.paint.player) then
		local player = self.paint.player
		self:EndPaint(player)
		changed = true
	end
	if changed then
		self:Changed()
	else
		FlushAutoRuneVisuals(self)
	end
	if self.players then
		for player in self.players do
			for _, facilityId in GameData.GetFacilityOrder() do
				if not self.unlockedFacilities[facilityId] and self:IsNearPad(player, facilityId) then
					if self:TryUnlockFacility(player, facilityId) then
						break
					end
				end
			end
		end
	end
end
function Manager.Close(self: Manager): ()
	self.closing = true
	for player in self.players do self:RemovePlayer(player) end
end
function Manager.Init(self: Manager): ()
	if self.initialized then
		return
	end
	self.initialized = true
	self.runtime.Parent = workspace
	self.scope:Own(self.runtime)
	Ragdoll.Init()
	if Physics.GroundRootEnabled then Ground.Init() end
	Door.Init(self.scope)
	self.scope:Connect(Net.ConnectRequest(function(player: Player, request: Types.Request): ()
		self:OnRequest(player, request)
	end))
	self.scope:Connect(RunService.Heartbeat:Connect(function(dt: number): ()
		local now = workspace:GetServerTimeNow()
		for player, record in self.players do
			local character = player.Character
			if character and record.characterScope and not record.closing then
				PersonalMovement.Step(record.movement, character, record.levels.moveSpeed, self.paint ~= nil and self.paint.player == player, now, dt)
			end
		end
		self:Update()
	end))
	for facilityId, pad in Scene.UnlockPads do
		local trigger = pad:FindFirstChild("TriggerZone")
		if trigger and trigger:IsA("BasePart") then
			self.scope:Connect(trigger.Touched:Connect(function(hit: BasePart): ()
				if self.closing or self.unlockedFacilities[facilityId] then
					return
				end
				local ancestor: Instance? = hit.Parent
				while ancestor and not ancestor:IsA("Model") do
					ancestor = ancestor.Parent
				end
				local player = if ancestor and ancestor:IsA("Model") then Players:GetPlayerFromCharacter(ancestor) else nil
				if player then
					self:TryUnlockFacility(player, facilityId)
				end
			end))
		end
	end
	for _ = 1, Config.StreetPopulation do
		local item = NPC.Spawn(self.runtime, self.items)
		if item then
			self.items[item.id] = item
		end
	end
	self:Changed()
end
function Manager.Destroy(self: Manager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	self:Close()
	if self.agents then
		AutomationAgents.Destroy(self.agents)
		self.agents = nil
	end
	self.scope:Destroy()
end
return Manager
