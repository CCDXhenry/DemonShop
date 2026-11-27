-- 街道矩形区域的面积采样、包含判断、最近点与拼接路线校验
--!strict
local Zones = {}

export type Zone = { frame: CFrame, halfX: number, halfZ: number, area: number }
export type InterestPoint = { id: string, position: Vector3, lookDirection: Vector3 }
local Epsilon = 1e-5
local BelowStreet = 1
local AboveStreet = 8

function Zones.New(frame: CFrame, size: Vector3): Zone
	return { frame = frame, halfX = size.X / 2, halfZ = size.Z / 2, area = size.X * size.Z }
end

function Zones.Contains(zones: { Zone }, position: Vector3, margin: number?): boolean
	local padding = (margin or 0) + Epsilon
	for _, zone in zones do
		local point = zone.frame:PointToObjectSpace(position)
		if math.abs(point.X) <= zone.halfX + padding and math.abs(point.Z) <= zone.halfZ + padding
			and point.Y >= -BelowStreet and point.Y <= AboveStreet then
			return true
		end
	end
	return false
end

function Zones.Sample(zones: { Zone }, random: Random): Vector3?
	local area = 0
	for _, zone in zones do area += zone.area end
	if area <= 0 then return nil end
	local position = random:NextNumber(0, area)
	for index, zone in zones do
		position -= zone.area
		if position <= 0 or index == #zones then
			return zone.frame:PointToWorldSpace(Vector3.new(
				random:NextNumber(-zone.halfX, zone.halfX), 0, random:NextNumber(-zone.halfZ, zone.halfZ)
			))
		end
	end
	return nil
end

function Zones.Clamp(zone: Zone, position: Vector3, inset: number): Vector3
	local point = zone.frame:PointToObjectSpace(position)
	local x = math.max(zone.halfX - inset, 0)
	local z = math.max(zone.halfZ - inset, 0)
	return zone.frame:PointToWorldSpace(Vector3.new(math.clamp(point.X, -x, x), 0, math.clamp(point.Z, -z, z)))
end

function Zones.Closest(zones: { Zone }, position: Vector3, inset: number): Vector3?
	local best: Vector3? = nil
	local distance = math.huge
	for _, zone in zones do
		local candidate = Zones.Clamp(zone, position, inset)
		local offset = candidate - position
		local squared = offset:Dot(offset)
		if squared < distance then best, distance = candidate, squared end
	end
	return best
end

local function Clip(start: number, finish: number, lower: number, upper: number, lo: number, hi: number): (number, number)
	local delta = finish - start
	if math.abs(delta) <= Epsilon then
		if start < lower - Epsilon or start > upper + Epsilon then return 1, 0 end
		return lo, hi
	end
	local a, b = (lower - start) / delta, (upper - start) / delta
	return math.max(lo, math.min(a, b)), math.min(hi, math.max(a, b))
end

function Zones.CoversSegment(zones: { Zone }, from: Vector3, to: Vector3): boolean
	local intervals: { { lo: number, hi: number } } = {}
	for _, zone in zones do
		local a, b = zone.frame:PointToObjectSpace(from), zone.frame:PointToObjectSpace(to)
		local lo, hi = Clip(a.X, b.X, -zone.halfX, zone.halfX, 0, 1)
		if lo > hi then continue end
		lo, hi = Clip(a.Z, b.Z, -zone.halfZ, zone.halfZ, lo, hi)
		if lo > hi then continue end
		lo, hi = Clip(a.Y, b.Y, -BelowStreet, AboveStreet, lo, hi)
		if lo <= Epsilon and hi >= 1 - Epsilon then return true end
		if lo <= hi then table.insert(intervals, { lo = lo, hi = hi }) end
	end
	table.sort(intervals, function(a, b) return a.lo < b.lo end)
	local covered = 0
	for _, interval in intervals do
		if interval.lo > covered + Epsilon then return false end
		covered = math.max(covered, interval.hi)
		if covered >= 1 - Epsilon then return true end
	end
	return false
end

function Zones.BoundaryPush(zones: { Zone }, position: Vector3, margin: number): Vector3
	if margin <= 0 or #zones == 0 then
		return Vector3.zero
	end
	local pushX = 0
	local pushZ = 0
	if not Zones.Contains(zones, position + Vector3.new(margin, 0, 0)) then
		pushX -= 1
	end
	if not Zones.Contains(zones, position + Vector3.new(-margin, 0, 0)) then
		pushX += 1
	end
	if not Zones.Contains(zones, position + Vector3.new(0, 0, margin)) then
		pushZ -= 1
	end
	if not Zones.Contains(zones, position + Vector3.new(0, 0, -margin)) then
		pushZ += 1
	end
	local push = Vector3.new(pushX, 0, pushZ)
	if push.Magnitude <= Epsilon then
		return Vector3.zero
	end
	return push.Unit
end

function Zones.FallbackInterestPoints(zones: { Zone }): { InterestPoint }
	local points: { InterestPoint } = {}
	local inset = 2.2
	local spacing = 20
	local counter = 0
	for zoneIndex, zone in zones do
		local spanX = math.max(0, zone.halfX * 2 - inset * 2)
		local count = math.max(1, math.floor(spanX / spacing))
		for _, signZ in { -1, 1 } do
			local localZ = signZ * math.max(0, zone.halfZ - inset)
			local outward = zone.frame:VectorToWorldSpace(Vector3.new(0, 0, signZ))
			local flatLook = Vector3.new(outward.X, 0, outward.Z)
			local lookDir = if flatLook.Magnitude > Epsilon then flatLook.Unit else Vector3.zAxis * signZ
			for i = 1, count do
				local frac = (i - 0.5) / count
				local localX = -zone.halfX + inset + frac * spanX
				local pos = zone.frame:PointToWorldSpace(Vector3.new(localX, 0, localZ))
				local outsideProbe = pos + lookDir * (inset + 0.8)
				if not Zones.Contains(zones, outsideProbe) then
					counter += 1
					table.insert(points, {
						id = string.format("Fallback_%d_%d", zoneIndex, counter),
						position = pos,
						lookDirection = lookDir,
					})
				end
			end
		end
	end
	return points
end

return Zones
