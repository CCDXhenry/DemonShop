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

local function body(id, fromTable)
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
	Carry.BeginAltarToss(item, fromTable, 0)
	return item, model
end

local automatic, model = body("table", true)
local manual, manualModel = body("shoulder", false)
local initialAutoCFrame = model.PrimaryPart.CFrame
local initialManualCFrame = manualModel.PrimaryPart.CFrame
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
check(model.PrimaryPart.CFrame == initialAutoCFrame, "server skips per-frame PivotTo during table lift")
check(model.UpperTorso.Anchored and not model.UpperTorso.CanCollide, "no collisions during lift")
check(manual.altarToss.flightStarts == 0 and manualModel.PrimaryPart.CFrame == initialManualCFrame, "manual toss skips table lift and per-frame server PivotTo")
check(near(automatic.altarToss.rest.Position, manual.altarToss.rest.Position) and near(automatic.altarToss.mouth.Position, Scene.AltarMouth.WorldCFrame.Position), "both sources feed the same furnace mouth")

step(Config.LiftSeconds)
check(model.PrimaryPart.CFrame == initialAutoCFrame and automatic.altarToss.flightStarts == Config.LiftSeconds, "server keeps body untouched at lift endpoint")

step(Config.FlightSeconds)
check(manual.altarToss ~= nil and not manual.convertEnds, "manual flight enters landing buffer before conversion")
check(manualModel.PrimaryPart.CFrame == initialManualCFrame, "server skips per-frame PivotTo before manual landEnds")
check(manualModel.UpperTorso.Anchored and not manualModel.UpperTorso.CanCollide, "landing buffer stays anchored without loose server physics")
check(B.altarOwner == nil and events == 0, "server never switches altar body into loose ragdoll physics")

local manualRest = manual.altarToss.rest
local manualLandedAt = Config.FlightSeconds + landSeconds
step(manualLandedAt + 0.02)
check(manual.altarToss == nil and manual.convertEnds == manualLandedAt + 5 and manual.version == 2, "manual toss lands deterministically and starts conversion")
check(manualModel:GetAttribute("PhysicsMode") == "AltarAnchored" and near(manualModel.PrimaryPart.CFrame.Position, manualRest.Position), "manual toss anchors at its altar rest pose")
check(automatic.altarToss ~= nil and not automatic.convertEnds and model.PrimaryPart.CFrame == initialAutoCFrame, "table toss continues its own clock without per-frame PivotTo")

local tableFlightEnd = Config.LiftSeconds + Config.FlightSeconds
step(tableFlightEnd + landSeconds * 0.5)
check(model.PrimaryPart.CFrame == initialAutoCFrame, "server skips per-frame PivotTo during landing cushion before landEnds")
check(model.UpperTorso.Anchored and not automatic.convertEnds, "body remains anchored while client animates descent")

local tableRest = automatic.altarToss.rest
local headRest = tableRest * model.Head:GetAttribute("RestPose")
local tableLandedAt = tableFlightEnd + landSeconds
step(tableLandedAt)
check(automatic.altarToss == nil and automatic.convertEnds == tableLandedAt + 5 and automatic.version == 2, "table toss completes landing and starts conversion once")
check(near(model.PrimaryPart.CFrame.Position, tableRest.Position) and near(model.Head.CFrame.Position, headRest.Position), "landing aligns root and limbs to altar rest pose")
check(model:GetAttribute("PhysicsMode") == "AltarAnchored", "final landing sets AltarAnchored mode")
check(model.UpperTorso.Transparency == 1 and not model.UpperTorso.CanCollide and not model.UpperTorso.CanTouch and not model.UpperTorso.CanQuery,
	"intake hides the authority body and disables all contacts")

local conversion = automatic.convertEnds
step(tableLandedAt + 1)
check(automatic.convertEnds == conversion and automatic.version == 2, "subsequent server ticks never restart conversion")

do
	local unflippedModel = R.Instance.new("Model")
	local flippedModel = R.Instance.new("Model")
	for _, m in {unflippedModel, flippedModel} do
		local base = if m == flippedModel then F.new(4, 2, 1) * F.Angles(0, math.pi, 0) else F.new(4, 2, 1)
		for _, name in {"HumanoidRootPart", "UpperTorso", "Head"} do
			local part = R.Instance.new("Part")
			part.Name, part.Size, part.Parent = name, V.new(1, 1, 1), m
			local offset = if name == "Head" then F.new(0, 1, 0) else F.identity
			part.CFrame = base * offset
			part:SetAttribute("RestPose", offset)
		end
		m.PrimaryPart = m.HumanoidRootPart
		m.Parent = B.world
	end
	local unflippedItem = {id = "same-flip-id", model = unflippedModel, version = 1, location = "Altar", paintFlipped = false}
	local flippedItem = {id = "same-flip-id", model = flippedModel, version = 1, location = "Altar", paintFlipped = true}
	Carry.BeginAltarToss(unflippedItem, true, 0)
	Carry.BeginAltarToss(flippedItem, true, 0)
	check(unflippedItem.altarToss.rest.LookVector:Dot(flippedItem.altarToss.rest.LookVector) < -0.9,
		"flipped body lands face-down opposite to unflipped rest pose")
	unflippedModel:Destroy()
	flippedModel:Destroy()
end

print("PASS", count, "altar toss assertions (deterministic trajectory; zero loose server physics)")
