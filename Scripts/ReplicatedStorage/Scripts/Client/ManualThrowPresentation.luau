-- 白膜手动投掷的本地翻滚、关节滞后、碰撞避让和落地缓冲。
--!strict
local Shared = script.Parent.Parent.Shared
local Arc = require(Shared.ThrowArc)
local Types = require(Shared.GameTypes)
local Adapter = require(script.Parent.JointAdapter)

local Visual = {}
local HandoffSeconds = 0.10
local StateGraceSeconds = 0.35
local GainRecoveryPerSecond = 8
local GainSteps = {1, 0.5, 0}

type Link = {
	part: BasePart, source: BasePart, parent: BasePart,
	attach: CFrame, detach: CFrame, weight: number, lag: number,
}

export type State = {
	toss: Types.PoolToss,
	version: number,
	ends: number,
	root: BasePart,
	sourceRoot: BasePart,
	model: Model,
	links: {Link},
	scenery: OverlapParams,
	gain: number,
	lastTime: number,
	handoffAt: number?,
	handoffFrom: {[BasePart]: CFrame}?,
}

local function Smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

function Visual.Ends(toss: Types.PoolToss): number
	local drop = toss.chuteDropFrom
	return toss.started + (toss.duration or 0)
		+ (if drop then Arc.DropDuration(drop, toss.target.Position, workspace.Gravity) else 0)
end

local function Rest(part: BasePart, root: BasePart): CFrame
	local rest = part:GetAttribute("RestPose")
	return if typeof(rest) == "CFrame" then rest else root.CFrame:ToObjectSpace(part.CFrame)
end

function Visual.Begin(model: Model, source: Model, joints: Adapter.Map, sourceJoints: Adapter.Map, toss: Types.PoolToss, version: number): State
	local root, sourceRoot = assert(model.PrimaryPart), assert(source.PrimaryPart)
	local links: {Link} = {}
	local function Collect(parent: BasePart)
		for name, joint in joints do
			if joint.parent ~= parent then continue end
			local lag, weight = 0.05, 0.16
			if string.find(name, "Shoulder") or string.find(name, "Hip") then
				lag, weight = 0.12, 0.78
			elseif string.find(name, "Elbow") or string.find(name, "Knee") then
				lag, weight = 0.24, 0.92
			elseif string.find(name, "Wrist") or string.find(name, "Ankle") then
				lag, weight = 0.32, 0.42
			end
			local rotation = (joint.c0.Rotation:Inverse() * Rest(parent, root).Rotation:Inverse()).RightVector
			local rest = (Rest(parent, root) * joint.c0):ToObjectSpace(Rest(joint.child, root) * joint.c1)
			local side = if string.sub(name, 1, 5) == "Right" then -1 else 1
			table.insert(links, {part=joint.child, source=sourceJoints[name].child, parent=parent,
				attach=joint.c0 * CFrame.fromRotationBetweenVectors(Vector3.xAxis, rotation),
				detach=CFrame.fromRotationBetweenVectors(rotation, Vector3.xAxis) * rest * joint.c1:Inverse(),
				weight=weight*side, lag=lag})
			Collect(joint.child)
		end
	end
	Collect(root)
	local filters: {Instance} = {workspace.Terrain}
	local district = workspace:FindFirstChild("NeonContractDistrict")
	if district then table.insert(filters, district) end
	local params = OverlapParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Include, filters
	params.RespectCanCollide, params.MaxParts = true, 1
	return {toss=toss,version=version,ends=Visual.Ends(toss),root=root,sourceRoot=sourceRoot,model=model,
		links=links,scenery=params,gain=1,lastTime=toss.started}
end

local function Fits(state: State): boolean
	local bounds, size = state.model:GetBoundingBox()
	if #workspace:GetPartBoundsInBox(bounds, size, state.scenery) == 0 then return true end
	for _, link in state.links do
		if #workspace:GetPartsInPart(link.part, state.scenery) ~= 0 then return false end
	end
	return true
end

local function Apply(state: State, root: CFrame, progress: number, phase: number, gain: number)
	state.root.CFrame = root
	for _, link in state.links do
		local swing = math.sin(2 * math.pi * (progress - link.lag)) * link.weight * phase * gain
		link.part.CFrame = link.parent.CFrame * link.attach * CFrame.Angles(swing, 0, 0) * link.detach
	end
end

-- 返回是否仍持有表现以及这一帧是否可安全显示本地姿态。
function Visual.Step(state: State, item: Types.ItemView, now: number): (boolean, boolean)
	local root, sourceRoot, toss = state.root, state.sourceRoot, state.toss
	if root.Parent ~= state.model or sourceRoot ~= item.model.PrimaryPart then return false, false end
	local elapsed = math.max(0, now - toss.started)
	local duration = toss.duration or 0
	local drop = toss.chuteDropFrom
	local base, roll, phase = toss.target, 0, 0
	local progress = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1
	if item.location == "Thrown" then
		if item.version ~= state.version or not item.toss or item.toss.started ~= toss.started
			or now > state.ends + StateGraceSeconds then return false, false end
		if elapsed < duration and toss.velocity then
			local point = Arc.Position(toss.from.Position, toss.velocity, workspace.Gravity, elapsed)
			local pose = CFrame.new(point) * (toss.releaseRotation or toss.from.Rotation):Lerp(toss.from.Rotation, Smooth(progress / 0.24))
			base = pose:Lerp(if drop then CFrame.new(drop) * toss.target.Rotation else toss.target, Smooth((progress - 0.76) / 0.24))
			phase, roll = Arc.VisualFlight(progress, duration)
		elseif drop and now < state.ends then
			local point = Arc.DropPosition(drop, toss.target.Position, workspace.Gravity, elapsed - duration)
			local dropProgress = (now - toss.started - duration) / (state.ends - toss.started - duration)
			base = CFrame.new(point) * toss.target.Rotation
			progress, phase = dropProgress, 0.16 * math.sin(math.pi * dropProgress)
		end
	elseif item.version ~= state.version + 1 then
		return false, false
	elseif item.location == "Ground" then
		local age = now - state.ends
		if age >= Arc.VisualBounceSeconds and ((sourceRoot.Position - toss.target.Position).Magnitude < 0.08
			or age >= StateGraceSeconds) then return false, false end
		progress = math.clamp(age / Arc.VisualBounceSeconds, 0, 1)
		phase = Arc.VisualBounce(age) * 2
		base = toss.target
	elseif item.location == "Pool" or item.location == "Chute" then
		local starts = state.handoffAt or now
		if not state.handoffAt then
			local frames = { [root] = root.CFrame }
			for _, link in state.links do frames[link.part] = link.part.CFrame end
			state.handoffAt, state.handoffFrom = starts, frames
		end
		local blend = (now - starts) / HandoffSeconds
		if blend >= 1 then return false, false end
		local frames = assert(state.handoffFrom)
		root.CFrame = frames[root]:Lerp(sourceRoot.CFrame, Smooth(blend))
		for _, link in state.links do
			link.part.CFrame = frames[link.part]:Lerp(link.source.CFrame, Smooth(blend))
		end
		return true, Fits(state)
	else
		return false, false
	end
	local rebound = if item.location == "Ground" then Arc.VisualBounce(now - state.ends) else 0
	local gain = math.min(1, state.gain + math.max(0, now - state.lastTime) * GainRecoveryPerSecond)
	state.lastTime = now
	local rotation = CFrame.Angles(math.sin(roll) * 0.38, roll, 0)
	local normal = toss.target:VectorToWorldSpace(toss.from:VectorToObjectSpace(Vector3.yAxis))
	for _, multiplier in GainSteps do
		local amount = gain * multiplier
		local pose = (base + normal * rebound * amount) * CFrame.identity:Lerp(rotation, amount)
		Apply(state, pose, progress, phase, amount)
		if Fits(state) then
			state.gain = amount
			return true, true
		end
	end
	state.gain = 0
	-- 贴得太近时以已复制的安全姿态继续显示同一具本地模型。
	root.CFrame = sourceRoot.CFrame
	for _, link in state.links do link.part.CFrame = link.source.CFrame end
	return true, Fits(state)
end

return Visual
