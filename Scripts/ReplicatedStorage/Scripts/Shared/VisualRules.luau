-- 视觉线段协议规则：有界校验、稳定标识、版本去重及全身体预算，供网络和服务端共用
--!strict
local GameTexts = require(script.Parent.GameTexts)
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local Surface = require(script.Parent.PaintSurface)
local Curve = require(script.Parent.CurvedSurface)
local Rules = {}
function Rules.New(): Types.VisualState return {segments={},count=0,revision=0} end
function Rules.Validate(raw: unknown): boolean
	if typeof(raw) ~= "table" then return false end
	local value = raw :: {[string]: unknown}
	if typeof(value.key) ~= "string" or #value.key > 160 or typeof(value.part) ~= "string" or #value.part > 32 then return false end
	for _, name in {"version","gesture","face"} do
		local number = value[name]
		if not Surface.IsFinite(number) then return false end
		local n = number :: number
		if n < 1 or n % 1 ~= 0 or n > 1000000000 then return false end
	end
	if (value.face :: number) > 6 then return false end
	for _, name in {"u0","v0","u1","v1"} do
		local number = value[name]
		if not Surface.IsFinite(number) then return false end
		if (number :: number) < 0 or (number :: number) > 1 then return false end
	end
	if value.surfaceVersion~=nil then
		if value.surfaceVersion~=Curve.Version then return false end
		for _,name in {"triangle0","triangle1"} do
			local number=value[name]
			if not Surface.IsFinite(number) then return false end
			local n=number :: number
			if n<1 or n>960 or n%1~=0 then return false end
		end
		if (value.u0 :: number)+(value.v0 :: number)>1.00001 or (value.u1 :: number)+(value.v1 :: number)>1.00001 then return false end
	elseif value.triangle0~=nil or value.triangle1~=nil then return false end
	if value.ink~=nil then
		return value.surfaceVersion==Curve.Version and value.triangle0==value.triangle1 and value.face==1 and value.gesture==1
			and value.u0==0 and value.v0==0 and value.u1==0 and value.v1==0
			and Curve.ValidInk(value.part :: string,value.triangle0 :: number,value.key :: string,value.ink)
	end
	return true
end
function Rules.Apply(state: Types.VisualState, segments: {Types.VisualSegment}, session: string): ({Types.VisualSegment}?, GameTexts.TextId?)
	local additions, seen = 0, {} :: {[string]: boolean}
	for _, segment in segments do
		if not Rules.Validate(segment) or (not segment.ink and string.sub(segment.key,1,#session+1) ~= session .. ":") then return nil,"InvalidVisualSegment" end
		if seen[segment.key] then return nil,"DuplicateVisualSegment" end
		seen[segment.key] = true
		local old = state.segments[segment.key]
		if old and (old.part ~= segment.part or old.face ~= segment.face or old.gesture ~= segment.gesture or old.u0 ~= segment.u0 or old.v0 ~= segment.v0 or old.triangle0~=segment.triangle0 or old.surfaceVersion~=segment.surfaceVersion) then return nil,"SegmentOriginChanged" end
		if not old and not segment.ink then additions += 1 end
	end
	if state.count - (state.inkCount or 0) + additions > Config.PaintLocalSegmentBudget then return nil,"PaintBudgetReached" end
	local accepted: {Types.VisualSegment} = {}
	for _, segment in segments do
		local old = state.segments[segment.key]
		if segment.ink then
			local merged,added = Curve.MergeInk(if old then old.ink else nil,segment.ink)
			if added then
				local stored=table.clone(segment)
				stored.ink,stored.version=merged,if old then old.version+1 else 1
				state.segments[segment.key]=stored
				if not old then
					state.count+=1
					state.inkCount=(state.inkCount or 0)+1
				end
				table.insert(accepted,stored)
			end
		elseif not old or segment.version > old.version then
			local stored: Types.VisualSegment={key=segment.key,version=segment.version,gesture=segment.gesture,part=segment.part,face=segment.face,u0=segment.u0,v0=segment.v0,u1=segment.u1,v1=segment.v1}
			stored.triangle0,stored.triangle1,stored.surfaceVersion=segment.triangle0,segment.triangle1,segment.surfaceVersion
			state.segments[segment.key] = stored
			if not old then state.count += 1 end
			table.insert(accepted,stored)
		end
	end
	if #accepted > 0 then state.revision += 1 end
	return accepted,nil
end
return Rules
