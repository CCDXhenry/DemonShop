-- 加工文案绑定：复用翻译器、按参数去重、翻译后拟合与集中释放
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameTexts = require(script.Parent.Parent.Shared.GameTexts)
local TranslationTool = require(ReplicatedStorage.Core.Scripts.Client.TranslationTool)
local TextFitting = require(script.Parent.UIManager.TextFitting)
local Tool = {}
Tool.__index = Tool

type Binding = { textId: GameTexts.TextId, args: {string} }
export type Controller = typeof(setmetatable({} :: {
	bindings: {[TextLabel]: Binding},
	connections: {[TextLabel]: {RBXScriptConnection}},
}, Tool))

function Tool.new(): Controller
	return setmetatable({bindings = {}, connections = {}}, Tool)
end

function Tool.Watch(self: Controller, label: TextLabel): ()
	if self.connections[label] or label:FindFirstAncestorWhichIsA("BillboardGui") then return end
	local function OnTextChanged(): ()
		TextFitting.FitTextLabel(label)
	end
	self.connections[label] = {
		label:GetPropertyChangedSignal("Text"):Connect(OnTextChanged),
		label:GetPropertyChangedSignal("ContentText"):Connect(OnTextChanged),
	}
	OnTextChanged()
end

function Tool.Bind(self: Controller, label: TextLabel, description: GameTexts.Description): ()
	local previous = self.bindings[label]
	local args: {string} = description.args or {}
	if previous and previous.textId == description.textId and #previous.args == #args then
		local equal = true
		for index, value in args do
			if previous.args[index] ~= value then equal = false; break end
		end
		if equal then return end
	end
	local entry = GameTexts.Entries[description.textId]
	self:Watch(label)
	label.AutoLocalize = false
	self.bindings[label] = {textId = description.textId, args = table.clone(args)}
	TranslationTool.CustomAutoLocalizeTextLabel(label, entry.source, entry.key, args)
end

function Tool.Clear(self: Controller, label: TextLabel): ()
	TranslationTool.RemoveCustomAutoLocalizeGui(label)
	self.bindings[label] = nil
	label.AutoLocalize = false
	label.Text = ""
end

function Tool.Notice(self: Controller, label: TextLabel, textId: GameTexts.TextId?, args: {string}?, legacyText: string?): ()
	local description: GameTexts.Description? = if textId and GameTexts.Entries[textId] then {textId = textId, args = args} else nil
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
end

return Tool
