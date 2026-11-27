-- 验证生产街道区域的权重、旋转、拼接与缺口约束
local Roblox = require("@lune/roblox")
local FS = require("@lune/fs")
local Luau = require("@lune/luau")
local V, C = Roblox.Vector3, Roblox.CFrame
local Zones = Luau.load(FS.readFile("Scripts/ServerStorage/Scripts/StreetWalkZones.luau"), {environment = {Vector3 = V}})()
local function zone(x, z, width, depth, yaw)
	return Zones.New(C.new(x, 20, z) * C.Angles(0, yaw or 0, 0), V.new(width, 1, depth))
end
local west, main = zone(-5, -2, 10, 6), zone(10, 0, 20, 10)
local zones = {west, main}
assert(Zones.Contains(zones, V.new(-5, 23, -2)))
assert(not Zones.Contains(zones, V.new(-5, 2, -2)))
assert(Zones.Contains(zones, V.new(-10.4, 23, -2), 0.5))
assert(Zones.CoversSegment(zones, V.new(-8, 23, -2), V.new(12, 23, -2)))
assert(not Zones.CoversSegment(zones, V.new(-8, 23, 1), V.new(8, 23, 5)))
assert(not Zones.CoversSegment({west, zone(12, 0, 20, 10)}, V.new(-8, 23, -2), V.new(8, 23, -2)))
local rotated = {zone(0, 0, 16, 4, math.pi / 2)}
assert(Zones.Contains(rotated, V.new(0, 23, 7)))
assert(not Zones.Contains(rotated, V.new(7, 23, 0)))
local nearest = Zones.Closest(zones, V.new(-5, 23, 5), 0.5)
assert(nearest and Zones.Contains(zones, nearest) and nearest.X < 0 and nearest.Z < 1)
local picks = {0, 0.5, 0.99}
for i, pick in picks do
	local calls = 0
	local sample = Zones.Sample(zones, {NextNumber = function(_, minimum, maximum)
		calls += 1
		return minimum + (maximum - minimum) * (if calls == 1 then pick else 0.5)
	end})
	assert(sample and ((sample.X < 0) == (i == 1)), "Zone weight must follow area")
end
assert(not Zones.Sample({}, {}))
local Scene = {Deck = {CFrame = C.new(0, 19, 0), Size = V.new(40, 2, 30)}}
local folder = nil
local gap = false
local source = FS.readFile("Scripts/ServerStorage/Scripts/Scene.luau")
local sceneStart = assert(source:find("local function ReadStreetWalkZones", 1, true))
local sceneEnd = assert(source:find("Scene.PoolDrop =", sceneStart, true))
local initScene = Luau.load(source:sub(sceneStart, sceneEnd - 1), {environment = {
	Vector3 = V, CFrame = C, Scene = Scene, StreetZones = Zones, Enum = Roblox.Enum, StreetFloorProbeSpacing = 2.5,
	district = {FindFirstChild = function() return folder end},
	RaycastParams = {new = function() return {} end},
	workspace = {
		Raycast = function(_, from)
			if gap and math.abs(from.X) < 1.5 then return nil end
			return {Position = V.new(from.X, 20, from.Z), Normal = V.yAxis}
		end,
		Blockcast = function() return nil end,
	},
}})
initScene()
local fallback = Scene.StreetPoint({NextNumber = function(_, a, b) return (a + b) / 2 end})
assert(fallback == V.new(0, 20, 0) and Scene.IsInStreetWalkZones(fallback), "missing folder uses legacy deck")
assert(not Scene.IsInStreetWalkZones(V.new(17, 23, 0)), "legacy deck uses four-stud sampling inset")
folder = Roblox.Instance.new("Folder")
initScene()
assert(Scene.IsInStreetWalkZones(fallback), "empty folder uses legacy deck")
assert(Scene.StreetRoute(V.new(-6, 23.2, 0), V.new(6, 20, 0)))
gap = true
assert(not Scene.StreetRoute(V.new(-6, 23.2, 0), V.new(6, 20, 0)), "reject ground gap between supported endpoints")
local pushWest = Zones.BoundaryPush(zones, V.new(-9.5, 20, -2), 1.5)
assert(pushWest.X > 0.5, "outer west boundary pushes inward")
local seamPush = Zones.BoundaryPush(zones, V.new(0, 20, -2), 1.5)
assert(seamPush.Magnitude < 0.01, "shared seam between overlapping zones must not push")
local fallbackPois = Zones.FallbackInterestPoints(zones)
assert(#fallbackPois >= 2, "fallback interest points generated along outer edges")
print("PASS: StreetWalkZones area, rotation, floor, margin, seam, corner, gap, fallback, boundary push and nearest point")
