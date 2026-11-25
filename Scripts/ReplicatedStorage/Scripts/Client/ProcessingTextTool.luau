-- 加工文案绑定：复用翻译器、按参数去重、翻译后拟合与集中释放
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameTexts = require(script.Parent.Parent.Shared.GameTexts)
local TranslationTool = require(ReplicatedStorage.Core.Scripts.Client.TranslationTool)
local TextFitting = require(script.Parent.UIManager.TextFitting)
local Tool = {}
Tool.__index = Tool

type Binding = {
	textId: GameTexts.TextId?,
	source: string,
	key: string,
	args: {string},
	argTextIds: {[number]: GameTexts.TextId}?,
	argSources: {[number]: string}?,
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

local function CloneStringMap(values: {[number]: string}?): {[number]: string}?
	if values == nil then
		return nil
	end
	return table.clone(values)
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

local function SameStringMap(a: {[number]: string}?, b: {[number]: string}?): boolean
	if a == nil and b == nil then
		return true
	end
	if a == nil or b == nil then
		return false
	end
	for index, value in pairs(a) do
		if b[index] ~= value then
			return false
		end
	end
	for index, value in pairs(b) do
		if a[index] ~= value then
			return false
		end
	end
	return true
end

local function ResolveArgs(
	label: TextLabel,
	rawArgs: {string},
	argTextIds: {[number]: GameTexts.TextId}?,
	argSources: {[number]: string}?
): {string}
	local resolved = table.clone(rawArgs)
	if argTextIds ~= nil then
		for index, argTextId in pairs(argTextIds) do
			local entryId: GameTexts.TextId = argTextId :: GameTexts.TextId
			local argEntry = GameTexts.GetEntry(entryId)
			if argEntry then
				resolved[index] = TranslationTool.Translate(label, argEntry.source)
			end
		end
	end
	if argSources ~= nil then
		for index, argSource in pairs(argSources) do
			if argSource ~= "" then
				resolved[index] = TranslationTool.Translate(label, argSource)
			end
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
		if binding and (binding.argTextIds or binding.argSources) and not self.refreshing[label] then
			local nextResolved = ResolveArgs(label, binding.args, binding.argTextIds, binding.argSources)
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
	local argSources = if textId == description.textId then description.argSources else nil
	if previous
		and previous.textId == textId
		and SameStringList(previous.args, args)
		and SameArgTextIds(previous.argTextIds, argTextIds)
		and SameStringMap(previous.argSources, argSources)
	then
		return
	end
	local resolvedArgs = ResolveArgs(label, args, argTextIds, argSources)
	self:Watch(label, argTextIds ~= nil or argSources ~= nil)
	label.AutoLocalize = false
	self.bindings[label] = {
		textId = textId,
		source = entry.source,
		key = entry.key,
		args = table.clone(args),
		argTextIds = CloneArgTextIds(argTextIds),
		argSources = CloneStringMap(argSources),
		resolvedArgs = resolvedArgs,
	}
	TranslationTool.CustomAutoLocalizeTextLabel(label, entry.source, entry.key, resolvedArgs)
end

function Tool.BindSource(self: Controller, label: TextLabel, source: string): ()
	local previous = self.bindings[label]
	if previous
		and previous.textId == nil
		and previous.source == source
		and previous.key == ""
		and #previous.args == 0
		and previous.argTextIds == nil
		and previous.argSources == nil
	then
		return
	end
	self:Watch(label, false)
	label.AutoLocalize = false
	self.bindings[label] = {
		textId = nil,
		source = source,
		key = "",
		args = {},
		argTextIds = nil,
		argSources = nil,
		resolvedArgs = {},
	}
	TranslationTool.CustomAutoLocalizeTextLabel(label, source, "")
end

function Tool.Clear(self: Controller, label: TextLabel): ()
	TranslationTool.RemoveCustomAutoLocalizeGui(label)
	self.bindings[label] = nil
	self.refreshing[label] = nil
	label.AutoLocalize = false
	label.Text = ""
end

function Tool.Notice(self: Controller, label: TextLabel, textId: GameTexts.TextId?, args: {string}?, legacyText: string?): ()
	local argSources: {[number]: string}? = nil
	if textId == "FacilityUnlocked" and args and args[2] and args[2] ~= "" then
		argSources = { [2] = args[2] }
	end
	local description: GameTexts.Description? = if textId and GameTexts.GetEntry(textId)
		then {textId = textId, args = args, argSources = argSources}
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
