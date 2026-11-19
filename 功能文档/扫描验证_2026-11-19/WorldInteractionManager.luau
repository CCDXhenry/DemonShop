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
type Binding = { prompt: ProximityPrompt, scope: Lifecycle.Lifecycle, signature: string, holding: Rules.Action?, textValid: boolean }
export type State = { snapshot: Types.Snapshot?, items: {[string]: Types.ItemView}, held: Types.ItemView?, potions: Rules.Potions?, enabled: boolean }
export type Manager = typeof(setmetatable({} :: {
	bindings: {[string]: Binding}, anchors: {[string]: BasePart}, readState: () -> State, suppressUntil: number,
}, Manager))
function Manager.new(anchors: {[string]: BasePart}, readState: () -> State): Manager
	return setmetatable({bindings={}, anchors=anchors, readState=readState, suppressUntil=0}, Manager)
end
function Manager.Remove(self: Manager, target: string): ()
	local binding = self.bindings[target]
	if not binding then return end
	self.bindings[target] = nil
	binding.holding = nil
	binding.scope:Destroy()
	TranslationTool.RemoveCustomAutoLocalizeGui(binding.prompt)
	binding.prompt:Destroy()
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
	return if state.enabled then Rules.Resolve(target, state.snapshot, state.items, state.held, state.potions) else nil
end
function Manager.Create(self: Manager, target: string, anchor: PromptParent): Binding
	local prompt = (ReplicatedStorage.UI:WaitForChild("WorldInteractionPrompt") :: ProximityPrompt):Clone()
	prompt.Enabled = false
	prompt.MaxActivationDistance = Config.InteractionRange
	local binding: Binding = {prompt=prompt, scope=Lifecycle.new(), signature="", textValid=false}
	self.bindings[target] = binding
	binding.scope:Connect(prompt.PromptButtonHoldBegan:Connect(function(): ()
		local action = self:Resolve(target)
		if not prompt.Enabled or not action or action.signature ~= binding.signature then return end
		binding.holding = action
		self.suppressUntil = os.clock() + InputReleaseGraceSeconds
	end))
	binding.scope:Connect(prompt.PromptButtonHoldEnded:Connect(function(): ()
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
		if not prompt.Enabled or not holding or not current or holding.signature ~= current.signature then return end
		Net.FireRequest({action="Interact", target=holding.target, version=holding.version})
	end))
	prompt.Parent = anchor
	return binding
end
function Manager.Refresh(self: Manager): ()
	local state = self.readState()
	local anchors: {[string]: PromptParent} = {}
	for target, part in self.anchors do anchors[target] = part end
	for id, item in state.items do
		local model = GetPickupModel(item)
		if model and Rules.Resolve(id, state.snapshot, state.items, state.held, state.potions) then
			-- 用整个模型作为提示父级，原生视线检查会忽略物品自己的网格。
			anchors[id] = model
		end
	end
	for target, binding in self.bindings do
		local anchor: Instance? = anchors[target]
		if not anchor or binding.prompt.Parent ~= anchor then self:Remove(target) end
	end
	for target, anchor in anchors do
		local action = if state.enabled then Rules.Resolve(target, state.snapshot, state.items, state.held, state.potions) else nil
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
				local text, object = GameTexts.GetEntry(action.action), GameTexts.GetEntry(action.object)
				if text and object then
					TranslationTool.CustomAutoLocalizeProximityPrompt(binding.prompt, text.source, text.key, nil, object.source, object.key, nil)
					binding.textValid = true
				else
					warn("未知世界交互文案：", action.action, action.object)
				end
			end
		end
		-- 状态变化至少禁用一帧，取消引擎内部正在进行的长按。
		binding.prompt.Enabled = action ~= nil and binding.textValid and not changed and anchor.Parent ~= nil
	end
end
function Manager.Destroy(self: Manager): ()
	for target in self.bindings do self:Remove(target) end
	self.suppressUntil = 0
end
return Manager
