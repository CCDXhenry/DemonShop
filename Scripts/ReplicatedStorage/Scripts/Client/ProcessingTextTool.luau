-- 加工文案绑定：复用翻译器、按参数去重、翻译后拟合与集中释放
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameTexts = require(script.Parent.Parent.Shared.GameTexts)
local TranslationTool = require(ReplicatedStorage.Core.Scripts.Client.TranslationTool)
local TextFitting = require(script.Parent.UIManager.TextFitting)
local Tool = {}
Tool.__index = Tool

type Binding = {
	textId: GameTexts.TextId,
	source: string,
	key: string,
	args: {string},
	argTextIds: {[number]: GameTexts.TextId}?,
	resolvedArgs: {string},
}
export type Controller = typeof(setmetatable({} :: {
	bindings: {[TextLabel]: Binding},
	connections: {[TextLabel]: {RBXScriptConnection}},
	refreshing: {[TextLabel]: boolean},
}, Tool))

local function CloneArgTextIds(argTextIds: {[number]: GameTexts.TextId}?): {[number]: GameTexts.TextId}?
	if argTextIds == nil then
		return nil
	end
	return table.clone(argTextIds)
end

local function SameStringList(a: {string}, b: {string}): boolean
	if #a ~= #b then
		return false
	end
	for index, value in a do
		if b[index] ~= value then
			return false
		end
	end
	return true
end

local function SameArgTextIds(a: {[number]: GameTexts.TextId}?, b: {[number]: GameTexts.TextId}?): boolean
	if a == nil and b == nil then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	for index, id in pairs(a) do
		if b[index] ~= id then
			return false
		end
	end
	for index, id in pairs(b) do
		if a[index] ~= id then
			return false
		end
	end
	return true
end

local function ResolveArgs(label: TextLabel, rawArgs: {string}, argTextIds: {[number]: GameTexts.TextId}?): {string}
	local resolved = table.clone(rawArgs)
	if argTextIds == nil then
		return resolved
	end
	for index, argTextId in pairs(argTextIds) do
		local entryId: GameTexts.TextId = argTextId :: GameTexts.TextId
		local argEntry = GameTexts.GetEntry(entryId)
		if argEntry then
			resolved[index] = TranslationTool.Translate(label, argEntry.source)
		end
	end
	return resolved
end

function Tool.new(): Controller
	return setmetatable({bindings = {}, connections = {}, refreshing = {}}, Tool)
end

function Tool.Watch(self: Controller, label: TextLabel, forceWatch: boolean?): ()
	local isBillboard = label:FindFirstAncestorWhichIsA("BillboardGui") ~= nil
	if self.connections[label] or (isBillboard and not forceWatch) then return end
	local function OnTextChanged(): ()
		local binding = self.bindings[label]
		if binding and binding.argTextIds and not self.refreshing[label] then
			local nextResolved = ResolveArgs(label, binding.args, binding.argTextIds)
			if not SameStringList(binding.resolvedArgs, nextResolved) then
				binding.resolvedArgs = nextResolved
				self.refreshing[label] = true
				TranslationTool.CustomAutoLocalizeTextLabel(label, binding.source, binding.key, nextResolved)
				self.refreshing[label] = nil
			end
		end
		if not label:FindFirstAncestorWhichIsA("BillboardGui") then
			TextFitting.FitTextLabel(label)
		end
	end
	self.connections[label] = {
		label:GetPropertyChangedSignal("Text"):Connect(OnTextChanged),
		label:GetPropertyChangedSignal("ContentText"):Connect(OnTextChanged),
	}
	if not isBillboard then
		OnTextChanged()
	end
end

function Tool.Bind(self: Controller, label: TextLabel, description: GameTexts.Description): ()
	local textId: GameTexts.TextId = description.textId
	local requestedEntry = GameTexts.GetEntry(textId)
	if not requestedEntry then
		warn("未知加工文案：", textId)
		textId = "UnknownNotice"
	end
	local entry: GameTexts.Entry = requestedEntry or GameTexts.Notices.UnknownNotice
	local previous = self.bindings[label]
	local args: {string} = if textId == description.textId then description.args or {} else {}
	local argTextIds = if textId == description.textId then description.argTextIds else nil
	if previous
		and previous.textId == textId
		and SameStringList(previous.args, args)
		and SameArgTextIds(previous.argTextIds, argTextIds)
	then
		return
	end
	local resolvedArgs = ResolveArgs(label, args, argTextIds)
	self:Watch(label, argTextIds ~= nil)
	label.AutoLocalize = false
	self.bindings[label] = {
		textId = textId,
		source = entry.source,
		key = entry.key,
		args = table.clone(args),
		argTextIds = CloneArgTextIds(argTextIds),
		resolvedArgs = resolvedArgs,
	}
	TranslationTool.CustomAutoLocalizeTextLabel(label, entry.source, entry.key, resolvedArgs)
end

function Tool.Clear(self: Controller, label: TextLabel): ()
	TranslationTool.RemoveCustomAutoLocalizeGui(label)
	self.bindings[label] = nil
	self.refreshing[label] = nil
	label.AutoLocalize = false
	label.Text = ""
end

function Tool.Notice(self: Controller, label: TextLabel, textId: GameTexts.TextId?, args: {string}?, legacyText: string?): ()
	local argTextIds: {[number]: GameTexts.TextId}? = nil
	if textId == "FacilityUnlocked" and args and args[2] then
		local resolved = GameTexts.ResolveLegacy(args[2])
		if resolved and not resolved.args then
			argTextIds = { [2] = resolved.textId }
		end
	end
	local description: GameTexts.Description? = if textId and GameTexts.GetEntry(textId)
		then {textId = textId, args = args, argTextIds = argTextIds}
		else nil
	if not description and legacyText then description = GameTexts.ResolveLegacy(legacyText) end
	if not description then
		warn("未知加工通知：", textId, legacyText)
		description = {textId = "UnknownNotice"}
	end
	self:Bind(label, description :: GameTexts.Description)
end

function Tool.Destroy(self: Controller): ()
	for label in self.bindings do TranslationTool.RemoveCustomAutoLocalizeGui(label) end
	for _, connections in self.connections do
		for _, connection in connections do connection:Disconnect() end
	end
	table.clear(self.bindings)
	table.clear(self.connections)
	table.clear(self.refreshing)
end

return Tool
