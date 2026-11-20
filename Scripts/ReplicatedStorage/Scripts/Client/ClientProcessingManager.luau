-- 加工客户端：共享状态展示、键鼠触屏交互、工作台俯视镜头及拖画
--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("GameTypes"))
local GameTexts = require(Shared.GameTexts)
local Sound = require(Shared:WaitForChild("GameSoundTool"))
local UIManager = require(script.Parent.UIManager)
local GameScreenGuiManager = require(script.Parent.UIManager.GameScreenGuiManager)
local Hints = require(Shared:WaitForChild("Hints"))
local Rotation = require(Shared.PaintRotation)
local Surface = require(Shared.PaintSurface)
local Curve = require(Shared.CurvedSurface)
local Net = require(Shared:WaitForChild("ProcessingNet"))
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local PaintView = require(script.Parent:WaitForChild("PaintView"))
local Presentation = require(script.Parent.BodyPresentation)
local WhiteBodies = require(script.Parent.WhiteBodyPresentationManager)
local Tuning = require(script.Parent.PresentationTuning)
local CharacterPresentation = require(script.Parent.CharacterPresentation)
local HitPresentation = require(script.Parent.HitPresentation)
local HitRules = require(Shared.HitFeedbackRules)
local Physics = require(Shared.PhysicsConfig)
local PaintCamera = require(script.Parent.PaintCamera)
local PaintBrush = require(script.Parent.PaintBrushContact)
local VisualUpload = require(script.Parent.VisualUpload)
local WorldInteractionManager = require(script.Parent.WorldInteractionManager)
local AltarSacrifice = require(script.Parent.AltarSacrificeView)
local PotionShelf = require(script.Parent.PotionShelfView)
local Client = {}
Client.__index = Client
local player = Players.LocalPlayer
export type Client = typeof(setmetatable(
	{} :: {
		scope: Lifecycle.Lifecycle,
		worldInteraction: WorldInteractionManager.Manager?,
		ui: GameScreenGuiManager.Manager,
		view: PaintView.View,
		presentation: Presentation.Presentation,
		characterView: CharacterPresentation.Presentation,
		paintCamera: PaintCamera.Controller,
		visualUpload: VisualUpload.Upload,
		visualClosing: boolean,
		hitView: HitPresentation.Presentation,
		hitState: HitRules.State,
		waitingHits: {Types.Notice},
		attackSequence: number,
		lastAttack: number,
		attackTarget: string?,
		comboEnds: number,
		bodies: WhiteBodies.Manager,
		altarView: AltarSacrifice.View,
		altarViews: { [string]: AltarSacrifice.View },
		altarBodyId: string?,
		altarLoopSound: Sound?,
		potionShelf: PotionShelf.View,
		lastHeldId: string?,
		lastHeldKind: string?,
		lastPoolCount: number?,
		lastPotionCount: number?,
		lastPaintSound: number,
		snapshot: Types.Snapshot?,
		items: { [string]: Types.ItemView },
		paintId: string?,
		session: string?,
		drawing: boolean,
		finishPaint: boolean,
		touch: InputObject?,
		pointer: Vector2?,
		pointerOrigin: Vector2?,
		hardwareOrigin: Vector2?,
		rotationAnchor: Vector2?,
		brushFrame: PaintBrush.Frame?,
		pendingCoverage: Types.Request?,
		paintSamples: {Types.Sample},
		localCovered: {[string]: boolean}?,
		visualGesture: number,
		orientation: CFrame,
		sentOrientation: CFrame,
		lastPaint: number,
		paintSequence: number,
		angularSpeed: number,
		target: string?,
		nearTable: boolean,
		lastSync: number,
		synced: boolean,
		lastHint: number,
		messageEnds: number,
		touchGuiEnabled: boolean?,
		initialized: boolean,
	},
	Client
))
local district = workspace:WaitForChild("NeonContractDistrict")
local tableModel = district:WaitForChild("RuneBodyTable")
local tablePlacement = tableModel:WaitForChild("BodyPlacementAnchor") :: BasePart
local tableInteract = tableModel:WaitForChild("TransferStartAnchor") :: BasePart
local function Anchor(station: string, name: string): BasePart
	return district:WaitForChild(station):WaitForChild(name) :: BasePart
end
local submitAnchor = district:WaitForChild("SummoningSubmitAnchor") :: BasePart
local interactionAnchors: {[string]: BasePart} = {
	Pool = Anchor("SoulHoldingPool", "PickupPointAnchor"),
	Table = tableInteract,
	Altar = Anchor("SoulConversionAltar", "BodyArrivalAnchor"),
	Shelf = Anchor("SoulCrystalDisplay", "StockPickupAnchor"),
	Sigil = submitAnchor,
}
local positions: { [string]: Vector3 } = {
	Pool = Anchor("SoulHoldingPool", "PickupPointAnchor").Position,
	Table = tableInteract.Position,
	Altar = Anchor("SoulConversionAltar", "BodyArrivalAnchor").Position,
	Shelf = Anchor("SoulCrystalDisplay", "StockPickupAnchor").Position,
	Sigil = submitAnchor.Position,
}
local function TablePose(): CFrame
	return Rotation.TablePose(tablePlacement.Position)
end
local function CameraPose(): CFrame
	return Rotation.CameraPose(tablePlacement.Position)
end
function Client.new(): Client
	local tableView, hitView, paint = Presentation.new(), HitPresentation.new(), PaintView.new()
	local bodies = WhiteBodies.new(tableView, hitView, function(id, model)
		if model then paint:Bind(id,model) else paint:Detach(id) end
	end)
	return setmetatable(
		{
			scope = Lifecycle.new(),
			ui = UIManager.GetGameScreenGuiManager(),
			view = paint,
			presentation = tableView,
			characterView = CharacterPresentation.new(),
			paintCamera = PaintCamera.new(),
			visualUpload = VisualUpload.new(),
			visualClosing = false,
			hitView = hitView,
			hitState = HitRules.New(), waitingHits={},
			attackSequence = 0,
			lastAttack = 0,
			attackTarget = nil,
			comboEnds = 0,
			bodies = bodies,
			altarView = AltarSacrifice.new(),
			altarViews = {},
			altarBodyId = nil,
			altarLoopSound = nil,
			potionShelf = PotionShelf.new(positions.Shelf),
			lastHeldId = nil,
			lastHeldKind = nil,
			lastPoolCount = nil,
			lastPotionCount = nil,
			lastPaintSound = 0,
			snapshot = nil,
			items = {},
			paintId = nil,
			session = nil,
			drawing = false,
			finishPaint = false,
			touch = nil,
			rotationAnchor = nil,
			paintSamples = {},
			localCovered = {},
			visualGesture = 0,
			orientation = CFrame.identity,
			sentOrientation = CFrame.identity,
			lastPaint = 0,
			paintSequence = 0,
			angularSpeed = 0,
			target = nil,
			nearTable = false,
			lastSync = 0,
			synced = false,
			lastHint = 0,
			messageEnds = 0,
			touchGuiEnabled = nil,
			initialized = false,
		},
		Client
	)
end
function Client.Text(self: Client, name: string, description: GameTexts.Description?): ()
	self.ui:SetText(name, description)
end
function Client.Notice(self: Client, notice: Types.Notice): ()
	self.ui:ShowNotice(notice)
end
function Client.Carried(self: Client): { Types.ItemView }
	local list: { Types.ItemView } = {}
	for _, item in self.items do
		if item.holder == player.UserId and item.kind == "Body" then
			table.insert(list, item)
		end
	end
	return list
end
function Client.Held(self: Client): Types.ItemView?
	local carried = self:Carried()
	if carried[1] then
		return carried[1]
	end
	for _, item in self.items do
		if item.holder == player.UserId then
			return item
		end
	end
	return nil
end
local function StackCount(model: Model): number
	local count = model:GetAttribute("StackCount")
	if typeof(count) == "number" and count > 0 then
		return count
	end
	return 1
end
function Client.Potions(self: Client): Hints.Potions
	local stored = 0
	local equipped = false
	local character = player.Character
	for _, item in self.items do
		local model = item.model
		if item.kind == "Potion" and item.location == "Toolbar" and model then
			stored += StackCount(model)
			if model.Parent == character then
				equipped = true
			end
		end
	end
	return { stored = stored, equipped = equipped }
end
function Client.ExitView(self: Client, altarTossStarted: number?): ()
	local id = self.paintId
	if not id then
		return
	end
	self.paintId = nil
	self.visualUpload:Clear()
	self.visualClosing = false
	self.session = nil
	self.drawing = false
	self.finishPaint = false
	self.pointer, self.brushFrame = nil, nil
	self.pointerOrigin, self.hardwareOrigin = nil, nil
	table.clear(self.paintSamples)
	if self.localCovered then table.clear(self.localCovered) end
	self.pendingCoverage = nil
	self.touch = nil
	self.rotationAnchor = nil
	self.angularSpeed = 0
	if altarTossStarted then
		local ends = altarTossStarted + Physics.AltarToss.LiftSeconds + Physics.AltarToss.CameraFollowSeconds
		self.paintCamera:FollowToss(ends, function(): Vector3?
			local torso = self.bodies:GetVisualPart(id, "UpperTorso")
			return if torso and torso:IsDescendantOf(workspace) then torso.Position else nil
		end)
	else
		self.paintCamera:Exit()
	end
	local touchGui = player:WaitForChild("PlayerGui"):FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") and self.touchGuiEnabled ~= nil then
		touchGui.Enabled = self.touchGuiEnabled
	end
	self.touchGuiEnabled = nil
	self.ui:SetPainting(false)
end
function Client.EnterView(self: Client, id: string, session: string, frames: Types.BodyPose?): ()
	if self.paintId then
		self:ExitView()
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self:CancelHitFeedback()
	self.paintId, self.session = id, session
	self.visualUpload:Begin(session)
	self.visualClosing = false
	self.paintSequence = 0
	self.lastPaint = os.clock()
	if self.localCovered then table.clear(self.localCovered) else self.localCovered = {} end
	self.orientation, self.sentOrientation = CFrame.identity, CFrame.identity
	if UserInputService.MouseEnabled then
		local inset = GuiService:GetGuiInset()
		self.pointer = UserInputService:GetMouseLocation() - inset
	end
	if frames and self.presentation.model == self.bodies:GetPaintModel(id) then
		self.presentation.targetBodyPose = frames
	end
	local touchGui = player:WaitForChild("PlayerGui"):FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") then
		self.touchGuiEnabled = touchGui.Enabled
		touchGui.Enabled = false
	end
	self.paintCamera:Enter(CameraPose())
	self.ui:SetPainting(true)
end
function Client.CancelHitFeedback(self: Client): ()
	for sequence, prediction in self.hitState.pending do
		if not prediction.resolved then self.bodies:Reject(prediction.target,player.UserId,sequence); prediction.resolved=true end
	end
	self.hitView:ResetCamera()
end
function Client.HitFeedback(self: Client, now: number, final: boolean, upgrade: boolean): ()
	if now-self.lastAttack>Config.HitFeedbackWindow or self.paintId or self:Held() then return end
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health<=0 or not character or not character:FindFirstChild("Club") then return end
	self.characterView:HitStop(now,final)
	if not self.bodies.pureModel then self.hitView:Shake(now,final,upgrade) end
	if Sound then
		Sound.Play(if final then "BodyStun" else "HitImpact")
	end
end
function Client.UpdateHits(self: Client, now: number): ()
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if self.paintId or self:Held() or not humanoid or humanoid.Health<=0 or not character or not character:FindFirstChild("Club") then
		self:CancelHitFeedback()
	else
		for sequence, prediction in self.hitState.pending do
			if prediction.resolved or prediction.played or now<prediction.due then continue end
			local id=HitRules.TakePrediction(self.hitState,sequence,now)
			local item=if id then self.items[id] else nil
			if not id or not item or item.kind~="Body" or item.location~="Street" or item.hits>=Config.StunHits
				or not item.model or not item.model.Parent or not item.model.PrimaryPart or not root or not root:IsA("BasePart") then
				prediction.played=false; prediction.resolved=true; continue
			end
			local delta=item.model.PrimaryPart.Position-root.Position
			if delta.Magnitude>=Config.AttackRange or (delta.Magnitude>0.1 and root.CFrame.LookVector:Dot(delta.Unit)<=-0.1) then
				prediction.played=false; prediction.resolved=true; continue
			end
			local torso=item.model:FindFirstChild("UpperTorso")
			local position=item.model.PrimaryPart.Position
			if torso and torso:IsA("BasePart") then position=torso.Position-root.CFrame.LookVector*torso.Size.Z*0.5 end
			local hits=item.hits+1
			if not self.bodies:Hit(id,player.UserId,sequence,item.version+1,hits,root.CFrame.LookVector,position,now,false,true) then
				self.hitView:Play(id,item.model,hits,root.CFrame.LookVector,now)
			end
			if not self.bodies.pureModel then self.hitView:Burst(id,position,root.CFrame.LookVector,false,now) end
			self:HitFeedback(now,false,false)
		end
	end
	HitRules.Prune(self.hitState,now)
	self.hitView:Apply(now)
end
function Client.OnHit(self: Client, notice: Types.Notice): ()
	local id,version,hits,started,direction,position=notice.id,notice.version,notice.hits,notice.started,notice.direction,notice.position
	if not id or not version or not hits or not started or not direction or not position then return end
	local item=self.items[id]
	if not item or not item.model or not item.model.Parent then
		if workspace:GetServerTimeNow()-started<=Config.HitSecondPoseSeconds and #self.waitingHits<32 then table.insert(self.waitingHits,notice) end
		return
	end
	if not self.bodies:AcceptNotice(id,version,hits,started) then return end
	local localActor=notice.actor==player.UserId
	local prediction=if localActor and notice.attackSequence then self.hitState.pending[notice.attackSequence] else nil
	if prediction and prediction.retired and prediction.target==id and hits<Config.StunHits then return end
	if prediction and prediction.target~=id and notice.attackSequence then self.bodies:Reject(prediction.target,player.UserId,notice.attackSequence) end
	local previous= self.hitState.versions[id] or 0
	local replay=HitRules.Confirm(self.hitState,id,version,if localActor then notice.attackSequence else nil)
	if version<=previous then return end
	local now=workspace:GetServerTimeNow()
	local age=now-started
	-- 正确目标修正现有脉冲；地面交接由含落点的权威 ItemView 启动。
	local final=hits>=Config.StunHits
	if final then self.hitView:Remove(id) end
	if age<0 or age>Config.HitSecondPoseSeconds then return end
	if item.location=="Street" and item.hits<Config.StunHits and item.version<=version then
		local managed=self.bodies:Hit(id,notice.actor or 0,notice.attackSequence,version,hits,direction,position,started,true,replay)
		if not managed and replay and not final then self.hitView:Play(id,item.model,hits,direction,started) end
	end
	if replay then
		if not self.bodies.pureModel and age<(if final then Config.HitFinalEffectSeconds else Config.HitEffectSeconds) then self.hitView:Burst(id,position,direction,final,started) end
	end
	if localActor and notice.attackSequence==self.attackSequence then
		if replay then self:HitFeedback(now,final,false)
		elseif final then self.hitView:UpgradeBurst(id); self:HitFeedback(now,true,true) end
	end
end
function Client.OnNotice(self: Client, notice: Types.Notice): ()
	if notice.kind=="Hit" then self:OnHit(notice); return end
	if notice.kind=="AttackResult" and notice.attackSequence then
		local pending=self.hitState.pending[notice.attackSequence]
		if pending and notice.hit~=true then self.bodies:Reject(pending.target,player.UserId,notice.attackSequence) end
		HitRules.Result(self.hitState,notice.attackSequence,notice.hit==true)
		return
	end
	if (notice.kind == "State" or notice.kind == "Delta") and notice.snapshot then
		local snapshot = notice.snapshot
		if self.snapshot and snapshot.revision < self.snapshot.revision then
			return
		end
		if notice.kind == "Delta" and (not self.snapshot or snapshot.revision > self.snapshot.revision + 1) then
			self.synced=false
			Net.FireRequest({action="Sync"})
			return
		end
		if notice.kind == "Delta" then
			local merged = table.clone(self.items)
			for _, id in ipairs(notice.removed or {}) do merged[id] = nil end
			for _, item in snapshot.items do merged[item.id] = item end
			snapshot.items = {}
			for _, item in merged do table.insert(snapshot.items, item) end
		end
		self.snapshot = snapshot
		self.potionShelf:Apply(snapshot.shelfItems, notice.kind == "Delta" and self.synced, os.clock())
		if snapshot.painter ~= player.UserId then
			self.presentation.targetOrientation = snapshot.paintOrientation or CFrame.identity
		end
		if snapshot.bodyPose and (self.paintId == nil or self.paintId == snapshot.tableId) then
			self.presentation.targetBodyPose = snapshot.bodyPose
		end
		local nextItems: { [string]: Types.ItemView } = {}
		for _, item in snapshot.items do
			nextItems[item.id] = item
		end
		self.bodies:UpdateState(nextItems,snapshot.bodyPose)
		for _,item in nextItems do
			if item.kind ~= "Body" and item.model then self.view:Bind(item.id,item.model) end
		end
		for id in self.items do
			if not nextItems[id] then
				self.view:Remove(id)
				self.hitView:Remove(id)
				self.hitState.versions[id]=nil
			end
		end
		for id,item in nextItems do
			if item.location~="Street" or item.hits>=Config.StunHits then self.hitView:Remove(id) end
		end
		self.items = nextItems
		local currentHeld = self:Held()
		local currentHeldId = currentHeld and currentHeld.id
		local currentHeldKind = currentHeld and currentHeld.kind
		local lastId = self.lastHeldId
		local lastKind = self.lastHeldKind
		local lastPool = self.lastPoolCount or snapshot.pool
		if lastId ~= currentHeldId then
			if not lastId and currentHeld then
				if currentHeldKind == "Body" then
					if snapshot.pool < lastPool then
						Sound.Play("PoolRetrieve", positions.Pool)
					else
						Sound.Play("BodyPickup")
					end
				end
			elseif lastId and not currentHeld then
				if lastKind == "Body" then
					local released = nextItems[lastId]
					if snapshot.pool > lastPool then
						Sound.Play("PoolDeposit", positions.Pool)
					elseif released and released.location == "Altar" then
						Sound.Play("AltarPlace", positions.Altar)
					else
						Sound.Play("BodyDrop")
					end
				end
			end
			self.lastHeldId = currentHeldId
			self.lastHeldKind = currentHeldKind
		end
		self.lastPoolCount = snapshot.pool
		local waiting=self.waitingHits
		self.waitingHits={}
		for _,hit in waiting do self:OnHit(hit) end
		table.clear(self.characterView.carriers)
		for _, item in nextItems do
			if item.holder and item.kind == "Body" then self.characterView.carriers[item.holder] = true end
		end
		if self.paintId and (snapshot.painter ~= player.UserId or snapshot.session ~= self.session) then
			local body = nextItems[self.paintId]
			self:ExitView(if body then body.altarTossStarted else nil)
		end
	elseif notice.kind == "Swing" and notice.actor and notice.started then
		-- 本地已即时预测；远端其他角色在对应空间位置播放挥舞音效，避免服务端广播延迟与回声
		if notice.actor ~= player.UserId then
			local otherPlayer = Players:GetPlayerByUserId(notice.actor)
			local otherChar = otherPlayer and otherPlayer.Character
			local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
			if Sound and otherRoot and otherRoot:IsA("BasePart") then
				Sound.Play("AttackSwing", otherRoot.Position)
			end
		end
	elseif notice.kind == "SyncComplete" then
		self.synced = true
	elseif notice.kind == "PaintPose" and notice.id then
		-- 本地笔迹逐帧保留，确认不擦除；操作者的角度始终由本地输入驱动。
		local snapshot = self.snapshot
		local isOperator = notice.id == self.paintId and notice.session == self.session
		local isCurrentTable = snapshot and notice.id == snapshot.tableId and notice.session == snapshot.session
		if not isOperator and not isCurrentTable then return end
		local item = self.items[notice.id]
		if item then item.progress = notice.progress or item.progress end
		if isOperator and self.pendingCoverage and notice.sequence == self.pendingCoverage.sequence then self.pendingCoverage=nil end
		if not isOperator then
			self.presentation.targetOrientation = notice.orientation or CFrame.identity
		end
	elseif notice.kind == "VisualDelta" and notice.id and notice.segments then
		local item = self.items[notice.id]
		if not item then return end
		self.view:Apply(notice.id,notice.segments)
		if notice.session == self.session and notice.sequence then self.visualUpload:Ack(notice.sequence) end
	elseif notice.kind == "VisualSnapshot" and notice.id and notice.segments then
		local item = self.items[notice.id]
		if not item then return end
		self.view:Apply(notice.id,notice.segments)
	elseif notice.kind == "VisualRejected" and notice.session == self.session then
		self.visualUpload.blocked=true
		self.drawing=false
		self.brushFrame = nil
		self.visualClosing=true
		if notice.id then self.view:Remove(notice.id) end
		Net.FireRequest({action="EndPaint",session=self.session,sequence=notice.sequence or self.visualUpload.acked})
		self.synced=false
		self.lastSync=0
		self:Notice(if notice.textId or notice.text then notice else {kind = "Message", textId = "PaintSyncFailed"})
		self.messageEnds=os.clock()+10
	elseif notice.kind == "FinishPaint" and notice.session == self.session then
		self.pendingCoverage=nil
		table.clear(self.paintSamples)
		self.sentOrientation=self.orientation
		self:RequestPaintEnd()
	elseif notice.kind == "BeginPaint" and notice.id and notice.session then
		self:EnterView(notice.id, notice.session, notice.bodyPose)
	elseif notice.kind == "EndPaint" and notice.session == self.session then
		self:ExitView(notice.started)
	elseif notice.kind == "Message" and (notice.textId or notice.text) then
		self:Notice(notice)
		self.messageEnds = os.clock() + 3
		if notice.textId == "CoinsAwarded" then
			Sound.Play("CoinReward")
		elseif notice.textId == "RuneComplete" then
			Sound.Play("PaintComplete")
		end
	end
end
function Client.RequestPaintEnd(self: Client): ()
	if not self.paintId or self.visualClosing then return end
	self.visualClosing=true
	self.visualUpload.closing=true
	-- 退出按钮只触发收尾，待发覆盖点已记录各自的落笔姿态。
	self.finishPaint=self.drawing or self.finishPaint
	self.drawing=false
	self.brushFrame = nil
	self.touch=nil
	self.rotationAnchor=nil
	self.angularSpeed=0
end
function Client.Drop(self: Client): ()
	if self.paintId then
		return
	end
	if not self:Held() and self.nearTable then
		Net.FireRequest({ action = "TakeTable" })
	else
		Net.FireRequest({ action = "Drop" })
	end
end
function Client.Attack(self: Client, inputTime: number?): ()
	local now = workspace:GetServerTimeNow()
	if self.worldInteraction and self.worldInteraction:IsInputBlocked() then return end
	if self.paintId or self:Held() or now - self.lastAttack < Config.AttackCooldown then return end
	local character = player.Character
	local weapon = character and character:FindFirstChild("Club")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not weapon or not weapon:IsA("Tool") or not humanoid or humanoid.Health <= 0 then return end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	self.lastAttack = now
	self.characterView:Swing(player.UserId, now)
	if Sound and root then
		Sound.Play("AttackSwing", root.Position)
	end
	local best: Types.ItemView? = nil
	local distance = Config.AttackRange
	for _, item in self.items do
		if item.kind == "Body" and item.location == "Street" and item.hits < Config.StunHits and item.model and item.model.PrimaryPart then
			local delta = item.model.PrimaryPart.Position - root.Position
			if delta.Magnitude < distance and (delta.Magnitude < 0.1 or root.CFrame.LookVector:Dot(delta.Unit) > -0.1) then
				distance = delta.Magnitude
				best = item
			end
		end
	end
	local combo = if self.attackTarget and now < self.comboEnds then self.items[self.attackTarget] else nil
	if combo and combo.kind == "Body" and combo.hits < Config.StunHits and combo.location == "Street" and combo.model and combo.model.PrimaryPart then
		local delta = combo.model.PrimaryPart.Position - root.Position
		if delta.Magnitude < Config.AttackRange and (delta.Magnitude < 0.1 or root.CFrame.LookVector:Dot(delta.Unit) > -0.1) then best = combo end
	end
	self.attackTarget = if best then best.id else nil
	self.comboEnds = now + Config.AttackComboSeconds
	self.attackSequence += 1
	local started=inputTime or now
	HitRules.Begin(self.hitState,self.attackSequence,if best then best.id else nil,started+Config.AttackWindup,now+Config.HitPredictionLifetime)
	if best then self.bodies:TrackPrediction(best.id,self.attackSequence,self.hitState.pending[self.attackSequence]) end
	Net.FireRequest({ action = "Attack", target = if best then best.id else nil, version = if best then best.version else nil, attackSequence=self.attackSequence })
end
local function PaintControl(anchor: Vector2, pointer: Vector2, viewport: Vector2): Vector2
	return Rotation.Velocity(pointer - anchor, viewport)
end
-- 松手后笔尖是指针原点。系统光标不能搬到喷口，之后只累加硬件鼠标位移。
local function PointerFromHardware(self: Client, hardware: Vector2): Vector2
	local origin, hardwareOrigin = self.pointerOrigin, self.hardwareOrigin
	if origin and hardwareOrigin then
		return origin + (hardware - hardwareOrigin)
	end
	return hardware
end
local function HardwareFromPointer(self: Client): Vector2?
	local pointer = self.pointer
	if not pointer then
		return nil
	end
	local origin, hardwareOrigin = self.pointerOrigin, self.hardwareOrigin
	if origin and hardwareOrigin then
		return hardwareOrigin + (pointer - origin)
	end
	return pointer
end
local function SnapPointerToBrush(self: Client, hardware: Vector2): ()
	local frame = self.brushFrame
	local tip = if frame then frame.tip else self.pointer
	if not tip then
		return
	end
	self.pointer = tip
	self.pointerOrigin = tip
	self.hardwareOrigin = hardware
end
-- 输入事件里的坐标比 GetMouseLocation 少一个顶栏高度。喷口使用前者。
local ignoreMouseMove = false
local catchHardwareOrigin = false
local function ReadMouse(): Vector2?
	local ok, value = pcall(function(): Vector2
		return UserInputService:GetMouseLocation()
	end)
	if ok and typeof(value) == "Vector2" then
		return value
	end
	return nil
end
local function ReadInset(): Vector2
	local ok, value = pcall(function(): Vector2
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(value) == "Vector2" then
		return value
	end
	return Vector2.zero
end
local function HardwareNow(fallback: Vector2): Vector2
	local mouse = ReadMouse()
	if not mouse then
		return fallback
	end
	return mouse - ReadInset()
end
local function FormatPoint(point: Vector2?): string
	if not point then
		return "nil"
	end
	return string.format("(%.1f,%.1f)", point.X, point.Y)
end
-- 把系统光标移到喷口。成功时后续输入会从笔尖发出，不再保留拖拽偏移。
local function WarpMouseToTip(tip: Vector2): boolean
	local target = tip + ReadInset()
	local before = ReadMouse()
	ignoreMouseMove = true
	local sent = pcall(function()
		local virtual = UserInputService:CreateVirtualInput()
		if virtual == nil then
			error("VirtualInput unavailable")
		end
		(virtual :: any):SendMousePosition(target)
	end)
	local after = ReadMouse()
	local arrived = sent and after ~= nil and (after - target).Magnitude <= 8
	--print(string.format(
	--	"[画笔重置] 喷口=%s 目标鼠标=%s 移动前=%s 移动后=%s 落到喷口=%s",
	--	FormatPoint(tip),
	--	FormatPoint(target),
	--	FormatPoint(before),
	--	FormatPoint(after),
	--	tostring(arrived)
	--))
	if arrived then
		return true
	end
	ignoreMouseMove = false
	return false
end

-- 在入队上报前按客户端本地已覆盖集合去重，避免重复转圈导致数千重复点堵死进度队列。
local function FilterNewCoverageSamples(self: Client, model: Model, samples: { Types.Sample }): { Types.Sample }
	if typeof(model) ~= "Instance" then
		return samples
	end
	local covered: { [string]: boolean } = self.localCovered or {}
	self.localCovered = covered
	local filtered: { Types.Sample } = {}
	local previous: Types.Sample? = nil
	local lastQueued: Types.Sample? = nil
	for _, sample in samples do
		if sample.breakBefore then
			previous = nil
		end
		local part = model:FindFirstChild(sample.part)
		if not part or not part:IsA("BasePart") or not Surface.IsBody(part) or not Surface.IsPaintSample(part, sample) then
			table.insert(filtered, sample)
			previous = nil
			lastQueued = sample
			continue
		end
		local curved = Curve.IsPart(part)
		local ink = sample
		if curved and sample.packedInk then
			ink = table.clone(sample)
			ink.u, ink.v = Curve.InkCenter(sample.u, sample.v)
		end
		local _, added = Surface.Stamp(part, ink, covered)
		if previous and not previous.packedInk and not sample.packedInk and previous.part == sample.part and previous.face == sample.face then
			if curved then
				local start = Curve.Point(part, previous)
				local finish = Curve.Point(part, sample)
				local distance = (finish - start).Magnitude
				if distance < Config.BrushRadius * 3 then
					local steps = math.ceil(distance / (Config.BrushRadius * 0.5))
					for index = 1, steps - 1 do
						local intermediate = Curve.ProjectLocal(part, start:Lerp(finish, index / steps))
						local _, segArea = Surface.Stamp(part, intermediate, covered)
						added += segArea
					end
				end
			else
				local dimensions = Surface.Dimensions(part.Size, sample.face)
				local distance = Vector2.new((sample.u - previous.u) * dimensions.X, (sample.v - previous.v) * dimensions.Y).Magnitude
				if distance < Config.BrushRadius * 3 then
					local steps = math.ceil(distance / (Config.BrushRadius * 0.5))
					for index = 1, steps - 1 do
						local alpha = index / steps
						local _, segArea = Surface.Stamp(part, {
							part = sample.part,
							face = sample.face,
							u = previous.u + (sample.u - previous.u) * alpha,
							v = previous.v + (sample.v - previous.v) * alpha,
						}, covered)
						added += segArea
					end
				end
			end
		end
		if added > 0 then
			if previous and not sample.breakBefore and previous.part == sample.part and previous.face == sample.face and previous ~= lastQueued then
				local anchor = table.clone(previous)
				anchor.breakBefore = true
				table.insert(filtered, anchor)
			end
			table.insert(filtered, sample)
			lastQueued = sample
		end
		previous = sample
	end
	return filtered
end

function Client.SamplePaint(self: Client, now: number): Vector2?
	local id, session, pointer = self.paintId, self.session, self.pointer
	local camera = workspace.CurrentCamera
	local display = self.presentation
	local model, geometry = display.model, display.geometry
	if not id or not session or not pointer or not camera or not self.paintCamera.ready
		or not model or not geometry or self.bodies:GetPaintModel(id) ~= model then
		self.brushFrame = nil
		return nil
	end

	local previous = self.brushFrame
	local basePose = TablePose()
	local rotationAxis: Vector3? = nil
	if self.rotationAnchor then
		local target = PaintControl(self.rotationAnchor, pointer, camera.ViewportSize)
		if target.Magnitude > 1e-6 then
			local localAxis = Vector3.new(target.Y, target.X, 0) / target.Magnitude
			local worldAxis = basePose:VectorToWorldSpace(localAxis)
			if worldAxis.Magnitude > 1e-6 then
				rotationAxis = worldAxis.Unit
			end
		end
	end
	if previous and previous.orientation == display.orientation and (previous.pointer - pointer).Magnitude < 1e-4 then
		return previous.tip
	end
	local resolver = PaintBrush.Resolver(model, camera, basePose, geometry, display.orientation)
	local samples, frame = PaintBrush.SamplePath(previous, pointer, display.orientation, geometry.radius, resolver, camera.ViewportSize, rotationAxis)
	self.brushFrame = frame
	if #samples > 0 then
		self.view:DrawLocal(id,session,self.visualGesture,samples)
		local queued = FilterNewCoverageSamples(self, model, samples)
		for _, sample in queued do table.insert(self.paintSamples,sample) end
		if now - self.lastPaintSound >= 0.12 then
			self.lastPaintSound = now
			Sound.Play("PaintStroke")
		end
	end
	return frame.tip
end

function Client.Paint(self: Client, now: number): Vector2?
	local session = self.session
	if not self.paintId or not session then return nil end
	local tip = if self.drawing then self:SamplePaint(now) else self.pointer
	local moved = Rotation.Distance(self.sentOrientation, self.orientation) > 0.001

	local pending = self.pendingCoverage
	if pending then
		-- 有间隔限制的服务端可能因包挤在一起而拒收；保留原序号并按较短重试间隔快速恢复。
		if now-self.lastPaint >= Config.PaintCoverageRetrySeconds then
			pending.orientation = self.orientation
			Net.FireRequest(pending)
			self.lastPaint = now
		end
	elseif now-self.lastPaint >= Config.PaintBatchInterval and (#self.paintSamples>0 or moved) then
		local count = math.min(#self.paintSamples,Config.PaintCoverageBatchSize)
		local samples = table.move(self.paintSamples,1,count,1,{})
		self.paintSamples = table.move(self.paintSamples,count+1,#self.paintSamples,1,{})
		self.lastPaint = now
		self.paintSequence += 1
		local request: Types.Request = {action="Paint",session=session,sequence=self.paintSequence,samples=samples,orientation=self.orientation}
		self.pendingCoverage = request
		self.sentOrientation = self.orientation
		Net.FireRequest(request)
	end
	self.finishPaint = not self.drawing and (#self.paintSamples>0 or self.pendingCoverage~=nil or moved)
	return tip
end

function Client.StepPaintRotation(self: Client, dt: number): ()
	local camera = workspace.CurrentCamera
	local anchor, pointer = self.rotationAnchor, self.pointer
	if not self.drawing or not self.paintCamera.ready or not camera or not anchor or not pointer then
		self.angularSpeed = 0
		return
	end
	local target = PaintControl(anchor, pointer, camera.ViewportSize)
	self.orientation, self.angularSpeed = Rotation.Step(self.orientation, self.angularSpeed, target, dt)
end

function Client.Update(self: Client, dt: number): ()
	local now = os.clock()
	if self.worldInteraction then self.worldInteraction:Refresh() end
	local missingModel = false
	for _, item in self.items do
		if not item.model or not item.model.Parent then missingModel = true; break end
	end
	if (not self.synced or missingModel) and now - self.lastSync > 3 and player:GetAttribute("GameReady") == true then
		Net.FireRequest({ action = "Sync" })
		self.lastSync = now
	end
	if now > self.messageEnds then
		self:Text("NoticeText", nil)
	end
	local curved=self.view.curved
	if self.paintId and curved and curved.failed and not curved.textures[self.paintId] then
		self:RequestPaintEnd()
		self:Text("NoticeText", {textId = "PaintSurfaceUnavailable"})
		self.messageEnds=now+5
	end
	local snapshot = self.snapshot
	if self.paintId then
		local item = self.items[self.paintId]
		if item and item.model then self.ui:SetProgress(item.progress) end
		local point = self:Paint(now)
		self.ui:UpdatePointer(point, self.drawing)
		ignoreMouseMove = false
		if catchHardwareOrigin and not self.drawing and self.hardwareOrigin then
			catchHardwareOrigin = false
			self.hardwareOrigin = HardwareNow(self.hardwareOrigin)
		end
	end
	-- 姿态和当前帧采样完成后再绘制，每帧统一消耗一次栅格化预算。
	self.view:Update(self.paintId)
	if self.paintId then
		self.visualUpload:Update(self.view:Drain(self.paintId),now,workspace:GetServerTimeNow(),self.visualClosing or not self.drawing,nil,not self.finishPaint and self.view:IsReady(self.paintId))
		if self.view.budgetReached then
			self:Text("NoticeText", {textId = "PaintSegmentLimit"})
			self.messageEnds=now+3
			self.view.budgetReached=false
		end
	end
	if now - self.lastHint < 0.1 then
		return
	end
	self.lastHint = now
	self:Text("CoinsText", {textId = "Coins", args = {tostring(player:GetAttribute("Coins") or 0)}})
	local carried = self:Carried()
	local held = self:Held()
	local focused = if self.attackTarget then self.items[self.attackTarget] else nil
	local head = focused and self.bodies:GetVisualPart(focused.id,"Head")
	UIManager.GetTargetGuiManager():Refresh({
		adornee = if head and head:IsA("BasePart") then head else nil,
		visible = not self.paintId and not held and focused ~= nil and focused.location == "Street" and focused.hits < Config.StunHits,
		hits = if focused then focused.hits else 0,
		touch = UserInputService.TouchEnabled,
	})
	local carryText: GameTexts.Description = { textId = "HandsEmpty" }
	if #carried > 1 then
		carryText = { textId = "CarryingBodies", args = { tostring(#carried) } }
	elseif carried[1] then
		carryText = { textId = if carried[1].stage == "Painted" then "CarryingRuneBody" else "CarryingBody" }
	elseif held then
		carryText = { textId = if held.stage == "Painted" then "CarryingRuneBody" else "CarryingBody" }
	end
	self:Text("CarryText", carryText)
	if snapshot then
		local stock: GameTexts.Description = {textId = "Stock", args = {tostring(snapshot.pool), tostring(Config.PoolCapacity), tostring(snapshot.shelf), tostring(Config.ShelfCapacity)}}
		local soonest: number? = nil
		for _, item in self.items do
			if item.kind == "Body" and item.location == "Altar" and item.convertEnds and item.convertEnds > workspace:GetServerTimeNow() then
				soonest = if soonest and soonest < item.convertEnds then soonest else item.convertEnds
			end
		end
		if snapshot.altarId or soonest then
			local seconds = if soonest then math.max(0, math.ceil(soonest - workspace:GetServerTimeNow())) else 0
			stock = if seconds > 0 then {textId = "AltarCountdown", args = {tostring(seconds), tostring(snapshot.shelf), tostring(Config.ShelfCapacity)}} else {textId = "AltarShelfFull"}
		end
		self:Text("StockText", stock)
	end
	self.ui:Refresh({painting=self.paintId~=nil,hasTarget=false,windowOpen=UIManager.HasShowingWindow()})
	if self.paintId then
		self:Text("HintText", {textId = "Painting"})
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	self.target = nil
	self.nearTable = false
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	-- 最近目标仅用于 HUD 原因提示；实际请求由对应原生提示绑定目标。
	local best = Config.InteractionRange
	for name, position in positions do
		local distance = (hrp.Position - position).Magnitude
		if name == "Table" and distance < Config.InteractionRange then
			self.nearTable = true
		end
		if distance < best then
			best = distance
			self.target = name
		end
	end
	local carryingBody = #carried > 0
	if not held or carryingBody then
		for _, item in self.items do
			local model = item.model
			local rootPart = model and model.PrimaryPart
			if rootPart and (item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits)) and (item.kind == "Body" or not carryingBody) then
				local distance = (hrp.Position - rootPart.Position).Magnitude
				if distance < best then
					best = distance
					self.target = item.id
				end
			end
		end
	end
	local target = self.target
	local potions = self:Potions()
	local previousPotions = self.lastPotionCount
	if previousPotions ~= nil and potions.stored > previousPotions then
		Sound.Play("PotionPickup", positions.Shelf)
	end
	self.lastPotionCount = potions.stored
	self:Text("HintText", if target then Hints.Action(target, snapshot, held, player.UserId, potions, carried) else Hints.Next(snapshot, held, potions, carried));
	self.ui:Refresh({painting=false,hasTarget=target~=nil,windowOpen=UIManager.HasShowingWindow()})
end
function Client.OnInput(self: Client, input: InputObject, processed: boolean): ()
	if self.visualClosing then return end
	if processed then
		return
	end
	if self.paintId and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		if self.drawing then return end
		self.drawing = true
		local hardware = Vector2.new(input.Position.X, input.Position.Y)
		if input.UserInputType == Enum.UserInputType.Touch then
			self.pointer = hardware
			self.touch = input
		else
			self.pointer = PointerFromHardware(self, hardware)
		end
		self.rotationAnchor = self.pointer
		self.brushFrame = nil
		self.visualGesture += 1
		self.finishPaint = false
		self:SamplePaint(os.clock())
	elseif input.KeyCode == Enum.KeyCode.Q then
		self:Drop()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- 先记录输入时间，原生提示仲裁占用的帧计入本地前摇。
		local inputTime=workspace:GetServerTimeNow()
		self.scope:Spawn(function(): ()
			RunService.Heartbeat:Wait()
			if self.initialized then self:Attack(inputTime) end
		end)
	end
end
function Client.OnMove(self: Client, input: InputObject): ()
	if self.visualClosing then return end
	if input ~= self.touch and (self.touch ~= nil or input.UserInputType ~= Enum.UserInputType.MouseMovement) then
		return
	end
	if ignoreMouseMove and input ~= self.touch then
		return
	end
	local hardware = Vector2.new(input.Position.X, input.Position.Y)
	self.pointer = if input == self.touch then hardware else PointerFromHardware(self, hardware)
end
function Client.OnRelease(self: Client, input: InputObject): ()
	if self.visualClosing then return end
	if input == self.touch or (not self.touch and input.UserInputType == Enum.UserInputType.MouseButton1) then
		local hardware = Vector2.new(input.Position.X, input.Position.Y)
		local mouseRelease = input ~= self.touch
		if self.drawing then
			local sampled = if mouseRelease then PointerFromHardware(self, hardware) else hardware
			self.pointer = sampled
			self:SamplePaint(os.clock())
			self.finishPaint = true
			if mouseRelease then
				SnapPointerToBrush(self, hardware)
				local tip = self.pointer
				if tip and WarpMouseToTip(tip) then
					self.pointer = tip
					self.pointerOrigin = tip
					self.hardwareOrigin = tip
				elseif tip then
					self.hardwareOrigin = HardwareNow(hardware)
					catchHardwareOrigin = true
				end
			end
		end
		self.drawing = false
		self.angularSpeed = 0
		self.rotationAnchor = nil
		self.brushFrame = nil
		if self.touch then self.pointer = nil end
		self.touch = nil
	end
end
function Client.ResetPaintView(self: Client): ()
	if self.visualClosing or not self.paintId then return end
	self.drawing = false
	self.finishPaint = #self.paintSamples > 0
	self.brushFrame, self.touch = nil, nil
	self.rotationAnchor = nil
	self.angularSpeed = 0
	self.orientation,self.sentOrientation=CFrame.identity,CFrame.identity
	Net.FireRequest({action="ResetView",session=self.session})
end
function Client.UpdateAltar(self: Client, now: number): ()
	local active: { Types.ItemView } = {}
	for _, item in self.items do
		if item.kind == "Body" and item.location == "Altar" then
			table.insert(active, item)
		end
	end
	if #active == 0 then
		if self.altarLoopSound then
			self.altarLoopSound:Stop()
			self.altarLoopSound = nil
			if self.altarBodyId then
				Sound.Play("AltarComplete", positions.Altar)
			end
		end
		for id, view in self.altarViews do
			self.view:ClearSacrifice(id)
			view:Clear()
			self.altarViews[id] = nil
		end
		self.altarBodyId = nil
		self.altarView:Clear()
		return
	end
	if not self.altarLoopSound then
		self.altarLoopSound = Sound.Play("AltarLoop", positions.Altar)
	end
	local seen: { [string]: boolean } = {}
	local shelfFull = self.snapshot ~= nil and self.snapshot.shelf >= Config.ShelfCapacity
	for _, item in active do
		seen[item.id] = true
		local model = self.bodies:GetAltarModel(item.id)
		if not model then
			self.view:ClearSacrifice(item.id)
			local flying = self.altarViews[item.id]
			if flying then flying:Clear(); self.altarViews[item.id] = nil end
			continue
		end
		if item.flyEnds and now < item.flyEnds then
			self.bodies:Fly(item.id, now)
			self.view:ClearSacrifice(item.id)
			local flying = self.altarViews[item.id]
			if flying then flying:Clear(); self.altarViews[item.id] = nil end
			continue
		end
		self.bodies:Fly(item.id, now)
		local view = self.altarViews[item.id]
		if not view then
			view = AltarSacrifice.new()
			self.altarViews[item.id] = view
		end
		local sample = view:Update(item.id, model, now, item.convertEnds or now, shelfFull)
		if sample then
			self.view:SetSacrifice(item.id, sample.brightness, sample.fade)
		end
	end
	for id, view in self.altarViews do
		if not seen[id] then
			self.view:ClearSacrifice(id)
			view:Clear()
			self.altarViews[id] = nil
		end
	end
	self.altarBodyId = active[1].id
end
function Client.Init(self: Client, gui: ScreenGui): ()
	if self.initialized then
		return
	end
	self.initialized = true
	if not self.scope.alive then self.scope=Lifecycle.new() end
	self.ui:Init(gui)
	self.worldInteraction = WorldInteractionManager.new(interactionAnchors, function(): WorldInteractionManager.State
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local modal = gui:FindFirstChild("ModalButton") :: GuiButton?
		return {snapshot=self.snapshot, items=self.items, held=self:Held(), carried=self:Carried(), potions=self:Potions(), enabled=self.initialized and self.synced and not self.paintId and humanoid ~= nil and humanoid.Health > 0 and not (modal and modal.Visible)}
	end)
	UIManager.GetTargetGuiManager():Init()
	self.ui:BindActions({
		attack=function(): () self:Attack() end,
		exitPaint=function(): () self:RequestPaintEnd() end,
		resetView=function(): () self:ResetPaintView() end,
	})
	self.scope:Connect(Net.ConnectNotify(function(notice: Types.Notice): ()
		self:OnNotice(notice)
	end))
	self.scope:Connect(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean): ()
		self:OnInput(input, processed)
	end))
	self.scope:Connect(UserInputService.InputChanged:Connect(function(input: InputObject): ()
		self:OnMove(input)
	end))
	self.scope:Connect(UserInputService.InputEnded:Connect(function(input: InputObject): ()
		self:OnRelease(input)
	end))
	local function OnPaintInputInterrupted(): ()
		if not self.drawing then return end
		if self.touch then
			self.pointer = nil
		else
			local hardware = HardwareFromPointer(self)
			if hardware then
				SnapPointerToBrush(self, hardware)
			end
		end
		self.drawing, self.finishPaint, self.touch = false, true, nil
		self.brushFrame = nil
		self.rotationAnchor = nil
		self.angularSpeed = 0
	end
	self.scope:Connect(UserInputService.WindowFocusReleased:Connect(OnPaintInputInterrupted))
	self.scope:Connect(GuiService.MenuOpened:Connect(OnPaintInputInterrupted))
	self.scope:Connect(player.CharacterAdded:Connect(function(): ()
		self:CancelHitFeedback()
		self:ExitView()
		self.paintCamera:Exit(true)
	end))
	local animationPhase = RunService.PreAnimation:Connect(function(): ()
		self.bodies:Restore()
		self.characterView:Restore()
		self.hitView:Restore()
	end)
	self.scope:Connect(animationPhase)
	local simulationPhase = RunService.PreSimulation:Connect(function(dt): ()
		Tuning.Commit()
		self.characterView:Apply(workspace:GetServerTimeNow())
		local now=workspace:GetServerTimeNow()
		self:UpdateHits(now)
		self.bodies:Step(now,dt,self.paintId~=nil)
		self:UpdateAltar(now)
		if self.presentation.model then
			if self.paintId then
				self:StepPaintRotation(dt)
				self.presentation.targetOrientation=self.orientation
			end
			self.presentation:Update(TablePose(),math.min(dt,0.1),self.paintId ~= nil)
		end
	end)
	self.scope:Connect(simulationPhase)
	self.bodies.phases={animationPhase,simulationPhase}
	self.bodies:OpenStudioDebug()
	RunService:BindToRenderStep("DemonShopHitCameraRestore",Enum.RenderPriority.Camera.Value-1,function(): ()
		self.hitView:RestoreCamera()
	end)
	RunService:BindToRenderStep("DemonShopHitCamera",Enum.RenderPriority.Camera.Value+1,function(): ()
		local now=workspace:GetServerTimeNow()
		local character=player.Character
		local humanoid=character and character:FindFirstChildOfClass("Humanoid")
		local enabled=not self.paintId and not self:Held() and humanoid~=nil and humanoid.Health>0 and character~=nil and character:FindFirstChild("Club")~=nil
		self.hitView:UpdateCamera(now,enabled)
		self.hitView:UpdateEffects(now)
	end)
	self.scope:Connect(RunService.RenderStepped:Connect(function(dt): ()
		self.paintCamera:StepToss(workspace:GetServerTimeNow(), dt)
		self.potionShelf:Step(os.clock())
		self:Update(dt)
	end))
end
function Client.Destroy(self: Client): ()
	RunService:UnbindFromRenderStep("DemonShopHitCameraRestore")
	RunService:UnbindFromRenderStep("DemonShopHitCamera")
	self.hitView:Clear()
	self.hitState=HitRules.New()
	self:ExitView()
	self.paintCamera:Destroy()
	self.ui:UnbindActions()
	UIManager.GetTargetGuiManager():Destroy()
	if self.worldInteraction then self.worldInteraction:Destroy(); self.worldInteraction = nil end
	self.scope:Destroy()
	self.potionShelf:Destroy()
	if self.altarBodyId then self.view:ClearSacrifice(self.altarBodyId); self.altarBodyId = nil end
	if self.altarLoopSound then self.altarLoopSound:Stop(); self.altarLoopSound = nil end
	for id, view in self.altarViews do
		self.view:ClearSacrifice(id)
		view:Clear()
		self.altarViews[id] = nil
	end
	self.altarView:Clear()
	self.bodies:Destroy()
	self.view:Destroy()
	self.presentation:Clear()
	self.characterView:Destroy()
	self.initialized = false
end
return Client
