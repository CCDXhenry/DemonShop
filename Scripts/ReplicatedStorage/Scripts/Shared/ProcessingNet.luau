-- 加工网络封装：可靠动作请求、状态通知及边界类型校验
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(script.Parent.GameTypes)
local Surface = require(script.Parent.PaintSurface)
local VisualRules = require(script.Parent.VisualRules)
local Config = require(script.Parent.GameConfig)
local Curve = require(script.Parent.CurvedSurface)
local BodyPose = require(script.Parent.PaintBodyPose)
local folder = ReplicatedStorage:WaitForChild("RemoteEvents")
local requestEvent = folder:WaitForChild("GameRequest") :: RemoteEvent
local notifyEvent = folder:WaitForChild("GameNotify") :: RemoteEvent
local Net = {}
function Net.Validate(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local r = value :: { [string]: unknown }
	if r.attackSequence ~= nil and (not Surface.IsFinite(r.attackSequence) or (r.attackSequence :: number) < 1 or (r.attackSequence :: number) % 1 ~= 0 or (r.attackSequence :: number) > 9007199254740991) then return false end
	if r.bodyPose~=nil and not BodyPose.ValidateWire(r.bodyPose) then return false end
	if typeof(r.action) ~= "string" or #r.action > 24 then
		return false
	end
	if r.target ~= nil and (typeof(r.target) ~= "string" or #r.target > 80) then
		return false
	end
	if r.session ~= nil and (typeof(r.session) ~= "string" or #r.session > 80) then
		return false
	end
	if r.version ~= nil and (not Surface.IsFinite(r.version) or (r.version :: number) % 1 ~= 0) then
		return false
	end
	for _, name in { "yaw", "pitch" } do
		if r[name] ~= nil and not Surface.IsFinite(r[name]) then
			return false
		end
	end
	if r.action == "PaintVisual" then
		if not Surface.IsFinite(r.sequence) or (r.sequence :: number) < 1 or (r.sequence :: number) % 1 ~= 0 or not Surface.IsFinite(r.started) then return false end
		if typeof(r.segments) ~= "table" then return false end
		local segments = r.segments :: {unknown}
		if #segments > Config.PaintVisualBatchSize then return false end
		local count=0
		for index,segment in segments do
			count+=1
			if count>Config.PaintVisualBatchSize or typeof(index)~="number" or index%1~=0 or index<1 or index>#segments or not VisualRules.Validate(segment) then return false end
		end
		if count~=#segments then return false end
	end
	if r.action == "EndPaint" and r.sequence ~= nil and (not Surface.IsFinite(r.sequence) or (r.sequence :: number) < 0 or (r.sequence :: number) % 1 ~= 0) then return false end
	if r.action == "Paint" then
		if not Surface.IsFinite(r.sequence) or (r.sequence :: number) % 1 ~= 0 or (r.sequence :: number) < 1 then return false end
		local samples = r.samples
		if typeof(samples) ~= "table" then
			return false
		end
		local list = samples :: { unknown }
		if #list > 12 then
			return false
		end
		for _, raw in ipairs(list) do
			if typeof(raw) ~= "table" then
				return false
			end
			local s = raw :: { [string]: unknown }
			if s.breakBefore ~= nil and typeof(s.breakBefore) ~= "boolean" then return false end
			if typeof(s.part) ~= "string" or #s.part > 32 then
				return false
			end
			if not Surface.IsFinite(s.face) or not Surface.IsFinite(s.u) or not Surface.IsFinite(s.v) then
				return false
			end
			local face, u, v = s.face :: number, s.u :: number, s.v :: number
			if s.triangle~=nil then
				if not Surface.IsFinite(s.triangle) or s.surfaceVersion~=Curve.Version then return false end
				local triangle=s.triangle :: number
				if triangle<1 or triangle>960 or triangle%1~=0 or u+v>1.00001 then return false end
			elseif s.surfaceVersion~=nil then return false end
			if face < 1 or face > 6 or face % 1 ~= 0 or u < 0 or u > 1 or v < 0 or v > 1 then
				return false
			end
		end
	end
	return true
end
function Net.FireRequest(request: Types.Request): ()
	requestEvent:FireServer(request)
end
function Net.ConnectRequest(callback: (Player, Types.Request) -> ()): RBXScriptConnection
	return requestEvent.OnServerEvent:Connect(function(player: Player, value: unknown): ()
		if Net.Validate(value) then
			callback(player, value :: Types.Request)
		end
	end)
end
function Net.FireNotify(player: Player, notice: Types.Notice): ()
	notifyEvent:FireClient(player, notice)
end
function Net.Broadcast(notice: Types.Notice): ()
	notifyEvent:FireAllClients(notice)
end
function Net.ConnectNotify(callback: (Types.Notice) -> ()): RBXScriptConnection
	return notifyEvent.OnClientEvent:Connect(callback)
end
return Net
