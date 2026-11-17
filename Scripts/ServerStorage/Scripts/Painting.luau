-- 权威画符服务：会话序号、可见表面校验、面积覆盖和独立连续笔划预算
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local Types = require(Shared.GameTypes)
local Surface = require(Shared.PaintSurface)
local Curve = require(Shared.CurvedSurface)
local BodyPose = require(Shared.PaintBodyPose)
local Painting = {}
export type Session = {
	player: Player, id: string, token: string, last: number, sequence: number,
	yaw: number, pitch: number, walkSpeed: number, jumpPower: number, jumpHeight: number,
	visualSequence: number?, visualWindow: number?, visualPackets: number?, finishing: boolean?,
}
export type Result = { stroke: Types.Stroke?, complete: boolean }
function Painting.Apply(session: Session, item: Types.Item, request: Types.Request, pose: CFrame, origin: Vector3, now: number): Result?
	local sequence = request.sequence
	if request.bodyPose and not BodyPose.Validate(item.model,request.bodyPose) then return nil end
	if not sequence or sequence <= session.sequence then return nil end
	session.sequence = sequence
	local elapsed = now - session.last
	if elapsed < Config.PaintBatchInterval * 0.7 then return nil end
	session.last = now
	-- 展示姿态由操作者提供；请求已通过有限数、会话及频率校验。
	-- 在该姿态下重新射线校验每个表面采样，不用网络到达间隔回限本地旋转。
	session.yaw = ((request.yaw or session.yaw) + math.pi) % (2 * math.pi) - math.pi
	session.pitch = math.clamp(request.pitch or session.pitch, -Config.PaintPitchLimit, Config.PaintPitchLimit)
	BodyPose.Apply(item.model,pose*CFrame.Angles(session.pitch,session.yaw,0),request.bodyPose)
	if request.bodyPose then item.poseBody=table.clone(request.bodyPose) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { item.model }
	local accepted: { Types.Sample } = {}
	local previous: Types.Sample? = nil
	for _, sample in ipairs(request.samples or {}) do
		if sample.breakBefore then previous = nil end
		local part = item.model:FindFirstChild(sample.part)
		if not part or not part:IsA("BasePart") or not Surface.IsBody(part) or not Surface.Allowed(part, sample.face) then previous = nil; continue end
		local curved=Curve.IsPart(part)
		if curved and not Curve.Valid(part,sample) then previous=nil;continue end
		local point = part.CFrame:PointToWorldSpace(if curved then Curve.Point(part,sample) else Surface.Point(part.Size, sample.face, sample.u, sample.v))
		local direction = point - origin
		if direction.Magnitude < 0.001 then previous = nil; continue end
		local hit = workspace:Raycast(origin, direction.Unit * (direction.Magnitude + 0.1), params)
		if not hit or hit.Instance ~= part or (hit.Position - point).Magnitude > 0.45 then previous = nil; continue end
		local _, area = Surface.Stamp(part, sample, item.covered)
		item.area += area
		-- 批次内同面短段补采样，判定不依赖显示线段数量。
		if previous and previous.part == sample.part and previous.face == sample.face then
			if curved then
				local start=Curve.Point(part,previous)
				local finish=Curve.Point(part,sample)
				local distance=(finish-start).Magnitude
				if distance<Config.BrushRadius*3 then
					for index=1,math.ceil(distance/(Config.BrushRadius*.5))-1 do
						local alpha=index/math.ceil(distance/(Config.BrushRadius*.5))
						local intermediate=Curve.ProjectLocal(part,start:Lerp(finish,alpha))
						local _,added=Surface.Stamp(part,intermediate,item.covered)
						item.area+=added
					end
				end
			else
			local dimensions = Surface.Dimensions(part.Size, sample.face)
			local distance = Vector2.new((sample.u - previous.u) * dimensions.X, (sample.v - previous.v) * dimensions.Y).Magnitude
			if distance < Config.BrushRadius * 3 then
				local steps = math.ceil(distance / (Config.BrushRadius * 0.5))
				for index = 1, steps - 1 do
					local alpha = index / steps
					local _, addedArea = Surface.Stamp(part, { part = sample.part, face = sample.face, u = previous.u + (sample.u - previous.u) * alpha, v = previous.v + (sample.v - previous.v) * alpha }, item.covered)
					item.area += addedArea
				end
			end
			end
		end
		table.insert(accepted, sample)
		previous = sample
	end
	if #accepted > 0 then
		item.paintSeconds += math.min(elapsed, 0.15)
	end
	item.poseYaw, item.posePitch = session.yaw, session.pitch
	item.progress = math.min(item.area / math.max(item.totalArea * Config.PaintTarget, 0.001), 1)
	local stroke: Types.Stroke? = nil
	if #accepted > 0 and item.strokePoints + #accepted <= Config.PaintStrokePointBudget then
		local recorded: Types.Stroke = { key = session.token .. ":" .. tostring(sequence), samples = accepted }
		stroke = recorded
		table.insert(item.strokes, recorded)
		item.strokePoints += #accepted
	end
	return { stroke = stroke, complete = item.progress >= 1 }
end
return Painting
