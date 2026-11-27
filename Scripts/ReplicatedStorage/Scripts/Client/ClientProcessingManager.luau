-- 加工客户端：共享状态展示、键鼠触屏交互、工作台俯视镜头及拖画
--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberExtension = require(ReplicatedStorage.Core.Scripts.Shared.NumberExtension)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local GameData = require(Shared:WaitForChild("GameData"))
local Types = require(Shared:WaitForChild("GameTypes"))
local GameTexts = require(Shared.GameTexts)
local Sound = require(Shared:WaitForChild("GameSoundTool"))
local UIManager = require(script.Parent.UIManager)
local GameScreenGuiManager = require(script.Parent.UIManager.GameScreenGuiManager)
local Hints = require(Shared:WaitForChild("Hints"))
local WorldInteractionRules = require(Shared.WorldInteractionRules)
local Rotation = require(Shared.PaintRotation)
local BodyPlacementMarkers = require(Shared:WaitForChild("BodyPlacementMarkers"))
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
local FixedCamera = require(Shared:WaitForChild("FixedCamera"))
local PaintCamera = require(script.Parent.PaintCamera)
local PaintBrush = require(script.Parent.PaintBrushContact)
local VisualUpload = require(script.Parent.VisualUpload)
local WorldInteractionManager = require(script.Parent.WorldInteractionManager)
local ManualThrow = require(script.Parent.ManualThrowController)
local ThrowArc = require(Shared.ThrowArc)
local AltarFurnace = require(script.Parent.AltarFurnaceView)
local PotionShelf = require(script.Parent.PotionShelfView)
local AutomationLineView = require(script.Parent.AutomationLineView)
local AutomationRules = require(Shared.AutomationRules)
local ProcessingText = require(script.Parent.ProcessingTextTool)
local PersonalShop = require(script.Parent.PersonalShop)
local PersonalRules = require(Shared.PersonalUpgradeRules)
local TouchJumpController = require(script.Parent.TouchJumpController)
local Client = {}
Client.__index = Client
local player = Players.LocalPlayer
local function PlayWeaponSlashSound(tier: GameData.WeaponConfig, position: Vector3): ()
	if not Sound then return end
	local template = tier.slashSoundTemplate
	if template and Sound.PlayLocal then
		Sound.PlayLocal(template, position)
		return
	end
	if Sound.Play then
		Sound.Play("AttackSwing", position)
	end
end
export type Client = typeof(setmetatable(
	{} :: {
		scope: Lifecycle.Lifecycle,
		worldInteraction: WorldInteractionManager.Manager?,
		closePersonalShop: (() -> ())?,
		ui: GameScreenGuiManager.Manager,
		padTexts: ProcessingText.Controller,
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
		altarFx: AltarFurnace.View,
		altarLoopSound: Sound?,
		potionShelf: PotionShelf.View,
		autoPotionShelf: PotionShelf.View?,
		automationView: AutomationLineView.View?,
		lastHeldId: string?,
		lastHeldKind: string?,
		lastPoolCount: number?,
		lastChuteCount: number?,
		lastPotionCount: number?,
		lastPaintSound: number,
		snapshot: Types.Snapshot?,
		items: { [string]: Types.ItemView },
		paintId: string?,
		paintBatch: { string }?,
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
		localProgress: number,
		localArea: number,
		localTotalArea: number,
		localFrontArea: number,
		localBackArea: number,
		localFrontTotalArea: number,
		localBackTotalArea: number,
		visualGesture: number,
		orientation: CFrame,
		sentOrientation: CFrame,
		paintFlipped: boolean,
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
		hiddenPlayerParts: { [Instance]: boolean }?,
		hidePlayersScope: Lifecycle.Lifecycle?,
		ignoreMouseMove: boolean,
		catchHardwareOrigin: boolean,
		completeFlash: { id: string, started: number, batch: { string }? }?,
		flipFlash: { id: string, started: number, batch: { string }? }?,
		initialized: boolean,
		closeCameraHideWatch: (() -> ())?,
		throw: ManualThrow.Controller?,
		touchJump: TouchJumpController.Controller?,
	},
	Client
))
local district = workspace:WaitForChild("NeonContractDistrict")
FixedCamera.HideAll(district)
local tableModel = district:WaitForChild("RuneBodyTable")
local tablePlacement = tableModel:WaitForChild("BodyPlacementAnchor") :: BasePart
local tableInteract = tableModel:WaitForChild("TransferStartAnchor") :: BasePart
local tableSlotSpecs = BodyPlacementMarkers.ReadSlotSpecs(tableModel, tablePlacement)
BodyPlacementMarkers.HideAll(tableModel)
local function Anchor(station: string, name: string): BasePart
	return district:WaitForChild(station):WaitForChild(name) :: BasePart
end
local submitAnchor = district:WaitForChild("SummoningSubmitAnchor") :: BasePart
local furnaceMouth = Anchor("SoulConversionAltar", "BodyRest"):WaitForChild("FurnaceMouth") :: Attachment
local shelfSign = Anchor("SoulCrystalDisplay", "StationPlaque")
local interactionAnchors: {[string]: BasePart} = {
	Pool = Anchor("SoulHoldingPool", "PickupPointAnchor"),
	Table = tableInteract,
	Altar = Anchor("SoulConversionAltar", "BodyArrivalAnchor"),
	Shelf = Anchor("SoulCrystalDisplay", "StockPickupAnchor"),
	Sigil = submitAnchor,
}
local poolFloor = district:WaitForChild("SoulHoldingPool"):WaitForChild("PoolFloor") :: BasePart
local positions: { [string]: Vector3 } = {
	Pool = Anchor("SoulHoldingPool", "PickupPointAnchor").Position,
	Table = tableInteract.Position,
	Altar = Anchor("SoulConversionAltar", "BodyArrivalAnchor").Position,
	Shelf = Anchor("SoulCrystalDisplay", "StockPickupAnchor").Position,
	Sigil = submitAnchor.Position,
}
local function OptionalPart(root: Instance?, ...: string): BasePart?
	local current: Instance? = root
	for i = 1, select("#", ...) do
		if not current then
			return nil
		end
		local name = select(i, ...)
		current = current:FindFirstChild(name)
	end
	return if current and current:IsA("BasePart") then current else nil
end
local autoLine = district:FindFirstChild("AutomationLine")
local chutePrompt = OptionalPart(autoLine, "ChutePromptAnchor")
local chuteDropZone = OptionalPart(autoLine, "FastChuteLanding", "DropZone")
local autoOutputPrompt = OptionalPart(autoLine, "AutoRuneMachine", "OutputPromptAnchor")
local autoShelfPickup = OptionalPart(autoLine, "AutoSmelterMachine", "AutoPotionRack", "AutoShelfPickupAnchor")
local autoRuneMachine = if autoLine then autoLine:FindFirstChild("AutoRuneMachine") else nil
local autoSmelterMachine = if autoLine then autoLine:FindFirstChild("AutoSmelterMachine") else nil
local padsFolder = if autoLine then autoLine:FindFirstChild("UnlockPads") else nil
if chutePrompt then
	interactionAnchors.Chute = chutePrompt
	positions.Chute = chutePrompt.Position
end
if autoOutputPrompt then
	interactionAnchors.AutoOutput = autoOutputPrompt
	positions.AutoOutput = autoOutputPrompt.Position
end
if autoShelfPickup then
	interactionAnchors.AutoShelf = autoShelfPickup
	positions.AutoShelf = autoShelfPickup.Position
end
local function TablePose(slot: number?): CFrame
	local index = slot or 1
	local spec = tableSlotSpecs[index]
	if spec then
		return spec.pose
	end
	return tableSlotSpecs[1].pose + (Rotation.BatchOffset(index) or Vector3.zero)
end
local function ActivePaintTarget(): number
	local flatTarget: number? = (Config :: any).PaintFlatTarget
	return if Config.PaintRotationEnabled then Config.PaintTarget else (flatTarget or Config.PaintTarget)
end
local function SyncLocalProgressFromServer(self: Client, progress: number, flipped: boolean): ()
	local clamped = math.clamp(progress, 0, 1)
	if not Config.PaintRotationEnabled and (self.localFrontTotalArea or 0) > 0 and (self.localBackTotalArea or 0) > 0 then
		local ratio = ActivePaintTarget()
		local frontTarget = math.max(self.localFrontTotalArea * ratio, 0.001)
		local backTarget = math.max(self.localBackTotalArea * ratio, 0.001)
		local flipAt = math.clamp(Config.PaintAutoFlipProgress, 0.05, 0.95)
		if clamped >= 1 then
			self.localProgress = 1
			self.localFrontArea = math.max(self.localFrontArea or 0, frontTarget)
			self.localBackArea = math.max(self.localBackArea or 0, backTarget)
		else
			if clamped > (self.localProgress or 0) then
				self.localProgress = clamped
			end
			if flipped or clamped >= flipAt then
				self.localFrontArea = math.max(self.localFrontArea or 0, frontTarget)
				local backRatio = math.clamp((clamped - flipAt) / (1 - flipAt), 0, 1)
				self.localBackArea = math.max(self.localBackArea or 0, backRatio * backTarget)
			else
				local frontRatio = math.clamp(clamped / flipAt, 0, 1)
				self.localFrontArea = math.max(self.localFrontArea or 0, frontRatio * frontTarget)
			end
		end
		self.localArea = (self.localFrontArea or 0) + (self.localBackArea or 0)
		return
	end
	local targetArea = math.max((self.localTotalArea or 0) * ActivePaintTarget(), 0.001)
	if clamped >= 1 then
		self.localProgress = 1
		self.localArea = math.max(self.localArea or 0, targetArea)
	elseif clamped > (self.localProgress or 0) then
		self.localProgress = clamped
		self.localArea = math.max(self.localArea or 0, clamped * targetArea)
	end
end
function Client.new(): Client
	local tableView, hitView, paint = Presentation.new(), HitPresentation.new(), PaintView.new()
	hitView:PrepareWeaponEffects()
	local bodies = WhiteBodies.new(tableView, hitView, function(id, model)
		if model then paint:Bind(id,model) else paint:Detach(id) end
	end)
	return setmetatable(
		{
			scope = Lifecycle.new(),
			ui = UIManager.GetGameScreenGuiManager(),
			padTexts = ProcessingText.new(),
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
			altarFx = AltarFurnace.new(furnaceMouth, shelfSign),
			altarLoopSound = nil,
			potionShelf = PotionShelf.new(positions.Shelf),
			autoPotionShelf = PotionShelf.new(positions.AutoShelf or Vector3.new(10.0, 2.0, -27.2), "AutoPotionShelfPresentation"),
			automationView = AutomationLineView.new(district, paint),
			lastHeldId = nil,
			lastHeldKind = nil,
			lastPoolCount = nil,
			lastChuteCount = nil,
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
			localProgress = 0,
			localArea = 0,
			localTotalArea = 0,
			localFrontArea = 0,
			localBackArea = 0,
			localFrontTotalArea = 0,
			localBackTotalArea = 0,
			visualGesture = 0,
			orientation = CFrame.identity,
			sentOrientation = CFrame.identity,
			paintFlipped = false,
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
			hiddenPlayerParts = {},
			hidePlayersScope = nil,
			ignoreMouseMove = false,
			catchHardwareOrigin = false,
			completeFlash = nil,
			flipFlash = nil,
			closeCameraHideWatch = nil,
			initialized = false,
			throw = nil,
			touchJump = nil,
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
	table.sort(list, function(a: Types.ItemView, b: Types.ItemView): boolean
		local left, right = a.carryOrder or 0, b.carryOrder or 0
		if left ~= right then
			return left > right
		end
		return a.id < b.id
	end)
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
function Client.ShoulderOccupied(self: Client): boolean
	for _, item in self.items do
		if item.holder == player.UserId and item.kind ~= "Body" then
			return true
		end
	end
	return false
end
local function StackCount(tool: Instance): number
	local count = tool:GetAttribute("StackCount")
	if typeof(count) == "number" and count > 0 then
		return count
	end
	return 1
end
function Client.Potions(self: Client): Hints.Potions
	local stored = 0
	local equipped = false
	local character = player.Character
	local backpack: Instance? = if (player :: any).FindFirstChildOfClass
		then player:FindFirstChildOfClass("Backpack")
		else nil
	local seen: { [Instance]: boolean } = {}
	local function Scan(container: Instance?, isEquipped: boolean): ()
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if not seen[child] and child:IsA("Tool") and child.Name == "Potion" then
				seen[child] = true
				stored += StackCount(child)
				if isEquipped or (character ~= nil and child.Parent == character) then
					equipped = true
				end
			end
		end
	end
	Scan(backpack, false)
	Scan(character, true)
	local sellLevel = if character then character:GetAttribute("Upgrade_sellBonus") :: number? else nil
	local reward = PersonalRules.ComputePlayerPayout(Config.PotionReward * stored, sellLevel or 1)
	return { stored = stored, equipped = equipped, reward = reward }
end
local function SetHiddenTransparency(instance: Instance, modifier: number): ()
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		local target = instance :: any
		if target.LocalTransparencyModifier ~= modifier then
			target.LocalTransparencyModifier = modifier
		end
	end
end
local function SetCharacterVisibility(character: Model, modifier: number, hidden: { [Instance]: boolean }): ()
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			SetHiddenTransparency(descendant, modifier)
			hidden[descendant] = true
		end
	end
end
local function RestoreHiddenPlayers(self: Client): ()
	if self.hidePlayersScope then
		self.hidePlayersScope:Destroy()
		self.hidePlayersScope = nil
	end
	local hidden = self.hiddenPlayerParts
	if hidden then
		for instance in hidden do
			SetHiddenTransparency(instance, 0)
		end
		table.clear(hidden)
	end
end
local function SyncHiddenPlayers(self: Client): ()
	if not Players or not Players.GetPlayers then
		return
	end
	local hidden: { [Instance]: boolean } = self.hiddenPlayerParts or {}
	self.hiddenPlayerParts = hidden
	for _, targetPlayer in Players:GetPlayers() do
		local character = targetPlayer.Character
		if character then
			SetCharacterVisibility(character, 1, hidden)
		end
	end
end

local function HidePlayerCharactersForPaint(self: Client): ()
	SyncHiddenPlayers(self)
end

local function HidePlayersForPaint(self: Client): ()
	RestoreHiddenPlayers(self)
	HidePlayerCharactersForPaint(self)
end

local function SetBatchFlash(view: PaintView.View, id: string, batch: { string }?, brightness: number?): ()
	if brightness then
		view:SetSacrifice(id, brightness, 0)
		for _, follower in ipairs(batch or {}) do view:SetSacrifice(follower, brightness, 0) end
	else
		view:ClearSacrifice(id)
		for _, follower in ipairs(batch or {}) do view:ClearSacrifice(follower) end
	end
end

local function SnapshotBatch(items: { [string]: Types.ItemView }): { string }
	local ids = {}
	for id, item in items do
		if item.paintSlot then table.insert(ids, id) end
	end
	return ids
end

local function FlashCompletion(self: Client, id: string, batch: { string }?): ()
	if Config.RuneCompleteFlashSeconds <= 0 then return end
	self.flipFlash = nil
	self.completeFlash = { id = id, batch = batch, started = os.clock() }
	SetBatchFlash(self.view, id, batch, 1)
end

function Client.TriggerAutoFlip(self: Client, animate: boolean): ()
	if Config.PaintRotationEnabled or self.paintFlipped then
		return
	end
	self.paintFlipped = true
	self.orientation = Rotation.FlipOrientation
	self.brushFrame = nil
	self.visualGesture += 1
	self.localProgress = math.max(self.localProgress or 0, Config.PaintAutoFlipProgress)
	if (self.localFrontTotalArea or 0) > 0 then
		self.localFrontArea = math.max(self.localFrontArea or 0, self.localFrontTotalArea * ActivePaintTarget())
		self.localArea = self.localFrontArea + (self.localBackArea or 0)
	end
	self.presentation:SetFlipped(true, animate)
	if animate then
		self:Text("NoticeText", { textId = "PaintFlipped" })
		self.messageEnds = os.clock() + 2.2
		if self.paintId and Config.PaintFlipFlashSeconds > 0 then
			self.flipFlash = { id = self.paintId, batch = self.paintBatch, started = os.clock() }
		end
		if Sound then
			Sound.Play("PaintFlip")
		end
	end
end
function Client.ExitView(self: Client, altarIntakeEnds: number?): ()
	local id = self.paintId
	if not id then
		return
	end
	self.paintId, self.paintBatch = nil, nil
	self.paintFlipped = false
	if self.flipFlash then
		if not self.completeFlash or self.completeFlash.id ~= self.flipFlash.id then
			SetBatchFlash(self.view, self.flipFlash.id, self.flipFlash.batch, nil)
		end
		self.flipFlash = nil
	end
	self.visualUpload:Clear()
	self.visualClosing = false
	self.session = nil
	self.drawing = false
	self.finishPaint = false
	self.pointer, self.brushFrame = nil, nil
	self.pointerOrigin, self.hardwareOrigin = nil, nil
	self.ignoreMouseMove, self.catchHardwareOrigin = false, false
	table.clear(self.paintSamples)
	if self.localCovered then table.clear(self.localCovered) end
	self.localProgress, self.localArea, self.localTotalArea = 0, 0, 0
	self.localFrontArea, self.localBackArea, self.localFrontTotalArea, self.localBackTotalArea = 0, 0, 0, 0
	self.pendingCoverage = nil
	self.touch = nil
	self.rotationAnchor = nil
	self.angularSpeed = 0
	if altarIntakeEnds then
		local ends = altarIntakeEnds + Physics.AltarToss.CameraPulseSeconds
		self.paintCamera:FollowToss(ends, function(): Vector3
			local mouth = furnaceMouth.WorldPosition
			local torso = self.bodies:GetVisualPart(id, "UpperTorso")
			local now = workspace:GetServerTimeNow()
			if torso and torso:IsDescendantOf(workspace) and now < altarIntakeEnds then
				local blend = math.clamp(1 - (altarIntakeEnds - now) / Physics.AltarToss.LandSeconds, 0, 1)
				return torso.Position:Lerp(mouth, blend)
			end
			return mouth
		end)
	else
		self.paintCamera:Exit()
	end
	if not self.paintCamera.follow then
		RestoreHiddenPlayers(self)
	end
	self:Text("HintText", nil)
	self.lastHint = 0
	local touchGui = player:WaitForChild("PlayerGui"):FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") and self.touchGuiEnabled ~= nil then
		touchGui.Enabled = self.touchGuiEnabled
	end
	self.touchGuiEnabled = nil
	self.ui:SetPainting(false)
end
function Client.EnterView(self: Client, id: string, session: string, frames: Types.BodyPose?, initialFlipped: boolean?, batch: { string }?): ()
	if self.paintId then
		self:ExitView()
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self:CancelHitFeedback()
	self.paintId, self.session, self.paintBatch = id, session, batch
	self.visualUpload:Begin(session)
	self.visualClosing = false
	self.paintSequence = 0
	self.lastPaint = os.clock()
	self.ignoreMouseMove, self.catchHardwareOrigin = false, false
	if self.localCovered then table.clear(self.localCovered) else self.localCovered = {} end
	local item = self.items[id]
	local initialProgress = if item then math.clamp(item.progress, 0, 1) else 0
	local paintModel = self.bodies:GetPaintModel(id)
	local totalArea = 0
	local frontTotal, backTotal = 0, 0
	if paintModel and typeof(paintModel) == "Instance" then
		totalArea = Surface.Total(paintModel)
		if paintModel:GetAttribute("SurfaceVersion") == Curve.Version then
			totalArea = math.max(0.001, totalArea - Curve.ExcludeInterior(paintModel, self.localCovered :: { [string]: boolean }))
		end
		frontTotal, backTotal = Surface.FlatSideTotals(paintModel, self.localCovered :: { [string]: boolean })
	end
	self.localTotalArea = totalArea
	self.localFrontTotalArea, self.localBackTotalArea = frontTotal, backTotal
	self.localFrontArea, self.localBackArea = 0, 0
	self.localProgress = 0
	self.localArea = 0
	local flipped = not Config.PaintRotationEnabled and (initialFlipped == true or (item ~= nil and item.paintFlipped == true))
	SyncLocalProgressFromServer(self, initialProgress, flipped)
	if self.view and self.view.Warmup then
		self.view:Warmup(id)
	end
	local initialOrientation = if Config.PaintRotationEnabled then CFrame.identity else Rotation.FlatOrientation(flipped)
	self.paintFlipped = flipped
	self.orientation, self.sentOrientation = initialOrientation, initialOrientation
	self.presentation:SetFlipped(flipped, false)
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
	self.paintCamera:EnterMarker(tableModel, Rotation.CameraPose(tablePlacement.Position, 1), 45)
	HidePlayersForPaint(self)
	self.ui:SetPainting(true)
end
function Client.CancelHitFeedback(self: Client): ()
	for sequence, prediction in self.hitState.pending do
		if not prediction.resolved then
			if prediction.targets then
				for targetId in prediction.targets do
					self.bodies:Reject(targetId, player.UserId, sequence)
				end
			else
				self.bodies:Reject(prediction.target, player.UserId, sequence)
			end
			prediction.resolved = true
		end
	end
	self.hitView:ResetCamera()
end
local function BodyVisualPosition(self: Client, item: Types.ItemView): (Vector3?, Vector3?)
	local authPart = if item.model then item.model.PrimaryPart else nil
	local authPos = if authPart then authPart.Position else nil
	local visPart = if self.bodies and self.bodies.GetVisualPart then self.bodies:GetVisualPart(item.id, "HumanoidRootPart") else nil
	local visPos = if visPart then visPart.Position else authPos
	return visPos, authPos
end
local function NearestStreetBodyDebug(self: Client, pose: CFrame): string
	local bestId: string? = nil
	local bestVisDist = math.huge
	local bestAuthDist = math.huge
	local bestDot = 0
	for _, item in self.items do
		if item.kind == "Body" and item.location == "Street" and item.hits < Config.StunHits and item.model and item.model.PrimaryPart then
			local visPos, authPos = BodyVisualPosition(self, item)
			if visPos then
				local delta = visPos - pose.Position
				local dist = delta.Magnitude
				if dist < bestVisDist then
					bestId = item.id
					bestVisDist = dist
					bestAuthDist = if authPos then (authPos - pose.Position).Magnitude else dist
					bestDot = if dist > 0.1 then pose.LookVector:Dot(delta.Unit) else 1
				end
			end
		end
	end
	if not bestId then
		return "nearest=none"
	end
	return string.format("nearest=%s visDist=%.2f authDist=%.2f dot=%.2f", bestId, bestVisDist, bestAuthDist, bestDot)
end
local function SelectHitTargets(self: Client, level: number, tier: GameData.WeaponConfig, pose: CFrame, now: number): { Types.ItemView }
	if tier.shape == "Single" then
		local best: Types.ItemView? = nil
		local distance = tier.range
		for _, item in self.items do
			if item.kind == "Body" and item.location == "Street" and item.hits < Config.StunHits and item.model and item.model.PrimaryPart then
				local visPos = BodyVisualPosition(self, item)
				if visPos then
					local delta = visPos - pose.Position
					if delta.Magnitude <= distance and (delta.Magnitude < 0.1 or pose.LookVector:Dot(delta.Unit) > -0.1) then
						distance = delta.Magnitude
						best = item
					end
				end
			end
		end
		local combo = if self.attackTarget and now < self.comboEnds then self.items[self.attackTarget] else nil
		if combo and combo.kind == "Body" and combo.hits < Config.StunHits and combo.location == "Street" and combo.model and combo.model.PrimaryPart then
			local visPos = BodyVisualPosition(self, combo)
			if visPos then
				local delta = visPos - pose.Position
				if delta.Magnitude <= tier.range and (delta.Magnitude < 0.1 or pose.LookVector:Dot(delta.Unit) > -0.1) then
					best = combo
				end
			end
		end
		self.attackTarget = if best then best.id else nil
		self.comboEnds = now + Config.AttackComboSeconds
		return if best then { best } else {}
	end
	self.attackTarget = nil
	type Candidate = { item: Types.ItemView, distance: number }
	local candidates: { Candidate } = {}
	for _, item in self.items do
		if item.kind == "Body" and item.location == "Street" and item.hits < Config.StunHits and item.model and item.model.PrimaryPart then
			local visPos = BodyVisualPosition(self, item)
			if visPos and PersonalRules.InWeaponArea(level, pose, visPos) then
				table.insert(candidates, { item = item, distance = (visPos - pose.Position).Magnitude })
			end
		end
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		if a.distance == b.distance then
			return a.item.id < b.item.id
		end
		return a.distance < b.distance
	end)
	local matched: { Types.ItemView } = {}
	local count = math.min(#candidates, tier.targets)
	for index = 1, count do
		table.insert(matched, candidates[index].item)
	end
	return matched
end
function Client.HitFeedback(self: Client, now: number, final: boolean, upgrade: boolean): ()
	if now-self.lastAttack>Config.HitFeedbackWindow or self.paintId or self:ShoulderOccupied() then return end
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health<=0 or not character or not PersonalRules.FindWeapon(character) then return end
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
	if self.paintId or self:ShoulderOccupied() or not humanoid or humanoid.Health<=0 or not character or not PersonalRules.FindWeapon(character) then
		self:CancelHitFeedback()
	else
		for sequence, prediction in self.hitState.pending do
			if prediction.resolved or prediction.played or now<prediction.due then continue end
			if prediction.deferred then
				local weapon = PersonalRules.FindWeapon(character)
				local level = if weapon then PersonalRules.WeaponLevel(weapon.Name) else nil
				if not weapon or not level or (prediction.weaponLevel ~= nil and level ~= prediction.weaponLevel)
					or now > prediction.expires or not root or not root:IsA("BasePart")
				then
					if Config.DebugAttackLog then
						local reason = if now > prediction.expires then "expired" elseif not weapon or not level then "no_weapon" elseif not root or not root:IsA("BasePart") then "no_root" else "weapon_changed"
						print(string.format("[Attack][Client] Cancel seq=%d reason=%s", sequence, reason))
					end
					prediction.played = false
					prediction.resolved = true
					continue
				end
				prediction.played = true
				local pose = root.CFrame
				local tier = PersonalRules.GetWeaponTier(level)
				local matched = SelectHitTargets(self, level, tier, pose, now)
				if tier.shape ~= "Single" then
					self.hitView:WeaponEffect(tier.model, pose, tier.range, tier.width)
				end
				local hitIds: { string } = {}
				for _, item in matched do
					table.insert(hitIds, item.id)
				end
				HitRules.SetTargets(self.hitState, sequence, hitIds)
				if Config.DebugAttackLog then
					local summary = if #matched > 0 then table.concat(hitIds, ",") else NearestStreetBodyDebug(self, pose)
					print(string.format("[Attack][Client] HitFrame seq=%d weapon=%s(lv=%d,%s) range=%.1f hits=%d %s",
						sequence, tier.model, level, tier.shape, tier.range, #matched, summary))
				end
				for _, item in matched do
					if self.bodies.TrackPrediction then
						self.bodies:TrackPrediction(item.id, sequence, prediction)
					end
					local visPos = BodyVisualPosition(self, item)
					local bodyPos = visPos or (item.model.PrimaryPart :: BasePart).Position
					local direction = pose.LookVector
					if tier.shape == "Slam" then
						local delta = pose.Position - bodyPos
						local horizontal = Vector3.new(delta.X, 0, delta.Z)
						if horizontal.Magnitude > 0.01 then
							direction = horizontal.Unit
						end
					end
					local torso = if self.bodies.GetVisualPart then self.bodies:GetVisualPart(item.id, "UpperTorso") else nil
					if not torso then
						local found = item.model:FindFirstChild("UpperTorso")
						if found and found:IsA("BasePart") then
							torso = found
						end
					end
					local position = if torso then torso.Position - direction * torso.Size.Z * 0.5 else bodyPos
					local hp = PersonalRules.RemainingNpcHp(item.hp, item.hits, tier.damage)
					local hits = math.min(Config.StunHits - 1, Config.StunHits - math.ceil(hp / Config.BruteDamage))
					if not self.bodies:Hit(item.id, player.UserId, sequence, item.version + 1, hits, direction, position, now, false, true) then
						self.hitView:Play(item.id, item.model, hits, direction, now)
					end
					if not self.bodies.pureModel then
						self.hitView:Burst(item.id, position, direction, false, now)
					end
				end
				if #matched > 0 then
					self:HitFeedback(now, false, false)
				end
				Net.FireRequest({
					action = "Attack",
					target = hitIds[1],
					targets = if #hitIds > 0 then hitIds else nil,
					attackPose = pose,
					attackSequence = sequence,
				})
				continue
			end
			local id=HitRules.TakePrediction(self.hitState,sequence,now)
			local item=if id then self.items[id] else nil
			if not id or not item or item.kind~="Body" or item.location~="Street" or item.hits>=Config.StunHits
				or not item.model or not item.model.Parent or not item.model.PrimaryPart or not root or not root:IsA("BasePart") then
				prediction.played=false; prediction.resolved=true; continue
			end
			local weapon = PersonalRules.FindWeapon(character)
			local level = if weapon then PersonalRules.WeaponLevel(weapon.Name) or 1 else 1
			local tier = PersonalRules.GetWeaponTier(level)
			local visPos = BodyVisualPosition(self, item) or item.model.PrimaryPart.Position
			local delta=visPos-root.Position
			if delta.Magnitude>tier.range or (delta.Magnitude>0.1 and root.CFrame.LookVector:Dot(delta.Unit)<=-0.1) then
				prediction.played=false; prediction.resolved=true; continue
			end
			local torso = if self.bodies.GetVisualPart then self.bodies:GetVisualPart(id, "UpperTorso") else nil
			if not torso then
				local found = item.model:FindFirstChild("UpperTorso")
				if found and found:IsA("BasePart") then torso = found end
			end
			local position = if torso then torso.Position - root.CFrame.LookVector * torso.Size.Z * 0.5 else visPos
			local hp = PersonalRules.RemainingNpcHp(item.hp, item.hits, tier.damage)
			local hits = math.min(Config.StunHits - 1, Config.StunHits - math.ceil(hp / Config.BruteDamage))
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
	local now=workspace:GetServerTimeNow()
	local age=now-started
	if not item or not item.model or not item.model.Parent then
		if age < Config.HitHealthSeconds and #self.waitingHits<32 then table.insert(self.waitingHits,notice) end
		return
	end
	if age >= 0 and age < Config.HitHealthSeconds and item.location == "Street"
		and item.hits < Config.StunHits and (item.version <= version or (item.hits == hits and item.hp == notice.hp))
	then
		UIManager.GetTargetGuiManager():ShowHit(id, version, hits, started, self.bodies:GetVisualPart(id, "Head"), notice.hp, notice.maxHp)
	end
	if not self.bodies:AcceptNotice(id,version,hits,started) then return end
	local localActor=notice.actor==player.UserId
	local prediction=if localActor and notice.attackSequence then self.hitState.pending[notice.attackSequence] else nil
	local predictedTarget = prediction ~= nil and HitRules.MatchesTarget(prediction, id)
	if prediction and prediction.retired and predictedTarget and hits<Config.StunHits then return end
	if prediction and not predictedTarget and not prediction.targets and notice.attackSequence then self.bodies:Reject(prediction.target,player.UserId,notice.attackSequence) end
	local previous= self.hitState.versions[id] or 0
	local replay=HitRules.Confirm(self.hitState,id,version,if localActor then notice.attackSequence else nil)
	if version<=previous then return end
	if Config.DebugAttackLog and localActor then
		print(string.format("[Attack][Client] HitConfirm seq=%s id=%s hp=%s/%s hits=%d replay=%s",
			tostring(notice.attackSequence), id, tostring(notice.hp), tostring(notice.maxHp), hits, tostring(replay)))
	end
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
		elseif final then
			self.hitView:UpgradeBurst(id)
			if not prediction or not prediction.finalFeedbackPlayed then
				self:HitFeedback(now,true,true)
				if prediction then prediction.finalFeedbackPlayed = true end
			end
		end
	end
end
function Client.OnNotice(self: Client, notice: Types.Notice): ()
	if notice.kind=="Hit" then self:OnHit(notice); return end
	if notice.kind == "WeaponEffect" and notice.weaponLevel and notice.attackPose and notice.started then
		if notice.actor == player.UserId then return end
		local age = workspace:GetServerTimeNow() - notice.started
		if age >= 0 and age < 0.4 then
			local weapon = PersonalRules.GetWeaponTier(notice.weaponLevel)
			self.hitView:WeaponEffect(weapon.model, notice.attackPose, weapon.range, weapon.width)
		end
		return
	end
	if notice.kind=="AttackResult" and notice.attackSequence then
		local pending=self.hitState.pending[notice.attackSequence]
		if Config.DebugAttackLog then
			print(string.format("[Attack][Client] Result seq=%d hit=%s", notice.attackSequence, tostring(notice.hit == true)))
		end
		if pending and notice.hit~=true then
			if pending.targets then
				for targetId in pending.targets do
					self.bodies:Reject(targetId,player.UserId,notice.attackSequence)
				end
			else
				self.bodies:Reject(pending.target,player.UserId,notice.attackSequence)
			end
		end
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
		local prevAutoShelf = if self.snapshot then self.snapshot.autoShelfItems else nil
		self.snapshot = snapshot
		local animate = notice.kind == "Delta" and self.synced
		self.potionShelf:Apply(snapshot.shelfItems, animate, os.clock())
		if animate and notice.altarOutput then
			self:PlayAltarOutput(notice.altarOutput, snapshot.shelfItems)
		end
		if self.autoPotionShelf then
			self.autoPotionShelf:Apply(snapshot.autoShelfItems or {}, notice.kind == "Delta" and self.synced, os.clock())
		end
		if self.UpdateAutomationViews then
			self:UpdateAutomationViews(snapshot)
		end
		if snapshot.bodyPose and (self.paintId == nil or self.paintId == snapshot.tableId) then
			self.presentation.targetBodyPose = snapshot.bodyPose
		end
		local nextItems: { [string]: Types.ItemView } = {}
		for _, item in snapshot.items do
			nextItems[item.id] = item
		end
		local addedFollowers = {}
		for id, prior in self.items do
			local current = nextItems[id]
			if prior.paintSlot and current and current.location == "Pool" then
				self.view:Remove(id)
			end
		end
		for id, current in nextItems do
			local prior = self.items[id]
			local toss = current.altarToss
			if animate and toss and (not prior or not prior.altarToss or prior.altarToss.landEnds ~= toss.landEnds) then
				self.altarFx:ScheduleIntake(id, toss.landEnds)
			end
			if current.paintSlot and (not prior or not prior.paintSlot) then
				table.insert(addedFollowers, id)
			end
		end
		self.bodies:UpdateState(nextItems,snapshot.bodyPose)
		if snapshot.tableId and #addedFollowers > 0 then
			self.view:Mirror(snapshot.tableId, addedFollowers)
		end
		if snapshot.painter ~= player.UserId then
			if Config.PaintRotationEnabled then
				self.presentation.targetOrientation = snapshot.paintOrientation or CFrame.identity
			else
				local tableItem = if snapshot.tableId then nextItems[snapshot.tableId] else nil
				local wantFlipped = snapshot.paintFlipped == true
					or (tableItem ~= nil and tableItem.paintFlipped == true)
					or (snapshot.paintOrientation ~= nil and Rotation.IsFlipped(snapshot.paintOrientation))
				self.presentation:SetFlipped(wantFlipped, false)
			end
		elseif not Config.PaintRotationEnabled and self.paintId ~= nil and self.paintId == snapshot.tableId then
			self.presentation:SetFlipped(self.paintFlipped, false)
		end
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
		local previousItems = self.items
		self.items = nextItems
		if self.automationView then
			self.automationView:OnSnapshot(snapshot, previousItems, nextItems, prevAutoShelf, animate, os.clock())
		end
		local currentHeld = self:Held()
		local currentHeldId = currentHeld and currentHeld.id
		local currentHeldKind = currentHeld and currentHeld.kind
		local lastId = self.lastHeldId
		local lastKind = self.lastHeldKind
		local lastPool = self.lastPoolCount or snapshot.pool
		local lastChute = self.lastChuteCount or (snapshot.chuteQueue or 0)
		local currentChute = snapshot.chuteQueue or 0
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
					-- 出手瞬间位置是 Thrown，落地或入池音效等落稳后再播。
					if not released or released.location ~= "Thrown" then
						if snapshot.pool > lastPool then
							Sound.Play("PoolDeposit", positions.Pool)
						elseif currentChute > lastChute then
							Sound.Play("PoolDeposit", positions.Chute or positions.Pool)
						elseif not released or released.location ~= "Altar" then
							Sound.Play("BodyDrop")
						end
					end
				end
			end
			self.lastHeldId = currentHeldId
			self.lastHeldKind = currentHeldKind
		end
		self.lastPoolCount = snapshot.pool
		self.lastChuteCount = currentChute
		for id, item in nextItems do
			local previous = previousItems[id]
			if previous and previous.location == "Thrown" and item.location ~= "Thrown" and item.kind == "Body" then
				if item.location == "Pool" then
					Sound.Play("PoolDeposit", positions.Pool)
				elseif item.location == "Chute" then
					Sound.Play("PoolDeposit", positions.Chute or positions.Pool)
				elseif item.location == "Ground" then
					local started = if previous.toss then previous.toss.started else nil
					if not self.bodies:HasManualImpactPlayed(id, started) then
						local model = item.model
						Sound.Play("BodyDrop", if model then model:GetPivot().Position else nil)
					end
				end
			end
		end
		for id, previous in previousItems do
			if previous.location == "Thrown" and previous.kind == "Body" and not nextItems[id] and currentChute > lastChute then
				Sound.Play("PoolDeposit", positions.Chute or positions.Pool)
				break
			end
		end
		local waiting=self.waitingHits
		self.waitingHits={}
		for _,hit in waiting do self:OnHit(hit) end
		table.clear(self.characterView.carriers)
		for _, item in nextItems do
			if item.holder and item.kind == "Body" then self.characterView.carriers[item.holder] = true end
		end
		if self.paintId and (snapshot.painter ~= player.UserId or snapshot.session ~= self.session) then
			local body = nextItems[self.paintId]
			self:ExitView(if body and body.altarToss then body.altarToss.landEnds else nil)
		end
	elseif notice.kind == "Swing" and notice.actor and notice.started then
		-- 本地已即时预测；远端其他角色在对应空间位置播放挥舞音效，避免服务端广播延迟与回声
		if notice.actor ~= player.UserId then
			local otherPlayer = Players:GetPlayerByUserId(notice.actor)
			local otherChar = otherPlayer and otherPlayer.Character
			local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				if notice.weaponLevel then
					PlayWeaponSlashSound(PersonalRules.GetWeaponTier(notice.weaponLevel), otherRoot.Position)
				elseif Sound.Play then
					Sound.Play("AttackSwing", otherRoot.Position)
				end
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
		if item then
			local before = item.progress
			item.progress = notice.progress or before
			if not isOperator and before < 1 and item.progress >= 1 then
				FlashCompletion(self, notice.id, SnapshotBatch(self.items))
			end
			if isOperator then
				local flippedNow = self.paintFlipped or notice.flipped == true
				SyncLocalProgressFromServer(self, item.progress, flippedNow)
				if not Config.PaintRotationEnabled and not self.paintFlipped
					and (notice.flipped == true or item.progress >= Config.PaintAutoFlipProgress) then
					self:TriggerAutoFlip(true)
				end
			end
		end
		if isOperator and self.pendingCoverage and notice.sequence == self.pendingCoverage.sequence then self.pendingCoverage=nil end
		if not isOperator then
			if Config.PaintRotationEnabled then
				self.presentation.targetOrientation = notice.orientation or CFrame.identity
			else
				local wantFlipped = notice.flipped == true or (notice.orientation ~= nil and Rotation.IsFlipped(notice.orientation))
				self.presentation:SetFlipped(wantFlipped, wantFlipped and not self.presentation.flipped)
			end
			if Config.PaintPhysicsEnabled and notice.bodyPose then
				self.presentation.targetBodyPose = notice.bodyPose
			end
		end
	elseif notice.kind == "VisualDelta" and notice.id and notice.segments then
		local item = self.items[notice.id]
		if not item then return end
		self.view:Apply(notice.id,notice.segments)
		for _, id in ipairs(notice.paintBatch or {}) do
			self.view:Apply(id, notice.segments)
		end
		if notice.session == self.session and notice.sequence then self.visualUpload:Ack(notice.sequence) end
		local snapshot = self.snapshot
		local isOperator = notice.id == self.paintId and notice.session == self.session
		local isCurrentTable = snapshot and notice.id == snapshot.tableId and notice.session == snapshot.session
		if not isOperator and isCurrentTable and Config.PaintPhysicsEnabled and notice.bodyPose then
			self.presentation.targetBodyPose = notice.bodyPose
		end
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
		if self.paintId then FlashCompletion(self, self.paintId, self.paintBatch) end
		self.pendingCoverage=nil
		table.clear(self.paintSamples)
		self.sentOrientation=self.orientation
		self:RequestPaintEnd()
	elseif notice.kind == "BeginPaint" and notice.id and notice.session then
		local initialFlipped = notice.flipped == true or (notice.orientation ~= nil and Rotation.IsFlipped(notice.orientation))
		self:EnterView(notice.id, notice.session, notice.bodyPose, initialFlipped, notice.paintBatch)
	elseif notice.kind == "EndPaint" and notice.session == self.session then
		local id = notice.id or self.paintId
		if id and (notice.altarToss or notice.started) then
			local item = self.items[id]
			if item then
				item.location = "Altar"
				item.stage = "Converting"
				item.altarToss = notice.altarToss or item.altarToss
				if self.synced and notice.altarToss then self.altarFx:ScheduleIntake(id, notice.altarToss.landEnds) end
				item.altarTossStarted = notice.started or (if notice.altarToss then notice.altarToss.started else item.altarTossStarted)
				if self.bodies and self.bodies.Bind then
					self.bodies:Bind(item)
				end
			end
		end
		self:ExitView(if notice.altarToss then notice.altarToss.landEnds else nil)
	elseif notice.kind == "Message" and (notice.textId or notice.text) then
		self:Notice(notice)
		self.messageEnds = os.clock() + 3
		if notice.textId == "CoinsAwarded" then
			Sound.Play("CoinReward")
		elseif notice.textId == "RuneComplete" or notice.textId == "FacilityUnlocked" then
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
function Client.TakeTable(self: Client): ()
	if self.paintId or self:Held() or not self.nearTable then
		return
	end
	Net.FireRequest({ action = "TakeTable" })
end
function Client.Attack(self: Client, inputTime: number?): ()
	local now = workspace:GetServerTimeNow()
	if self.worldInteraction and self.worldInteraction:IsInputBlocked() then return end
	if self.paintId or self:ShoulderOccupied() then return end
	local character = player.Character
	local weapon = PersonalRules.FindWeapon(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not weapon or not humanoid or humanoid.Health <= 0 then return end
	local level = PersonalRules.WeaponLevel(weapon.Name)
	if not level then return end
	local tier = PersonalRules.GetWeaponTier(level)
	local cooldown = if tier.attackCooldown > 0 then tier.attackCooldown else Config.AttackCooldown
	if now - self.lastAttack < cooldown then return end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	self.lastAttack = now
	self.characterView:Swing(player.UserId, now, tier.slashAnim)
	PlayWeaponSlashSound(tier, root.Position)
	self.attackSequence += 1
	local started = inputTime or now
	HitRules.Begin(self.hitState, self.attackSequence, nil, started + Config.AttackWindup, now + Config.HitPredictionLifetime, true, level)
	if Config.DebugAttackLog then
		print(string.format("[Attack][Client] Swing seq=%d weapon=%s(lv=%d,%s) cooldown=%.2f windup=%.2f",
			self.attackSequence, tier.model, level, tier.shape, cooldown, Config.AttackWindup))
	end
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
-- 把系统光标移到喷口。成功时后续输入会从笔尖发出，不再保留拖拽偏移。
local function WarpMouseToTip(self: Client, tip: Vector2): boolean
	local target = tip + ReadInset()
	self.ignoreMouseMove = true
	local sent = pcall(function()
		local virtual = UserInputService:CreateVirtualInput()
		if virtual == nil then
			error("VirtualInput unavailable")
		end
		(virtual :: any):SendMousePosition(target)
	end)
	local after = ReadMouse()
	local arrived = sent and after ~= nil and (after - target).Magnitude <= 8
	if arrived then
		return true
	end
	self.ignoreMouseMove = false
	return false
end

-- 在入队上报前按客户端本地已覆盖集合去重，并返回本帧新增覆盖面积供客户端即时推进进度条。
local function FilterNewCoverageSamples(
	self: Client,
	model: Model,
	samples: { Types.Sample },
	basePose: CFrame?,
	geometry: Rotation.Geometry?,
	displayedOrientation: CFrame?,
	cameraOrigin: Vector3?,
	flatSide: number?
): ({ Types.Sample }, number)
	if typeof(model) ~= "Instance" then
		return samples, 0
	end
	local covered: { [string]: boolean } = self.localCovered or {}
	self.localCovered = covered
	local filtered: { Types.Sample } = {}
	local totalAdded = 0
	local previous: Types.Sample? = nil
	local lastQueued: Types.Sample? = nil
	local displayedFrame = if basePose and geometry and displayedOrientation
		then Rotation.Pose(basePose, geometry, displayedOrientation)
		else nil
	local pivotAtDisplayed = if displayedFrame
		then displayedFrame:PointToWorldSpace(if geometry and geometry.center then geometry.center else Vector3.zero)
		else nil
	local cachedSliceOrientation: CFrame? = nil
	local cachedToCamera: Vector3? = nil
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
		if curved and sample.slice and displayedFrame and pivotAtDisplayed and basePose and geometry and cameraOrigin then
			local sampledOrientation = (sample.orientation or displayedOrientation or CFrame.identity).Rotation
			if sampledOrientation ~= cachedSliceOrientation or not cachedToCamera then
				local sampledFrame = Rotation.Pose(basePose, geometry, sampledOrientation)
				local rayOrigin = displayedFrame:PointToWorldSpace(sampledFrame:PointToObjectSpace(cameraOrigin))
				local toCameraVec = rayOrigin - pivotAtDisplayed
				cachedToCamera = if toCameraVec.Magnitude > 0.001 then toCameraVec.Unit else Vector3.yAxis
				cachedSliceOrientation = sampledOrientation
			end
			local worldPoint = part.CFrame:PointToWorldSpace(Curve.Point(part, sample))
			if (worldPoint - pivotAtDisplayed):Dot(cachedToCamera :: Vector3) < Config.PaintSliceHemisphereMinDot then
				previous = nil
				continue
			end
		end
		local ink = sample
		if curved and sample.packedInk then
			ink = table.clone(sample)
			ink.u, ink.v = Curve.InkCenter(sample.u, sample.v)
		end
		local _, added = Surface.Stamp(part, ink, covered, flatSide)
		local sampleDistance: number? = nil
		if previous and not previous.packedInk and not sample.packedInk and previous.part == sample.part and previous.face == sample.face then
			if curved then
				local start = Curve.Point(part, previous)
				local finish = Curve.Point(part, sample)
				local distance = (finish - start).Magnitude
				sampleDistance = distance
				if distance < Config.BrushRadius * 3 then
					local steps = math.ceil(distance / (Config.BrushRadius * 0.5))
					for index = 1, steps - 1 do
						local intermediate = Curve.ProjectLocal(part, start:Lerp(finish, index / steps))
						local _, segArea = Surface.Stamp(part, intermediate, covered, flatSide)
						added += segArea
					end
				end
			else
				local dimensions = Surface.Dimensions(part.Size, sample.face)
				local distance = Vector2.new((sample.u - previous.u) * dimensions.X, (sample.v - previous.v) * dimensions.Y).Magnitude
				sampleDistance = distance
				if distance < Config.BrushRadius * 3 then
					local steps = math.ceil(distance / (Config.BrushRadius * 0.5))
					for index = 1, steps - 1 do
						local alpha = index / steps
						local _, segArea = Surface.Stamp(part, {
							part = sample.part,
							face = sample.face,
							u = previous.u + (sample.u - previous.u) * alpha,
							v = previous.v + (sample.v - previous.v) * alpha,
						}, covered, flatSide)
						added += segArea
					end
				end
			end
		end
		if added > 0 then
			totalAdded += added
			if previous and not sample.breakBefore and previous.part == sample.part and previous.face == sample.face and previous ~= lastQueued then
				local skipAnchor = not Config.PaintRotationEnabled and sampleDistance ~= nil and sampleDistance < Config.BrushRadius * 1.25
				if not skipAnchor then
					local anchor = table.clone(previous)
					anchor.breakBefore = true
					table.insert(filtered, anchor)
				end
			end
			table.insert(filtered, sample)
			lastQueued = sample
		end
		previous = sample
	end
	return filtered, totalAdded
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
	if Config.PaintRotationEnabled and self.rotationAnchor then
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
		local flatSide: number? = if Config.PaintRotationEnabled then nil else Curve.FlatSide(model, self.paintFlipped)
		self.view:DrawLocal(id,session,self.visualGesture,samples,flatSide)
		local cameraFrame = camera.CFrame
		local cameraOrigin: Vector3? = if typeof(cameraFrame) == "CFrame" then cameraFrame.Position else nil
		local queued, addedArea = FilterNewCoverageSamples(self, model, samples, basePose, geometry, display.orientation, cameraOrigin, flatSide)
		if addedArea > 0 then
			if (self.localTotalArea or 0) <= 0 and typeof(model) == "Instance" then
				local total = Surface.Total(model)
				if model:GetAttribute("SurfaceVersion") == Curve.Version then
					total = math.max(0.001, total - Curve.ExcludeInterior(model, self.localCovered :: { [string]: boolean }))
				end
				self.localTotalArea = total
				local frontTotal, backTotal = Surface.FlatSideTotals(model, self.localCovered :: { [string]: boolean })
				self.localFrontTotalArea, self.localBackTotalArea = frontTotal, backTotal
				local item = self.items[id]
				local baseProgress = if item then math.clamp(item.progress, 0, 1) else 0
				SyncLocalProgressFromServer(self, baseProgress, self.paintFlipped)
			end
			if not Config.PaintRotationEnabled and (self.localFrontTotalArea or 0) > 0 and (self.localBackTotalArea or 0) > 0 then
				if self.paintFlipped then
					self.localBackArea = (self.localBackArea or 0) + addedArea
				else
					self.localFrontArea = (self.localFrontArea or 0) + addedArea
				end
				self.localArea = (self.localFrontArea or 0) + (self.localBackArea or 0)
				local predicted = math.min(
					Surface.FlatProgress(self.localFrontArea or 0, self.localBackArea or 0, self.localFrontTotalArea, self.localBackTotalArea, self.paintFlipped),
					0.99
				)
				self.localProgress = math.max(self.localProgress or 0, predicted)
			elseif (self.localTotalArea or 0) > 0 then
				self.localArea = (self.localArea or 0) + addedArea
				local targetArea = math.max(self.localTotalArea * ActivePaintTarget(), 0.001)
				local predicted = math.min(self.localArea / targetArea, 0.99)
				self.localProgress = math.max(self.localProgress or 0, predicted)
			end
		end
		for _, sample in queued do
			if not Config.PaintRotationEnabled and not sample.orientation then
				sample.orientation = display.orientation
			end
			table.insert(self.paintSamples,sample)
		end
		if not Config.PaintRotationEnabled and not self.paintFlipped and (self.localProgress or 0) >= Config.PaintAutoFlipProgress then
			self:TriggerAutoFlip(true)
		end
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
	local flipping = self.presentation:IsFlipping()
	if flipping then
		self.brushFrame = nil
	end
	local tip = if self.drawing and not flipping then self:SamplePaint(now) else self.pointer
	local moved = Rotation.Distance(self.sentOrientation, self.orientation) > 0.001

	local pending = self.pendingCoverage
	if pending then
		-- 有间隔限制的服务端可能因包挤在一起而拒收；保留原序号并按较短重试间隔快速恢复。
		if now-self.lastPaint >= Config.PaintCoverageRetrySeconds then
			pending.orientation = self.orientation
			local pose = self.presentation:CapturePose()
			if pose then pending.bodyPose = pose end
			Net.FireRequest(pending)
			self.lastPaint = now
		end
	elseif now-self.lastPaint >= Config.PaintBatchInterval and (#self.paintSamples>0 or moved) then
		local count = math.min(#self.paintSamples,Config.PaintCoverageBatchSize)
		local samples = table.move(self.paintSamples,1,count,1,{})
		self.paintSamples = table.move(self.paintSamples,count+1,#self.paintSamples,1,{})
		self.lastPaint = now
		self.paintSequence += 1
		local request: Types.Request = {action="Paint",session=session,sequence=self.paintSequence,samples=samples,orientation=self.orientation,bodyPose=self.presentation:CapturePose()}
		self.pendingCoverage = request
		self.sentOrientation = self.orientation
		Net.FireRequest(request)
	end
	self.finishPaint = not self.drawing and (#self.paintSamples>0 or self.pendingCoverage~=nil or moved)
	return tip
end

function Client.StepPaintRotation(self: Client, dt: number): ()
	if not Config.PaintRotationEnabled then
		self.orientation = Rotation.FlatOrientation(self.paintFlipped)
		self.angularSpeed = 0
		return
	end
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
	if self.throw then
		self.throw:Update(workspace:GetServerTimeNow())
	end
	if self.worldInteraction then self.worldInteraction:Refresh() end
	local missingModel = false
	for _, item in self.items do
		if item.location == "Toolbar" or item.location == "Shelf" then
			continue
		end
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
		if item and item.model then self.ui:SetProgress(math.max(item.progress, self.localProgress or 0)) end
		local point = self:Paint(now)
		self.ui:UpdatePointer(point, self.drawing and not self.presentation:IsFlipping())
		self.ignoreMouseMove = false
		if self.catchHardwareOrigin and not self.drawing and self.hardwareOrigin then
			self.catchHardwareOrigin = false
			self.hardwareOrigin = HardwareNow(self.hardwareOrigin)
		end
	end
	-- 姿态和当前帧采样完成后再绘制，每帧统一消耗一次栅格化预算。
	self.view:Update(self.paintId)
	local completeFlash = self.completeFlash
	if completeFlash then
		local elapsed = now - completeFlash.started
		local duration = math.max(Config.RuneCompleteFlashSeconds, 0.05)
		if elapsed >= duration then
			if self.view and self.view.ClearSacrifice then
				SetBatchFlash(self.view, completeFlash.id, completeFlash.batch, nil)
			end
			self.completeFlash = nil
		else
			local hold = duration * 0.3
			local brightness = if elapsed <= hold then 1 else math.clamp(1 - (elapsed - hold) / (duration - hold), 0, 1)
			if self.view and self.view.SetSacrifice then
				SetBatchFlash(self.view, completeFlash.id, completeFlash.batch, brightness)
			end
		end
	end
	local flipFlash = self.flipFlash
	if flipFlash then
		if completeFlash and completeFlash.id == flipFlash.id then
			self.flipFlash = nil
		else
			local elapsed = now - flipFlash.started
			local duration = math.max(Config.PaintFlipFlashSeconds, 0.05)
			if elapsed >= duration then
				if self.view and self.view.ClearSacrifice then
					SetBatchFlash(self.view, flipFlash.id, flipFlash.batch, nil)
				end
				self.flipFlash = nil
			else
				local hold = duration * 0.25
				local weight = if elapsed <= hold then 1 else math.clamp(1 - (elapsed - hold) / (duration - hold), 0, 1)
				if self.view and self.view.SetSacrifice then
					SetBatchFlash(self.view, flipFlash.id, flipFlash.batch, weight * Config.PaintFlipFlashBrightness)
				end
			end
		end
	end
	if self.paintId then
		local dirty = self.view:Drain(self.paintId)
		local followers = self.paintBatch
		if followers and #followers > 0 and next(dirty) then
			local segments = {}
			for _, segment in dirty do table.insert(segments, segment) end
			for _, id in followers do self.view:Apply(id, segments) end
		end
		self.visualUpload:Update(dirty,now,workspace:GetServerTimeNow(),self.visualClosing or not self.drawing,self.presentation:CapturePose(),not self.finishPaint and self.view:IsReady(self.paintId))
		if self.view.budgetReached then
			self:Text("NoticeText", {textId = "PaintSegmentLimit"})
			self.messageEnds=now+3
			self.view.budgetReached=false
		end
	end
	if not self.paintId and not self.paintCamera.follow and self.hiddenPlayerParts and next(self.hiddenPlayerParts) ~= nil then
		RestoreHiddenPlayers(self)
	end
	if now - self.lastHint < 0.1 then
		return
	end
	self.lastHint = now
	self:Text("CoinsText", {textId = "Coins", args = {NumberExtension.FormatBigNumberAA(player:GetAttribute("Coins") or 0)}})
	if self.UpdateAutomationViews then
		self:UpdateAutomationViews(snapshot)
	end
	local carried = self:Carried()
	local held = self:Held()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local weaponEquipped = PersonalRules.FindWeapon(character) ~= nil
	local carryingBody = #carried > 0
	local canAttack = alive and weaponEquipped and not self:ShoulderOccupied()
	local canThrow = alive and carryingBody and not weaponEquipped
	local windowOpen = UIManager.HasShowingWindow()
	local focused = if self.attackTarget then self.items[self.attackTarget] else nil
	local head = focused and self.bodies:GetVisualPart(focused.id,"Head")
	local targetGui = UIManager.GetTargetGuiManager()
	targetGui:RefreshHits(workspace:GetServerTimeNow(), function(id: string): BasePart?
		local item = self.items[id]
		if item and item.location == "Street" and item.hits < Config.StunHits then
			return self.bodies:GetVisualPart(id, "Head")
		end
		return nil
	end)
	targetGui:Refresh({
		id = focused and focused.id,
		adornee = if head and head:IsA("BasePart") then head else nil,
		visible = not self.paintId and canAttack and focused ~= nil and focused.location == "Street" and focused.hits < Config.StunHits,
		hits = if focused then focused.hits else 0,
		hp = focused and focused.hp,
		maxHp = focused and focused.maxHp,
		touch = UserInputService.TouchEnabled,
	})
	self.ui:Refresh({painting=self.paintId~=nil,hasTarget=false,windowOpen=windowOpen,canAttack=canAttack,canThrow=canThrow})
	if self.paintId then
		SyncHiddenPlayers(self)
		self:Text("HintText", { textId = if Config.PaintRotationEnabled then "Painting" else "PaintingFlat" })
		return
	end
	if self.paintCamera.follow ~= nil then
		return
	end
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
	if not held or carryingBody then
		for _, item in self.items do
			local model = item.model
			local rootPart = model and model.PrimaryPart
			if rootPart and not item.holder and WorldInteractionRules.IsPickupLocation(item) and (item.kind == "Body" or not carryingBody) then
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
	self:Text("HintText", if target then Hints.Action(target, snapshot, held, player.UserId, potions, carried) else Hints.Next(snapshot, held, potions, carried, weaponEquipped))
	self.ui:Refresh({painting=false,hasTarget=target~=nil,windowOpen=windowOpen,canAttack=canAttack,canThrow=canThrow})
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
		self.rotationAnchor = if Config.PaintRotationEnabled then self.pointer else nil
		self.brushFrame = nil
		self.visualGesture += 1
		self.finishPaint = false
		self:SamplePaint(os.clock())
	elseif input.KeyCode == Enum.KeyCode.Q then
		self:TakeTable()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not PersonalRules.FindWeapon(player.Character) and self.throw and self.throw:OnMouseBegan(input) then
			return
		end
		-- 先记录输入时间，原生提示仲裁占用的帧计入本地前摇。
		local inputTime=workspace:GetServerTimeNow()
		self.scope:Spawn(function(): ()
			RunService.Heartbeat:Wait()
			if self.initialized then self:Attack(inputTime) end
		end)
	end
end
function Client.OnMove(self: Client, input: InputObject): ()
	if self.throw and self.throw:OnInputChanged(input) then
		return
	end
	if self.visualClosing then return end
	if input ~= self.touch and (self.touch ~= nil or input.UserInputType ~= Enum.UserInputType.MouseMovement) then
		return
	end
	if self.ignoreMouseMove and input ~= self.touch then
		return
	end
	local hardware = Vector2.new(input.Position.X, input.Position.Y)
	self.pointer = if input == self.touch then hardware else PointerFromHardware(self, hardware)
end
function Client.OnRelease(self: Client, input: InputObject): ()
	if self.throw and self.throw:OnInputEnded(input) then
		return
	end
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
				if Config.PaintRotationEnabled then
					SnapPointerToBrush(self, hardware)
					local tip = self.pointer
					if tip and WarpMouseToTip(self, tip) then
						self.pointer = tip
						self.pointerOrigin = tip
						self.hardwareOrigin = tip
					elseif tip then
						self.hardwareOrigin = HardwareNow(hardware)
						self.catchHardwareOrigin = true
					end
				else
					self.pointerOrigin, self.hardwareOrigin = nil, nil
					self.catchHardwareOrigin = false
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
	if not Config.PaintRotationEnabled or self.visualClosing or not self.paintId then return end
	self.drawing = false
	self.finishPaint = #self.paintSamples > 0
	self.brushFrame, self.touch = nil, nil
	self.rotationAnchor = nil
	self.angularSpeed = 0
	self.orientation,self.sentOrientation=CFrame.identity,CFrame.identity
	Net.FireRequest({action="ResetView",session=self.session})
end
function Client.PlayAltarOutput(self: Client, output: Types.AltarOutput, slots: { [string]: CFrame }): ()
	if self.altarFx:PlayOutput(output, slots, workspace:GetServerTimeNow()) then
		Sound.Play("AltarComplete", self.altarFx.mouth.WorldPosition)
	end
end

function Client.UpdateAltar(self: Client, now: number): ()
	local earliest: number? = nil
	for id, item in self.items do
		if item.kind ~= "Body" or item.location ~= "Altar" then continue end
		local toss = item.altarToss
		local ends = item.convertEnds
		if toss and now >= toss.landEnds then ends = toss.landEnds + Config.ConversionSeconds end
		if ends and (not earliest or ends < earliest) then earliest = ends end

		if item.flyEnds then self.bodies:Fly(id, now) end
		local flash = self.completeFlash
		if toss then
			local t = math.clamp(1 - (toss.landEnds - now) / Physics.AltarToss.LandSeconds, 0, 1)
			if t > 0 then
				self.view:SetSacrifice(id, 0, t * t * (3 - 2 * t))
			end
		elseif item.flyEnds and (not flash or (flash.id ~= id and not table.find(flash.batch or {}, id))) then
			self.view:ClearSacrifice(id)
		end
	end

	local fx = self.altarFx
	local slots = if self.snapshot then self.snapshot.shelfItems else {}
	if fx:Step(self.items, earliest, slots, now) then
		Sound.Play("AltarPlace", fx.mouth.WorldPosition)
	end
	if earliest and not self.altarLoopSound then
		self.altarLoopSound = Sound.Play("AltarLoop", fx.mouth.WorldPosition, nil, true)
	elseif not earliest and self.altarLoopSound then
		Sound.Stop(self.altarLoopSound)
		self.altarLoopSound = nil
	end
end
function Client.UpdateAutomationViews(self: Client, snapshot: Types.Snapshot?): ()
	local rawCoins = player:GetAttribute("Coins")
	local coins = if typeof(rawCoins) == "number" then rawCoins else 0
	local unlocked = if snapshot then snapshot.unlockedFacilities else nil
	if padsFolder then
		for _, child in padsFolder:GetChildren() do
			if child:IsA("Model") then
				AutomationRules.SyncPad(child, unlocked, coins)
				local facilityId = child:GetAttribute("FacilityId")
				if typeof(facilityId) == "number" and facilityId >= 1 and facilityId % 1 == 0 then
					local guiAnchor = child:FindFirstChild("GuiAnchor")
					local bb = if guiAnchor then guiAnchor:FindFirstChild("PadGui") else nil
					if bb and bb:IsA("BillboardGui") then
						bb.AutoLocalize = false
					end
					local card = if bb then bb:FindFirstChild("CardFrame") else nil
					if card then
						local titleLabel = card:FindFirstChild("TitleText")
						local titleSource = AutomationRules.DescribeTitle(facilityId)
						if titleLabel and titleLabel:IsA("TextLabel") and titleSource then
							self.padTexts:BindSource(titleLabel, titleSource)
						end
						local descLabel = card:FindFirstChild("DescText")
						local descSource = AutomationRules.DescribeDesc(facilityId)
						if descLabel and descLabel:IsA("TextLabel") and descSource then
							self.padTexts:BindSource(descLabel, descSource)
						end
						local priceFrame = card:FindFirstChild("PriceFrame")
						local priceLabel = if priceFrame then priceFrame:FindFirstChild("PriceText") else nil
						local priceDesc = AutomationRules.DescribePrice(facilityId)
						if priceLabel and priceLabel:IsA("TextLabel") and priceDesc then
							self.padTexts:Bind(priceLabel, priceDesc)
						end
					end
				end
			end
		end
	end
	local serverNow = workspace:GetServerTimeNow()
	if autoRuneMachine then
		autoRuneMachine:SetAttribute("Working", snapshot ~= nil and (snapshot.autoRuneEnds or 0) > serverNow)
	end
	if autoSmelterMachine then
		autoSmelterMachine:SetAttribute("Working", snapshot ~= nil and (snapshot.autoSmelterEnds or 0) > serverNow)
	end
end
function Client.BindBruteNameplates(self: Client): ()
	local playerGui = player:WaitForChild("PlayerGui")
	local ui = ReplicatedStorage:WaitForChild("UI")
	local bindings: { [BasePart]: { gui: BillboardGui, label: TextLabel } } = {}
	local function OnAdded(instance: Instance): ()
		if instance.Name ~= "Head" or not instance:IsA("BasePart") or bindings[instance] then return end
		local agent = instance.Parent
		if not agent or not agent:IsA("Model") or agent:GetAttribute("AgentRole") ~= "Brute" then return end
		local agentId = agent:GetAttribute("AgentId")
		local facilityId: number? =
			if agentId == "HellBrute_1" then GameData.FacilityId.Brute1 elseif agentId == "HellBrute_2" then GameData.FacilityId.Brute2 else nil
		local facility = if facilityId then GameData.GetFacility(facilityId) else nil
		if not facility then return end
		local template = ui:FindFirstChild("BruteNameGui")
		if not template or not template:IsA("BillboardGui") then return end
		local nameplate = template:Clone()
		local label = nameplate.ContentFrame.NameText :: TextLabel
		nameplate.Adornee = instance
		nameplate.Parent = playerGui
		bindings[instance] = { gui = nameplate, label = label }
		self.scope:Own(nameplate)
		self.padTexts:BindSource(label, facility.name_t)
	end
	local function OnRemoving(instance: Instance): ()
		if not instance:IsA("BasePart") then return end
		local binding = bindings[instance]
		if binding then
			bindings[instance] = nil
			self.padTexts:Clear(binding.label)
			binding.gui:Destroy()
		end
	end
	self.scope:Connect(workspace.DescendantAdded:Connect(OnAdded))
	self.scope:Connect(workspace.DescendantRemoving:Connect(OnRemoving))
	local runtime = workspace:FindFirstChild("GameRuntime")
	local agents = runtime and runtime:FindFirstChild("AutomationAgents")
	if agents then
		for _, instance in agents:GetDescendants() do OnAdded(instance) end
	end
end
function Client.Init(self: Client, gui: ScreenGui): ()
	if self.initialized then
		return
	end
	self.initialized = true
	if not self.scope.alive then self.scope=Lifecycle.new() end
	if self.closeCameraHideWatch then
		self.closeCameraHideWatch()
	end
	self.closeCameraHideWatch = FixedCamera.WatchAndHide(district)
	self.ui:Init(gui)
	local modal = gui:FindFirstChild("ModalButton")
	self.touchJump = TouchJumpController.new(self.ui:GetJumpButton(), function(): boolean
		if not self.initialized or self.paintId ~= nil or UIManager.HasShowingWindow() or GuiService.MenuIsOpen then
			return false
		end
		if modal and modal:IsA("GuiObject") and modal.Visible then
			return false
		end
		return true
	end)
	self.closePersonalShop = PersonalShop.Init(gui, self.ui:GetSprintButton(), self.scope)
	self.worldInteraction = WorldInteractionManager.new(interactionAnchors, function(): WorldInteractionManager.State
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local modal = gui:FindFirstChild("ModalButton") :: GuiButton?
		return {snapshot=self.snapshot, items=self.items, held=self:Held(), carried=self:Carried(), potions=self:Potions(), enabled=self.initialized and self.synced and not self.paintId and humanoid ~= nil and humanoid.Health > 0 and not (modal and modal.Visible)}
	end)
	UIManager.GetTargetGuiManager():Init()
	self:BindBruteNameplates()
	local stick = self.ui:GetThrowStick()
	if stick then
		self.throw = ManualThrow.new(stick, {
			TopBody = function(): Types.ItemView?
				return self:Carried()[1]
			end,
			CanAim = function(): boolean
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not self.initialized or self.paintId ~= nil or not humanoid or humanoid.Health <= 0
					or PersonalRules.FindWeapon(character) then
					return false
				end
				if UIManager.HasShowingWindow() then
					return false
				end
				local modal = gui:FindFirstChild("ModalButton")
				if modal and modal:IsA("GuiObject") and modal.Visible then
					return false
				end
				if self.worldInteraction and self.worldInteraction:IsInputBlocked() then
					return false
				end
				return true
			end,
			CanStore = function(position: Vector3, _normal: Vector3?, _hitBaffle: boolean?, hitCageKind: string?): boolean
				local top = self:Carried()[1]
				local snapshot = self.snapshot
				if not top or top.stage == "Painted" or not snapshot then
					return false
				end
				local unlockedA00 = snapshot.unlockedFacilities ~= nil and snapshot.unlockedFacilities[GameData.FacilityId.FastChute] == true
				if hitCageKind == "Pool" or (unlockedA00 and hitCageKind == "Chute") then
					return true
				end
				local inPool = ThrowArc.InsidePoolStrict(poolFloor.CFrame, poolFloor.Size, position, Physics.PoolStackHeight)
				local inChute = if chuteDropZone
					then ThrowArc.InsideChuteLanding(chuteDropZone.CFrame, chuteDropZone.Size, position, Physics.ChuteStackHeight)
					else false
				local kind = ThrowArc.CanStoreThrow(unlockedA00, inPool, inChute, false, snapshot.pool, nil)
				return kind == "Pool" or kind == "Chute"
			end,
			ChuteBaffles = function(): Instance?
				local snapshot = self.snapshot
				if not snapshot or not snapshot.unlockedFacilities or not snapshot.unlockedFacilities[GameData.FacilityId.FastChute] then return nil end
				return if autoLine then autoLine:FindFirstChild("ChuteThrowBaffles") else nil
			end,
			CageTargets = function()
				local list = {
					{ kind = "Pool", frame = poolFloor.CFrame, size = poolFloor.Size, inset = Physics.Cage.PoolWallInset },
				}
				local snapshot = self.snapshot
				local unlockedA00 = snapshot ~= nil and snapshot.unlockedFacilities ~= nil and snapshot.unlockedFacilities[GameData.FacilityId.FastChute] == true
				if unlockedA00 and chuteDropZone then
					table.insert(list, { kind = "Chute", frame = chuteDropZone.CFrame, size = chuteDropZone.Size, inset = Physics.Cage.ChuteWallInset })
				end
				return list
			end,
			Ignored = function(): { Instance }
				local list: { Instance } = {}
				local character = player.Character
				if character then
					table.insert(list, character)
				end
				for _, item in self:Carried() do
					if item.model then
						table.insert(list, item.model)
					end
				end
				return list
			end,
		})
	end
	self.ui:BindActions({
		attack=function(): () self:Attack() end,
		exitPaint=function(): () self:RequestPaintEnd() end,
		resetView=function(): () self:ResetPaintView() end,
	})
	self.scope:Connect(Net.ConnectNotify(function(notice: Types.Notice): ()
		self:OnNotice(notice)
	end))
	self.scope:Connect(player:GetAttributeChangedSignal("Coins"):Connect(function(): ()
		if self.UpdateAutomationViews then
			self:UpdateAutomationViews(self.snapshot)
		end
	end))
	if self.UpdateAutomationViews then
		self:UpdateAutomationViews(self.snapshot)
	end
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
		elseif Config.PaintRotationEnabled then
			local hardware = HardwareFromPointer(self)
			if hardware then
				SnapPointerToBrush(self, hardware)
			end
		else
			self.pointerOrigin, self.hardwareOrigin = nil, nil
			self.catchHardwareOrigin = false
		end
		self.drawing, self.finishPaint, self.touch = false, true, nil
		self.brushFrame = nil
		self.rotationAnchor = nil
		self.angularSpeed = 0
	end
	self.scope:Connect(UserInputService.WindowFocusReleased:Connect(function(): ()
		OnPaintInputInterrupted()
		if self.throw then
			self.throw:Cancel()
		end
	end))
	self.scope:Connect(GuiService.MenuOpened:Connect(OnPaintInputInterrupted))
	self.scope:Connect(player.CharacterAdded:Connect(function(): ()
		self:CancelHitFeedback()
		self:ExitView()
		self.paintCamera:Exit(true)
		if self.throw then
			self.throw:Cancel()
		end
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
			self.bodies:SyncPaintBatch(tableSlotSpecs)
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
		local enabled=not self.paintId and not self:ShoulderOccupied() and humanoid~=nil and humanoid.Health>0 and character~=nil and PersonalRules.FindWeapon(character)~=nil
		self.hitView:UpdateCamera(now,enabled)
		self.hitView:UpdateEffects(now)
	end)
	self.scope:Connect(RunService.RenderStepped:Connect(function(dt): ()
		self.paintCamera:StepToss(workspace:GetServerTimeNow(), dt)
		self.potionShelf:Step(os.clock())
		if self.autoPotionShelf then
			self.autoPotionShelf:Step(os.clock())
		end
		if self.automationView then
			self.automationView:Step(self.snapshot, self.items, os.clock(), workspace:GetServerTimeNow())
		end
		self:Update(dt)
	end))
end
function Client.Destroy(self: Client): ()
	if self.touchJump then
		self.touchJump:Destroy()
		self.touchJump = nil
	end
	if self.throw then
		self.throw:Destroy()
		self.throw = nil
	end
	RunService:UnbindFromRenderStep("DemonShopHitCameraRestore")
	RunService:UnbindFromRenderStep("DemonShopHitCamera")
	self.hitView:Clear()
	self.hitState=HitRules.New()
	self:ExitView()
	RestoreHiddenPlayers(self)
	if self.completeFlash then
		SetBatchFlash(self.view, self.completeFlash.id, self.completeFlash.batch, nil)
		self.completeFlash = nil
	end
	if self.flipFlash then
		SetBatchFlash(self.view, self.flipFlash.id, self.flipFlash.batch, nil)
		self.flipFlash = nil
	end
	self.paintCamera:Destroy()
	self.ui:UnbindActions()
	self.padTexts:Destroy()
	UIManager.GetTargetGuiManager():Destroy()
	if self.worldInteraction then self.worldInteraction:Destroy(); self.worldInteraction = nil end
	if self.closePersonalShop then
		self.closePersonalShop()
		self.closePersonalShop = nil
	end
	if self.closeCameraHideWatch then
		self.closeCameraHideWatch()
		self.closeCameraHideWatch = nil
	end
	self.scope:Destroy()
	self.potionShelf:Destroy()
	if self.autoPotionShelf then
		self.autoPotionShelf:Destroy()
	end
	if self.automationView then
		self.automationView:Destroy()
		self.automationView = nil
	end
	if self.altarLoopSound then
		Sound.Stop(self.altarLoopSound)
		self.altarLoopSound = nil
	end
	self.altarFx:Destroy()
	self.ignoreMouseMove, self.catchHardwareOrigin = false, false
	self.bodies:Destroy()
	self.view:Destroy()
	self.presentation:Clear()
	self.characterView:Destroy()
	self.initialized = false
end
return Client
