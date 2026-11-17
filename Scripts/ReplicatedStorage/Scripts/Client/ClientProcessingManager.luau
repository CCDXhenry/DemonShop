-- 加工客户端：共享状态展示、键鼠触屏交互、工作台镜头及拖画旋转
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("GameTypes"))
local Hints = require(Shared:WaitForChild("Hints"))
local Surface = require(Shared:WaitForChild("PaintSurface"))
local Net = require(Shared:WaitForChild("ProcessingNet"))
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local TextFitting = require(script.Parent:WaitForChild("UIManager"):WaitForChild("TextFitting"))
local PaintPointer = require(script.Parent.PaintPointer)
local PaintView = require(script.Parent:WaitForChild("PaintView"))
local Presentation = require(script.Parent.BodyPresentation)
local CharacterPresentation = require(script.Parent.CharacterPresentation)
local PaintCamera = require(script.Parent.PaintCamera)
local VisualUpload = require(script.Parent.VisualUpload)
local Client = {}
Client.__index = Client
local player = Players.LocalPlayer
export type Client = typeof(setmetatable(
	{} :: {
		scope: Lifecycle.Lifecycle,
		view: PaintView.View,
		presentation: Presentation.Presentation,
		characterView: CharacterPresentation.Presentation,
		paintCamera: PaintCamera.Controller,
		visualUpload: VisualUpload.Upload,
		visualClosing: boolean,
		poseStarted: number,
		lastAttack: number,
		attackTarget: string?,
		comboEnds: number,
		targetGui: BillboardGui?,
		presentationId: string?,
		lastFrame: number,
		gui: ScreenGui?,
		root: Frame?,
		snapshot: Types.Snapshot?,
		items: { [string]: Types.ItemView },
		paintId: string?,
		session: string?,
		drawing: boolean,
		finishPaint: boolean,
		touch: InputObject?,
		pointer: Vector2,
		lastPointer: Vector2?,
		visualPointer: Vector2?,
		visualGesture: number,
		visualGap: boolean,
		yaw: number,
		pitch: number,
		sentYaw: number,
		sentPitch: number,
		lastPaint: number,
		paintSequence: number,
		rotationInput: Vector2,
		angularVelocity: Vector2,
		target: string?,
		targetVersion: number?,
		nearTable: boolean,
		lastSync: number,
		synced: boolean,
		paintPrevious: Types.Sample?,
		lastHint: number,
		messageEnds: number,
		touchGuiEnabled: boolean?,
		initialized: boolean,
	},
	Client
))
local district = workspace:WaitForChild("NeonContractDistrict")
local tableAnchor = district:WaitForChild("RuneBodyTable"):WaitForChild("BodyPlacementAnchor") :: BasePart
local tableInteract = district.RuneBodyTable:WaitForChild("TransferStartAnchor") :: BasePart
local function Anchor(station: string, name: string): BasePart
	return district:WaitForChild(station):WaitForChild(name) :: BasePart
end
local submitAnchor = district:WaitForChild("SummoningSubmitAnchor") :: BasePart
local positions: { [string]: Vector3 } = {
	Pool = Anchor("SoulHoldingPool", "PickupPointAnchor").Position,
	Table = tableInteract.Position,
	Altar = Anchor("SoulConversionAltar", "BodyArrivalAnchor").Position,
	Shelf = Anchor("SoulCrystalDisplay", "StockPickupAnchor").Position,
	Sigil = submitAnchor.Position,
}
local function TablePose(): CFrame
	return tableAnchor.CFrame * CFrame.new(0, 4, 0)
end
local function CameraPose(): CFrame
	local center = TablePose().Position
	return CFrame.lookAt(center + Vector3.new(0, 1, 12), center)
end
function Client.new(): Client
	return setmetatable(
		{
			scope = Lifecycle.new(),
			view = PaintView.new(),
			presentation = Presentation.new(),
			characterView = CharacterPresentation.new(),
			paintCamera = PaintCamera.new(),
			visualUpload = VisualUpload.new(),
			visualClosing = false,
			poseStarted = 0,
			lastAttack = 0,
			attackTarget = nil,
			comboEnds = 0,
			targetGui = nil,
			presentationId = nil,
			lastFrame = os.clock(),
			gui = nil,
			root = nil,
			snapshot = nil,
			items = {},
			paintId = nil,
			session = nil,
			drawing = false,
			finishPaint = false,
			touch = nil,
			pointer = Vector2.zero,
			lastPointer = nil,
			visualPointer = nil,
			visualGesture = 0,
			visualGap = true,
			yaw = 0,
			pitch = 0,
			sentYaw = 0,
			sentPitch = 0,
			lastPaint = 0,
			paintSequence = 0,
			rotationInput = Vector2.zero,
			angularVelocity = Vector2.zero,
			target = nil,
			targetVersion = nil,
			nearTable = false,
			lastSync = 0,
			synced = false,
			paintPrevious = nil,
			lastHint = 0,
			messageEnds = 0,
			touchGuiEnabled = nil,
			initialized = false,
		},
		Client
	)
end
function Client.Text(self: Client, name: string, text: string): ()
	local root = self.root
	if not root then
		return
	end
	local label = root:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
		TextFitting.FitTextLabel(label)
	end
end
function Client.Held(self: Client): Types.ItemView?
	for _, item in self.items do
		if item.holder == player.UserId then
			return item
		end
	end
	return nil
end
function Client.ExitView(self: Client): ()
	if not self.paintId then
		return
	end
	self.paintId = nil
	self.visualUpload:Clear()
	self.visualClosing = false
	self.session = nil
	self.drawing = false
	self.finishPaint = false
	self.lastPointer = nil
	self.visualPointer = nil
	self.visualGap = true
	self.paintPrevious = nil
	self.touch = nil
	self.rotationInput, self.angularVelocity = Vector2.zero, Vector2.zero
	self.paintCamera:Exit()
	local touchGui = player:WaitForChild("PlayerGui"):FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") and self.touchGuiEnabled ~= nil then
		touchGui.Enabled = self.touchGuiEnabled
	end
	self.touchGuiEnabled = nil
	local root = self.root
	if root then
		(root:FindFirstChild("PaintFrame") :: Frame).Visible = false
		(root:FindFirstChild("ExitPaintButton") :: GuiButton).Visible = false
		(root:FindFirstChild("ResetViewButton") :: GuiButton).Visible = false
	end
end
function Client.EnterView(self: Client, id: string, session: string): ()
	if self.paintId then
		self:ExitView()
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self.paintId, self.session = id, session
	self.visualUpload:Begin(session)
	self.visualClosing = false
	self.paintSequence = 0
	self.lastPaint = os.clock()
	self.yaw, self.pitch, self.sentYaw, self.sentPitch = 0, 0, 0, 0
	local touchGui = player:WaitForChild("PlayerGui"):FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") then
		self.touchGuiEnabled = touchGui.Enabled
		touchGui.Enabled = false
	end
	self.paintCamera:Enter(CameraPose())
	local root = self.root
	if root then
		(root:FindFirstChild("PaintFrame") :: Frame).Visible = true
		(root:FindFirstChild("ExitPaintButton") :: GuiButton).Visible = true
		(root:FindFirstChild("ResetViewButton") :: GuiButton).Visible = true
	end
end
function Client.OnNotice(self: Client, notice: Types.Notice): ()
	if (notice.kind == "State" or notice.kind == "Delta") and notice.snapshot then
		local snapshot = notice.snapshot
		if self.snapshot and snapshot.revision < self.snapshot.revision then
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
		if snapshot.painter ~= player.UserId then
			self.presentation.targetYaw = snapshot.poseYaw or 0
			self.presentation.targetPitch = snapshot.posePitch or 0
			self.presentation.targetBodyPose = snapshot.bodyPose
		end
		local nextItems: { [string]: Types.ItemView } = {}
		for _, item in snapshot.items do
			nextItems[item.id] = item
			if item.model then
				self.view:Bind(item.id, item.model)
			end
		end
		for id in self.items do
			if not nextItems[id] then
				self.view:Remove(id)
			end
		end
		self.items = nextItems
		table.clear(self.characterView.carriers)
		for _, item in nextItems do
			if item.holder and item.kind == "Body" then self.characterView.carriers[item.holder] = true end
		end
		if self.paintId and (snapshot.painter ~= player.UserId or snapshot.session ~= self.session) then
			self:ExitView()
		end
	elseif notice.kind == "Swing" and notice.actor and notice.started then
		-- 本地已预测；其他角色由 Animator 复制，确认通知不重复播放。
	elseif notice.kind == "SyncComplete" then
		self.synced = true
	elseif notice.kind == "PaintPose" and notice.id then
		-- 本地笔迹逐帧保留，确认不擦除；操作者的角度始终由本地输入驱动。
		local item = self.items[notice.id]
		if item then item.progress = notice.progress or item.progress end
		if notice.id ~= self.paintId and (notice.started or 0) >= self.poseStarted then
			self.poseStarted = notice.started or 0
			self.presentation.targetYaw = notice.yaw or 0
			self.presentation.targetPitch = notice.pitch or 0
			self.presentation.targetBodyPose = notice.bodyPose
		end
	elseif notice.kind == "VisualDelta" and notice.id and notice.segments then
		if not self.items[notice.id] then return end
		self.view:Apply(notice.id,notice.segments)
		if notice.session == self.session and notice.sequence then self.visualUpload:Ack(notice.sequence) end
		if notice.id ~= self.paintId and (notice.started or 0)>=self.poseStarted then
			self.poseStarted=notice.started or 0
			self.presentation.targetYaw,self.presentation.targetPitch=notice.yaw or 0,notice.pitch or 0
			self.presentation.targetBodyPose=notice.bodyPose
		end
	elseif notice.kind == "VisualSnapshot" and notice.id and notice.segments then
		if not self.items[notice.id] then return end
		self.view:Apply(notice.id,notice.segments)
	elseif notice.kind == "VisualRejected" and notice.session == self.session then
		self.visualUpload.blocked=true
		self.drawing=false
		self.visualClosing=true
		if notice.id then self.view:Remove(notice.id) end
		Net.FireRequest({action="EndPaint",session=self.session,sequence=notice.sequence or self.visualUpload.acked})
		self.synced=false
		self.lastSync=0
		self:Text("NoticeText",notice.text or "Paint sync failed. Please reconnect.")
		self.messageEnds=os.clock()+10
	elseif notice.kind == "FinishPaint" and notice.session == self.session then
		self:RequestPaintEnd()
	elseif notice.kind == "BeginPaint" and notice.id and notice.session then
		self:EnterView(notice.id, notice.session)
	elseif notice.kind == "EndPaint" and notice.session == self.session then
		self:ExitView()
	elseif notice.kind == "Message" and notice.text then
		self:Text("NoticeText", notice.text)
		self.messageEnds = os.clock() + 3
	end
end
function Client.RequestPaintEnd(self: Client): ()
	if not self.paintId or self.visualClosing then return end
	self.visualClosing=true
	self.visualUpload.closing=true
	-- 退出按钮位置不是落笔位置；只收尾已有手势，并冻结最后的画布端点。
	self.finishPaint=self.drawing or self.finishPaint
	if self.finishPaint then self.pointer=self.visualPointer or self.lastPointer or self.pointer end
	self.drawing=false
	self.touch=nil
	self.rotationInput,self.angularVelocity=Vector2.zero,Vector2.zero
end
function Client.Interact(self: Client): ()
	if not self.synced or self.paintId or not self.target then
		return
	end
	Net.FireRequest({ action = "Interact", target = self.target, version = self.targetVersion })
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
function Client.Attack(self: Client): ()
	local now = workspace:GetServerTimeNow()
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
	Net.FireRequest({ action = "Attack", target = if best then best.id else nil, version = if best then best.version else nil })
end
local function SamplePaintPath(model: Model, camera: Camera, from: Vector2, pointer: Vector2, spacing: number, maximum: number, gap: boolean): ({ Types.Sample }, boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local steps = math.clamp(math.ceil((pointer - from).Magnitude / spacing), 1, maximum - 1)
	local samples: { Types.Sample } = {}
	for index = 0, steps do
		local point = from:Lerp(pointer, index / steps)
		local ray = camera:ScreenPointToRay(point.X, point.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 100, params)
		if hit and hit.Instance:IsA("BasePart") and Surface.IsBody(hit.Instance) then
			local sample = Surface.Project(hit.Instance, hit.Position, hit.Normal)
			if Surface.Allowed(hit.Instance, sample.face) then
				sample.breakBefore = if gap then true else nil
				table.insert(samples, sample)
				gap = false
			else gap = true end
		else gap = true end
	end
	return samples, gap
end
function Client.Paint(self: Client, now: number): ()
	local id, session = self.paintId, self.session
	if not id or not session or not (self.drawing or self.finishPaint) then return end
	local item = self.items[id]
	local camera = workspace.CurrentCamera
	local model = self.presentation.model or (item and item.model)
	if not model or not camera then return end
	-- 每个显示帧立即补齐屏幕路径；跨帧同面追加，确认回包不替换本地笔迹。
	local visual, gap = SamplePaintPath(model, camera, self.visualPointer or self.pointer, self.pointer, Config.PaintVisualSamplePixels, Config.PaintVisualSamplesPerFrame, self.visualGap)
	self.visualPointer, self.visualGap = self.pointer, gap
	if #visual > 0 then
		self.view:DrawLocal(id,session,self.visualGesture,visual)
	end
	-- 覆盖率上报保持限频，单独采样当前姿态，不能用网络频率控制可见颜料。
	if now - self.lastPaint >= Config.PaintBatchInterval or self.finishPaint then
		self.lastPaint = now
		local samples = SamplePaintPath(model, camera, self.lastPointer or self.pointer, self.pointer, 8, 12, false)
		self.lastPointer = self.pointer
		local previous, last = self.paintPrevious, samples[#samples]
		local unchanged = #samples <= 2 and previous and last and last.part == previous.part and last.face == previous.face and last.triangle==previous.triangle and math.abs(last.u - previous.u) + math.abs(last.v - previous.v) < 0.001 and math.abs(self.yaw - self.sentYaw) + math.abs(self.pitch - self.sentPitch) < 0.001
		if #samples > 0 and not unchanged then
			self.paintPrevious = samples[#samples]
			if previous and #samples < 12 and not samples[1].breakBefore and previous.part == samples[1].part and previous.face == samples[1].face then table.insert(samples, 1, previous) end
			self.paintSequence += 1
			Net.FireRequest({action="Paint",session=session,sequence=self.paintSequence,samples=samples,yaw=self.yaw,pitch=self.pitch,bodyPose=self.presentation:CapturePose()})
			self.sentYaw, self.sentPitch = self.yaw, self.pitch
		elseif #samples == 0 then self.paintPrevious = nil end
	end
	if self.finishPaint then
		self.finishPaint = false
		self.lastPointer, self.visualPointer, self.paintPrevious = nil, nil, nil
		self.visualGap = true
		self.angularVelocity = Vector2.zero
	end
end
function Client.Update(self: Client): ()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local dt = math.min(now - self.lastFrame, 0.1)
	self.lastFrame = now
	local missingModel = false
	for _, item in self.items do
		if not item.model or not item.model.Parent then missingModel = true; break end
	end
	if (not self.synced or missingModel) and now - self.lastSync > 3 and player:GetAttribute("GameReady") == true then
		Net.FireRequest({ action = "Sync" })
		self.lastSync = now
	end
	if now > self.messageEnds then
		self:Text("NoticeText", "")
	end
	local curved=self.view.curved
	if self.paintId and curved and curved.failed and not curved.textures[self.paintId] then
		self:RequestPaintEnd()
		self:Text("NoticeText","PAINT SURFACE UNAVAILABLE. PLEASE TRY AGAIN.")
		self.messageEnds=now+5
	end
	if self.paintId then
		if self.drawing or self.finishPaint then
			local desired = self.rotationInput * Config.PaintSensitivity / math.max(dt, 0.001)
			if desired.Magnitude > Config.PaintAngularSpeed then desired = desired.Unit * Config.PaintAngularSpeed end
			self.angularVelocity = self.angularVelocity:Lerp(desired, 1 - math.exp(-Config.PaintRotationResponse * dt))
			self.yaw = (self.yaw + self.angularVelocity.X * dt + math.pi) % (2 * math.pi) - math.pi
			self.pitch = math.clamp(self.pitch + self.angularVelocity.Y * dt, -Config.PaintPitchLimit, Config.PaintPitchLimit)
		else
			self.angularVelocity = Vector2.zero
		end
		self.rotationInput = Vector2.zero
	end
	local snapshot = self.snapshot
	local tableItem = if snapshot and snapshot.tableId then self.items[snapshot.tableId] else nil
	if tableItem and tableItem.model and tableItem.location == "Table" then
		local display = self.presentation:Bind(tableItem.model,if self.paintId~=tableItem.id then self.presentation.targetBodyPose else nil)
		self.presentationId = tableItem.id
		self.view:Bind(tableItem.id, display)
		if self.paintId == tableItem.id then
			self.presentation.targetYaw, self.presentation.targetPitch = self.yaw, self.pitch
		end
		self.presentation:Update(TablePose(), dt, self.paintId == tableItem.id)
	elseif self.presentationId then
		local previous = self.items[self.presentationId]
		if previous and previous.model then self.view:Bind(previous.id, previous.model) end
		self.presentation:Clear()
		self.presentationId = nil
	end
	if self.root and camera then PaintPointer.Update(self.root, self.presentation.model, camera, self.pointer, self.paintId ~= nil and (not UserInputService.TouchEnabled or self.drawing)) end
	if self.paintId then
		local item = self.items[self.paintId]
		if item and item.model then
			self:Text("ProgressText", string.format("%d%%", math.floor(item.progress * 100)))
			if self.root then
				local fill = self.root:FindFirstChild("FillFrame", true)
				if fill and fill:IsA("Frame") then
					fill.Size = UDim2.fromScale(item.progress, 1)
				end
			end
		end

		if self.paintCamera.ready then self:Paint(now) end
	end
	-- 姿态和当前帧采样完成后再绘制，每帧统一消耗一次栅格化预算。
	self.view:Update(self.paintId)
	if self.paintId then
		self.visualUpload:Update(self.view:Drain(self.paintId),now,workspace:GetServerTimeNow(),self.yaw,self.pitch,self.visualClosing or not self.drawing,self.presentation:CapturePose(),not self.finishPaint and self.view:IsReady(self.paintId))
		if self.view.budgetReached then
			self:Text("NoticeText","PAINT SEGMENT LIMIT REACHED")
			self.messageEnds=now+3
			self.view.budgetReached=false
		end
	end
	if now - self.lastHint < 0.1 then
		return
	end
	self.lastHint = now
	self:Text("CoinsText", string.format("COINS  %d", player:GetAttribute("Coins") or 0))
	local held = self:Held()
	if self.targetGui then
		local focused = if self.attackTarget then self.items[self.attackTarget] else nil
		local head = focused and focused.model and focused.model:FindFirstChild("Head")
		self.targetGui.Enabled = not self.paintId and not held and focused ~= nil and focused.location == "Street" and head ~= nil
		if head and head:IsA("BasePart") then self.targetGui.Adornee = head end
		local text = self.targetGui:FindFirstChild("CountText", true)
		if focused and text and text:IsA("TextLabel") then text.Text = if focused.hits >= Config.StunHits then "STUNNED  [E]" else string.format("HIT %d / %d", focused.hits, Config.StunHits) end
	end
	self:Text(
		"CarryText",
		if held
			then (if held.kind == "Potion" then "CARRYING POTION" elseif held.stage == "Painted" then "CARRYING RUNE BODY" else "CARRYING BODY")
			else "HANDS EMPTY"
	)

	if snapshot then
		local stock = string.format("POOL %d/8  |  POTIONS %d/8", snapshot.pool, snapshot.shelf)
		if snapshot.altarId then
			local seconds = math.max(0, math.ceil(snapshot.altarEnds - workspace:GetServerTimeNow()))
			stock = if seconds > 0 then string.format("ALTAR %ds  |  POTIONS %d/8", seconds, snapshot.shelf) else "ALTAR READY - SHELF FULL"
		end
		self:Text("StockText", stock)
	end
	local root = self.root
	if not root then
		return
	end
	local touch = UserInputService.TouchEnabled
	local painting = self.paintId ~= nil
	for _, name in { "InteractButton", "DropButton", "AttackButton" } do
		(root:FindFirstChild(name) :: GuiButton).Visible = not painting and not touch
	end
	(root:FindFirstChild("ExitPaintButton") :: GuiButton).Visible = painting and not touch;
	(root:FindFirstChild("ResetViewButton") :: GuiButton).Visible = painting and not touch
	if self.gui and camera then
		(self.gui:FindFirstChild("TouchLandscapeFrame") :: Frame).Visible = touch and not painting and camera.ViewportSize.X >= camera.ViewportSize.Y;
		(self.gui:FindFirstChild("TouchPortraitFrame") :: Frame).Visible = touch and not painting and camera.ViewportSize.X < camera.ViewportSize.Y;
		(self.gui:FindFirstChild("TouchPaintFrame") :: Frame).Visible = touch and painting
	end
	if self.paintId then
		self:Text("HintText", "DRAG ON THE BODY TO PAINT + ROTATE")
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	self.target = nil
	self.targetVersion = nil
	self.nearTable = false
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local best = Config.InteractionRange
	for name, position in positions do
		local distance = (hrp.Position - position).Magnitude
		if name == "Table" and distance < Config.InteractionRange then
			self.nearTable = true
		end
		if distance < best then
			best = distance
			self.target = name
			self.targetVersion = if snapshot then snapshot.stationVersions[name] else nil
		end
	end
	if not held then
		for _, item in self.items do
			if (item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits)) and item.model and item.model.PrimaryPart then
				local distance = (hrp.Position - item.model.PrimaryPart.Position).Magnitude
				if distance < best then
					best = distance
					self.target = item.id
					self.targetVersion = item.version
				end
			end
		end
	end
	local target = self.target
	self:Text("HintText", if target then "E  " .. Hints.Action(target, snapshot, held, player.UserId) else Hints.Next(snapshot, held))
	local drop = root:FindFirstChild("DropButton") :: GuiButton
	local dropText = drop:FindFirstChild("LabelText") :: TextLabel
	local text = if not held and self.nearTable and snapshot and snapshot.tableId then "Q  TAKE TABLE BODY" else "Q  DROP"
	if dropText.Text ~= text then
		dropText.Text = text
		TextFitting.FitTextLabel(dropText)
	end
end
function Client.OnInput(self: Client, input: InputObject, processed: boolean): ()
	if self.visualClosing then return end
	if processed then
		return
	end
	if self.paintId and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		self.drawing = true
		self.pointer = Vector2.new(input.Position.X, input.Position.Y)
		self.lastPointer = self.pointer
		self.visualPointer = self.pointer
		self.visualGesture += 1
		self.visualGap = true
		self.paintPrevious = nil
		self.finishPaint = false
		if input.UserInputType == Enum.UserInputType.Touch then
			self.touch = input
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		self:Interact()
	elseif input.KeyCode == Enum.KeyCode.Q then
		self:Drop()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		self:Attack()
	end
end
function Client.OnMove(self: Client, input: InputObject): ()
	if self.visualClosing then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= self.touch then
		return
	end
	local point = Vector2.new(input.Position.X, input.Position.Y)
	if self.paintId and self.drawing then
		local delta = point - self.pointer
		-- 只有笔尖仍落在身体上时才驱动旋转，单批旋转有界并与服务端一致。
		local item = self.items[self.paintId]
		local camera = workspace.CurrentCamera
		if item and item.model and camera then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { self.presentation.model or item.model }
			local ray = camera:ScreenPointToRay(point.X, point.Y)
			if workspace:Raycast(ray.Origin, ray.Direction * 100, params) then
				if delta.Magnitude >= Config.PaintDeadzonePixels then self.rotationInput += delta end
			end
		end
	end
	self.pointer = point
end
function Client.OnRelease(self: Client, input: InputObject): ()
	if self.visualClosing then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input == self.touch then
		if self.drawing then
			self.pointer = Vector2.new(input.Position.X, input.Position.Y)
			self.finishPaint = true
		end
		self.drawing = false
		self.angularVelocity = Vector2.zero
		self.touch = nil
	end
end
function Client.ResetPaintView(self: Client): ()
	if self.visualClosing or not self.paintId then return end
	self.yaw,self.pitch,self.sentYaw,self.sentPitch=0,0,0,0
	Net.FireRequest({action="ResetView",session=self.session})
end
function Client.Init(self: Client, gui: ScreenGui): ()
	if self.initialized then
		return
	end
	self.initialized = true
	self.gui = gui
	local targetGui = (ReplicatedStorage.UI:WaitForChild("TargetGui") :: BillboardGui):Clone()
	targetGui.Parent = player:WaitForChild("PlayerGui")
	self.targetGui = targetGui
	self.scope:Own(targetGui)
	local root = gui:WaitForChild("CenterFrame") :: Frame
	self.root = root
	for _, v in gui:GetDescendants() do
		if v:IsA("TextLabel") then
			TextFitting.FitTextLabel(v)
		end
	end
	self.scope:Connect(Net.ConnectNotify(function(notice: Types.Notice): ()
		self:OnNotice(notice)
	end))
	self.scope:Connect((root:WaitForChild("InteractButton") :: GuiButton).Activated:Connect(function(): ()
		self:Interact()
	end))
	self.scope:Connect((root:WaitForChild("DropButton") :: GuiButton).Activated:Connect(function(): ()
		self:Drop()
	end))
	self.scope:Connect((root:WaitForChild("AttackButton") :: GuiButton).Activated:Connect(function(): ()
		self:Attack()
	end))
	self.scope:Connect((root:WaitForChild("ExitPaintButton") :: GuiButton).Activated:Connect(function(): ()
		self:RequestPaintEnd()
	end))
	self.scope:Connect((root:WaitForChild("ResetViewButton") :: GuiButton).Activated:Connect(function(): ()
		self:ResetPaintView()
	end))
	for _, frameName in { "TouchLandscapeFrame", "TouchPortraitFrame", "TouchPaintFrame" } do
		local controls = gui:WaitForChild(frameName)
		for _, button in controls:GetChildren() do
			if button:IsA("GuiButton") then
				self.scope:Connect(button.Activated:Connect(function(): ()
					if button.Name == "InteractButton" then
						self:Interact()
					elseif button.Name == "DropButton" then
						self:Drop()
					elseif button.Name == "AttackButton" then
						self:Attack()
					elseif button.Name == "ExitPaintButton" then
						self:RequestPaintEnd()
					else
						self:ResetPaintView()
					end
				end))
			end
		end
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
	self.scope:Connect(player.CharacterAdded:Connect(function(): ()
		self:ExitView()
		self.paintCamera:Exit(true)
	end))
	self.scope:Connect(RunService.PreAnimation:Connect(function(): ()
		self.characterView:Restore()
	end))
	self.scope:Connect(RunService.PreSimulation:Connect(function(): ()
		self.characterView:Apply(workspace:GetServerTimeNow())
	end))
	self.scope:Connect(RunService.RenderStepped:Connect(function(): ()
		self:Update()
	end))
end
function Client.Destroy(self: Client): ()
	self:ExitView()
	self.paintCamera:Destroy()
	self.scope:Destroy()
	self.view:Destroy()
	self.presentation:Clear()
	self.characterView:Destroy()
	self.gui,self.root=nil,nil
	self.initialized = false
end
return Client
