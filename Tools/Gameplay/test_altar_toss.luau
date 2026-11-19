-- 离线验证祭坛抬升、服务端布娃娃交接、回收和转化结算。
local R = require("@lune/roblox")
local B = require("./Boundary")
local Carry = require("./Carry")
local Scene = require("./AltarScene")
local Manager = require("./AltarProcessing")
local Config = require("./PhysicsConfig").AltarToss
local F, V = R.CFrame, R.Vector3
local count = 0

local function check(ok, message)
	assert(ok, message)
	count += 1
end

local function near(a, b)
	return (a - b).Magnitude < 1e-4
end

local function body(id, layer, fromTable)
	local model = R.Instance.new("Model")
	for _, name in {"HumanoidRootPart", "UpperTorso", "Head"} do
		local part = R.Instance.new("Part")
		part.Name, part.Size, part.Parent = name, V.new(1, 1, 1), model
		local offset = if name == "Head" then F.new(0, 1, 0) else F.identity
		part.CFrame = F.new(4, 2, 1) * offset
		part:SetAttribute("RestPose", offset)
	end
	model.PrimaryPart = model.HumanoidRootPart
	model.Parent = B.world
	local item = {id = id, model = model, version = 1, location = "Altar"}
	Carry.BeginAltarToss(item, layer, fromTable, 0)
	return item, model
end

local automatic, model = body("table", 0, true)
local manual = body("shoulder", 1, false)
local escaped, escapedModel = body("escaped", 0, false)
local timeout, timeoutModel = body("timeout", 0, false)
local start = model.PrimaryPart.CFrame.Position
local events = 0
local manager = setmetatable({
	items = {table = automatic, shoulder = manual, escaped = escaped, timeout = timeout},
	nextUpdate = math.huge,
	Changed = function() events += 1 end,
}, {__index = Manager})
local function step(now)
	B.now = now
	manager:Update()
end

step(Config.LiftSeconds / 2)
check(near(model.PrimaryPart.CFrame.Position, start + V.yAxis * Config.LiftHeight / 2), "table body lifts vertically before launch")
check(model.UpperTorso.Anchored and not model.UpperTorso.CanCollide, "no collisions during lift")
check(manual.altarToss.flightStarts == 0 and not near(manual.model.PrimaryPart.CFrame.Position, start), "manual toss skips table lift")
check(automatic.altarToss.rest.Position.Y < manual.altarToss.rest.Position.Y, "simultaneous tosses have independent layers")
step(Config.LiftSeconds)
check(near(model.PrimaryPart.CFrame.Position, start + V.yAxis * Config.LiftHeight), "arc starts at the lift endpoint")
step(Config.FlightSeconds)
check(manual.altarToss.released ~= nil and automatic.altarToss.released == nil, "each flight releases on its own clock")
check(not escapedModel.UpperTorso.Anchored and escapedModel.UpperTorso.CanCollide, "release restores real physics and collisions")
check(B.altarOwner == nil and not escaped.convertEnds and events == 0, "server owns flight completion without a thrower or conversion")
local release = Config.LiftSeconds + Config.FlightSeconds
step(release)
check(automatic.altarToss.released == release and not model.UpperTorso.Anchored, "table flight releases at its endpoint")
local actualLanding = automatic.altarToss.rest + V.new(.3, 0, 0)
model.UpperTorso.CFrame = actualLanding
model.PrimaryPart.CFrame = actualLanding
model.Head.CFrame = actualLanding * F.new(0, .8, 0)
local originalHead = model.Head.CFrame
model.UpperTorso.AssemblyLinearVelocity = V.xAxis * (Config.StableSpeed + 1)

local outside = Scene.AltarRest.CFrame * F.new(0, 1, 6)
escapedModel.UpperTorso.CFrame = outside
escapedModel.PrimaryPart.CFrame = outside
local recoverAt = release + .1
step(recoverAt)
check(escaped.altarToss.recovery ~= nil and near(escapedModel.PrimaryPart.CFrame.Position, outside.Position), "recovery starts from the visible pose")
check(escapedModel.UpperTorso.Anchored and not escapedModel.UpperTorso.CanCollide, "recovery suspends collisions")
check(not automatic.convertEnds and not escaped.convertEnds, "conversion waits for actual settling")
check(automatic.altarToss.stableSince == nil, "a moving torso within the altar stays under physics")
model.UpperTorso.AssemblyLinearVelocity = V.zero
step(recoverAt + .01)
local rest = escaped.altarToss.rest
local headRest = rest * escapedModel.Head:GetAttribute("RestPose")
step(recoverAt + Config.RecoverySeconds / 2)
check(near(escapedModel.PrimaryPart.CFrame.Position, outside.Position:Lerp(rest.Position, .5)), "recovery has a continuous midpoint")
check(model.UpperTorso.Anchored and model.Head.CFrame == originalHead, "normal settling preserves each body's actual pose")
local conversion = automatic.convertEnds
check(conversion == B.now + 5 and automatic.version == 2, "normal landing starts conversion once")
step(recoverAt + Config.RecoverySeconds + .001)
check(near(escapedModel.PrimaryPart.CFrame.Position, rest.Position) and near(escapedModel.Head.CFrame.Position, headRest.Position), "recovery ends at the surface pose")
check(escapedModel:GetAttribute("PhysicsMode") == "AltarAnchored" and escaped.convertEnds == B.now + 5, "only final recovery anchors and starts conversion")
step(Config.FlightSeconds + Config.SettleSeconds + .001)
check(timeout.altarToss.recovery ~= nil and timeoutModel.UpperTorso.Anchored and not timeout.convertEnds, "settle timeout enters recovery")
check(automatic.convertEnds == conversion and automatic.version == 2, "subsequent server ticks never restart conversion")
print("PASS", count, "altar toss assertions (production state machine; engine physics mocked)")
