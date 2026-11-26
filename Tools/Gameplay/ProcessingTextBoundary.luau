-- 文案离线边界：标签属性信号、可延迟翻译器及拟合计数
local B = {fits = 0, translations = 0, locale = "en"}
function B.Signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			callbacks[callback] = true
			return {Disconnect = function() callbacks[callback] = nil end}
		end,
		Fire = function() for callback in callbacks do callback() end end,
		Count = function() local count = 0; for _ in callbacks do count += 1 end; return count end,
	}
end
function B.Label(billboard)
	local changed, destroying = B.Signal(), B.Signal()
	local values = {Text = "", AutoLocalize = true, Parent = {}, Destroying = destroying}
	local methods = {
		GetPropertyChangedSignal = function() return changed end,
		FindFirstAncestorWhichIsA = function() return billboard end,
		IsA = function(_, name) return name == "TextLabel" end,
	}
	return setmetatable({}, {
		__index = function(_, key) return methods[key] or values[key] end,
		__newindex = function(_, key, value)
			local old = values[key]; values[key] = value
			if key == "Text" and value ~= old then changed.Fire() end
		end,
	}), changed
end
B.TextFitting = {FitTextLabel = function() B.fits += 1 end, FitMarkedText = function() return nil end}
B.players = {LocalPlayer = {}}
B.localizationService = {GetTranslatorForPlayerAsync = function()
	B.pending = coroutine.running()
	return coroutine.yield()
end}
B.localeChanged = B.Signal()
B.translator = {
	Translate = function(_, _, source) B.translations += 1; return B.locale .. ":" .. source end,
	FormatByKey = function(_, key, args) B.translations += 1; return B.locale .. ":" .. key .. ":" .. table.concat(args, ",") end,
	GetPropertyChangedSignal = function() return B.localeChanged end,
}
return B
