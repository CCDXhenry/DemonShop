-- Studio 客户端热调：验证完整快照，在仿真步边界发布不可变配置。
--!strict
local RunService = game:GetService("RunService")
local Physics = require(script.Parent.Parent.Shared.PhysicsConfig)
local Tuning = {}
type Values = {[string]: {[string]: number}}
type Range = {number}
local ranges: {[string]: {[string]: Range}} = {
	Contact={WaistDegrees={0,45},StrongDegrees={0,45},FrequencyHz={0.1,30},DampingRatio={0.1,3},DelaySeconds={0,0.08},EnterPad={0,1},ExitPad={0,1.5}},
	Hit={FrequencyHz={0.1,30},DampingRatio={0.1,3},FirstDegrees={0,45},SecondDegrees={0,60},DelaySeconds={0,0.1}},
	Fall={PhysicsSeconds={0,0.65},TipSeconds={0.18,0.65},HoldSeconds={0,.25},NearStuds={1,60},DesktopBodies={0,2},MobileBodies={0,1},JointLimit={0,6}}, Carry={LiftSeconds={0.01,2}},
	LOD={NearStuds={1,500}, FarStuds={1,2000}}, Limits={MaxStepSeconds={1/240,0.1}, AngularSpeed={1,60}},
}
local effective = Physics.Presentation
local pending: Physics.Presentation? = nil
local activeRevision, lastRevision = 0, 0
local function InStudio(): boolean
	return RunService:IsStudio() and RunService:IsClient()
end
function Tuning.ApplyOverrides(patch: unknown, revision: number): (boolean, string?)
	if not InStudio() then return false, "Studio client required" end
	if typeof(revision) ~= "number" or revision ~= math.floor(revision) or revision <= lastRevision or not (revision <= 2^53-1) then return false, "invalid revision" end
	if typeof(patch) ~= "table" then return false, "expected patch table" end
	local candidate: Values = {}
	for group, values in ((pending or effective) :: unknown) :: Values do candidate[group] = table.clone(values) end
	for group, fields in patch :: {[unknown]: unknown} do
		if typeof(group) ~= "string" or not candidate[group] or typeof(fields) ~= "table" then return false, "unknown group or invalid fields" end
		for key, value in fields :: {[unknown]: unknown} do
			if typeof(key) ~= "string" or candidate[group][key] == nil or typeof(value) ~= "number" then return false, "unknown or non-numeric parameter" end
			candidate[group][key] = value
		end
	end
	for group, fields in candidate do
		for key, value in fields do
			local range = ranges[group][key]
			if not (value >= range[1] and value <= range[2]) then return false, group.."."..key.." out of range" end
		end
		table.freeze(fields)
	end
	if candidate.Contact.EnterPad > candidate.Contact.ExitPad then return false, "contact hysteresis inverted" end
	if candidate.LOD.NearStuds >= candidate.LOD.FarStuds then return false, "LOD distances must increase" end
	pending = (table.freeze(candidate) :: unknown) :: Physics.Presentation
	lastRevision = revision
	return true, nil
end
function Tuning.Reset()
	if InStudio() then pending = Physics.Presentation; lastRevision += 1 end
end
function Tuning.Commit()
	if pending then effective, activeRevision, pending = pending, lastRevision, nil end
end
function Tuning.GetEffectiveConfig(): (Physics.Presentation, number)
	return effective, activeRevision
end
return Tuning
