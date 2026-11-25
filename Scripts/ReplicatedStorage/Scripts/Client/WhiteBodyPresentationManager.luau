-- 按 ItemId 管理白膜可见性、关节控制权、工位兼容控制器与流送重绑。
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GameConfig = require(script.Parent.Parent.Shared.GameConfig)
local Physics = require(script.Parent.Parent.Shared.PhysicsConfig)
local ThrowArc = require(script.Parent.Parent.Shared.ThrowArc)
local HitRules = require(script.Parent.Parent.Shared.HitFeedbackRules)
local Types = require(script.Parent.Parent.Shared.GameTypes)
local Adapter = require(script.Parent.JointAdapter)
local TableView = require(script.Parent.BodyPresentation)
local HitView = require(script.Parent.HitPresentation)
local Tuning = require(script.Parent.PresentationTuning)
local Contact = require(script.Parent.SoftContact)
local Impact = require(script.Parent.ImpactReaction)
local Mixer = require(script.Parent.PoseMixer)
local Fall = require(script.Parent.LocalRagdoll)
local Input = game:GetService("UserInputService")
local Manager = {}
Manager.__index = Manager
type AuthorityHandoff = {
	started: number, duration: number, version: number, fromRoot: CFrame, sourceRoot: BasePart,
	altar: boolean,
	parts: {{visual: BasePart, source: BasePart, from: CFrame}},
}
type LocalAltarPart = {
	visual: BasePart,
	source: BasePart,
	fromOffset: CFrame,
	restOffset: CFrame,
	lag: number,
	swingAngle: number,
}
type LocalAltarToss = {
	started: number,
	flightStarts: number,
	flightEnds: number,
	landEnds: number,
	fromRoot: CFrame,
	restRoot: CFrame,
	fromTable: boolean,
	settled: boolean,
	parts: { LocalAltarPart },
}
type BodyView = {
	id: string, authorityModel: Model, visualModel: Model?, bindGeneration: number, appliedVersion: number,
	fall: Fall.State?, history: Fall.History?, sampleDt: number?,
	handoff: AuthorityHandoff?,
	altarToss: LocalAltarToss?,
	offsets: {[string]: CFrame}, modelSince: number, boundAt: number, impacts: Impact.State, finalVersion: number?, mode: string, requested: string, jointMap: Adapter.Map, sourceJoints: Adapter.Map, rootTarget: BasePart?,
	physicsMask: {[string]: boolean}, predictionTokens: {[number]: HitRules.Prediction},
	cleanup: {RBXScriptConnection}, hidden: {[BasePart]: number}, dirty: boolean, retryAt: number, diagnostic: string?,
}
export type Manager = typeof(setmetatable({} :: {
	views: {[string]: BodyView}, items: {[string]: Types.ItemView}, enabled: boolean, destroyed: boolean,
	contactEnabled: boolean, impactEnabled: boolean, fallEnabled: boolean, pureModel: boolean, contacts: {[string]: Contact.State},
	retiredAt: {[string]: number}, lastPositions: {[BasePart]: Vector3}, queries: number,
	generation: number, step: number, tableView: TableView.Presentation, hitView: HitView.Presentation,
	onDisplay: (string, Model?) -> (), phases: {RBXScriptConnection}, debugEndpoint: BindableFunction?,
	flyOrigin: { [string]: CFrame }, rootMissingAt: { [string]: number }, rootWarned: { [string]: boolean },
}, Manager))
function Manager.new(tableView: TableView.Presentation, hitView: HitView.Presentation, onDisplay: (string, Model?) -> ()): Manager
	local self: Manager = setmetatable({views={}, items={}, enabled=true, destroyed=false, generation=0, step=0,
		contacts={}, retiredAt={}, lastPositions={}, queries=0, contactEnabled=true, impactEnabled=true, fallEnabled=true, pureModel=false,
		tableView=tableView, hitView=hitView, onDisplay=onDisplay, phases={}, flyOrigin={}, rootMissingAt={}, rootWarned={}}, Manager)
	hitView.managed = function(id, source)
		local v = self.views[id]
		return v ~= nil and v.mode == "Street" and v.authorityModel == source
	end
	return self
end
function Manager.GetAuthorityModel(self: Manager, id: string): Model?
	local item = self.items[id]
	local model = item and item.model
	return if model and model:IsDescendantOf(workspace) then model else nil
end
function Manager.GetVisualModel(self: Manager, id: string): Model?
	local v = self.views[id]
	return (v and v.visualModel) or self:GetAuthorityModel(id)
end
function Manager.GetVisualPart(self: Manager, id: string, name: string): BasePart?
	local model = self:GetVisualModel(id)
	local part = model and model:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end
function Manager.GetPaintModel(self: Manager, id: string): Model?
	return self:GetVisualModel(id)
end
function Manager.GetAltarModel(self: Manager, id: string): Model?
	local view = self.views[id]
	return if view and view.mode == "Altar" then view.visualModel else nil
end
function Manager.IsAltarTossing(self: Manager, id: string, now: number): boolean
	local view = self.views[id]
	local toss = view and view.altarToss
	if not toss then return false end
	return not toss.settled and now < toss.landEnds
end
local function Release(self: Manager, v: BodyView)
	self.views[v.id] = nil
	self.contacts[v.id]=nil
	v.handoff = nil
	v.altarToss = nil
	table.clear(v.impacts)
	for part, value in v.hidden do part.LocalTransparencyModifier = value end
	table.clear(v.hidden)
	for _, connection in v.cleanup do connection:Disconnect() end
	table.clear(v.cleanup)
	self.hitView:Remove(v.id)
	if v.visualModel then
		if self.tableView.model == v.visualModel then self.tableView:Clear() end
		v.visualModel:Destroy()
		v.visualModel = nil
	end
	table.clear(v.jointMap)
	table.clear(v.sourceJoints)
	for _,prediction in v.predictionTokens do prediction.resolved=true; prediction.retired=true end
	table.clear(v.predictionTokens)
end
function Manager.Unbind(self: Manager, id: string)
	local v = self.views[id]
	if self.items[id] and not self.destroyed then self.retiredAt[id]=workspace:GetServerTimeNow() end
	self.items[id] = nil
	self.flyOrigin[id] = nil
	self.rootMissingAt[id] = nil
	self.rootWarned[id] = nil
	if v then Release(self,v); self.onDisplay(id,nil) end
end
local function HasPrimaryRoot(model: Model): boolean
	local root = model.PrimaryPart
	return root ~= nil and root.Name == "HumanoidRootPart" and root:IsDescendantOf(model)
end
local function Mode(item: Types.ItemView, source: Model, enabled: boolean): string
	if item.toss then return "Authority" end
	if item.location == "Table" then return "Table" end
	if item.location == "Altar" then
		return if enabled then "Altar" else "Authority"
	end
	if item.location == "Carried" or source:GetAttribute("PhysicsMode") == "Carried" or source:GetAttribute("MotionState") == "Carried" then return "Authority" end
	if enabled and item.fall and (item.location=="Ground" or (item.location=="Street" and item.hits>=GameConfig.StunHits)) then return "Ground" end
	if enabled and item.location=="Street" and item.hits<GameConfig.StunHits and source:GetAttribute("GroundPresentation")==true then return "Street" end
	if enabled and item.location == "Street" and item.hits < GameConfig.StunHits
		and (source:GetAttribute("PhysicsMode")==nil or source:GetAttribute("PhysicsMode")=="Walking") and source:GetAttribute("MotionState") ~= "Down" then return "Street" end
	return "Authority"
end
local function Sanitize(parent: Instance, clone: Model, anchorAll: boolean, keepSockets: boolean)
	for _, node in parent:GetChildren() do
		if node:IsA("LuaSourceContainer") or node:IsA("Humanoid") or node:IsA("Animator") or node:IsA("AnimationController")
			or node:IsA("ProximityPrompt") or node:IsA("LayerCollector") or node:IsA("BodyMover")
			or node:IsA("WeldConstraint") or (node:IsA("JointInstance") and not node:IsA("Motor6D"))
			or node.Name=="CarryResources" or node.Name=="CarryAnchor" or node.Name=="StaggerAttachment" or node.Name=="WhiteBodyShoulder"
			or (node:IsA("Constraint") and not node:IsA("AnimationConstraint") and not (keepSockets and node:IsA("BallSocketConstraint")))
			or (node:IsA("NoCollisionConstraint") and not keepSockets) then
			node:Destroy()
			continue
		elseif node:IsA("BasePart") then
			node.Anchored = anchorAll or node == clone.PrimaryPart
			node.CanCollide, node.CanTouch, node.CanQuery = false, false, false
			node.Massless = true
		end
		Sanitize(node,clone,anchorAll,keepSockets)
	end
end
local function Prepare(self: Manager, v: BodyView, receivedPose: Types.BodyPose?)
	local source = v.authorityModel
	v.sourceJoints = Adapter.Map(source)
	local clone = source:Clone()
	assert(clone, "source is not archivable")
	v.visualModel = clone
	local clonedRoot = clone:FindFirstChild("HumanoidRootPart")
	if not HasPrimaryRoot(clone) and clonedRoot and clonedRoot:IsA("BasePart") then clone.PrimaryPart = clonedRoot end
	clone.Name = if v.requested == "Table" then "LocalRuneBody" elseif v.requested == "Altar" then "LocalAltarBody" else "LocalWhiteBody"
	local forTable = v.requested == "Table"
	local forAltar = v.requested == "Altar"
	Sanitize(clone,clone,forTable or forAltar,forTable)
	v.jointMap = Adapter.Map(clone)
	v.rootTarget = source.PrimaryPart
	if forTable then
		self.tableView:Attach(source,clone,v.jointMap.Root.drive,receivedPose)
	elseif forAltar or v.requested=="Ground" then
		if forAltar then
			for _, joint in v.jointMap do
				local drive = joint.drive
				if drive:IsA("Motor6D") then
					drive.Enabled = false
				else
					drive.IsKinematic, drive.Enabled = true, false
				end
			end
		end
		for _, node in source:GetDescendants() do
			if node:IsA("BasePart") then
				local copy = clone:FindFirstChild(node.Name, true)
				if copy and copy:IsA("BasePart") then copy.CFrame = node.CFrame end
			end
		end
	else
		for name, joint in v.jointMap do
			local original = v.sourceJoints[name]
			assert(Adapter.IsKinematic(original), "authority no longer kinematic at "..name)
			joint.child.CFrame = original.child.CFrame
			Adapter.Write(joint,Adapter.Read(original))
		end
	end
	local root, target = clone.PrimaryPart, v.rootTarget
	assert(root and target, "lost root during bind")
	root.CFrame = target.CFrame
	-- Clone may not copy non-replicated local properties. Transfer each current display value explicitly.
	for _, node in source:GetDescendants() do
		if node:IsA("BasePart") then
			local copy = clone:FindFirstChild(node.Name)
			assert(copy and copy:IsA("BasePart"), "missing visual part "..node.Name)
			v.hidden[node] = node.LocalTransparencyModifier
			copy.LocalTransparencyModifier = node.LocalTransparencyModifier
		end
	end
	clone.Parent = workspace
	for part in v.hidden do part.LocalTransparencyModifier = 1 end
	v.mode = v.requested
	return true
end
local function BeginFall(self: Manager,v: BodyView,fall: Types.GroundFall,late: boolean)
	local cfg=Tuning.GetEffectiveConfig()
	local cap=math.floor(if Input.TouchEnabled then cfg.Fall.MobileBodies else cfg.Fall.DesktopBodies)
	local active=if self.tableView.dynamic then 1 else 0
	for _,other in self.views do if other.fall and other.fall.active then active+=1 end end
	local camera=workspace.CurrentCamera
	local near=camera and (camera.CFrame.Position-fall.target.Position).Magnitude<=cfg.Fall.NearStuds
	local root=assert(assert(v.visualModel).PrimaryPart)
	local settled=late or near~=true or workspace:GetServerTimeNow()-fall.started>cfg.Fall.PhysicsSeconds
	local state=Fall.Begin(root,v.jointMap,fall,v.history or {},v.sampleDt or 0,cfg,self.fallEnabled and active<cap,settled)
	v.fall,v.physicsMask=state,state.mask
	v.history=nil
	v.mode,v.requested="Ground","Ground"
	self.contacts[v.id]=nil
	table.clear(v.impacts)
	table.clear(v.offsets)
	self.hitView:Remove(v.id)
end
local function BeginHandoff(v: BodyView, version: number, duration: number, altar: boolean): boolean
	local visual = v.visualModel
	local visualRoot = visual and visual.PrimaryPart
	local sourceRoot = v.authorityModel.PrimaryPart
	if not visual or visual.Parent ~= workspace or not visualRoot or not sourceRoot then return false end
	local handoff: AuthorityHandoff = {
		started=workspace:GetServerTimeNow(), duration=duration, version=version, altar=altar,
		fromRoot=visualRoot.CFrame, sourceRoot=sourceRoot, parts={},
	}
	for part in v.hidden do
		local copy = visual:FindFirstChild(part.Name)
		if not copy or not copy:IsA("BasePart") or not part:IsDescendantOf(v.authorityModel) then return false end
		table.insert(handoff.parts, {visual=copy, source=part, from=handoff.fromRoot:ToObjectSpace(copy.CFrame)})
	end
	if v.fall then Fall.StopPhysics(v.fall, v.jointMap) end
	for _, joint in v.jointMap do
		local drive = joint.drive
		if drive:IsA("Motor6D") then
			drive.Enabled = false
		else
			drive.IsKinematic, drive.Enabled = true, false
		end
	end
	for _, part in handoff.parts do
		part.visual.Anchored = true
		part.visual.CanCollide = false
	end
	v.fall, v.history = nil, nil
	v.mode, v.requested = if altar then "AltarHandoff" else "CarryHandoff", "Authority"
	v.handoff = handoff
	return true
end

local function StepHandoff(v: BodyView, handoff: AuthorityHandoff, now: number): boolean
	local duration = handoff.duration
	if now >= handoff.started + duration or handoff.sourceRoot ~= v.authorityModel.PrimaryPart then return false end
	local t = math.clamp((now - handoff.started) / duration, 0, 1)
	local alpha = t * t * (3 - 2 * t)
	local sourceRoot = handoff.sourceRoot.CFrame
	local root = handoff.fromRoot:Lerp(sourceRoot, alpha)
	for _, part in handoff.parts do
		if part.visual.Parent ~= v.visualModel or part.source.Parent ~= v.authorityModel then return false end
		part.visual.CFrame = root * part.from:Lerp(sourceRoot:ToObjectSpace(part.source.CFrame), alpha)
	end
	return true
end

local function SmoothStep(t: number): number
	local clamped = math.clamp(t, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

local function LimbInertia(name: string): (number, number)
	if name == "HumanoidRootPart" or name == "LowerTorso" or name == "UpperTorso" then
		return 0, 0
	elseif name == "Head" then
		return 0.35, 0.14
	elseif string.find(name, "Upper") then
		return 0.55, 0.22
	elseif string.find(name, "Lower") then
		return 0.80, 0.30
	end
	return 1.0, 0.36
end

local function PartRestOffset(visual: BasePart, source: BasePart, sourceRoot: BasePart): CFrame
	if visual.Name == "HumanoidRootPart" then
		return CFrame.identity
	end
	local rest = visual:GetAttribute("RestPose") or source:GetAttribute("RestPose")
	if typeof(rest) == "CFrame" then
		return rest
	end
	return sourceRoot.CFrame:ToObjectSpace(source.CFrame)
end

local function DisableAltarJointDrives(v: BodyView): ()
	for _, joint in v.jointMap do
		local drive = joint.drive
		if drive:IsA("Motor6D") then
			drive.Enabled = false
		else
			drive.IsKinematic, drive.Enabled = true, false
		end
	end
end

local function ApplyAltarSettledPose(v: BodyView, toss: LocalAltarToss): ()
	local visual = v.visualModel
	local visualRoot = visual and visual.PrimaryPart
	if not visual or visual.Parent ~= workspace or not visualRoot then return end
	visualRoot.CFrame = toss.restRoot
	for _, part in toss.parts do
		if part.visual.Parent == visual then
			part.visual.CFrame = toss.restRoot * part.restOffset
		end
	end
	toss.settled = true
end

local function StepAltarToss(v: BodyView, item: Types.ItemView, now: number): ()
	local toss = v.altarToss
	local visual = v.visualModel
	local visualRoot = visual and visual.PrimaryPart
	if not toss or toss.settled or not visual or visual.Parent ~= workspace or not visualRoot then return end
	if item.altarToss then
		toss.restRoot = item.altarToss.rest
	elseif v.authorityModel.PrimaryPart then
		toss.restRoot = v.authorityModel.PrimaryPart.CFrame
	end
	if now >= toss.landEnds then
		ApplyAltarSettledPose(v, toss)
		return
	end
	local altarCfg = Physics.AltarToss
	local liftHeight = if toss.fromTable then altarCfg.LiftHeight else 0
	local launchRoot = toss.fromRoot + Vector3.yAxis * liftHeight
	local dropRoot = toss.restRoot + Vector3.yAxis * altarCfg.DropClearance
	local rootCFrame: CFrame
	local limbProgress = 0
	local limbPitch = 0
	if now < toss.flightStarts then
		local span = math.max(toss.flightStarts - toss.started, 0.001)
		local raw = math.clamp((now - toss.started) / span, 0, 1)
		local alpha = SmoothStep(raw)
		rootCFrame = toss.fromRoot + Vector3.yAxis * (liftHeight * alpha)
		limbProgress = alpha * 0.35
		limbPitch = -math.sin(raw * math.pi) * 0.55
	elseif now < toss.flightEnds then
		local span = math.max(toss.flightEnds - toss.flightStarts, 0.001)
		local raw = math.clamp((now - toss.flightStarts) / span, 0, 1)
		local alpha = SmoothStep(raw)
		local base = launchRoot:Lerp(dropRoot, alpha)
		local arc = 4 * alpha * (1 - alpha) * altarCfg.ArcHeight
		rootCFrame = base + Vector3.yAxis * arc
		limbProgress = (if toss.fromTable then 0.35 else 0) + alpha * (if toss.fromTable then 0.50 else 0.85)
		limbPitch = math.sin(raw * math.pi) * 0.75
	else
		local span = math.max(toss.landEnds - toss.flightEnds, 0.001)
		local raw = math.clamp((now - toss.flightEnds) / span, 0, 1)
		local touchSplit = 0.45
		if raw < touchSplit then
			local fallT = raw / touchSplit
			local fallAlpha = fallT * fallT
			rootCFrame = dropRoot:Lerp(toss.restRoot, fallAlpha)
		else
			local impactT = (raw - touchSplit) / (1 - touchSplit)
			local bounce = math.sin(impactT * math.pi) * (1 - impactT) * (altarCfg.LandBounceStuds or 0.14)
			rootCFrame = toss.restRoot + Vector3.yAxis * bounce
		end
		limbProgress = 0.85 + SmoothStep(raw) * 0.15
		limbPitch = -math.sin(raw * math.pi) * (1 - raw) * 0.65
	end
	visualRoot.CFrame = rootCFrame
	for _, part in toss.parts do
		if part.visual.Parent ~= visual then continue end
		local delayed = math.clamp((limbProgress - part.lag * 0.12) / math.max(1 - part.lag * 0.12, 0.001), 0, 1)
		local localFrame = part.fromOffset:Lerp(part.restOffset, SmoothStep(delayed))
		if part.swingAngle > 0 and math.abs(limbPitch) > 1e-4 then
			localFrame = localFrame * CFrame.Angles(limbPitch * part.swingAngle, 0, 0)
		end
		part.visual.CFrame = rootCFrame * localFrame
	end
end

local function BeginAltarToss(v: BodyView, item: Types.ItemView, fromTable: boolean): boolean
	local visual = v.visualModel
	local visualRoot = visual and visual.PrimaryPart
	local sourceRoot = v.authorityModel.PrimaryPart
	if not visual or visual.Parent ~= workspace or not visualRoot or not sourceRoot then return false end
	local tossInfo = item.altarToss
	local started = if tossInfo then tossInfo.started else item.altarTossStarted
	if started == nil then
		v.altarToss = nil
		return false
	end
	DisableAltarJointDrives(v)
	local visualTorso = visual:FindFirstChild("UpperTorso")
	local sourceTorso = v.authorityModel:FindFirstChild("UpperTorso")
	local fromRoot = visualRoot.CFrame
	if fromTable then
		if visualTorso and visualTorso:IsA("BasePart") and sourceTorso and sourceTorso:IsA("BasePart") then
			local torsoRest = PartRestOffset(visualTorso, sourceTorso, sourceRoot)
			fromRoot = visualTorso.CFrame * torsoRest:Inverse()
			visualRoot.CFrame = fromRoot
		end
	elseif tossInfo then
		fromRoot = tossInfo.from
		visualRoot.CFrame = fromRoot
	end
	local altarCfg = Physics.AltarToss
	local flightStarts = if tossInfo then tossInfo.flightStarts else started + (if fromTable then altarCfg.LiftSeconds else 0)
	local flightEnds = flightStarts + altarCfg.FlightSeconds
	local landSeconds = altarCfg.LandSeconds or 0.32
	local landEnds = if tossInfo and tossInfo.landEnds then tossInfo.landEnds else flightEnds + landSeconds
	local restRoot = if tossInfo then tossInfo.rest else sourceRoot.CFrame
	local parts: { LocalAltarPart } = {}
	for part in v.hidden do
		local copy = visual:FindFirstChild(part.Name)
		if not copy or not copy:IsA("BasePart") or not part:IsDescendantOf(v.authorityModel) then return false end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanTouch = false
		copy.CanQuery = false
		copy.AssemblyLinearVelocity = Vector3.zero
		copy.AssemblyAngularVelocity = Vector3.zero
		local lag, swingAngle = LimbInertia(copy.Name)
		local fromOffset = if fromTable
			then fromRoot:ToObjectSpace(copy.CFrame)
			else sourceRoot.CFrame:ToObjectSpace(part.CFrame)
		table.insert(parts, {
			visual = copy,
			source = part,
			fromOffset = fromOffset,
			restOffset = PartRestOffset(copy, part, sourceRoot),
			lag = lag,
			swingAngle = swingAngle,
		})
	end
	v.altarToss = {
		started = started,
		flightStarts = flightStarts,
		flightEnds = flightEnds,
		landEnds = landEnds,
		fromRoot = fromRoot,
		restRoot = restRoot,
		fromTable = flightStarts > started,
		settled = false,
		parts = parts,
	}
	return true
end

local function SyncAltarToss(v: BodyView, item: Types.ItemView): ()
	local tossInfo = item.altarToss
	local started = if tossInfo then tossInfo.started else item.altarTossStarted
	local current = v.altarToss
	if not current then
		if started ~= nil then
			BeginAltarToss(v, item, false)
		end
		return
	end
	if tossInfo then
		current.restRoot = tossInfo.rest
		current.flightStarts = tossInfo.flightStarts
		current.flightEnds = tossInfo.flightStarts + Physics.AltarToss.FlightSeconds
		current.landEnds = tossInfo.landEnds
		current.fromTable = tossInfo.flightStarts > tossInfo.started
	elseif started == nil and item.convertEnds ~= nil and v.authorityModel.PrimaryPart then
		current.restRoot = v.authorityModel.PrimaryPart.CFrame
	end
end

local function TransitionTableToAltar(self: Manager, v: BodyView, item: Types.ItemView): boolean
	local visual = v.visualModel
	if not visual or visual.Parent ~= workspace or not HasPrimaryRoot(visual) then return false end
	if self.tableView.model == visual then
		self.tableView:Clear()
	end
	visual.Name = "LocalAltarBody"
	DisableAltarJointDrives(v)
	for _, node in visual:GetDescendants() do
		if node:IsA("BasePart") then
			node.Anchored = true
			node.CanCollide, node.CanTouch, node.CanQuery = false, false, false
			node.Massless = true
			node.AssemblyLinearVelocity = Vector3.zero
			node.AssemblyAngularVelocity = Vector3.zero
		end
	end
	v.handoff = nil
	v.fall, v.history = nil, nil
	v.mode, v.requested = "Altar", "Altar"
	v.appliedVersion = item.version
	BeginAltarToss(v, item, true)
	return true
end

function Manager.Bind(self: Manager, item: Types.ItemView, receivedPose: Types.BodyPose?)
	if self.destroyed then return end
	local id = item.id
	if item.kind ~= "Body" then
		if self.items[id] then self:Unbind(id) end
		return
	end
	local previous = self.items[id]
	if previous and previous.version > item.version then return end
	self.items[id] = item
	local source = self:GetAuthorityModel(id)
	local v: BodyView? = self.views[id]
	if not source then
		self.rootMissingAt[id] = nil
		self.rootWarned[id] = nil
		if v then Release(self,v); self.onDisplay(id,source) end
		return
	end
	local mode = Mode(item, source, self.enabled)
	local carried = item.location == "Carried" or item.location == "BruteCarried"
	if v and v.handoff then
		local handoff = v.handoff
		local expected = handoff.version
		-- 物理属性与快照可能先后抵达，只接受本次拾取。
		local matching = if handoff.altar then item.location == "Altar" and item.version == expected
			elseif carried then item.version == expected
			else item.version == expected - 1 and item.version == v.appliedVersion
		if self.enabled and v.authorityModel == source and mode == "Authority" and matching
			and v.visualModel and v.visualModel.Parent == workspace then
			return
		end
		Release(self, v)
		v = nil
	elseif self.enabled and v and v.mode == "Ground" and v.authorityModel == source and mode == "Authority"
		and not item.toss and (carried or (item.version == v.appliedVersion and item.fall)) then
		local version = if carried then item.version else item.version + 1
		if BeginHandoff(v, version, Physics.CarryStack.HandoffSeconds, false) then return end
	end
	if mode ~= "Authority" and not HasPrimaryRoot(source) then
		local since = self.rootMissingAt[id]
		if not since then
			self.rootMissingAt[id] = os.clock()
		elseif not self.rootWarned[id] and os.clock() - since >= 2 then
			self.rootWarned[id] = true
			warn("[WhiteBody]", id, if v then v.bindGeneration else self.generation, "missing HumanoidRootPart primary root")
		end
		return
	end
	self.rootMissingAt[id] = nil
	self.rootWarned[id] = nil
	if v and v.authorityModel == source and v.mode == "Table" and mode == "Altar" and not v.dirty
		and (not v.diagnostic or os.clock() < v.retryAt) and v.visualModel and v.visualModel.Parent == workspace then
		if TransitionTableToAltar(self, v, item) then
			return
		end
	end
	if v and v.authorityModel == source and v.requested == mode and not v.dirty
		and (not v.diagnostic or os.clock() < v.retryAt) and (not v.visualModel or v.visualModel.Parent == workspace) then
		v.appliedVersion = item.version
		if mode == "Altar" then
			SyncAltarToss(v, item)
		end
		return
	end
	if mode=="Ground" and item.fall and v and v.mode=="Street" and not v.dirty and v.authorityModel==source and v.visualModel and v.visualModel.Parent==workspace then
		BeginFall(self,v,item.fall,false)
		v.appliedVersion=item.version
		return
	end
	local boundAt=if previous or v then workspace:GetServerTimeNow() else self.retiredAt[id] or -math.huge
	local sameModelTransition=v and not v.dirty and v.authorityModel==source and v.requested~=mode
	local modelSince=if v and sameModelTransition then v.modelSince else boundAt
	local priorDiagnostic = v and v.diagnostic
	if v then Release(self,v) end
	self.generation += 1
	local generation = self.generation
	local view: BodyView = {id=id, authorityModel=source, visualModel=nil, bindGeneration=generation, appliedVersion=item.version,
		offsets={}, modelSince=modelSince, boundAt=boundAt, impacts={}, mode="Authority", requested=mode, jointMap={}, sourceJoints={}, rootTarget=source.PrimaryPart,
		physicsMask={}, predictionTokens={}, cleanup={}, hidden={}, dirty=false, retryAt=0, diagnostic=nil}
	self.views[id] = view
	if mode ~= "Authority" then
		local ok, reason = pcall(function()
			Prepare(self,view,receivedPose)
			if mode=="Ground" and item.fall then
				BeginFall(self,view,item.fall,true)
			elseif mode == "Altar" then
				BeginAltarToss(view, item, false)
			end
		end)
		if not ok then
			Release(self,view)
			view.diagnostic = tostring(reason)
			view.retryAt = os.clock() + 2
			if priorDiagnostic ~= view.diagnostic then warn("[WhiteBody]", id, generation, view.diagnostic) end
			self.views[id] = view
		end
		local function OnStructure(node: Instance)
			local current = self.views[id]
			if not current or current.bindGeneration ~= generation then return end
			if node:IsA("BasePart") or node:IsA("Motor6D") or node:IsA("AnimationConstraint") or node:IsA("Attachment") then current.dirty = true end
		end
		table.insert(view.cleanup,source.DescendantAdded:Connect(OnStructure))
		table.insert(view.cleanup,source.DescendantRemoving:Connect(OnStructure))
		table.insert(view.cleanup,source:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			OnStructure(source.PrimaryPart or view.rootTarget or source)
		end))
	end
	self.onDisplay(id,self:GetPaintModel(id))
	if item.location == "Altar" and item.flyEnds then self:Fly(id, workspace:GetServerTimeNow()) end
end
function Manager.Fly(self: Manager, id: string, now: number): ()
	local item = self.items[id]
	local v = self.views[id]
	local visual = v and v.visualModel
	local landing = v and v.authorityModel:GetPivot()
	if not item or not v or not visual or not visual.Parent or not landing or not item.flyEnds then return end
	if now >= item.flyEnds then
		visual:PivotTo(landing)
		self.flyOrigin[id] = nil
		return
	end
	local origin = self.flyOrigin[id]
	if not origin then
		origin = CFrame.new(landing.Position + Vector3.new(0, GameConfig.PaintFlyHeight, 0)) * landing.Rotation
		self.flyOrigin[id] = origin
	end
	local span = math.max(GameConfig.PaintFlySeconds, 0.001)
	local alpha = math.clamp(1 - (item.flyEnds - now) / span, 0, 1)
	local smooth = alpha * alpha * (3 - 2 * alpha)
	local posed = origin:Lerp(landing, smooth)
	visual:PivotTo(CFrame.new(posed.Position + Vector3.yAxis * math.sin(smooth * math.pi) * GameConfig.PaintFlyHeight) * posed.Rotation)
end
function Manager.UpdateState(self: Manager, items: {[string]: Types.ItemView}, tablePose: Types.BodyPose?)
	-- Release the departing table controller before attaching the next occupant, independent of map order.
	for id, v in self.views do
		local nextItem = items[id]
		if not nextItem then self:Unbind(id)
		else
			if nextItem.location == "Altar" and nextItem.flyEnds and workspace:GetServerTimeNow() < nextItem.flyEnds and not self.flyOrigin[id] and v.visualModel and v.visualModel.Parent then
				self.flyOrigin[id] = v.visualModel:GetPivot()
			end
			if v.mode == "Table" and (nextItem.location ~= "Table" or nextItem.model ~= v.authorityModel) then
				if self.enabled and nextItem.location == "Altar" and nextItem.model == v.authorityModel
					and not v.dirty and v.visualModel and v.visualModel.Parent == workspace then
					self.items[id] = nextItem
					TransitionTableToAltar(self, v, nextItem)
				else
					-- 同一 ItemId 的笔迹保留到新展示模型。
					Release(self,v)
					if not nextItem.model or not nextItem.model:IsDescendantOf(workspace) then self.onDisplay(id,nil) end
				end
			end
		end
	end
	for id in self.items do if not items[id] then self:Unbind(id) end end
	for _, item in items do self:Bind(item,tablePose) end
end
function Manager.TrackPrediction(self: Manager, id: string, sequence: number, prediction: HitRules.Prediction)
	local v = self.views[id]
	if v then v.predictionTokens[sequence] = prediction else prediction.resolved = true end
end
function Manager.SetEnabled(self: Manager, enabled: boolean)
	if self.destroyed or self.enabled == enabled then return end
	self.enabled = enabled
	if not enabled then table.clear(self.lastPositions); self.queries=0 end
	for _,item in self.items do self:Bind(item) end
end
function Manager.Restore(self: Manager)
	for _,v in self.views do
		if v.mode == "Street" and self.items[v.id].hits<GameConfig.StunHits-1 then
			for name,joint in v.jointMap do
				if joint.applied then
					if Adapter.IsKinematic(v.sourceJoints[name]) then Adapter.Restore(joint) else joint.applied=nil end
				end
			end
		end
	end
end
local function Key(actor: number, sequence: number): string
	return tostring(actor).."/"..tostring(sequence)
end
function Manager.AcceptNotice(self: Manager, id: string, version: number, hits: number, started: number): boolean
	local v,item=self.views[id],self.items[id]
	if not v or not item or v.dirty or started<v.modelSince or version<v.appliedVersion or v.authorityModel~=item.model then return false end
	if hits>=GameConfig.StunHits then return item.location=="Street" or item.location=="Ground" end
	return not v.finalVersion and Mode(item,v.authorityModel,true)=="Street"
end
function Manager.Hit(self: Manager, id: string, actor: number, sequence: number?, version: number, hits: number,
	direction: Vector3, position: Vector3, started: number, confirmed: boolean, replay: boolean)
	local v=self.views[id]
	if not v or v.mode~="Street" or not self.impactEnabled then return false end
	if not v.rootTarget or v.dirty or v.finalVersion or version<v.appliedVersion or started<v.boundAt then return true end
	if v.authorityModel:GetAttribute("PhysicsMode")=="Loose" then return true end
	if confirmed and hits>=GameConfig.StunHits then v.finalVersion=version end
	local key=if sequence then Key(actor,sequence) else "version/"..version
	Impact.Input(v.impacts,key,v.sourceJoints,v.rootTarget.CFrame,position,direction,hits,started,confirmed,replay,(Tuning.GetEffectiveConfig()))
	return true
end
function Manager.Reject(self: Manager, id: string?, actor: number, sequence: number)
	local v=if id then self.views[id] else nil
	if v then Impact.Reject(v.impacts,Key(actor,sequence)) end
end
function Manager.SetLayer(self: Manager, layer: string, enabled: boolean)
	if layer=="SoftContact" then
		if self.contactEnabled==enabled then return end
		self.contactEnabled=enabled
		if not enabled then
			table.clear(self.contacts); table.clear(self.lastPositions); self.queries=0
			for _,v in self.views do table.clear(v.offsets) end
		end
	elseif layer=="LocalRagdoll" then
		self.fallEnabled=enabled
		if not enabled then
			for _,v in self.views do
				if v.fall and v.fall.active then Fall.StopPhysics(v.fall,v.jointMap) end
			end
		end
	elseif layer=="ImpactReaction" then
		if self.impactEnabled==enabled then return end
		self.impactEnabled=enabled
		for id,v in self.views do table.clear(v.impacts); table.clear(v.offsets); self.hitView:Remove(id) end
	end
end
local function UpdateContact(self: Manager, dt: number)
	local cfg=Tuning.GetEffectiveConfig()
	local camera=workspace.CurrentCamera
	if not camera then return end
	local bodies: {Contact.Body}={}
	local actors: {Contact.Actor}={}
	local positions: {[BasePart]: Vector3}={}
	local function Actor(part: BasePart): Vector3
		local previous=self.lastPositions[part] or part.Position
		positions[part]=part.Position
		table.insert(actors,{part=part,previous=previous,radius=math.max(part.Size.X*0.48,part.Size.Z*0.5)})
		return previous
	end
	for _,player in Players:GetPlayers() do
		local character=player.Character
		local torso=character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
		if torso and torso:IsA("BasePart") then Actor(torso) end
	end
	for id,v in self.views do
		if v.mode~="Street" or not v.rootTarget or v.dirty then continue end
		local torso=v.sourceJoints.Waist.child
		if (torso.Position-camera.CFrame.Position).Magnitude>cfg.LOD.NearStuds then self.contacts[id]=nil; continue end
		table.insert(bodies,{id=id,torso=torso,root=v.rootTarget,previous=Actor(torso)})
	end
	self.queries=Contact.Update(bodies,actors,self.contacts,dt,cfg)
	self.lastPositions=positions
end
local function ArcPosition(from: Vector3, to: Vector3, alpha: number): Vector3
	local mid = (from + to) * 0.5 + Vector3.new(0, Physics.PoolTossArcHeight, 0)
	return from:Lerp(mid, alpha):Lerp(mid:Lerp(to, alpha), alpha)
end
local function DrivePoolToss(item: Types.ItemView, now: number): ()
	local toss = item.toss
	local player = Players.LocalPlayer
	local model = item.model
	if not toss or not player or toss.owner ~= player.UserId or not model or not model.Parent then return end
	local root = model.PrimaryPart
	if (root and root.Anchored) or model:GetAttribute("MotionState") == "ChutePile" then return end
	local launchOrigin = toss.origin
	local launchVelocity = toss.velocity
	local manual = toss.kind == "Manual" and launchOrigin ~= nil and launchVelocity ~= nil
	local duration = if manual then (toss.duration or Physics.ManualThrow.PreviewDurationSeconds) else Physics.PoolTossSeconds
	local elapsed = now - toss.started
	local dropFrom = toss.chuteDropFrom
	if dropFrom and elapsed >= duration then
		local point = ThrowArc.DropPosition(dropFrom, toss.target.Position, workspace.Gravity, elapsed - duration)
		model:PivotTo(CFrame.new(point) * toss.target.Rotation)
		return
	end
	if elapsed < duration then
		local rotation = toss.from.Rotation
		local position: Vector3
		if manual and launchOrigin and launchVelocity then
			position = ThrowArc.Position(launchOrigin, launchVelocity, workspace.Gravity, math.max(elapsed, 0))
			local floor = toss.target.Position.Y
			if position.Y < floor then
				position = Vector3.new(position.X, floor, position.Z)
			end
		else
			local alpha = if duration <= 0 then 1 else elapsed / duration
			position = ArcPosition(toss.from.Position, toss.target.Position, alpha)
			rotation = toss.from.Rotation:Lerp(toss.target.Rotation, alpha)
		end
		model:PivotTo(CFrame.new(position) * rotation)
		return
	end
	if model:GetAttribute("PoolTossLaunched") == toss.started then return end
	model:SetAttribute("PoolTossLaunched", toss.started)
	model:PivotTo(toss.target)
	local velocity = Vector3.new(0, -Physics.PoolDropSpeed, 0)
	local spin = Vector3.zero
	if toss.wallStop then
		velocity = Vector3.zero
	elseif manual and launchVelocity then
		velocity = ThrowArc.Velocity(launchVelocity, workspace.Gravity, duration)
		if velocity.Magnitude > Physics.MaximumLinearSpeed then
			velocity = velocity.Unit * Physics.MaximumLinearSpeed
		end
		velocity = ThrowArc.LimitDrop(velocity)
	else
		local limit = Physics.PoolSpin
		spin = Vector3.new((math.random() * 2 - 1) * limit, (math.random() * 2 - 1) * limit, (math.random() * 2 - 1) * limit)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			part.AssemblyLinearVelocity = velocity
			part.AssemblyAngularVelocity = spin
		end
	end
end
function Manager.Step(self: Manager, now: number, seconds: number, painting: boolean?)
	if self.destroyed then return end
	self.step += 1
	local dt=seconds
	for id,at in self.retiredAt do if now-at>GameConfig.HitPredictionLifetime then self.retiredAt[id]=nil end end
	for _,item in self.items do self:Bind(item) end
	if self.enabled and self.contactEnabled then UpdateContact(self,dt) end
	local cfg=Tuning.GetEffectiveConfig()
	local available=math.floor(if Input.TouchEnabled then cfg.Fall.MobileBodies else cfg.Fall.DesktopBodies)-(if painting or self.tableView.dynamic then 1 else 0)
	for _,item in self.items do
		DrivePoolToss(item, now)
		local v = self.views[item.id]
		if not v then continue end
		local handoff = v.handoff
		if handoff then
			if not StepHandoff(v, handoff, now) then
				Release(self, v)
				self:Bind(item)
			end
			continue
		end
		if v.mode == "Altar" and v.altarToss and not v.altarToss.settled then
			StepAltarToss(v, item, now)
			continue
		end
		for sequence,prediction in v.predictionTokens do
			if now>prediction.expires then v.predictionTokens[sequence]=nil end
		end
		if v.fall then
			if v.fall.sleepPose then continue end
			if v.fall.active then
				local camera=workspace.CurrentCamera
				if available<=0 or not camera or (camera.CFrame.Position-v.fall.target.Position).Magnitude>cfg.Fall.NearStuds+4 then
					Fall.StopPhysics(v.fall,v.jointMap)
				else
					available-=1
				end
			end
			debug.profilebegin("WhiteBody.Fall")
			Fall.Step(v.fall,v.jointMap,dt)
			debug.profileend()
			continue
		end
		if v.mode ~= "Street" then continue end
		if v.authorityModel:GetAttribute("GroundPresentation")==true and (v.authorityModel:GetAttribute("PhysicsMode")~="Walking" or (v.rootTarget and v.rootTarget.CFrame.UpVector.Y<.5)) then continue end
		if item.hits>=GameConfig.StunHits-1 then
			local history=v.history or {}
			Fall.Sample(v.jointMap,history)
			v.history,v.sampleDt=history,dt
		end
		local root = v.visualModel and v.visualModel.PrimaryPart
		if not root or not v.rootTarget then v.dirty = true; continue end
		root.CFrame = v.rootTarget.CFrame
		local rotations: {[string]: Vector3}?=nil
		local shift=Vector3.zero
		if self.impactEnabled and next(v.impacts) then rotations,shift=Impact.Step(v.impacts,now+dt,cfg) end
		local legacy=if self.impactEnabled then nil else function(name: string) return self.hitView:Sample(v.id,name,now) end
		Mixer.Commit(v.jointMap,v.sourceJoints,v.physicsMask,root.CFrame,self.contacts[v.id],rotations,shift,legacy,self.step,v.offsets,dt,cfg.Limits.AngularSpeed)
	end
end
function Manager.GetDebugStats(self: Manager)
	local views = {}
	local connections = 0
	for _,connection in self.phases do if connection.Connected then connections += 1 end end
	for id,v in self.views do
		local joints = {}
		local map = v.jointMap
		local visual = v.visualModel
		local tableController = visual ~= nil and self.tableView.model == visual
		local streetController = visual ~= nil and (v.mode == "Street" or v.mode=="Ground")
		local altarController = visual ~= nil and v.mode == "Altar"
		local authorityController = not visual and v.authorityModel:IsDescendantOf(workspace)
		if authorityController and not v.diagnostic then
			-- Bypass has no retained rig/connection cache. Inspect it only for an explicit diagnostics request.
			local ok, authorityMap = pcall(Adapter.Map,v.authorityModel)
			if ok then map=authorityMap end
		end
		for name,joint in map do
			local owner = v.mode
			local submissions = if joint.step == self.step then joint.submissions else 0
			if tableController then
				owner=if self.tableView.dynamic and name ~= "Root" then "Physics" else "Table"
			elseif altarController then
				owner="Altar"
			elseif authorityController then
				local drive=joint.drive
				if not Adapter.IsKinematic(joint) then owner="AuthorityPhysics"
				elseif drive:IsA("Motor6D") and self.hitView.offsets[drive] then owner="LegacyHit"; submissions=1
				else owner="AuthorityAnimation" end
			elseif v.physicsMask[name] then owner="Physics" end
			joints[name] = {owner=owner, submissions=submissions}
		end
		local controllers=(if streetController or v.handoff then 1 else 0)+(if tableController then 1 else 0)+(if altarController then 1 else 0)+(if authorityController then 1 else 0)
		local contact=self.contacts[id]
		local touches,springs,pulses,predictions={},{},{},{}
		for sequence,p in v.predictionTokens do predictions[sequence]={due=p.due,played=p.played,resolved=p.resolved} end
		if contact then
			for part,touch in contact.touches do table.insert(touches,{part=part.Name,actor=if part.Parent then part.Parent.Name else nil,normal=touch.normal,speed=touch.speed,strength=touch.strength,phase=touch.phase}) end
			for name,spring in contact.springs do springs[name]={position=spring.Position,velocity=spring.Velocity} end
		end
		for key,pulse in v.impacts do pulses[key]={point=pulse.point,started=pulse.started,age=pulse.age,confirmed=pulse.confirmed,rejected=pulse.rejected,
			gain=pulse.gain,position=pulse.channels[1].Position,velocity=pulse.channels[1].Velocity} end
		views[id] = {contact=if contact then contact.phase else "Exit",touches=touches,springs=springs,pulses=pulses,predictions=predictions,controllers=controllers, mode=v.mode, physicsMode=v.authorityModel:GetAttribute("PhysicsMode"), generation=v.bindGeneration,
			weights={contact=if contact then 1 else 0,impact=if next(v.impacts) then 1 else 0,base=1},
			fallActive=v.fall and v.fall.active, asleep=v.fall and v.fall.sleepPose~=nil, sockets=v.fall and #v.fall.sockets,
			version=v.appliedVersion, joints=joints, connections=#v.cleanup, diagnostic=v.diagnostic}
	end
	local _,revision=Tuning.GetEffectiveConfig()
	return {queries=self.queries,revision=revision,contactEnabled=self.contactEnabled,impactEnabled=self.impactEnabled,pureModel=self.pureModel,
		views=views, runServiceConnections=connections, step=self.step}
end
-- Studio 插件与游戏使用独立 require 缓存，以客户端本地函数访问实际运行实例。
function Manager.OpenStudioDebug(self: Manager)
	if not RunService:IsStudio() or not RunService:IsClient() or self.debugEndpoint then return end
	local endpoint = Instance.new("BindableFunction")
	endpoint.Name = "StudioDebug"
	endpoint.OnInvoke = function(command: string, value: unknown, revision: number?)
		if (command=="SoftContact" or command=="ImpactReaction" or command=="LocalRagdoll") and typeof(value)=="boolean" then self:SetLayer(command,value); return true end
		if command=="PureModel" and typeof(value)=="boolean" then self.pureModel=value; self.hitView:ResetCamera(); return true end
		if command == "Stats" then return self:GetDebugStats() end
		if command == "SetEnabled" and typeof(value) == "boolean" then self:SetEnabled(value); return true end
		if command == "ApplyOverrides" and revision then return Tuning.ApplyOverrides(value,revision) end
		if command == "GetEffectiveConfig" then return Tuning.GetEffectiveConfig() end
		if command == "Reset" then Tuning.Reset(); return true end
		return false
	end
	self.debugEndpoint = endpoint
	endpoint.Parent = script
end
function Manager.Destroy(self: Manager)
	if self.destroyed then return end
	self.destroyed = true
	table.clear(self.lastPositions)
	for id in self.items do self:Unbind(id) end
	table.clear(self.retiredAt)
	self.hitView.managed = nil
	for _,connection in self.phases do connection:Disconnect() end
	table.clear(self.phases)
	if self.debugEndpoint then self.debugEndpoint:Destroy(); self.debugEndpoint=nil end
end
return Manager
