-- 权威画符服务：会话序号、可见表面校验、面积覆盖和独立连续笔划预算
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local Types = require(Shared.GameTypes)
local Surface = require(Shared.PaintSurface)
local Curve = require(Shared.CurvedSurface)
local Rotation = require(Shared.PaintRotation)
local BodyPose = require(Shared.PaintBodyPose)
local Painting = {}
export type Session = {
	player: Player, id: string, token: string, last: number, sequence: number,
	orientation: CFrame, walkSpeed: number, jumpPower: number, jumpHeight: number,
	geometry: Rotation.Geometry?,
	visualSequence: number?, visualWindow: number?, visualPackets: number?, finishing: boolean?,
	coverageWindow: number?, coveragePackets: number?,
}
export type Result = { stroke: Types.Stroke?, complete: boolean }
local CoveragePacketsPerSecond = 30
function Painting.SetPose(session: Session, item: Types.Item, base: CFrame, orientation: CFrame, forceApply: boolean?): ()
	if orientation ~= session.orientation or forceApply then
		local rotated = Rotation.Pose(base, session.geometry, orientation)
		if item.poseBody then
			BodyPose.Apply(item.model, rotated, item.poseBody)
		else
			item.model:PivotTo(rotated)
		end
	end
	session.orientation = orientation
	item.paintOrientation = orientation
end

function Painting.Apply(session: Session, item: Types.Item, request: Types.Request, pose: CFrame, origin: Vector3, now: number): Result?
	local sequence = request.sequence
	if not sequence or sequence <= session.sequence then return nil end
	local elapsed = now - session.last
	if elapsed < Config.PaintBatchInterval * 0.2 then return nil end
	if now - (session.coverageWindow or 0) >= 1 then
		session.coverageWindow = now
		session.coveragePackets = 0
	end
	if (session.coveragePackets or 0) >= CoveragePacketsPerSecond then
		return nil
	end
	session.coveragePackets = (session.coveragePackets or 0) + 1
	session.sequence = sequence
	session.last = now
	local poseChanged = false
	if Config.PaintPhysicsEnabled and request.bodyPose and BodyPose.Validate(item.model, request.bodyPose) then
		item.poseBody = table.clone(request.bodyPose)
		poseChanged = true
	end
	local orientation = if Config.PaintRotationEnabled
		then (request.orientation or session.orientation).Rotation
		else CFrame.identity
	local current = Rotation.Pose(pose, session.geometry, session.orientation)
	if poseChanged and item.poseBody then
		BodyPose.Apply(item.model, current, item.poseBody)
	end
	local pivotAtCurrent = current:PointToWorldSpace(if session.geometry then session.geometry.center else Vector3.zero)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { item.model }
	local mesh: Curve.BodyMesh? = nil
	local accepted: { Types.Sample } = {}
	local previous: Types.Sample? = nil
	local rayOrigin = origin
	local rayOrientation = session.orientation
	for _, sample in ipairs(request.samples or {}) do
		if sample.breakBefore then previous = nil end
		local part = item.model:FindFirstChild(sample.part)
		if not part or not part:IsA("BasePart") or not Surface.IsBody(part) or not Surface.IsPaintSample(part, sample) then previous = nil; continue end
		local curved=Curve.IsPart(part)
		local sampledOrientation = if Config.PaintRotationEnabled
			then (sample.orientation or orientation).Rotation
			else CFrame.identity
		if sampledOrientation ~= rayOrientation then
			-- 将历史视点换算到当前模型姿态，每批只移动实体一次；保留连续笔划 previous 供同面线段补采样。
			local sampled = Rotation.Pose(pose, session.geometry, sampledOrientation)
			rayOrigin = current:PointToWorldSpace(sampled:PointToObjectSpace(origin))
			rayOrientation = sampledOrientation
		end
		local localPoint = if curved then Curve.Point(part,sample) else Surface.Point(part.Size, sample.face, sample.u, sample.v)
		local point = part.CFrame:PointToWorldSpace(localPoint)
		local direction = point - rayOrigin
		if direction.Magnitude < 0.001 then previous = nil; continue end
		if curved then
			if sample.slice and Config.PaintRotationEnabled then
				-- 旋转横截面采样允许肢体凹处与内侧落墨，仅校验采样点位于旋转姿态的镜头侧有效半球，防止不旋转直涂背面。
				local toCameraVec = rayOrigin - pivotAtCurrent
				local toCamera = if toCameraVec.Magnitude > 0.001 then toCameraVec.Unit else Vector3.yAxis
				if (point - pivotAtCurrent):Dot(toCamera) < Config.PaintSliceHemisphereMinDot then
					previous = nil
					continue
				end
			else
				local parts = mesh or Curve.BodyMesh(item.model)
				mesh = parts
				local visible,depth = Curve.FirstHit(parts,rayOrigin,direction.Unit,direction.Magnitude+.015)
				if not visible or visible.part~=sample.part or math.abs(depth-direction.Magnitude)>.015 then
					previous=nil
					continue
				end
			end
		else
			local hit = workspace:Raycast(rayOrigin,direction.Unit*(direction.Magnitude+.1),params)
			if not hit or hit.Instance~=part or (hit.Position-point).Magnitude>.45 or Surface.Project(part,hit.Position,hit.Normal).face~=sample.face then
				previous=nil
				continue
			end
		end
		local ink = sample
		if curved and sample.packedInk then
			ink = table.clone(sample)
			ink.u,ink.v = Curve.InkCenter(sample.u,sample.v)
		end
		local _, area = Surface.Stamp(part, ink, item.covered)
		item.area += area
		-- 批次内同面短段补采样，判定不依赖显示线段数量。
		if previous and not previous.packedInk and not sample.packedInk and previous.part == sample.part and previous.face == sample.face then
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
	Painting.SetPose(session, item, pose, orientation)
	local targetRatio = if Config.PaintRotationEnabled then Config.PaintTarget else (Config.PaintFlatTarget or Config.PaintTarget)
	item.progress = math.min(item.area / math.max(item.totalArea * targetRatio, 0.001), 1)
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
