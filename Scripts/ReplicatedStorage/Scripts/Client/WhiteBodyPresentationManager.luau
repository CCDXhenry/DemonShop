-- 按 ItemId 管理白膜可见性、关节控制权、工位兼容控制器与流送重绑。
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GameConfig = require(script.Parent.Parent.Shared.GameConfig)
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
type BodyView = {
	id: string, authorityModel: Model, visualModel: Model?, bindGeneration: number, appliedVersion: number,
	fall: Fall.State?, history: Fall.History?, sampleDt: number?,
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
}, Manager))
function Manager.new(tableView: TableView.Presentation, hitView: HitView.Presentation, onDisplay: (string, Model?) -> ()): Manager
	local self: Manager = setmetatable({views={}, items={}, enabled=true, destroyed=false, generation=0, step=0,
		contacts={}, retiredAt={}, lastPositions={}, queries=0, contactEnabled=true, impactEnabled=true, fallEnabled=true, pureModel=false,
		tableView=tableView, hitView=hitView, onDisplay=onDisplay, phases={}}, Manager)
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
local function Release(self: Manager, v: BodyView)
	self.views[v.id] = nil
	self.contacts[v.id]=nil
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
	if v then Release(self,v); self.onDisplay(id,nil) end
end
local function Mode(item: Types.ItemView, source: Model, enabled: boolean): string
	if item.location == "Table" then return "Table" end
	if item.location == "Altar" then return "Altar" end
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
	clone.Name = if v.requested == "Table" then "LocalRuneBody" elseif v.requested == "Altar" then "LocalAltarBody" else "LocalWhiteBody"
	local forTable = v.requested == "Table"
	local forAltar = v.requested == "Altar"
	Sanitize(clone,clone,forTable or forAltar,forTable)
	v.jointMap = Adapter.Map(clone)
	v.rootTarget = source.PrimaryPart
	if forTable then
		self.tableView:Attach(source,clone,v.jointMap.Root.drive,receivedPose)
	elseif forAltar or v.requested=="Ground" then
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
	local v = self.views[id]
	if not source then
		if v then Release(self,v); self.onDisplay(id,source) end
		return
	end
	local mode = Mode(item, source, self.enabled)
	if v and v.authorityModel == source and v.requested == mode and not v.dirty
		and (not v.diagnostic or os.clock() < v.retryAt) and (not v.visualModel or v.visualModel.Parent == workspace) then
		v.appliedVersion = item.version
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
			if mode=="Ground" and item.fall then BeginFall(self,view,item.fall,true) end
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
end
function Manager.UpdateState(self: Manager, items: {[string]: Types.ItemView}, tablePose: Types.BodyPose?)
	-- Release the departing table controller before attaching the next occupant, independent of map order.
	for id, v in self.views do
		local nextItem = items[id]
		if not nextItem then self:Unbind(id)
		elseif v.mode == "Table" and (nextItem.location ~= "Table" or nextItem.model ~= v.authorityModel) then
			-- Same id keeps its atlas across this synchronous handoff.
			Release(self,v)
			if not nextItem.model or not nextItem.model:IsDescendantOf(workspace) then self.onDisplay(id,nil) end
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
		local v = self.views[item.id]
		if not v then continue end
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
		local controllers=(if streetController then 1 else 0)+(if tableController then 1 else 0)+(if altarController then 1 else 0)+(if authorityController then 1 else 0)
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
