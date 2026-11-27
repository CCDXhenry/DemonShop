-- 离线验证正式搬运模块的肩位、路径、补位与取消。
local R = require("@lune/roblox")
local B = require("./Boundary")
local Carry = require("./Carry")
local Physics = require("./PhysicsConfig")
local F, V = R.CFrame, R.Vector3
local stackConfig = Physics.CarryStack
local duration = Physics.Presentation.Carry.LiftSeconds
local count = 0
local function check(ok, name)
	assert(ok, name)
	count += 1
end
local function near(a, b)
	return math.abs(a - b) < 1e-4
end
local function sameFrame(a, b)
	return (a.Position - b.Position).Magnitude < 1e-4
		and (a.RightVector - b.RightVector).Magnitude < 1e-4
		and (a.UpVector - b.UpVector).Magnitude < 1e-4
end
local function part(parent, name, size, frame)
	local value = R.Instance.new("Part")
	value.Name, value.Size, value.CFrame, value.Parent = name, size, frame, parent
	return value
end
B.unequip = function(humanoid)
	local weapon = humanoid.Parent:FindFirstChild("W01_RustyPan")
	if weapon then weapon.Parent = B.backpack end
end
B.equip = function(humanoid, weapon) weapon.Parent = humanoid.Parent end
B.now = 1
local character = R.Instance.new("Model")
local size = V.new(2, 1.6, 1)
part(character, "HumanoidRootPart", size, F.identity)
local shoulder = part(character, "UpperTorso", size, F.new(0, 4, 0))
local humanoid = R.Instance.new("Humanoid")
humanoid.Health, humanoid.Parent = 100, character
B.backpack = R.Instance.new("Backpack")
local tool = R.Instance.new("Tool")
tool.Name, tool.Parent = "W01_RustyPan", character
local player = {Character=character, FindFirstChild=function(_, name) return if name == "Backpack" then B.backpack else nil end}
local function take(layer)
	local model = R.Instance.new("Model")
	local from = F.new(0, 0, -4) * F.Angles(math.pi / 2, 0, 0)
	model.PrimaryPart = part(model, "HumanoidRootPart", size, from)
	part(model, "UpperTorso", size, from)
	local item = {kind="Body", model=model, version=0}
	check(Carry.Take(item, player, layer), "valid body pickup")
	check(sameFrame(item.model.UpperTorso.CFrame, from) and sameFrame(item.carryTransition.from, from), "keep source pose on pickup")
	check(sameFrame(item.carryTarget.CFrame, shoulder.CFrame:ToObjectSpace(from)), "attachment starts on the actual torso")
	return item
end
local items = {}
for layer = 0, 31 do
	local item = take(layer)
	table.insert(items, item)
	Carry.Restack(items)
	check(item.carryLayer == layer, "uses final layer at pickup")
	check(item.carryTransition.started == 1 and sameFrame(item.carryTransition.from, item.model.UpperTorso.CFrame), "adding layers preserves lift origins")
	local position = item.carryBaseOffset.Position
	if layer == 0 then
		check(sameFrame(item.carryBaseOffset, F.new(Physics.ShoulderOffset) * Physics.ShoulderRotation), "base shoulder pose")
	else
		local previous = items[layer].carryBaseOffset.Position
		local gap = if layer == 1 then stackConfig.SecondGap elseif layer == 2 then stackConfig.ThirdGap
			else stackConfig.NextGap * stackConfig.GapDecay ^ (layer - 3)
		check(position.Y > previous.Y and near(position.Y - previous.Y, gap), "increasing layer heights")
		check(near(position.X - Physics.ShoulderOffset.X, if layer % 2 == 1 then stackConfig.SideOffset else -stackConfig.SideOffset), "alternating layer offsets")
		check(position.Z >= previous.Z and position.Z <= Physics.ShoulderOffset.Z + stackConfig.BackLimit + 1e-4, "bounded rear offset")
	end
end
check(tool.Parent == character, "picking up and stacking bodies keeps the equipped weapon")
local top = items[32]
local limit = Physics.ShoulderOffset.Y + stackConfig.SecondGap + stackConfig.ThirdGap + stackConfig.NextGap / (1 - stackConfig.GapDecay)
check(top.carryBaseOffset.Position.Y < limit, "32 bodies stay below the height limit")
local first = items[1]
local function sample(item, t)
	Carry.AdvanceTransition(item, B.now + duration * t)
	return shoulder.CFrame * item.carryTarget.CFrame
end
local takeoff = sample(first, .2).Position
check(near(takeoff.X, 0) and near(takeoff.Z, -4) and takeoff.Y > 0, "lift vertically before moving toward player")
local arc = sample(top, stackConfig.LandFraction).Position
local finish = (shoulder.CFrame * top.carryBaseOffset).Position
check(near(arc.Y - finish.Y, stackConfig.ArcClearance) and near(arc.X - finish.X, stackConfig.OutsideClearance), "approach above and outside the final layer")
local movement = V.new(3, 1, 2)
shoulder.CFrame += movement
local dip = sample(top, stackConfig.DipFraction).Position
check((dip - finish - movement + V.yAxis * stackConfig.SettleDepth).Magnitude < 1e-4, "dips once and tracks a moving shoulder at landing")
check((sample(top, 1).Position - (shoulder.CFrame * top.carryBaseOffset).Position).Magnitude < 1e-4, "finish tracks a moving shoulder")
check(top.carryTransition == nil, "lift clears on completion")
for _, item in items do sample(item, 1) end
B.now += duration
Carry.Detach(table.remove(items))
Carry.Restack(items)
check(items[31].carryLayer == 30 and items[31].carryTransition == nil, "top removal does not disturb lower layers")
Carry.Detach(table.remove(items, 2))
local shifted = items[2]
local from = shifted.carryTarget.CFrame
Carry.Restack(items)
check(first.carryTransition == nil and shifted.carryLayer == 1 and sameFrame(shifted.carryTransition.from, from), "middle removal shifts only higher layers")
Carry.AdvanceTransition(shifted, B.now + stackConfig.RestackSeconds * .5)
local halfway = shifted.carryTarget.CFrame
check(near(halfway.Position.Y, (from.Position.Y + shifted.carryBaseOffset.Position.Y) * .5), "supplementary move interpolates")
B.now += stackConfig.RestackSeconds * .5
local nextShifted = items[3]
Carry.AdvanceTransition(nextShifted, B.now)
local activePose = nextShifted.carryTarget.CFrame
Carry.Detach(table.remove(items, 2))
Carry.Restack(items)
check(nextShifted.carryLayer == 1 and sameFrame(nextShifted.carryTransition.from, activePose), "second removal rebases the active transition")
local lifting = take(#items)
table.insert(items, lifting)
Carry.AdvanceTransition(lifting, B.now + .1)
B.now += .1
activePose = shoulder.CFrame * lifting.carryTarget.CFrame
Carry.Detach(table.remove(items, 2))
Carry.Restack(items)
check(lifting.carryTransition.kind == "Lift" and sameFrame(lifting.carryTransition.from, activePose), "shift a lifting body from its current target")
for _, item in items do
	Carry.Detach(item)
	check(not item.carryTransition and not item.carryLayer and not item.carryTarget and not item.carryResources
		and not item.model.UpperTorso:FindFirstChild("CarryAnchor"), "detach cancels the entire transition")
end
shoulder.Size = size * 1.5
local scaled = take(1)
local offset = (Physics.ShoulderOffset + V.new(stackConfig.SideOffset, stackConfig.SecondGap, stackConfig.BackStep)) * 1.5
check(sameFrame(scaled.carryBaseOffset, F.new(offset) * F.Angles(0, stackConfig.Yaw, 0) * Physics.ShoulderRotation), "layer scales with the player's torso")
tool.Parent = B.backpack
Carry.Static(scaled, F.identity)
check(tool.Parent == B.backpack, "station drop-off leaves a holstered weapon in the backpack")
local dropped = take(0)
Carry.Detach(dropped)
check(tool.Parent == B.backpack, "detaching the last body does not auto-equip the weapon")
check(not shoulder:FindFirstChild("WhiteBodyShoulder"), "all shoulder attachments released")
print("PASS", count, "carry stack assertions")
