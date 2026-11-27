local R = require("@lune/roblox")
local Physics = require("./PhysicsConfig")
local Groups = require("./CollisionGroups")
local Geometry = require("./CageGeometry")
local Service = require("./CagePhysicsBoundary")

Groups.Init()
Groups.Init()
local arms = Physics.FallGroup
local scenery = Physics.SceneryGroup
local body = Physics.BodyGroup
local walking = Physics.WalkingNpcGroup
local contained = Physics.CageContainedGroup
local cage = Physics.CageWallGroup
local baffle = Physics.ChuteBaffleGroup
local function check(left, right, expected)
	assert(Service:CollisionGroupsAreCollidable(left, right) == expected, left .. " vs " .. right)
end
for _, group in { "Default", "Custom", arms, scenery, body, walking, contained, cage, baffle } do
	check(cage, group, false)
	check(baffle, group, group == body or group == contained)
	check(arms, group, group == scenery)
	check(walking, group, group == "Default" or group == "Custom" or group == scenery)
end
for _, group in { "Default", "Custom", scenery, body, contained } do
	check(contained, group, true)
end
check(scenery, "Custom", false)
check(body, body, true)
assert(Service.registrations == 7, "init registered a group twice")

local frame = R.CFrame.new(3, 2, 7) * R.CFrame.Angles(0, math.pi, 0)
local size = R.Vector3.new(27.5, 1.6, 18.3)
local inset = Physics.Cage.ChuteWallInset
local place = function(x,y,z) return frame:PointToWorldSpace(R.Vector3.new(x,y,z)) end
assert(Geometry.Contains(frame, size, place(0, 12, 0), inset), "upper cage must capture falling bodies")
assert(not Geometry.Contains(frame, size, place(0, 16, 0), inset), "upper entry margin must remain open")
assert(not Geometry.Contains(frame, size, place(14, 2, 0), inset), "outside bodies must pass through")
assert(not Geometry.Contains(frame, size, place(12.8, 2, 0), inset), "body center must clear the inset wall")
assert(not Geometry.Contains(frame, size, place(0, -2, 0), inset), "body below cage is outside")
local walls = Geometry.Walls(frame, size, inset)
assert(walls.West.Size.Y == 16 and walls.East.Size.Y == 16 and walls.West.Size.X == 2)
local innerX, innerZ = Geometry.InnerHalfSize(size, inset)
assert(math.abs(frame:PointToObjectSpace(walls.East.Frame.Position).X - (innerX + 1)) < 0.001)
assert(math.abs(walls.North.Size.X - (innerX * 2 + 4)) < 0.001, "corners must close")
assert(math.abs(walls.East.Size.Z - innerZ * 2) < 0.001)

-- 预览单向内壁命中：外部飞入不截断，进入净空后撞对侧内壁截断且法线向内。
local inDist = Geometry.IntersectInnerWall(frame, size, inset, place(innerX + 4, 4, 0), frame:VectorToWorldSpace(R.Vector3.new(-6, 0, 0)))
assert(inDist == nil, "entering cage from outside must pass through")
local outDist, outPos, outNorm = Geometry.IntersectInnerWall(frame, size, inset, place(innerX - 2, 4, 0), frame:VectorToWorldSpace(R.Vector3.new(6, 0, 0)))
assert(outDist ~= nil and math.abs(outDist - 2) < 0.01, "exiting cage hits inner wall at exact distance")
assert(outPos ~= nil and math.abs(frame:PointToObjectSpace(outPos).X - innerX) < 0.01)
assert(outNorm ~= nil and frame:VectorToObjectSpace(outNorm).X < -0.99, "inner wall normal points inward")

local Carry = require("./CageCarry")
local Boundary = require("./CageCarryBoundary")
local function makeModel(x)
	local m = { Parent = {}, torso = { Position = R.Vector3.new(x, 3, 0), AssemblyLinearVelocity = R.Vector3.new(30, -5, 0), Anchored = false, IsA = function(_, cls) return cls == "BasePart" end } }
	function m:GetAttribute() return self.cage end
	function m:GetDescendants() return { self.torso } end
	function m:GetPivot() return R.CFrame.new(self.torso.Position) end
	function m:PivotTo(cf) self.torso.Position = cf.Position end
	return m
end

-- 1) 抛掷者在线：服务端只切 CageContained 与落地材质，不抢回 NetworkOwner、不改写客户端速度、不 PivotTo 拉扯。
Boundary.Players.online[1] = true
local onlineModel = makeModel(-2)
local onlineItem = { model = onlineModel, stage = "Unpainted", poolToss = { kind = "Manual", started = 10, owner = 1, canEnterChute = true } }
local settled = 0
local function onSettled() settled += 1 end
assert(not Carry.AdvanceManualToss(onlineItem, 10, onSettled, true) and onlineModel.cage == nil)
onlineModel.torso.Position = R.Vector3.new(1, 3, 0)
assert(not Carry.AdvanceManualToss(onlineItem, 10.01, onSettled, false) and onlineModel.cage == nil)
assert(not Carry.AdvanceManualToss(onlineItem, 10.02, onSettled, true) and onlineModel.cage == "Chute")
assert(table.concat(Boundary.changes, ",") == "Chute,ground physics" and settled == 0)
assert(onlineModel.torso.AssemblyLinearVelocity.X == 30, "online thrower keeps client velocity untouched")
onlineModel.torso.Position = R.Vector3.new(12, 3, 0)
assert(not Carry.AdvanceManualToss(onlineItem, 10.025, onSettled, true) and onlineModel.cage == "Chute" and onlineModel.torso.Position.X == 12, "server never fights client physics with PivotTo")
-- 由测试中的客户端物理把白膜带回落料垫，再开始计算垫内稳定时间。
onlineModel.torso.Position = R.Vector3.new(10.5, 3, 0)
onlineModel.torso.AssemblyLinearVelocity = R.Vector3.zero
assert(not Carry.AdvanceManualToss(onlineItem, 10.03, onSettled, true))
assert(Carry.AdvanceManualToss(onlineItem, 10.2, onSettled, true) and settled == 1)
assert(#Boundary.changes == 2, "capture must not repeat while settling")

-- 2) 抛掷者离线兜底：服务端接管所有权并施加水平速度阻尼，保留竖直下落速度。
table.clear(Boundary.changes)
Boundary.Players.online[2] = nil
local offlineModel = makeModel(1)
local offlineItem = { model = offlineModel, stage = "Unpainted", poolToss = { kind = "Manual", started = 20, owner = 2, canEnterChute = true } }
assert(not Carry.AdvanceManualToss(offlineItem, 20.02, onSettled, true) and offlineModel.cage == "Chute")
assert(table.concat(Boundary.changes, ",") == "Chute,ground physics,server owner")
assert(offlineModel.torso.AssemblyLinearVelocity.X > 10 and offlineModel.torso.AssemblyLinearVelocity.X <= Physics.Cage.EntryMaxHorizontalSpeed, "offline fallback damps horizontal speed")
assert(offlineModel.torso.AssemblyLinearVelocity.Y == -5, "offline fallback preserves vertical drop speed")

-- 3) 纯算法软边界反弹与围观端撞击检测：轻弹吸能 + 回拉不卡墙 + 单体冷却支撑
local hx, hz = Geometry.InnerHalfSize(size, inset)
-- 笼内正常飞行未接近壁面 -> nil
assert(Geometry.ResolveSoftBounce(frame, size, inset, place(0, 4, 0), frame:VectorToWorldSpace(R.Vector3.new(10, -2, 0))) == nil, "interior flight must not bounce")
-- 向南壁高速穿出 -> 回拉至内侧 clearance，法向轻弹，切向衰减，角速度衰减，返回南墙内法线
local outVel = frame:VectorToWorldSpace(R.Vector3.new(10, -4, 20))
local bounce = Geometry.ResolveSoftBounce(frame, size, inset, place(1, 4, hz + 0.5), outVel)
assert(bounce ~= nil, "penetrating south wall must resolve bounce")
local localOffset = frame:VectorToObjectSpace(bounce.offset)
local localDelta = frame:VectorToObjectSpace(bounce.velocityDelta)
local afterLocalPos = frame:PointToObjectSpace(place(1, 4, hz + 0.5) + bounce.offset)
local afterLocalVel = frame:VectorToObjectSpace(outVel + bounce.velocityDelta)
assert(math.abs(afterLocalPos.Z - (hz - Physics.Cage.SoftBounceClearance)) < 0.01, "position pulled inside soft boundary")
assert(afterLocalVel.Z < -Physics.Cage.SoftBounceMinPush + 0.01 and math.abs(afterLocalVel.Z + 20 * Physics.Cage.SoftBounceRestitution) < 0.01, "normal speed uses soft restitution")
assert(math.abs(afterLocalVel.X - 10 * Physics.Cage.SoftBounceTangentDamping) < 0.01, "tangent speed damped")
assert(math.abs(afterLocalVel.Y + 4) < 0.01, "vertical speed preserved")
assert(bounce.angularScale == Physics.Cage.SoftBounceAngularDamping, "angular damping applied")
assert(bounce.hitWall == "South" and bounce.hitNormal ~= nil and frame:VectorToObjectSpace(bounce.hitNormal).Z < -0.99, "impact normal points inward")
-- 回拉后下一帧向内飞行不再触发二次反弹（杜绝反复反弹卡墙）
assert(Geometry.ResolveSoftBounce(frame, size, inset, frame:PointToWorldSpace(afterLocalPos), frame:VectorToWorldSpace(afterLocalVel)) == nil, "rebounded body moving inward must not re-bounce")
-- 围观客户端位置穿越软壁检测
local obsImpact = Geometry.DetectSoftImpact(frame, size, inset, place(0, 4, hz - 0.8), place(0, 4, hz + 0.1), R.Vector3.zero, 1 / 60)
assert(obsImpact ~= nil and obsImpact.wall == "South" and frame:VectorToObjectSpace(obsImpact.normal).Z < -0.99, "observer detects soft impact from displacement")
-- 已入笼但超时未稳的白膜必须在 MaxFlightSeconds + SoftBounceSettleGrace 后兜底收敛
local stuckSettled = 0
local stuckModel = makeModel(1)
local stuckItem = { model = stuckModel, stage = "Unpainted", poolToss = { kind = "Manual", started = 30, owner = 1, canEnterChute = true } }
assert(not Carry.AdvanceManualToss(stuckItem, 30.02, function() stuckSettled += 1 end, true) and stuckModel.cage == "Chute")
assert(not Carry.AdvanceManualToss(stuckItem, 30 + Physics.ManualThrow.MaxFlightSeconds + 0.1, function() stuckSettled += 1 end, true) and stuckSettled == 0)
assert(Carry.AdvanceManualToss(stuckItem, 30 + Physics.ManualThrow.MaxFlightSeconds + Physics.Cage.SoftBounceSettleGrace + 0.01, function() stuckSettled += 1 end, true) and stuckSettled == 1, "contained body settles after grace timeout")
print("PASS: collision matrix, soft cage geometry, and manual flight capture before settling")
