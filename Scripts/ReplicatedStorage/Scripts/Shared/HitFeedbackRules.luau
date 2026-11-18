-- 受击反馈规则：攻击预测关联、目标版本去重及按绝对时间计算动作包络
--!strict
local Rules = {}
export type Prediction = { target: string?, due: number, expires: number, played: boolean, resolved: boolean }
export type State = { pending: {[number]: Prediction}, versions: {[string]: number} }
function Rules.New(): State
	return {pending={}, versions={}}
end
function Rules.Begin(state: State, sequence: number, target: string?, due: number, expires: number): ()
	state.pending[sequence]={target=target,due=due,expires=expires,played=false,resolved=false}
end
function Rules.TakePrediction(state: State, sequence: number, now: number): string?
	local prediction=state.pending[sequence]
	if not prediction or prediction.resolved or prediction.played or now<prediction.due or now>prediction.expires then return nil end
	prediction.played=true
	return prediction.target
end
function Rules.Confirm(state: State, id: string, version: number, sequence: number?): boolean
	local prediction=if sequence then state.pending[sequence] else nil
	local duplicate=prediction~=nil and prediction.played and prediction.target==id
	if prediction then prediction.resolved=true end
	local previous=state.versions[id] or 0
	if version<=previous then return false end
	state.versions[id]=version
	return not duplicate
end
function Rules.Result(state: State, sequence: number, hit: boolean): ()
	local prediction=state.pending[sequence]
	-- Successful results can arrive before Hit; retain the played flag for deduplication.
	if prediction and not hit then state.pending[sequence]=nil end
end
function Rules.Prune(state: State, now: number): ()
	for sequence,prediction in state.pending do
		if now>prediction.expires then state.pending[sequence]=nil end
	end
end
function Rules.Envelope(age: number, duration: number, peak: number): number
	if age<0 or age>=duration then return 0 end
	if age<peak then return math.sin(age/peak*math.pi/2) end
	local t=(age-peak)/(duration-peak)
	return math.cos(t*math.pi*1.5)*(1-t)^2
end
return Rules
