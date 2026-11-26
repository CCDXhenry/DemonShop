-- 符文视觉同步协议规则：有界校验、稳定标识、版本去重及全身体预算，供网络和服务端共用
--!strict
local GameTexts = require(script.Parent.GameTexts)
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local Surface = require(script.Parent.PaintSurface)
local Curve = require(script.Parent.CurvedSurface)
local Rules = {}
local AngleBound = math.pi + 1e-4

function Rules.New(): Types.VisualState
	return { segments = {}, count = 0, revision = 0 }
end

function Rules.Validate(raw: unknown): boolean
	if typeof(raw) ~= "table" then
		return false
	end
	local value = raw :: { [string]: unknown }
	if typeof(value.key) ~= "string" or #value.key > 160 or typeof(value.part) ~= "string" or #value.part > 32 then
		return false
	end
	for _, name in { "version", "gesture", "face", "glyph" } do
		local number = value[name]
		if not Surface.IsFinite(number) then
			return false
		end
		local n = number :: number
		if n < 1 or n % 1 ~= 0 or n > 1000000000 then
			return false
		end
	end
	if (value.face :: number) > 6 or (value.glyph :: number) > Config.RuneGlyphCount then
		return false
	end
	for _, name in { "u", "v" } do
		local number = value[name]
		if not Surface.IsFinite(number) then
			return false
		end
		if (number :: number) < 0 or (number :: number) > 1 then
			return false
		end
	end
	if not Surface.IsFinite(value.angle) or math.abs(value.angle :: number) > AngleBound then
		return false
	end
	if not Surface.IsFinite(value.scale) or (value.scale :: number) < Config.RuneMinScale - 1e-5 or (value.scale :: number) > 1 + 1e-5 then
		return false
	end
	if value.surfaceVersion ~= nil then
		if value.surfaceVersion ~= Curve.Version then
			return false
		end
		local triangle = value.triangle
		if not Surface.IsFinite(triangle) then
			return false
		end
		local n = triangle :: number
		if n < 1 or n > 960 or n % 1 ~= 0 then
			return false
		end
		if (value.u :: number) + (value.v :: number) > 1.00001 then
			return false
		end
	elseif value.triangle ~= nil then
		return false
	end
	if value.side ~= nil and value.side ~= 1 and value.side ~= 2 then
		return false
	end
	return true
end

function Rules.Apply(state: Types.VisualState, segments: { Types.VisualSegment }, session: string): ({ Types.VisualSegment }?, GameTexts.TextId?)
	local additions, seen = 0, {} :: { [string]: boolean }
	for _, segment in segments do
		if not Rules.Validate(segment) or string.sub(segment.key, 1, #session + 1) ~= session .. ":" then
			return nil, "InvalidVisualSegment"
		end
		if seen[segment.key] then
			return nil, "DuplicateVisualSegment"
		end
		seen[segment.key] = true
		local old = state.segments[segment.key]
		if old and (
			old.part ~= segment.part
			or old.face ~= segment.face
			or old.gesture ~= segment.gesture
			or old.u ~= segment.u
			or old.v ~= segment.v
			or old.glyph ~= segment.glyph
			or old.angle ~= segment.angle
			or old.scale ~= segment.scale
			or old.triangle ~= segment.triangle
			or old.surfaceVersion ~= segment.surfaceVersion
			or old.side ~= segment.side
		) then
			return nil, "SegmentOriginChanged"
		end
		if not old then
			additions += 1
		end
	end
	if state.count + additions > Config.PaintLocalSegmentBudget then
		return nil, "PaintBudgetReached"
	end
	local accepted: { Types.VisualSegment } = {}
	for _, segment in segments do
		local old = state.segments[segment.key]
		if not old or segment.version > old.version then
			local stored: Types.VisualSegment = {
				key = segment.key,
				version = segment.version,
				gesture = segment.gesture,
				part = segment.part,
				face = segment.face,
				u = segment.u,
				v = segment.v,
				glyph = segment.glyph,
				angle = segment.angle,
				scale = math.clamp(segment.scale, Config.RuneMinScale, 1),
				triangle = segment.triangle,
				surfaceVersion = segment.surfaceVersion,
				side = segment.side,
			}
			state.segments[segment.key] = stored
			if not old then
				state.count += 1
			end
			table.insert(accepted, stored)
		end
	end
	if #accepted > 0 then
		state.revision += 1
	end
	return accepted, nil
end

return Rules
