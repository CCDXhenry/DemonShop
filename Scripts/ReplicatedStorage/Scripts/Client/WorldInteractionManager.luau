-- 原生世界交互管理器：维护玩家私有提示、状态失效取消、网络请求和生命周期
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local Rules = require(Shared.WorldInteractionRules)
local Types = require(Shared.GameTypes)
local GameTexts = require(Shared.GameTexts)
local Config = require(Shared.GameConfig)
local Net = require(Shared.ProcessingNet)
local Lifecycle = require(Shared.LifecycleTool)
local TranslationTool = require(ReplicatedStorage.Core.Scripts.Client.TranslationTool)
local InputReleaseGraceSeconds = 0.1
local Manager = {}
Manager.__index = Manager
type PromptParent = BasePart | Model
type Binding = { prompt: ProximityPrompt, scope: Lifecycle.Lifecycle, defaultHoldDuration: number, signature: string, holding: Rules.Action?, textValid: boolean, isDynamic: boolean }
type CachedItem = {
	kind: string,
	stage: string,
	location: string,
	version: number,
	hits: number,
	holder: number?,
	model: Model?,
	hasParent: boolean,
	hasPrimary: boolean,
}
type RefreshCache = {
	enabled: boolean,
	hasSnapshot: boolean,
	revision: number?,
	pool: number?,
	shelf: number?,
	tableId: string?,
	painter: number?,
	stationVersions: { [string]: number },
	stationVersionCount: number,
	heldId: string?,
	heldVersion: number?,
	heldKind: string?,
	heldStage: string?,
	carriedCount: number,
	carriedIds: { string },
	carriedVersions: { number },
	carriedKinds: { string },
	carriedStages: { string },
	potionEquipped: boolean,
	itemCount: number,
	items: { [string]: CachedItem },
	anchorAttached: { [string]: boolean },
}
export type State = { snapshot: Types.Snapshot?, items: {[string]: Types.ItemView}, held: Types.ItemView?, carried: {Types.ItemView}?, potions: Rules.Potions?, enabled: boolean }
export type Manager = typeof(setmetatable({} :: {
	bindings: {[string]: Binding}, anchors: {[string]: BasePart}, readState: () -> State, suppressUntil: number, recovering: boolean, cache: RefreshCache?,
}, Manager))
function Manager.new(anchors: {[string]: BasePart}, readState: () -> State): Manager
	return setmetatable({bindings={}, anchors=anchors, readState=readState, suppressUntil=0, recovering=false, cache=nil}, Manager)
end
function Manager.GetTemplatePrompt(self: Manager): ProximityPrompt
	local ui = ReplicatedStorage:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("WorldInteractionPrompt")
	if template and template:IsA("ProximityPrompt") then
		return template
	end
	for _, anchor in self.anchors do
		local prompt = anchor:FindFirstChild("WorldInteractionPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			return prompt
		end
	end
	error("未找到 WorldInteractionPrompt 模板实例")
end
function Manager.Remove(self: Manager, target: string): ()
	local binding = self.bindings[target]
	if not binding then return end
	self.bindings[target] = nil
	binding.holding = nil
	binding.scope:Destroy()
	TranslationTool.RemoveCustomAutoLocalizeGui(binding.prompt)
	binding.prompt.Enabled = false
	if binding.isDynamic then
		binding.prompt:Destroy()
	end
end
function Manager.IsInputBlocked(self: Manager): boolean
	if os.clock() < self.suppressUntil then return true end
	for _, binding in self.bindings do if binding.holding then return true end end
	return false
end
local function GetPickupModel(item: Types.ItemView?): Model?
	local model = item and item.model
	if model and model.Parent and model.PrimaryPart then return model end
	return nil
end
function Manager.Resolve(self: Manager, target: string): Rules.Action?
	local state = self.readState()
	local anchor: Instance? = self.anchors[target] or GetPickupModel(state.items[target])
	local binding = self.bindings[target]
	if not anchor or not anchor.Parent or not binding or binding.prompt.Parent ~= anchor then return nil end
	return if state.enabled then Rules.Resolve(target, state.snapshot, state.items, state.held, state.potions, state.carried) else nil
end
function Manager.Create(self: Manager, target: string, anchor: PromptParent): Binding
	local isStation = (self.anchors[target] :: BasePart?) ~= nil
	local prompt: ProximityPrompt
	if isStation then
		local existing = anchor:FindFirstChild("WorldInteractionPrompt")
		if existing and existing:IsA("ProximityPrompt") then
			prompt = existing
		else
			prompt = self:GetTemplatePrompt():Clone()
			prompt.Parent = anchor
		end
	else
		prompt = self:GetTemplatePrompt():Clone()
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = Config.InteractionRange
		prompt.Parent = anchor
	end
	prompt.Enabled = false
	if prompt.MaxActivationDistance <= 0 then
		prompt.MaxActivationDistance = Config.InteractionRange
	end
	local binding: Binding = {prompt=prompt, scope=Lifecycle.new(), defaultHoldDuration=prompt.HoldDuration, signature="", textValid=false, isDynamic=not isStation}
	self.bindings[target] = binding
	binding.scope:Connect(prompt.PromptButtonHoldBegan:Connect(function(): ()
		if prompt.HoldDuration <= 0 then return end
		local action = self:Resolve(target)
		if not prompt.Enabled or not action or action.signature ~= binding.signature then return end
		binding.holding = action
		self.suppressUntil = os.clock() + InputReleaseGraceSeconds
	end))
	binding.scope:Connect(prompt.PromptButtonHoldEnded:Connect(function(): ()
		if prompt.HoldDuration <= 0 then return end
		local holding = binding.holding
		self.suppressUntil = os.clock() + InputReleaseGraceSeconds
		-- 引擎完成长按时也可能先发出 HoldEnded；当前事件批次完成后再释放令牌。
		task.defer(function(): () if binding.holding == holding then binding.holding = nil end end)
	end))
	binding.scope:Connect(prompt.PromptHidden:Connect(function(): () binding.holding = nil end))
	binding.scope:Connect(prompt.Triggered:Connect(function(): ()
		local holding, current = binding.holding, self:Resolve(target)
		binding.holding = nil
		self.suppressUntil = os.clock() + InputReleaseGraceSeconds
		if not prompt.Enabled or not current or current.signature ~= binding.signature then return end
		if prompt.HoldDuration > 0 and (not holding or holding.signature ~= current.signature) then return end
		Net.FireRequest({action="Interact", target=current.target, version=current.version})
	end))
	return binding
end
local function CheckDirtyAndSyncCache(self: Manager, state: State): boolean
	local dirty = false
	local cache: RefreshCache
	if self.cache then
		cache = self.cache
		if cache.enabled ~= state.enabled then
			cache.enabled = state.enabled
			dirty = true
		end
	else
		cache = {
			enabled = state.enabled,
			hasSnapshot = false,
			stationVersions = {},
			stationVersionCount = 0,
			carriedCount = 0,
			carriedIds = {},
			carriedVersions = {},
			carriedKinds = {},
			carriedStages = {},
			potionEquipped = false,
			itemCount = 0,
			items = {},
			anchorAttached = {},
		}
		self.cache = cache
		dirty = true
	end
	local snapshot = state.snapshot
	local hasSnapshot = snapshot ~= nil
	if cache.hasSnapshot ~= hasSnapshot then
		cache.hasSnapshot = hasSnapshot
		dirty = true
	end
	if snapshot then
		if cache.revision ~= snapshot.revision then cache.revision = snapshot.revision; dirty = true end
		if cache.pool ~= snapshot.pool then cache.pool = snapshot.pool; dirty = true end
		if cache.shelf ~= snapshot.shelf then cache.shelf = snapshot.shelf; dirty = true end
		if cache.tableId ~= snapshot.tableId then cache.tableId = snapshot.tableId; dirty = true end
		if cache.painter ~= snapshot.painter then cache.painter = snapshot.painter; dirty = true end
		local versionCount = 0
		local versionChanged = false
		for k, v in snapshot.stationVersions do
			versionCount += 1
			if cache.stationVersions[k] ~= v then
				cache.stationVersions[k] = v
				versionChanged = true
			end
		end
		if versionCount ~= cache.stationVersionCount then
			cache.stationVersionCount = versionCount
			versionChanged = true
		end
		if versionChanged then
			for k in cache.stationVersions do
				if snapshot.stationVersions[k] == nil then
					cache.stationVersions[k] = nil
				end
			end
			dirty = true
		end
	elseif cache.stationVersionCount > 0 then
		cache.revision, cache.pool, cache.shelf, cache.tableId, cache.painter = nil, nil, nil, nil, nil
		table.clear(cache.stationVersions)
		cache.stationVersionCount = 0
		dirty = true
	end
	local held = state.held
	local heldId = if held then held.id else nil
	local heldVersion = if held then held.version else nil
	local heldKind = if held then held.kind else nil
	local heldStage = if held then held.stage else nil
	if cache.heldId ~= heldId or cache.heldVersion ~= heldVersion or cache.heldKind ~= heldKind or cache.heldStage ~= heldStage then
		cache.heldId, cache.heldVersion, cache.heldKind, cache.heldStage = heldId, heldVersion, heldKind, heldStage
		dirty = true
	end
	local carried = state.carried
	local carriedCount = if carried then #carried else 0
	if cache.carriedCount ~= carriedCount then
		cache.carriedCount = carriedCount
		dirty = true
	end
	if carried then
		for index = 1, carriedCount do
			local entry = carried[index]
			if cache.carriedIds[index] ~= entry.id
				or cache.carriedVersions[index] ~= entry.version
				or cache.carriedKinds[index] ~= entry.kind
				or cache.carriedStages[index] ~= entry.stage then
				cache.carriedIds[index] = entry.id
				cache.carriedVersions[index] = entry.version
				cache.carriedKinds[index] = entry.kind
				cache.carriedStages[index] = entry.stage
				dirty = true
			end
		end
	end
	local potionEquipped = state.potions ~= nil and state.potions.equipped == true
	if cache.potionEquipped ~= potionEquipped then
		cache.potionEquipped = potionEquipped
		dirty = true
	end
	for target, part in self.anchors do
		local attached = part.Parent ~= nil
		if cache.anchorAttached[target] ~= attached then
			cache.anchorAttached[target] = attached
			dirty = true
		end
		local binding = self.bindings[target]
		if binding and binding.prompt.Parent ~= part then
			dirty = true
		end
	end
	local itemCount = 0
	local cachedItems = cache.items
	local itemsChanged = false
	for id, item in state.items do
		itemCount += 1
		local model: Model? = item.model :: Model?
		local hasParent = if model then model.Parent ~= nil else false
		local hasPrimary = if model then model.PrimaryPart ~= nil else false
		local entry = cachedItems[id]
		if not entry then
			cachedItems[id] = {
				kind = item.kind,
				stage = item.stage,
				location = item.location,
				version = item.version,
				hits = item.hits,
				holder = item.holder,
				model = model,
				hasParent = hasParent,
				hasPrimary = hasPrimary,
			}
			itemsChanged = true
		elseif entry.kind ~= item.kind
			or entry.stage ~= item.stage
			or entry.location ~= item.location
			or entry.version ~= item.version
			or entry.hits ~= item.hits
			or entry.holder ~= item.holder
			or entry.model ~= model
			or entry.hasParent ~= hasParent
			or entry.hasPrimary ~= hasPrimary then
			entry.kind = item.kind
			entry.stage = item.stage
			entry.location = item.location
			entry.version = item.version
			entry.hits = item.hits
			entry.holder = item.holder
			entry.model = model
			entry.hasParent = hasParent
			entry.hasPrimary = hasPrimary
			itemsChanged = true
		end
		if not dirty and not itemsChanged then
			local binding = self.bindings[id]
			if binding and (not model or binding.prompt.Parent ~= model) then
				itemsChanged = true
			end
		end
	end
	if itemCount ~= cache.itemCount then
		cache.itemCount = itemCount
		itemsChanged = true
	end
	if itemsChanged then
		for id in cachedItems do
			if state.items[id] == nil then
				cachedItems[id] = nil
			end
		end
		dirty = true
	end
	return dirty
end
function Manager.Refresh(self: Manager): ()
	local state = self.readState()
	local dirty = CheckDirtyAndSyncCache(self, state)
	if not dirty and not self.recovering then
		return
	end
	local anchors: {[string]: PromptParent} = {}
	local resolvedActions: {[string]: Rules.Action} = {}
	for target, part in self.anchors do anchors[target] = part end
	for id, item in state.items do
		local model = GetPickupModel(item)
		if model then
			local action = Rules.Resolve(id, state.snapshot, state.items, state.held, state.potions, state.carried)
			if action then
				-- 用整个模型作为提示父级，原生视线检查会忽略物品自己的网格。
				anchors[id] = model
				if state.enabled then
					resolvedActions[id] = action
				end
			end
		end
	end
	for target, binding in self.bindings do
		local anchor: Instance? = anchors[target]
		if not anchor or binding.prompt.Parent ~= anchor then self:Remove(target) end
	end
	local anyRecovering = false
	for target, anchor in anchors do
		local action = if state.enabled then (resolvedActions[target] or (if self.anchors[target] then Rules.Resolve(target, state.snapshot, state.items, state.held, state.potions, state.carried) else nil)) else nil
		local binding = self.bindings[target]
		if not binding and action and anchor.Parent then binding = self:Create(target, anchor) end
		if not binding then continue end
		local signature = if action then action.signature else ""
		local changed = binding.signature ~= signature
		if changed then
			binding.holding = nil
			binding.prompt.Enabled = false
			binding.signature = signature
			binding.textValid = false
			if action then
				binding.prompt.HoldDuration = if action.instant then 0 else binding.defaultHoldDuration
				local text, object = GameTexts.GetEntry(action.action), GameTexts.GetEntry(action.object)
				if text and object then
					TranslationTool.CustomAutoLocalizeProximityPrompt(binding.prompt, text.source, text.key, nil, object.source, object.key, nil)
					binding.textValid = true
				else
					warn("未知世界交互文案：", action.action, action.object)
				end
			end
		end
		local ready = action ~= nil and binding.textValid and anchor.Parent ~= nil
		-- 状态变化至少禁用一帧，取消引擎内部正在进行的长按。
		binding.prompt.Enabled = ready and not changed
		if changed and ready then
			anyRecovering = true
		end
	end
	self.recovering = anyRecovering
end
function Manager.Destroy(self: Manager): ()
	for target in self.bindings do self:Remove(target) end
	self.suppressUntil = 0
	self.recovering = false
	self.cache = nil
end
return Manager
