-- 服务端维护冲刺意图、耐力、角色合法速度和水平位移预算
--!strict
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Config = require(Shared.GameConfig)
local Rules = require(Shared.PersonalUpgradeRules)

local Movement = {}
local Sprint = Config.Sprint
export type State = {
	wanted: boolean,
	stamina: number,
	recoverDelay: number,
	exhausted: boolean,
	nextReplication: number,
	nextCheck: number,
	lastCheck: number,
	lastPosition: Vector3?,
	distanceCredit: number,
	speed: number,
}

function Movement.New(): State
	return {
		wanted = false, stamina = Sprint.stamina, recoverDelay = 0, exhausted = false,
		nextReplication = 0, nextCheck = 0, lastCheck = 0, lastPosition = nil,
		distanceCredit = Sprint.distanceTolerance, speed = 0,
	}
end

function Movement.Publish(state: State, character: Model, speed: number, active: boolean): ()
	character:SetAttribute("PersonalWalkSpeed", speed)
	character:SetAttribute("PersonalSprinting", active)
	character:SetAttribute("PersonalStamina", math.round(state.stamina))
end

local function CheckDisplacement(state: State, root: BasePart, speed: number, now: number): ()
	if now < state.nextCheck then
		return
	end
	state.nextCheck = now + Sprint.speedCheckInterval
	local position = root.Position
	local previous = state.lastPosition
	local dt = now - state.lastCheck
	state.lastCheck = now
	if previous then
		local available = state.distanceCredit + (math.max(speed, state.speed) + Sprint.speedTolerance) * dt
		local delta = Vector3.new(position.X - previous.X, 0, position.Z - previous.Z)
		if delta.Magnitude > available then
			local excess = delta.Unit * (delta.Magnitude - available)
			root.CFrame -= excess
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
			position -= excess
		end
		state.distanceCredit = math.clamp(available - delta.Magnitude, 0, Sprint.distanceTolerance)
	end
	state.lastPosition = position
	state.speed = speed
end

function Movement.Step(state: State, character: Model, level: number, painting: boolean, now: number, dt: number): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local tier = Rules.GetMoveTier(level)
	if painting then
		state.wanted = false
	end
	local canMove = not painting and not root.Anchored and not humanoid.SeatPart
	local active = canMove and state.wanted and (tier.unlimited or not state.exhausted)
	local velocity = root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 1
	state.stamina, state.recoverDelay = Rules.StepStamina(state.stamina, state.recoverDelay, active and moving, tier.unlimited, math.min(dt, 0.25))
	if state.stamina <= 0 then
		state.exhausted = true
		active = false
	elseif state.stamina >= Sprint.restartStamina then
		state.exhausted = false
	end
	local speed = if painting then 0 elseif active then tier.sprint else tier.walk
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
	if canMove then
		CheckDisplacement(state, root, speed, now)
	else
		state.lastPosition = nil
		state.distanceCredit = Sprint.distanceTolerance
	end
	if now >= state.nextReplication then
		state.nextReplication = now + Sprint.replicationInterval
		Movement.Publish(state, character, speed, active)
	end
end

return Movement
