-- 离线验证祭坛抬升、确定性抛物线与落台时间轴、部件姿态归位和转化结算。
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
local manual, manualModel = body("shoulder", 1, false)
local start = model.PrimaryPart.CFrame.Position
local events = 0
local manager = setmetatable({
	items = {table = automatic, shoulder = manual},
	nextUpdate = math.huge,
	Changed = function() events += 1 end,
}, {__index = Manager})
local function step(now)
	B.now = now
	manager:Update()
end

local landSeconds = Config.LandSeconds or 0.32
check(automatic.altarToss.landEnds == Config.LiftSeconds + Config.FlightSeconds + landSeconds, "table toss schedules deterministic landing time")
check(manual.altarToss.landEnds == Config.FlightSeconds + landSeconds, "manual toss schedules deterministic landing time without lift")

step(Config.LiftSeconds / 2)
check(near(model.PrimaryPart.CFrame.Position, start + V.yAxis * Config.LiftHeight / 2), "table body lifts vertically before launch")
check(model.UpperTorso.Anchored and not model.UpperTorso.CanCollide, "no collisions during lift")
check(manual.altarToss.flightStarts == 0 and not near(manualModel.PrimaryPart.CFrame.Position, start), "manual toss skips table lift")
check(automatic.altarToss.rest.Position.Y < manual.altarToss.rest.Position.Y, "simultaneous tosses have independent layers")

step(Config.LiftSeconds)
check(near(model.PrimaryPart.CFrame.Position, start + V.yAxis * Config.LiftHeight), "arc starts at the lift endpoint")

step(Config.FlightSeconds)
check(manual.altarToss ~= nil and not manual.convertEnds, "manual flight enters landing buffer before conversion")
check(manualModel.UpperTorso.Anchored and not manualModel.UpperTorso.CanCollide, "landing buffer stays anchored without loose server physics")
check(B.altarOwner == nil and events == 0, "server never switches altar body into loose ragdoll physics")

local manualLandedAt = Config.FlightSeconds + landSeconds
step(manualLandedAt)
check(manual.altarToss == nil and manual.convertEnds == manualLandedAt + 5 and manual.version == 2, "manual toss lands deterministically and starts conversion")
check(manualModel:GetAttribute("PhysicsMode") == "AltarAnchored" and near(manualModel.PrimaryPart.CFrame.Position, Scene.AltarRest.CFrame.Position) == false, "manual toss anchors at its altar rest pose")
check( automatic.altarToss ~= nil and not automatic.convertEnds, "table toss continues its own clock independently")

local tableFlightEnd = Config.LiftSeconds + Config.FlightSeconds
step(tableFlightEnd + landSeconds * 0.5)
local drop = automatic.altarToss.rest + Scene.AltarRest.CFrame.UpVector * Config.DropClearance
check(model.PrimaryPart.CFrame.Position.Y < drop.Position.Y and model.PrimaryPart.CFrame.Position.Y > automatic.altarToss.rest.Position.Y, "landing phase smoothly descends from drop clearance to altar surface")
check(model.UpperTorso.Anchored and not automatic.convertEnds, "body remains anchored while descending onto altar")

local tableRest = automatic.altarToss.rest
local headRest = tableRest * model.Head:GetAttribute("RestPose")
local tableLandedAt = tableFlightEnd + landSeconds
step(tableLandedAt)
check(automatic.altarToss == nil and automatic.convertEnds == tableLandedAt + 5 and automatic.version == 2, "table toss completes landing and starts conversion once")
check(near(model.PrimaryPart.CFrame.Position, tableRest.Position) and near(model.Head.CFrame.Position, headRest.Position), "landing aligns root and limbs to altar rest pose")
check(model:GetAttribute("PhysicsMode") == "AltarAnchored", "final landing sets AltarAnchored mode")

local conversion = automatic.convertEnds
step(tableLandedAt + 1)
check(automatic.convertEnds == conversion and automatic.version == 2, "subsequent server ticks never restart conversion")
print("PASS", count, "altar toss assertions (deterministic trajectory; zero loose server physics)")
