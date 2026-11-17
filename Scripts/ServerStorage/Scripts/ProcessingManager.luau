-- 加工业务管理器：共享工位、搬运、权威画符和奖励；玩家生命周期由基础入口装配
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local Types = require(Shared.GameTypes)
local Net = require(Shared.ProcessingNet)
local Lifecycle = require(Shared.LifecycleTool)
local Info = require(script.Parent.ServerGameInfo)
local Scene = require(script.Parent.Scene)
local NPC = require(script.Parent.NPC)
local Carry = require(script.Parent.Carry)
local Ragdoll = require(script.Parent.Ragdoll)
local Door = require(script.Parent.Door)
local Painting = require(script.Parent.Painting)
local Replication = require(script.Parent.Replication)
local VisualRules = require(Shared.VisualRules)
local BodyPose = require(Shared.PaintBodyPose)
type PlayerData = { IsActive: (Player) -> boolean, CanAddCoins: (Player, number) -> boolean, AddCoins: (Player, number) -> boolean }
type PaintSession = Painting.Session
type PlayerRecord = {
	scope: Lifecycle.Lifecycle,
	lastAttack: number,
	lastRequest: number,
	lastSync: number,
	closing: boolean,
}
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
		shelf: { string },
		tableId: string?,
		altarId: string?,
		altarEnds: number,
		paint: PaintSession?,
		stationVersions: { [string]: number },
		stationKeys: { [string]: string },
		revision: number,
		nextSpawn: number,
		nextUpdate: number,
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
		paint = nil,
		stationVersions = { Pool = 1, Table = 1, Altar = 1, Shelf = 1, Sigil = 1 },
		stationKeys = {},
		revision = 0,
		nextSpawn = 0,
		nextUpdate = 0,
	}, Manager)
end
function Manager.Snapshot(self: Manager): Types.Snapshot
	local list: { Types.ItemView } = {}
	for _, item in self.items do
		table.insert(list, {
			id = item.id,
			kind = item.kind,
			stage = item.stage,
			location = item.location,
			version = item.version,
			model = item.model,
			hits = item.hits,
			progress = item.progress,
			holder = if item.holder then item.holder.UserId else nil,
			visualCount = if item.visualState then item.visualState.count else 0,
		})
	end
	local body = if self.tableId then self.items[self.tableId] else nil
	return {
		revision = self.revision,
		poseYaw = if body then body.poseYaw or 0 else 0,
		posePitch = if body then body.posePitch or 0 else 0,
		bodyPose = if body then body.poseBody else nil,
		stationVersions = table.clone(self.stationVersions),
		items = list,
		pool = #self.pool,
		shelf = #self.shelf,
		tableId = self.tableId,
		altarId = self.altarId,
		altarEnds = self.altarEnds,
		painter = if self.paint then self.paint.player.UserId else nil,
		session = if self.paint then self.paint.token else nil,
	}
end
function Manager.Changed(self: Manager): ()
	local keys: { [string]: string } = {
		Pool = table.concat(self.pool, ","),
		Table = (self.tableId or "") .. (if self.paint then self.paint.token else ""),
		Altar = (self.altarId or "") .. tostring(self.altarEnds),
		Shelf = table.concat(self.shelf, ","),
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
function Manager.Tell(_self: Manager, player: Player, text: string): ()
	Net.FireNotify(player, { kind = "Message", text = text })
end
function Manager.Held(self: Manager, player: Player): Types.Item?
	for _, item in self.items do
		if item.holder == player then
			return item
		end
	end
	return nil
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
function Manager.Arrange(self: Manager): ()
	for index, id in self.pool do
		local item = self.items[id]
		if item then
			Carry.Static(item, Scene.PoolPose(index))
		end
	end
	for index, id in self.shelf do
		local item = self.items[id]
		if item then
			Carry.Static(item, Scene.ShelfPose(index))
		end
	end
end
function Manager.EndPaint(self: Manager, player: Player): ()
	local session = self.paint
	if not session or session.player ~= player then
		return
	end
	local item = self.items[session.id]
	if item and item.progress>=1 then item.stage="Painted";item.version+=1 end
	if item and item.stage ~= "Painted" then
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
	if character then
		local brush = character:FindFirstChild("RuneBrush")
		if brush then
			brush:Destroy()
		end
	end
	if hum and hum.Health > 0 then
		local backpack = player:FindFirstChild("Backpack")
		local club = backpack and backpack:FindFirstChild("Club")
		if club and club:IsA("Tool") then
			hum:EquipTool(club)
		end
	end
	player:SetAttribute("Painting", false)
	self.paint = nil
	Net.FireNotify(player, { kind = "EndPaint", session = session.token })
end
function Manager.BeginPaint(self: Manager, player: Player, item: Types.Item): ()
	if self.paint then
		self:Tell(player, "The table is in use.")
		return
	end
	local character = player.Character
	local root = self:Root(player)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not hum then
		return
	end
	local session: PaintSession = {
		player = player,
		id = item.id,
		token = HttpService:GenerateGUID(false),
		last = workspace:GetServerTimeNow(),
		sequence = 0,
		yaw = 0,
		pitch = 0,
		walkSpeed = hum.WalkSpeed,
		jumpPower = hum.JumpPower,
		jumpHeight = hum.JumpHeight,
	}
	self.paint = session
	item.poseYaw, item.posePitch = 0, 0
	item.poseBody=nil
	item.stage = "Painting"
	item.version += 1
	hum:UnequipTools()
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	root.Anchored = true
	local brush = ReplicatedStorage.Models.RuneBrush:Clone() :: Tool
	brush.Parent = player:WaitForChild("Backpack")
	hum:EquipTool(brush)
	player:SetAttribute("Painting", true)
	Carry.Static(item, Scene.TablePose())
	Net.FireNotify(player, { kind = "BeginPaint", id = item.id, session = session.token })
end
function Manager.Pool(self: Manager, player: Player): ()
	local held = self:Held(player)
	if held then
		if held.kind ~= "Body" or held.stage == "Painted" then
			self:Tell(player, "Store unfinished bodies here.")
			return
		end
		if #self.pool >= Config.PoolCapacity then
			self:Tell(player, "The holding pool is full.")
			return
		end
		Carry.Detach(held)
		held.location = "Pool"
		held.version += 1
		table.insert(self.pool, held.id)
	elseif #self.pool > 0 then
		local id = self.pool[1]
		local item = self.items[id]
		if item and Carry.Take(item, player) then
			table.remove(self.pool, 1)
		end
	else
		self:Tell(player, "The holding pool is empty.")
	end
	self:Arrange()
end
function Manager.Table(self: Manager, player: Player): ()
	if self.paint then
		self:Tell(player, "The table is in use.")
		return
	end
	local held = self:Held(player)
	if self.tableId then
		if held then
			self:Tell(player, "The table is occupied.")
			return
		end
		local item = self.items[self.tableId]
		if not item then
			return
		end
		if item.stage == "Painted" then
			if Carry.Take(item, player) then
				self.tableId = nil
			end
		else
			self:BeginPaint(player, item)
		end
		return
	end
	if held and (held.kind ~= "Body" or held.stage == "Painted") then
		self:Tell(player, "Bring an unfinished body.")
		return
	end
	local item = held
	if not item and #self.pool > 0 then
		item = self.items[self.pool[1]]
		table.remove(self.pool, 1)
		self:Arrange()
	end
	if not item then
		self:Tell(player, "Bring a stunned body or fill the pool.")
		return
	end
	Carry.Static(item, Scene.TablePose())
	item.location = "Table"
	item.streetSlot = false
	item.version += 1
	self.tableId = item.id
	self:BeginPaint(player, item)
end
function Manager.Altar(self: Manager, player: Player): ()
	local item = self:Held(player)
	if self.altarId then
		self:Tell(player, "The altar is occupied.")
		return
	end
	if not item or item.kind ~= "Body" or item.stage ~= "Painted" then
		self:Tell(player, "The altar needs a completed rune body.")
		return
	end
	Carry.Static(item, Scene.Altar.CFrame * CFrame.new(0, 2, 0) * CFrame.Angles(math.pi / 2, 0, 0))
	item.location, item.stage = "Altar", "Converting"
	item.version += 1
	self.altarId, self.altarEnds = item.id, workspace:GetServerTimeNow() + Config.ConversionSeconds
end
function Manager.Shelf(self: Manager, player: Player): ()
	if self:Held(player) then
		self:Tell(player, "Your hands are full.")
		return
	end
	if #self.shelf == 0 then
		self:Tell(player, "No potions are ready.")
		return
	end
	local item = self.items[self.shelf[1]]
	if item and Carry.Take(item, player) then
		table.remove(self.shelf, 1)
		self:Arrange()
	end
end
function Manager.Submit(self: Manager, player: Player): ()
	local record = self.players[player]
	local item = self:Held(player)
	if not record or not self.data.IsActive(player) then
		return
	end
	if not item or item.kind ~= "Potion" then
		self:Tell(player, "Bring a potion to the summoning sigil.")
		return
	end
	if not self.data.CanAddCoins(player, Config.PotionReward) then
		self:Tell(player, "Coin limit reached.")
		return
	end
	Carry.Detach(item)
	self.items[item.id] = nil
	item.stage = "Consumed"
	item.model:Destroy()
	self.stationVersions.Sigil += 1
	self.data.AddCoins(player, Config.PotionReward)
	self:Tell(player, "+100 COINS")
end
function Manager.Attack(self: Manager, player: Player, request: Types.Request): ()
	local record = self.players[player]
	local root = self:Root(player)
	if not record or not root or self:Held(player) or (self.paint and self.paint.player == player) then
		return
	end
	local character = player.Character
	local weapon = character and character:FindFirstChild("Club")
	if not weapon or not weapon:IsA("Tool") then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - record.lastAttack < Config.AttackCooldown then
		return
	end
	record.lastAttack = now
	Net.Broadcast({ kind = "Swing", actor = player.UserId, started = now })
	-- 只在服务端接受挥击后播放一次；复用武器内的官方空间音效。
	local handle = weapon:FindFirstChild("Handle")
	local slash = handle and handle:FindFirstChild("SwordSlash")
	if slash and slash:IsA("Sound") then
		slash:Stop()
		slash.TimePosition = 0
		slash:Play()
	end
	self.scope:Spawn(function(): ()
		task.wait(Config.AttackWindup)
		local item = if request.target then self.items[request.target] else nil
		if not item or item.kind ~= "Body" or item.location ~= "Street" or item.hits >= Config.StunHits or item.version ~= request.version then
			return
		end
		local root = self:Root(player)
		if not root or self.players[player] ~= record or record.closing or self:Held(player) then return end
		local equipped = player.Character and player.Character:FindFirstChild("Club")
		if equipped ~= weapon or player.Character ~= character then return end
		local target = item.model.PrimaryPart
		if not target or not self:Near(player, target.Position, Config.AttackRange, item.model) then
			return
		end
		local delta = target.Position - root.Position
		if delta.Magnitude > 0.1 and root.CFrame.LookVector:Dot(delta.Unit) < -0.1 then
			return
		end
		NPC.Hit(item, root.CFrame.LookVector)
		self:Tell(player, if item.hits >= Config.StunHits then "STUNNED - E TO CARRY" else string.format("HIT %d/%d", item.hits, Config.StunHits))
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
	Net.Broadcast({ kind = "PaintPose", id = item.id, session = session.token, sequence = request.sequence, yaw = session.yaw, pitch = session.pitch, progress = item.progress, bodyPose=item.poseBody, started=workspace:GetServerTimeNow() })
	if result and result.complete then
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
	local reason: string?=nil
	local now=workspace:GetServerTimeNow()
	if now-(session.visualWindow or 0)>=1 then session.visualWindow=now;session.visualPackets=0 end
	if sequence~=previous+1 then reason="Paint batch out of sequence."
	elseif (session.visualPackets or 0)>=Config.PaintVisualPacketsPerSecond then reason="Paint upload rate exceeded." end
	for _,segment in request.segments do
		local part=item.model:FindFirstChild(segment.part)
		if not part or not part:IsA("BasePart") or not part:GetAttribute("Paintable") then reason="Invalid paint body part.";break end
		if part:GetAttribute("SurfaceVersion")~=segment.surfaceVersion then reason="Paint surface version mismatch.";break end
	end
	local state=item.visualState or VisualRules.New()
	local accepted: {Types.VisualSegment}?=nil
	if not reason then accepted,reason=VisualRules.Apply(state,request.segments,session.token) end
	if reason or not accepted then
		Net.FireNotify(player,{kind="VisualRejected",id=item.id,session=session.token,sequence=previous,text=reason or "Paint upload rejected."})
		return
	end
	item.visualState=state
	session.visualSequence=sequence
	session.visualPackets=(session.visualPackets or 0)+1
	session.yaw=((request.yaw or session.yaw)+math.pi)%(2*math.pi)-math.pi
	session.pitch=math.clamp(request.pitch or session.pitch,-Config.PaintPitchLimit,Config.PaintPitchLimit)
	item.poseYaw,item.posePitch=session.yaw,session.pitch
	if request.bodyPose and BodyPose.Validate(item.model,request.bodyPose) then item.poseBody=table.clone(request.bodyPose) end
	BodyPose.Apply(item.model,Scene.TablePose()*CFrame.Angles(session.pitch,session.yaw,0),item.poseBody)
	Net.Broadcast({kind="VisualDelta",id=item.id,session=session.token,sequence=sequence,segments=accepted,visualRevision=state.revision,yaw=session.yaw,pitch=session.pitch,bodyPose=item.poseBody,started=math.min(request.started or now,now)})
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
	if request.action=="EndPaint" then
		local session=self.paint
		if session and session.player==player and session.token==request.session and (request.sequence or 0)==(session.visualSequence or 0) then
			local complete=session.finishing
			self:EndPaint(player)
			if complete then self:Tell(player,"Rune complete. Pick up the body.") end
			self:Changed()
		end
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
		if request.action == "ResetView" then
			self.paint.yaw = 0
			self.paint.pitch = 0
			local i = self.items[self.paint.id]
			if i then
				i.poseYaw, i.posePitch = 0, 0
				i.model:PivotTo(Scene.TablePose())
				Net.Broadcast({ kind = "PaintPose", id = i.id, session = self.paint.token, yaw = 0, pitch = 0, progress = i.progress,started=now })
			end
		end
		return
	end
	local target = request.target
	if request.action == "Attack" then
		self:Attack(player, request)
	elseif request.action == "Drop" then
		local held = self:Held(player)
		local root = self:Root(player)
		if held and root then
			Carry.Drop(held, root.Position + root.CFrame.LookVector * 3)
		end
	elseif request.action == "TakeTable" then
		if not self:Held(player) and not self.paint and self.tableId and self:Near(player, Scene.TableInteract.Position, Config.InteractionRange, nil) then
			local item = self.items[self.tableId]
			if item and Carry.Take(item, player) then
				self.tableId = nil
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
				self:Tell(player, "Station changed. Try interacting again.")
				return
			end
			if not self:Near(player, position, Config.InteractionRange, nil) then
				self:Tell(player, "Move closer with a clear path to the station.")
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
			if self:Held(player) then
				self:Tell(player, "Your hands are full.")
				return
			end
			if not item or item.version ~= request.version then
				self:Tell(player, "Item changed or was taken. Choose it again.")
			elseif item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits) then
				local primary = item.model.PrimaryPart
				if primary and self:Near(player, primary.Position, Config.InteractionRange, item.model) then
					Carry.Take(item, player)
				else
					self:Tell(player, "Move closer with a clear path to the item.")
				end
			else
				self:Tell(player, "This item is occupied or cannot be carried yet.")
			end
		end
	end
	self:Changed()
end
function Manager.ReleasePlayer(self: Manager, player: Player): ()
	self:EndPaint(player)
	local held = self:Held(player)
	if held then
		local primary = held.model.PrimaryPart
		Carry.Drop(held, if primary then primary.Position else Scene.PoolPickup.Position)
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
	for _, v in backpack:GetChildren() do
		if v:IsA("Tool") then
			v:Destroy()
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
	record.scope:Destroy()
	self.players[player] = nil
	self.removing[player] = nil
end
function Manager.Update(self: Manager): ()
	if self.closing then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < self.nextUpdate then
		return
	end
	self.nextUpdate = now + 0.1
	local count, bodies = 0, 0
	for _, item in self.items do
		if Carry.Update(item, now) then self:Changed() end
		if item.streetSlot then
			count += 1
		end
		if item.kind == "Body" then
			bodies += 1
		end
		if item.kind == "Body" then
			NPC.Update(item, now)
			if item.hits >= Config.StunHits then
				Ragdoll.LimitVelocity(item.model)
			end
		end
		local primary = item.model.PrimaryPart
		if primary and primary.Position.Y < -40 then
			if item.holder then
				self:EndPaint(item.holder)
			end
			Carry.Drop(item, Vector3.new(0, -100, 0))
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
	if self.altarId and now >= self.altarEnds and #self.shelf < Config.ShelfCapacity then
		local item = self.items[self.altarId]
		if item then
			item.model:Destroy()
			self.items[item.id] = nil
			local model = ReplicatedStorage.Models.Potion:Clone() :: Model
			local id = HttpService:GenerateGUID(false)
			model:SetAttribute("ItemId", id)
			model.Parent = self.runtime
			local potion: Types.Item = {
				id = id,
				kind = "Potion",
				stage = "Ready",
				location = "Shelf",
				version = 1,
				model = model,
				holder = nil,
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
			table.insert(self.shelf, id)
		end
		self.altarId = nil
		self.altarEnds = 0
		self:Arrange()
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
