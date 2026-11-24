-- 手动丢置离线规则：斜抛射程、扫掠时长、入池颜色条件与严格池边界
local Arc = require("./ThrowArc")
local Physics = require("./PhysicsConfig")
local R = require("@lune/roblox")
local Vector2, Vector3, CFrame = R.Vector2, R.Vector3, R.CFrame
local checks = 0
local function Check(value: boolean, label: string): ()
	checks += 1
	assert(value, label)
end
local gravity = 196.2
local config = Physics.ManualThrow
local direction = Vector3.zAxis
local velocity = Arc.LaunchVelocity(direction, gravity)
local angle = math.rad(config.AngleDegrees)
local speed = math.sqrt(config.RangeStuds * gravity / math.sin(angle * 2))
Check(math.abs(velocity.Magnitude - speed) < 1e-4, "launch speed")
Check(velocity.Y > 0 and velocity.Z > 0 and math.abs(velocity.X) < 1e-6, "launch axes")
local origin = Vector3.new(0, 5, 0)
Check((Arc.Position(origin, velocity, gravity, 0) - origin).Magnitude < 1e-6, "position at release")
local flight = 2 * velocity.Y / gravity
local landed = Arc.Position(origin, velocity, gravity, flight)
Check(math.abs(landed.Y - origin.Y) < 1e-3, "flat return height")
Check(math.abs((landed - origin).Z - config.RangeStuds) < 1e-3, "flat range")
local endVelocity = Arc.Velocity(velocity, gravity, flight)
Check(math.abs(endVelocity.Y + velocity.Y) < 1e-3, "symmetric vertical speed")
local shoulder = CFrame.new(0, 3, 0)
local launch = Arc.Origin(shoulder, direction)
Check(math.abs(launch.Z - config.ForwardStuds) < 1e-6 and math.abs(launch.Y - (3 + config.HeightStuds)) < 1e-6, "shoulder origin")
Check(Arc.Horizontal(Vector3.zero, Vector3.xAxis) == Vector3.xAxis, "horizontal fallback")
Check(Arc.StickDirection(Vector2.new(0.05, 0), Vector3.zAxis) == nil, "stick deadzone")
local aimed = Arc.StickDirection(Vector2.new(0, 1), Vector3.zAxis)
Check(aimed ~= nil and aimed:Dot(Vector3.zAxis) > 0.99, "stick forward")
local duration, point, missed = Arc.Sweep(origin, velocity, gravity, 0.05, 0.2, config.SweepSize, function(): nil
	return nil
end)
Check(math.abs(duration - 0.2) < 1e-6, "sweep miss duration")
Check((point - Arc.Position(origin, velocity, gravity, 0.2)).Magnitude < 1e-4, "sweep miss point")
Check(missed == nil, "sweep miss has no landing ring")
local cappedTime, cappedPoint, cappedSurface = Arc.Sweep(origin, velocity, gravity, 0.05, 2, config.SweepSize, function(): nil
	return nil
end, 3)
Check(cappedSurface == nil, "arc past the length cap has no landing")
Check(cappedTime < 2, "length cap stops before the time limit")
Check(math.abs((cappedPoint - origin).Magnitude - 3) < 0.05, "length cap follows the arc")
local hitTime, hitPoint, hitSurface = Arc.Sweep(origin, velocity, gravity, 0.05, 2, config.SweepSize, function(_frame: any, _size: any, delta: Vector3): any
	return { Distance = delta.Magnitude * 0.25, Position = Vector3.new(1, 2, 3), Normal = Vector3.yAxis }
end, 100)
Check(hitSurface ~= nil and ((hitSurface :: Vector3) - Vector3.new(1, 2, 3)).Magnitude < 1e-4, "landing is the surface hit")
Check(hitTime > 0 and hitTime < 2 and hitPoint.Y > (hitSurface :: Vector3).Y, "body stops above the surface")
local slope = Vector3.new(0, 3, 4).Unit
local _, _, _, reported = Arc.Sweep(origin, velocity, gravity, 0.05, 2, config.SweepSize, function(_frame: any, _size: any, delta: Vector3): any
	return { Distance = delta.Magnitude * 0.5, Position = Vector3.new(0, 1, 0), Normal = slope }
end, 100)
Check(reported ~= nil and (reported :: Vector3):Dot(slope) > 0.999, "sweep reports the landing normal")
local flat = Arc.RingCFrame(Vector3.new(4, 1, 2), Vector3.yAxis)
Check(math.abs(flat.Position.Y - (1 + config.RingLiftStuds)) < 1e-4 and flat.XVector:Dot(Vector3.yAxis) > 0.999, "flat landing lays the ring on the surface")
local sloped = Arc.RingCFrame(Vector3.zero, slope)
Check(sloped.XVector:Dot(slope) > 0.999 and math.abs(sloped.Position:Dot(slope) - config.RingLiftStuds) < 1e-4, "ring follows the sloped landing")
local dropped = Arc.LimitDrop(Vector3.new(12, -40, 3))
Check(math.abs(dropped.Y + config.SettleDropSpeed) < 1e-4 and dropped.X == 12 and dropped.Z == 3, "release drop is limited")
Check(Arc.LimitDrop(Vector3.new(1, -1, 0)).Y == -1, "gentle drop stays")
local first, finish, size0, size1 = Arc.BeamCurve(origin, velocity, gravity, flight / 2)
Check(Arc.IsFiniteVector(first.Position) and Arc.IsFiniteVector(finish.Position) and size0 > 0 and size1 > 0, "beam curve")
local floor = CFrame.new(10, 2, -4)
local size = Vector3.new(10, 1, 8)
local center = floor.Position
Check(Arc.InsidePoolStrict(floor, size, center + Vector3.new(4.9, 2, 3.9), 10), "inside strict pool")
Check(not Arc.InsidePoolStrict(floor, size, center + Vector3.new(6.2, 2, 0), 10), "pad outside strict pool")
Check(Arc.InsidePoolStrict(floor, size, center + Vector3.new(0, 0.5 + 10, 0), 10), "wall top included")
Check(not Arc.InsidePoolStrict(floor, size, center + Vector3.new(0, 0.5 + 10.2, 0), 10), "above wall excluded")
local poolKind, poolFull = Arc.Landing(true, false, 3, 8)
Check(poolKind == "Pool" and not poolFull, "store when room remains")
local fullKind, fullNotice = Arc.Landing(true, false, 8, 8)
Check(fullKind == "Ground" and fullNotice, "full pool stays on the ground and notifies")
local paintedKind, paintedNotice = Arc.Landing(true, true, 0, 8)
Check(paintedKind == "Ground" and not paintedNotice, "painted body does not enter the pool")
local outsideKind, outsideNotice = Arc.Landing(false, false, 0, 8)
Check(outsideKind == "Ground" and not outsideNotice, "outside the pool stays on the ground")
local unlimitedKind, unlimitedNotice = Arc.Landing(true, false, 100, nil)
Check(unlimitedKind == "Pool" and not unlimitedNotice, "unlimited pool accepts overflow throws")
print("throw arc checks", checks)
