-- 加工业务管理器：共享工位、搬运、权威画符和奖励；玩家生命周期由基础入口装配
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
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
local BodyPose = require(Shared.PaintBodyPose)
local PaintRotation = require(Shared.PaintRotation)
local CurvedSurface = require(Shared.CurvedSurface)
type PlayerData = { IsActive: (Player) -> boolean, CanAddCoins: (Player, number) -> boolean, AddCoins: (Player, number) -> boolean }
type PaintSession = Painting.Session
type PlayerRecord = {
	scope: Lifecycle.Lifecycle,
	lastAttack: number,
	lastRequest: number,
	lastSync: number,
	closing: boolean,
}
local PotionReserveName = "PotionReserve"
local Manager = {}
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
		shelf: { [number]: { string } },
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
	local playerData: PlayerData = data or { IsActive = Info.IsActive, CanAddCoins = Info.CanAddCoins, AddCoins = Info.AddCoins }
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
		shelf = {},
		tableId = nil,
		altarId = nil,
		altarEnds = 0,
		altarHeld = false,
		paint = nil,
		stationVersions = { Pool = 1, Table = 1, Altar = 1, Shelf = 1, Sigil = 1 },
		stationKeys = {},
		revision = 0,
		nextSpawn = 0,
		nextUpdate = 0,
		nextToolbarOrder = 0,
	}, Manager)
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
function Manager.Snapshot(self: Manager): Types.Snapshot
	local shelfItems: { [string]: CFrame } = {}
	for quality, ids in self.shelf do
		for slot, id in ids do
			shelfItems[id] = Scene.ShelfPose(quality, slot)
		end
	end
	local list: { Types.ItemView } = {}
	for _, item in self.items do
		if item.location == "Shelf" then continue end
		table.insert(list, {
			id = item.id,
			kind = item.kind,
			stage = item.stage,
			location = item.location,
			version = item.version,
			model = item.model,
			hits = item.hits,
			fall = item.fall,
			progress = item.progress,
			holder = if item.holder then item.holder.UserId else nil,
			visualCount = if item.visualState then item.visualState.count else 0,
			paintFlipped = item.paintFlipped == true,
			flyEnds = item.flyEnds,
			convertEnds = item.convertEnds,
			toss = if item.poolToss then { from = item.poolToss.from, target = item.poolToss.target, started = item.poolToss.started, owner = item.poolToss.owner } else nil,
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
		pool = #self.pool,
		shelf = self:ShelfCount(),
		shelfItems = shelfItems,
		tableId = self.tableId,
		altarId = self.altarId,
		altarEnds = self.altarEnds,
		painter = if self.paint then self.paint.player.UserId else nil,
		session = if self.paint then self.paint.token else nil,
	}
end
function Manager.Changed(self: Manager): ()
	local _, _, altarKey = self:AltarSummary()
	local keys: { [string]: string } = {
		Pool = table.concat(self.pool, ","),
		Table = (self.tableId or "") .. (if self.paint then self.paint.token else ""),
		Altar = altarKey,
		Shelf = self:ShelfKey(),
	}
	for name, key in keys do
		if self.stationKeys[name] ~= key then
			self.stationKeys[name] = key
			self.stationVersions[name] += 1
		end
	end
	self.revision += 1
	self.replication:Broadcast(self:Snapshot())
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
		return (a.carryOrder or 0) > (b.carryOrder or 0)
	end)
	return list
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
	for _, item in self.items do
		if item ~= except and item.holder == player and item.kind == "Body" then
			return true
		end
	end
	return false
end
function Manager.Restack(self: Manager, player: Player): ()
	local stack = self:Carried(player)
	if #stack == 0 then
		return
	end
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
function Manager.Near(self: Manager, player: Player, position: Vector3, range: number, target: Model?): boolean
	local root = self:Root(player)
	local char = player.Character
	return root ~= nil and char ~= nil and (root.Position - position).Magnitude <= range and Scene.Visible(char, position, target)
end
function Manager.ShelfCount(self: Manager): number
	local count = 0
	for _, ids in self.shelf do
		count += #ids
	end
	return count
end
function Manager.QualityCount(self: Manager, quality: number): number
	local ids = self.shelf[quality]
	return if ids then #ids else 0
end
function Manager.ShelfKey(self: Manager): string
	local qualities: { number } = {}
	for quality in self.shelf do
		table.insert(qualities, quality)
	end
	table.sort(qualities)
	local parts: { string } = {}
	for _, quality in qualities do
		local ids = self.shelf[quality]
		if ids then
			table.insert(parts, tostring(quality) .. ":" .. table.concat(ids, ","))
		end
	end
	return table.concat(parts, ";")
end
function Manager.LaunchToAltar(self: Manager, item: Types.Item): ()
	local layer = 0
	for _, other in self.items do
		if other ~= item and other.kind == "Body" and other.location == "Altar" then layer += 1 end
	end
	local now = workspace:GetServerTimeNow()
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
	local model = ReplicatedStorage.Models.Potion:Clone() :: Model
	local id = HttpService:GenerateGUID(false)
	model:SetAttribute("ItemId", id)
	model:SetAttribute("Quality", quality)
	local potion: Types.Item = {
		id = id,
		kind = "Potion",
		stage = "Ready",
		location = "Shelf",
		version = 1,
		model = model,
		holder = nil,
		quality = quality,
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
	local pile = self.shelf[quality]
	if not pile then
		pile = {}
		self.shelf[quality] = pile
	end
	table.insert(pile, id)
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
		self:LaunchToAltar(item)
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
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.WalkSpeed = session.walkSpeed
		hum.JumpPower = session.jumpPower
		hum.JumpHeight = session.jumpHeight
	end
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
	if hum and hum.Health > 0 and #self:Carried(player) == 0 then
		local backpack = player:FindFirstChild("Backpack")
		local club = backpack and backpack:FindFirstChild("Club")
		if club and club:IsA("Tool") then
			hum:EquipTool(club)
		end
	end
	player:SetAttribute("Painting", false)
	self.paint = nil
	Net.FireNotify(player, { kind = "EndPaint", session = session.token, id = session.id, started = altarTossStarted, altarToss = altarToss })
end
function Manager.BeginPaint(self: Manager, player: Player, item: Types.Item): ()
	if self.paint then
		self:Tell(player, "TableInUse")
		return
	end
	local character = player.Character
	local root = self:Root(player)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not hum then
		return
	end
	local initialFlipped = not Config.PaintRotationEnabled and item.paintFlipped == true
	local initialOrientation = PaintRotation.FlatOrientation(initialFlipped)
	local session: PaintSession = {
		player = player,
		id = item.id,
		token = HttpService:GenerateGUID(false),
		last = workspace:GetServerTimeNow(),
		sequence = 0,
		orientation = initialOrientation,
		walkSpeed = hum.WalkSpeed,
		jumpPower = hum.JumpPower,
		jumpHeight = hum.JumpHeight,
	}
	self.paint = session
	item.paintOrientation = initialOrientation
	item.poseBody=nil
	item.stage = "Painting"
	item.version += 1
	local keep = self:HasOtherBodies(player, item)
	hum:UnequipTools()
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	root.Anchored = true
	player:SetAttribute("Painting", true)
	Carry.Static(item, Scene.TablePose(), not keep)
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
	if keep then
		self:Restack(player)
	end
	Net.FireNotify(player, { kind = "BeginPaint", id = item.id, session = session.token, bodyPose = frames, orientation = initialOrientation, flipped = initialFlipped })
end
function Manager.Pool(self: Manager, player: Player): ()
	local stack = self:Carried(player)
	local chosen: Types.Item? = nil
	for _, item in stack do
		if item.stage ~= "Painted" then
			chosen = item
			break
		end
	end
	if chosen then
		if #self.pool >= Config.PoolCapacity then
			self:Tell(player, "PoolFull")
			return
		end
		local keep = #stack > 1
		chosen.location = "Pool"
		chosen.version += 1
		table.insert(self.pool, chosen.id)
		Carry.TossIntoPool(chosen, not keep)
		if keep then
			self:Restack(player)
		end
	elseif #stack > 0 or self:ShoulderOccupied(player) then
		self:Tell(player, "StoreUnfinished")
	elseif #self.pool > 0 then
		local id = self.pool[1]
		local item = self.items[id]
		if item and Carry.Take(item, player) then
			table.remove(self.pool, 1)
			self:Restack(player)
		end
	else
		self:Tell(player, "PoolIsEmpty")
	end
end
function Manager.Table(self: Manager, player: Player): ()
	if self.paint then
		self:Tell(player, "TableInUse")
		return
	end
	local stack = self:Carried(player)
	local occupied = #stack > 0 or self:ShoulderOccupied(player)
	if self.tableId then
		if occupied then
			self:Tell(player, "TableIsOccupied")
			return
		end
		local item = self.items[self.tableId]
		if not item then
			return
		end
		if item.stage == "Painted" then
			if Carry.Take(item, player) then
				self.tableId = nil
				self:Restack(player)
			end
		else
			self:BeginPaint(player, item)
		end
		return
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
		return
	end
	local item = chosen
	if not item and #self.pool > 0 then
		item = self.items[self.pool[1]]
		table.remove(self.pool, 1)
	end
	if not item then
		self:Tell(player, "BringStunned")
		return
	end
	local keep = chosen ~= nil and self:HasOtherBodies(player, item)
	Carry.Static(item, Scene.TablePose(), not keep)
	item.location = "Table"
	item.streetSlot = false
	item.version += 1
	self.tableId = item.id
	if keep then
		self:Restack(player)
	end
	self:BeginPaint(player, item)
end
function Manager.Altar(self: Manager, player: Player): ()
	local chosen: Types.Item? = nil
	for _, item in self:Carried(player) do
		if item.stage == "Painted" then
			chosen = item
			break
		end
	end
	if not chosen then
		self:Tell(player, "AltarNeedsCompleted")
		return
	end
	self:LaunchToAltar(chosen)
end
function Manager.OwnedPotion(self: Manager, player: Player, quality: number): Types.Item?
	for _, item in self.items do
		if item.kind == "Potion" and item.owner == player and item.quality == quality and item.location == "Toolbar" then
			return item
		end
	end
	return nil
end
function Manager.GrantStack(self: Manager, player: Player, quality: number, count: number): Tool?
	local existing = self:OwnedPotion(player, quality)
	if existing and existing.model:IsA("Tool") then
		local nextCount = (existing.stack or 1) + count
		existing.stack = nextCount
		existing.model:SetAttribute("StackCount", nextCount)
		existing.version += 1
		return existing.model
	end
	local model = ReplicatedStorage.Models.Potion:Clone()
	if not model:IsA("Tool") then
		model:Destroy()
		return nil
	end
	local tool = model
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
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		tool.Parent = backpack
	end
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
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child.Name == "Potion" then
			child.Parent = reserve
		end
	end
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
function Manager.Shelf(self: Manager, player: Player): ()
	if #self:Carried(player) > 0 then
		self:Tell(player, "HandsFull")
		return
	end
	if self:ShelfCount() == 0 then
		self:Tell(player, "PotionsNotReady")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if (self.paint and self.paint.player == player) or not character or not humanoid or humanoid.Health <= 0 or not backpack then
		return
	end
	local qualities: { number } = {}
	for quality, ids in self.shelf do
		if #ids > 0 then
			table.insert(qualities, quality)
		end
	end
	table.sort(qualities)
	local equip: Tool? = nil
	local granted: { number } = {}
	for _, quality in qualities do
		local ids = self.shelf[quality]
		local tool = if ids then self:GrantStack(player, quality, #ids) else nil
		if tool then
			if tool.Parent ~= backpack and tool.Parent ~= character then
				tool.Parent = backpack
			end
			table.insert(granted, quality)
			equip = tool
		end
	end
	for _, quality in granted do
		local ids = self.shelf[quality]
		if ids then
			for _, id in ids do
				local item = self.items[id]
				if item then
					self.items[id] = nil
					item.model:Destroy()
				end
			end
			self.shelf[quality] = nil
		end
	end
	if equip then
		humanoid:EquipTool(equip)
	end
end
function Manager.Submit(self: Manager, player: Player): ()
	local record = self.players[player]
	local item = self:EquippedPotion(player)
	if not record or not self.data.IsActive(player) then
		return
	end
	if not item then
		self:Tell(player, "BringPotionSigil")
		return
	end
	-- 售出一次：当前服务器每位资料已就绪的玩家各得完整奖励；无人可收款则不消耗药水。
	local reward = Config.PotionReward
	local recipients: { Player } = {}
	local blocked: { Player } = {}
	for _, other in Players:GetPlayers() do
		if self.data.IsActive(other) then
			if self.data.CanAddCoins(other, reward) then
				table.insert(recipients, other)
			else
				table.insert(blocked, other)
			end
		end
	end
	if #recipients == 0 then
		self:Tell(player, "CoinLimit")
		return
	end
	local count = item.stack or 1
	if count > 1 then
		item.stack = count - 1
		item.model:SetAttribute("StackCount", item.stack)
		item.version += 1
	else
		self.items[item.id] = nil
		item.stage = "Consumed"
		item.model:Destroy()
	end
	self.stationVersions.Sigil += 1
	for _, other in recipients do
		if self.data.AddCoins(other, reward) then
			self:Tell(other, "CoinsAwarded", { tostring(reward) })
		else
			self:Tell(other, "CoinLimit")
		end
	end
	for _, other in blocked do
		self:Tell(other, "CoinLimit")
	end
end
function Manager.Attack(self: Manager, player: Player, request: Types.Request): ()
	local function OnResult(hit: boolean): ()
		Net.FireNotify(player, {kind="AttackResult",attackSequence=request.attackSequence,hit=hit})
	end
	local record = self.players[player]
	local root = self:Root(player)
	if not record or not root or self:Held(player) or (self.paint and self.paint.player == player) then
		OnResult(false)
		return
	end
	local character = player.Character
	local weapon = character and character:FindFirstChild("Club")
	if not weapon or not weapon:IsA("Tool") then
		OnResult(false)
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - record.lastAttack < math.max(0, Config.AttackCooldown - Config.AttackCooldownTolerance) then
		OnResult(false)
		return
	end
	record.lastAttack = now
	Net.Broadcast({ kind = "Swing", actor = player.UserId, started = now })
	-- 客户端本地已即时预测播放挥击音效，广播通知同步至远端；服务端不直接 Play，避免广播回声与网络延迟。
	self.scope:Spawn(function(): ()
		task.wait(Config.AttackWindup)
		local item = if request.target then self.items[request.target] else nil
		if not item or item.kind ~= "Body" or item.location ~= "Street" or item.hits >= Config.StunHits or item.version ~= request.version then
			OnResult(false)
			return
		end
		local root = self:Root(player)
		if not root or self.players[player] ~= record or record.closing or self:Held(player) then OnResult(false); return end
		local equipped = player.Character and player.Character:FindFirstChild("Club")
		if equipped ~= weapon or player.Character ~= character then OnResult(false); return end
		local target = item.model.PrimaryPart
		-- 以客户端近战表现为主；服务端仅做防跨距与防穿墙的必要校验，不再复检前摇后朝向。
		if not target or not self:Near(player, target.Position, Config.AttackServerRange, item.model) then
			OnResult(false)
			return
		end
		local direction = root.CFrame.LookVector
		local torso = item.model:FindFirstChild("UpperTorso")
		local position = target.Position
		if torso and torso:IsA("BasePart") then
			position = torso.Position - direction * torso.Size.Z * 0.5
		end
		NPC.Hit(item, direction)
		Net.Broadcast({kind="Hit",actor=player.UserId,attackSequence=request.attackSequence,id=item.id,
			version=item.version,hits=item.hits,started=workspace:GetServerTimeNow(),direction=direction,position=position})
		OnResult(true)
		if item.hits >= Config.StunHits then
			self:Tell(player, "StunnedCarry")
		else
			self:Tell(player, "HitCount", { tostring(item.hits), tostring(Config.StunHits) })
		end
		self:Changed()
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
	local result = Painting.Apply(session, item, request, Scene.TablePose(), Scene.CameraPose().Position, workspace:GetServerTimeNow())
	-- 重复或过快的请求已被规则层拒绝，不再向全服放大广播。
	if not result then
		return
	end
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
	session.visualSequence=sequence
	session.visualPackets=(session.visualPackets or 0)+1
	if Config.PaintPhysicsEnabled and request.bodyPose and BodyPose.Validate(item.model, request.bodyPose) then
		item.poseBody = table.clone(request.bodyPose)
		Painting.SetPose(session, item, Scene.TablePose(), session.orientation, true)
	end
	-- 操作者本地已即时渲染，只回传轻量序号确认；完整符文增量仅同步给其他旁观者。
	Net.FireNotify(player, { kind = "VisualDelta", id = item.id, session = session.token, sequence = sequence, segments = {}, visualRevision = state.revision })
	local observerNotice: Types.Notice = { kind = "VisualDelta", id = item.id, session = session.token, sequence = sequence, segments = accepted, visualRevision = state.revision, bodyPose = item.poseBody }
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.FireNotify(other, observerNotice)
		end
	end
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
		Net.FireNotify(player, { kind = "State", snapshot = self:Snapshot() })
		local histories: {{id: string,item: Types.Item,revision: number,segments: {Types.VisualSegment}}}={}
		for _,item in self.items do
			local state=item.visualState
			if state then
				local segments: {Types.VisualSegment}={}
				for _,segment in state.segments do table.insert(segments,segment) end
				table.insert(histories,{id=item.id,item=item,revision=state.revision,segments=segments})
			end
		end
		self.scope:Spawn(function(): ()
			local packets=0
			for _,history in histories do
				for first=1,#history.segments,Config.PaintVisualBatchSize do
					if self.items[history.id]~=history.item or self.players[player]~=record or record.closing then break end
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
	if request.action == "Drop" then
		local stack = self:Carried(player)
		local root = self:Root(player)
		local top = stack[1]
		if top and root then
			Carry.Drop(top, root.Position + root.CFrame.LookVector * 3, #stack == 1)
			if #stack > 1 then
				self:Restack(player)
			end
		elseif root then
			local held = self:Held(player)
			if held then
				Carry.Drop(held, root.Position + root.CFrame.LookVector * 3)
			end
		end
	elseif request.action == "TakeTable" then
		if not self:Held(player) and not self.paint and self.tableId and self:Near(player, Scene.TableInteract.Position, Config.InteractionRange, nil) then
			local item = self.items[self.tableId]
			if item and Carry.Take(item, player) then
				self.tableId = nil
				self:Restack(player)
			end
		end
	elseif request.action == "Interact" and target then
		local positions = {
			Pool = Scene.PoolPickup.Position,
			Table = Scene.TableInteract.Position,
			Altar = Scene.Altar.Position,
			Shelf = Scene.Shelf.Position,
			Sigil = Scene.SigilPosition,
		}
		local position = positions[target]
		if position then
			if request.version ~= self.stationVersions[target] then
				self:Tell(player, "StationChanged")
				return
			end
			if target == "Pool" then
				self:Pool(player)
			elseif target == "Table" then
				self:Table(player)
			elseif target == "Altar" then
				self:Altar(player)
			elseif target == "Shelf" then
				self:Shelf(player)
			else
				self:Submit(player)
			end
		else
			local item = self.items[target]
			local carried = self:Carried(player)
			if not item or item.version ~= request.version then
				self:Tell(player, "ItemChanged")
			elseif item.kind ~= "Body" and (#carried > 0 or self:Held(player) ~= nil) then
				self:Tell(player, "HandsFull")
			elseif item.kind == "Body" and self:ShoulderOccupied(player) then
				self:Tell(player, "HandsFull")
			elseif item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits) then
				local root=item.model.PrimaryPart
				if root and self:Near(player,root.Position,Config.InteractionRange,item.model) then
					if Carry.Take(item, player, #carried) and item.kind == "Body" then
						self:Restack(player)
					end
				else
					self:Tell(player,"ItemUnavailable")
				end
			else
				self:Tell(player, "ItemUnavailable")
			end
		end
	end
	self:Changed()
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
	self:Changed()
end
function Manager.OnCharacter(self: Manager, player: Player, character: Model): ()
	local record = self.players[player]
	if not record then
		return
	end
	self:ReleasePlayer(player)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	if not record.scope.alive or player.Character ~= character then
		return
	end
	root.CFrame = Scene.Spawn.CFrame * CFrame.new(0, 4, 0)
	local backpack = player:WaitForChild("Backpack")
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
	local club = ReplicatedStorage.Models.Club:Clone() :: Tool
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local handle = club:FindFirstChild("Handle")
	local slash = handle and handle:FindFirstChild("SwordSlash")
	if slash and slash:IsA("Sound") then
		slash.SoundId = Config.WeaponSlashSound
		local function OnStopSlash(): () slash:Stop() end
		record.scope:Connect(club.Unequipped:Connect(OnStopSlash))
		record.scope:Connect(humanoid.Died:Connect(OnStopSlash))
	end
	club.Parent = backpack
	humanoid:EquipTool(club)
	record.scope:Connect(humanoid.Died:Connect(function(): ()
		self:ReleasePlayer(player)
	end))
end
function Manager.AddPlayer(self: Manager, player: Player): ()
	if self.players[player] or self.closing then
		return
	end
	if not self.data.IsActive(player) then return end
	local record: PlayerRecord = { scope = Lifecycle.new(), lastAttack = 0, lastRequest = 0, lastSync = 0, closing = false }
	self.players[player] = record
	record.scope:Connect(player.CharacterRemoving:Connect(function(character: Model): ()
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
		elseif item.poolToss and Carry.AdvancePoolToss(item, now) then
			changedMotion = true
		end
	end
	if changedMotion then self:Changed() end
	if now < self.nextUpdate then
		return
	end
	self.nextUpdate = now + 0.1
	local count, bodies = 0, 0
	for _, item in self.items do
		local carrier = item.holder
		if Carry.Update(item, now) then
			if carrier then
				self:Restack(carrier)
			end
			self:Changed()
		end
		if item.streetSlot then
			count += 1
		end
		if item.kind == "Body" then
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
				self:Changed()
			end
		elseif item.location ~= "Altar" and primary and primary.Position.Y < -40 then
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
			self:Changed()
		end
	end
	if count < Config.StreetPopulation and bodies < Config.MaximumBodies and now >= self.nextSpawn then
		local item = NPC.Spawn(self.runtime, self.items)
		if item then
			self.items[item.id] = item
			self:Changed()
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
	local changed = false
	for _, item in ready do
		if self.items[item.id] ~= item then continue end
		if self:QualityCount(Config.DefaultPotionQuality) >= Config.ShelfCapacity then
			item.altarHeld = true
		elseif item.altarHeld then
			item.altarHeld = false
			item.convertEnds = now + Config.AltarClimaxSeconds
			changed = true
		else
			self:SpawnAltarPotion(item)
			changed = true
		end
	end
	if changed then
		self:Changed()
	end
	if self.paint and not self:Root(self.paint.player) then
		local player = self.paint.player
		self:EndPaint(player)
		self:Changed()
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
	Scene.EnsurePoolContainment()
	if Physics.GroundRootEnabled then Ground.Init() end
	Scene.BindPoolCollision()
	Door.Init(self.scope)
	self.scope:Connect(Net.ConnectRequest(function(player: Player, request: Types.Request): ()
		self:OnRequest(player, request)
	end))
	self.scope:Connect(RunService.Heartbeat:Connect(function(): ()
		self:Update()
	end))
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
	self.scope:Destroy()
end
return Manager
