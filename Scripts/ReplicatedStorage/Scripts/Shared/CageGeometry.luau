-- 定义地下围挡与楼上井口挡板的几何及 Edit 构建入口
--!strict
local Physics = require(script.Parent.PhysicsConfig)
local Geometry = {}
local Config = Physics.Cage
type Wall = { Frame: CFrame, Size: Vector3 }
export type SoftBounce = {
	offset: Vector3,
	velocityDelta: Vector3,
	angularScale: number,
	hitWall: string?,
	hitPosition: Vector3?,
	hitNormal: Vector3?,
	impactSpeed: number,
}
export type SoftImpact = {
	wall: string,
	position: Vector3,
	normal: Vector3,
	speed: number,
}

function Geometry.InnerHalfSize(size: Vector3, inset: number?): (number, number)
	local wallInset = inset or 0
	return math.max(0.5, size.X * 0.5 - wallInset), math.max(0.5, size.Z * 0.5 - wallInset)
end

function Geometry.Contains(frame: CFrame, size: Vector3, position: Vector3, inset: number?): boolean
	local point = frame:PointToObjectSpace(position)
	local halfY = size.Y * 0.5
	local innerX, innerZ = Geometry.InnerHalfSize(size, inset)
	return math.abs(point.X) <= math.max(0, innerX - Config.EntryInset)
		and math.abs(point.Z) <= math.max(0, innerZ - Config.EntryInset)
		and point.Y >= -halfY
		and point.Y <= Config.WallHeight - halfY - Config.EntryInset
end

function Geometry.Retains(frame: CFrame, size: Vector3, position: Vector3, inset: number?): boolean
	local point = frame:PointToObjectSpace(position)
	local halfY = size.Y * 0.5
	local innerX, innerZ = Geometry.InnerHalfSize(size, inset)
	local tolerance = Config.WallThickness
	return math.abs(point.X) <= innerX + tolerance
		and math.abs(point.Z) <= innerZ + tolerance
		and point.Y >= -halfY - tolerance
		and point.Y <= Config.WallHeight - halfY + tolerance
end

function Geometry.ClampInside(frame: CFrame, size: Vector3, inset: number?, position: Vector3, margin: number?): Vector3
	local point = frame:PointToObjectSpace(position)
	local innerX, innerZ = Geometry.InnerHalfSize(size, inset)
	local pad = margin or 0.35
	local limitX = math.max(0, innerX - pad)
	local limitZ = math.max(0, innerZ - pad)
	local clamped = Vector3.new(math.clamp(point.X, -limitX, limitX), point.Y, math.clamp(point.Z, -limitZ, limitZ))
	return frame:PointToWorldSpace(clamped)
end

local function CheckSoftAxis(
	coord: number,
	vel: number,
	limit: number,
	posName: string,
	negName: string
): (boolean, number, number, boolean, number, string?, number)
	local absCoord = math.abs(coord)
	local sign = if coord >= 0 then 1 else -1
	local penetration = absCoord - limit
	local vOut = vel * sign
	local triggered = penetration > 0
		or (absCoord >= limit - Config.SoftBouncePreemptMargin and vOut >= Config.ImpactMinSpeed)
	if not triggered then
		return false, 0, vel, false, 0, nil, sign
	end
	if penetration > 0 and vOut < Config.SoftBounceRestThreshold then
		local pull = penetration + Config.SoftBounceClearance
		if penetration <= 1.5 then
			pull = math.min(pull, Config.SoftBounceMaxShiftPerStep)
		end
		local newVel = if vOut > 0 then 0 else vel
		return true, -sign * pull, newVel, false, 0, nil, sign
	end
	local shift = if penetration > 0 then -sign * (penetration + Config.SoftBounceClearance) else 0
	local newVel = vel
	local bounced = false
	if vOut > -Config.SoftBounceMinPush then
		local vIn = if vOut > 0
			then math.clamp(vOut * Config.SoftBounceRestitution, Config.SoftBounceMinPush, Config.SoftBounceMaxPush)
			else Config.SoftBounceMinPush
		newVel = -sign * vIn
		bounced = vOut > 0.5
	end
	local wallName: string? = nil
	if vOut >= Config.ImpactMinSpeed then
		wallName = if sign > 0 then posName else negName
	end
	return true, shift, newVel, bounced, vOut, wallName, sign
end

function Geometry.ResolveSoftBounce(frame: CFrame, size: Vector3, inset: number?, position: Vector3, velocity: Vector3): SoftBounce?
	local p = frame:PointToObjectSpace(position)
	local halfY = size.Y * 0.5
	if p.Y < -halfY - 1 or p.Y > Config.WallHeight - halfY then
		return nil
	end
	local v = frame:VectorToObjectSpace(velocity)
	local hx, hz = Geometry.InnerHalfSize(size, inset)
	local hitX, shiftX, newVX, bouncedX, vOutX, wallX, signX = CheckSoftAxis(p.X, v.X, hx, "East", "West")
	local hitZ, shiftZ, newVZ, bouncedZ, vOutZ, wallZ, signZ = CheckSoftAxis(p.Z, v.Z, hz, "South", "North")
	if not hitX and not hitZ then
		return nil
	end
	if bouncedX and not hitZ then
		newVZ *= Config.SoftBounceTangentDamping
	end
	if bouncedZ and not hitX then
		newVX *= Config.SoftBounceTangentDamping
	end
	local localShift = Vector3.new(shiftX, 0, shiftZ)
	local localDelta = Vector3.new(newVX - v.X, 0, newVZ - v.Z)
	if localShift.Magnitude <= 1e-5 and localDelta.Magnitude <= 1e-5 then
		return nil
	end
	local bestWall: string? = nil
	local bestLocalPos: Vector3? = nil
	local bestLocalNormal: Vector3? = nil
	local bestImpactSpeed = 0
	local clampedY = math.clamp(p.Y, 0.5, math.max(0.5, Config.WallHeight - halfY - 0.5))
	if wallX and vOutX > bestImpactSpeed then
		bestImpactSpeed = vOutX
		bestWall = wallX
		bestLocalPos = Vector3.new(signX * hx, clampedY, math.clamp(p.Z, -hz, hz))
		bestLocalNormal = Vector3.new(-signX, 0, 0)
	end
	if wallZ and vOutZ > bestImpactSpeed then
		bestImpactSpeed = vOutZ
		bestWall = wallZ
		bestLocalPos = Vector3.new(math.clamp(p.X, -hx, hx), clampedY, signZ * hz)
		bestLocalNormal = Vector3.new(0, 0, -signZ)
	end
	local angularScale = if bouncedX or bouncedZ then Config.SoftBounceAngularDamping else 1
	return {
		offset = frame:VectorToWorldSpace(localShift),
		velocityDelta = frame:VectorToWorldSpace(localDelta),
		angularScale = angularScale,
		hitWall = bestWall,
		hitPosition = if bestLocalPos then frame:PointToWorldSpace(bestLocalPos) else nil,
		hitNormal = if bestLocalNormal then frame:VectorToWorldSpace(bestLocalNormal).Unit else nil,
		impactSpeed = bestImpactSpeed,
	}
end

function Geometry.DetectSoftImpact(
	frame: CFrame,
	size: Vector3,
	inset: number?,
	prevPos: Vector3,
	currPos: Vector3,
	velocity: Vector3,
	dt: number
): SoftImpact?
	local p1 = frame:PointToObjectSpace(currPos)
	local halfY = size.Y * 0.5
	if p1.Y < -halfY - 1 or p1.Y > Config.WallHeight - halfY then
		return nil
	end
	local p0 = frame:PointToObjectSpace(prevPos)
	local v = frame:VectorToObjectSpace(velocity)
	local stepDt = math.max(dt, 1 / 120)
	local vStep = (p1 - p0) / stepDt
	local hx, hz = Geometry.InnerHalfSize(size, inset)
	local clampedY = math.clamp(p1.Y, 0.5, math.max(0.5, Config.WallHeight - halfY - 0.5))
	local margin = Config.SoftBounceObserverMargin
	local best: SoftImpact? = nil
	local function checkObserverAxis(coord: number, vel: number, stepVel: number, limit: number, posName: string, negName: string, isX: boolean): ()
		local absCoord = math.abs(coord)
		if absCoord < limit - margin or absCoord > limit + 2.5 then
			return
		end
		local sign = if coord >= 0 then 1 else -1
		local outSpeed = math.max(vel * sign, stepVel * sign)
		if outSpeed < Config.ImpactMinSpeed then
			return
		end
		if best and outSpeed <= best.speed then
			return
		end
		local localPos = if isX
			then Vector3.new(sign * limit, clampedY, math.clamp(p1.Z, -hz, hz))
			else Vector3.new(math.clamp(p1.X, -hx, hx), clampedY, sign * limit)
		local localNormal = if isX then Vector3.new(-sign, 0, 0) else Vector3.new(0, 0, -sign)
		best = {
			wall = if sign > 0 then posName else negName,
			position = frame:PointToWorldSpace(localPos),
			normal = frame:VectorToWorldSpace(localNormal).Unit,
			speed = outSpeed,
		}
	end
	checkObserverAxis(p1.X, v.X, vStep.X, hx, "East", "West", true)
	checkObserverAxis(p1.Z, v.Z, vStep.Z, hz, "South", "North", false)
	return best
end

local function ResolveModelLimbClamp(model: Model, frame: CFrame, size: Vector3, inset: number?, velocity: Vector3): (Vector3, Vector3)
	local hx, hz = Geometry.InnerHalfSize(size, inset)
	local halfY = size.Y * 0.5
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local found = false
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Anchored then
			continue
		end
		local okName, name = pcall(function(): string return part.Name end)
		if okName and name == "HumanoidRootPart" then
			continue
		end
		local lp = frame:PointToObjectSpace(part.Position)
		if lp.Y < -halfY - 1 or lp.Y > Config.WallHeight - halfY then
			continue
		end
		local rad = 0
		local okSize, pSize = pcall(function(): Vector3 return part.Size end)
		if okSize and typeof(pSize) == "Vector3" then
			rad = math.max(pSize.X, pSize.Z) * 0.35
		end
		found = true
		minX = math.min(minX, lp.X - rad)
		maxX = math.max(maxX, lp.X + rad)
		minZ = math.min(minZ, lp.Z - rad)
		maxZ = math.max(maxZ, lp.Z + rad)
	end
	if not found then
		return Vector3.zero, Vector3.zero
	end
	local shiftX = 0
	if maxX > hx and minX >= -hx then
		shiftX = -math.min(maxX - hx + Config.SoftBounceClearance, Config.SoftBounceMaxShiftPerStep)
	elseif minX < -hx and maxX <= hx then
		shiftX = math.min(-hx - minX + Config.SoftBounceClearance, Config.SoftBounceMaxShiftPerStep)
	end
	local shiftZ = 0
	if maxZ > hz and minZ >= -hz then
		shiftZ = -math.min(maxZ - hz + Config.SoftBounceClearance, Config.SoftBounceMaxShiftPerStep)
	elseif minZ < -hz and maxZ <= hz then
		shiftZ = math.min(-hz - minZ + Config.SoftBounceClearance, Config.SoftBounceMaxShiftPerStep)
	end
	if shiftX == 0 and shiftZ == 0 then
		return Vector3.zero, Vector3.zero
	end
	local v = frame:VectorToObjectSpace(velocity)
	local dvx = if (shiftX < 0 and v.X > 0) or (shiftX > 0 and v.X < 0) then -v.X else 0
	local dvz = if (shiftZ < 0 and v.Z > 0) or (shiftZ > 0 and v.Z < 0) then -v.Z else 0
	return frame:VectorToWorldSpace(Vector3.new(shiftX, 0, shiftZ)), frame:VectorToWorldSpace(Vector3.new(dvx, 0, dvz))
end

function Geometry.ApplySoftBounceToModel(model: Model, frame: CFrame, size: Vector3, inset: number?): SoftBounce?
	local torso = model:FindFirstChild("UpperTorso") or model.PrimaryPart
	if not torso or not torso:IsA("BasePart") or torso.Anchored then
		return nil
	end
	local okVel, currentVel = pcall(function(): Vector3
		return torso.AssemblyLinearVelocity
	end)
	if not okVel or typeof(currentVel) ~= "Vector3" then
		return nil
	end
	local result = Geometry.ResolveSoftBounce(frame, size, inset, torso.Position, currentVel)
	local limbShift, limbDelta = ResolveModelLimbClamp(model, frame, size, inset, currentVel)
	if not result and limbShift.Magnitude <= 1e-5 then
		return nil
	end
	local totalOffset = if result then result.offset else limbShift
	local totalDelta = if result then result.velocityDelta else limbDelta
	local angularScale = if result then result.angularScale else 1
	if result and limbShift.Magnitude > 1e-5 then
		local rLocal = frame:VectorToObjectSpace(result.offset)
		local lLocal = frame:VectorToObjectSpace(limbShift)
		local mergedX = if math.abs(rLocal.X) >= math.abs(lLocal.X) then rLocal.X else lLocal.X
		local mergedZ = if math.abs(rLocal.Z) >= math.abs(lLocal.Z) then rLocal.Z else lLocal.Z
		totalOffset = frame:VectorToWorldSpace(Vector3.new(mergedX, rLocal.Y, mergedZ))
	end
	if totalOffset.Magnitude > 1e-4 then
		local okPivot = pcall(function(): ()
			model:PivotTo(model:GetPivot() + totalOffset)
		end)
		if not okPivot then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and not part.Anchored then
					part.CFrame = part.CFrame + totalOffset
				end
			end
		end
	end
	if totalDelta.Magnitude > 1e-5 or angularScale < 1 then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then
				if totalDelta.Magnitude > 1e-5 then
					local okPartVel, partVel = pcall(function(): Vector3
						return part.AssemblyLinearVelocity
					end)
					if okPartVel and typeof(partVel) == "Vector3" then
						part.AssemblyLinearVelocity = partVel + totalDelta
					end
				end
				if angularScale < 1 then
					local okAng, partAng = pcall(function(): Vector3
						return part.AssemblyAngularVelocity
					end)
					if okAng and typeof(partAng) == "Vector3" then
						part.AssemblyAngularVelocity = partAng * angularScale
					end
				end
			end
		end
	end
	return result or {
		offset = totalOffset,
		velocityDelta = totalDelta,
		angularScale = 1,
		hitWall = nil,
		hitPosition = nil,
		hitNormal = nil,
		impactSpeed = 0,
	}
end

function Geometry.IntersectInnerWall(frame: CFrame, size: Vector3, inset: number?, from: Vector3, delta: Vector3): (number?, Vector3?, Vector3?)
	local p0 = frame:PointToObjectSpace(from)
	local d = frame:VectorToObjectSpace(delta)
	local dist = delta.Magnitude
	if dist <= 1e-5 then
		return nil, nil, nil
	end
	local hx, hz = Geometry.InnerHalfSize(size, inset)
	local minY = -size.Y * 0.5
	local maxY = Config.WallHeight - size.Y * 0.5
	local bestT: number? = nil
	local bestPoint: Vector3? = nil
	local bestNormal: Vector3? = nil

	local function testPlane(t: number, normal: Vector3): ()
		if t < 0 or t > 1 then return end
		if bestT and t >= bestT then return end
		local hit = p0 + d * t
		if hit.Y < minY or hit.Y > maxY then return end
		if math.abs(hit.X) > hx + 1e-3 or math.abs(hit.Z) > hz + 1e-3 then return end
		bestT, bestPoint, bestNormal = t, hit, normal
	end

	-- 仅拦截向外穿出收拢内壁的轨迹段（单向放行：从外向内飞入不阻挡）。
	if d.X > 1e-5 and p0.X <= hx + 1e-3 and p0.X + d.X >= hx - 1e-3 then
		testPlane((hx - p0.X) / d.X, -Vector3.xAxis)
	end
	if d.X < -1e-5 and p0.X >= -hx - 1e-3 and p0.X + d.X <= -hx + 1e-3 then
		testPlane((-hx - p0.X) / d.X, Vector3.xAxis)
	end
	if d.Z > 1e-5 and p0.Z <= hz + 1e-3 and p0.Z + d.Z >= hz - 1e-3 then
		testPlane((hz - p0.Z) / d.Z, -Vector3.zAxis)
	end
	if d.Z < -1e-5 and p0.Z >= -hz - 1e-3 and p0.Z + d.Z <= -hz + 1e-3 then
		testPlane((-hz - p0.Z) / d.Z, Vector3.zAxis)
	end

	if bestT and bestPoint and bestNormal then
		return bestT * dist, frame:PointToWorldSpace(bestPoint), frame:VectorToWorldSpace(bestNormal).Unit
	end
	return nil, nil, nil
end

function Geometry.Walls(frame: CFrame, size: Vector3, inset: number?): { [string]: Wall }
	local height, thickness = Config.WallHeight, Config.WallThickness
	local innerX, innerZ = Geometry.InnerHalfSize(size, inset)
	local x, y, z = innerX + thickness * 0.5, (height - size.Y) * 0.5, innerZ + thickness * 0.5
	return {
		West = { Frame = frame * CFrame.new(-x, y, 0), Size = Vector3.new(thickness, height, innerZ * 2) },
		East = { Frame = frame * CFrame.new(x, y, 0), Size = Vector3.new(thickness, height, innerZ * 2) },
		North = { Frame = frame * CFrame.new(0, y, -z), Size = Vector3.new(innerX * 2 + 2 * thickness, height, thickness) },
		South = { Frame = frame * CFrame.new(0, y, z), Size = Vector3.new(innerX * 2 + 2 * thickness, height, thickness) },
	}
end

function Geometry.Baffles(frame: CFrame, size: Vector3, topY: number): { [string]: Wall }
	local thickness = Config.BaffleThickness
	local bottomY = frame.Position.Y - Config.BaffleFloorOverlap
	local height = topY - bottomY
	local y = (topY + bottomY) * 0.5 - frame.Position.Y
	local x = (size.X + thickness) * 0.5 - Config.BaffleContactInset
	local z = (size.Z + thickness) * 0.5 - Config.BaffleContactInset
	return {
		West = { Frame = frame * CFrame.new(-x, y, 0), Size = Vector3.new(thickness, height, size.Z) },
		East = { Frame = frame * CFrame.new(x, y, 0), Size = Vector3.new(thickness, height, size.Z) },
		Back = { Frame = frame * CFrame.new(0, y, z), Size = Vector3.new(size.X + 2 * thickness, height, thickness) },
	}
end

function Geometry.Build(parent: Instance, folderName: string, walls: { [string]: Wall }): ()
	assert(not game:GetService("RunService"):IsRunning(), "Cage geometry requires Edit mode")
	local existingFolder = parent:FindFirstChild(folderName)
	local folder: Instance
	if existingFolder then
		assert(existingFolder:IsA("Folder"), "Expected wall folder: " .. folderName)
		folder = existingFolder
	else
		local created = Instance.new("Folder")
		created.Name = folderName
		created.Parent = parent
		folder = created
	end
	for name, wall in walls do
		local existing = folder:FindFirstChild(name)
		assert(not existing or existing:IsA("BasePart"), "Expected wall part: " .. name)
		local part: BasePart = if existing then existing :: BasePart else Instance.new("Part")
		part.Name = name
		part.Size, part.CFrame = wall.Size, wall.Frame
		part.Anchored, part.CastShadow, part.Transparency = true, false, 1
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, true
		part.Parent = folder
	end
end

return Geometry
