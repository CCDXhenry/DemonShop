-- 身体表面纯规则：局部面坐标、面积加权覆盖与笔刷栅格去重
--!strict
local Config = require(script.Parent.GameConfig)
local Types = require(script.Parent.GameTypes)
local Curve = require(script.Parent.CurvedSurface)
local Surface = {}
Surface.Faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom }
function Surface.IsFinite(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end
function Surface.IsBody(part: Instance): boolean
	return part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part:GetAttribute("Paintable") == true
end
function Surface.Allowed(part: BasePart, face: number): boolean
	return face >= 1 and face <= 6
end
function Surface.IsPaintSample(part: BasePart, sample: Types.Sample): boolean
	if Curve.IsPart(part) then
		return Curve.Valid(part,sample) and Curve.Geometry(part).triangles[sample.triangle :: number].allowed
	end
	return sample.triangle == nil and Surface.Allowed(part,sample.face)
end
function Surface.Dimensions(size: Vector3, face: number): Vector2
	if face <= 2 then
		return Vector2.new(size.X, size.Y)
	end
	if face <= 4 then
		return Vector2.new(size.Z, size.Y)
	end
	return Vector2.new(size.X, size.Z)
end
function Surface.Point(size: Vector3, face: number, u: number, v: number): Vector3
	local x, y = u - 0.5, 0.5 - v
	if face == 1 then
		return Vector3.new(x * size.X, y * size.Y, -size.Z / 2)
	end
	if face == 2 then
		return Vector3.new(-x * size.X, y * size.Y, size.Z / 2)
	end
	if face == 3 then
		return Vector3.new(-size.X / 2, y * size.Y, -x * size.Z)
	end
	if face == 4 then
		return Vector3.new(size.X / 2, y * size.Y, x * size.Z)
	end
	if face == 5 then
		return Vector3.new(x * size.X, size.Y / 2, -y * size.Z)
	end
	return Vector3.new(x * size.X, -size.Y / 2, y * size.Z)
end
function Surface.Project(part: BasePart, point: Vector3, normal: Vector3): Types.Sample
	if Curve.IsPart(part) then return Curve.ProjectLocal(part,part.CFrame:PointToObjectSpace(point)) end
	local p, n, size = part.CFrame:PointToObjectSpace(point), part.CFrame:VectorToObjectSpace(normal), part.Size
	local face, u, v = 1, 0.5, 0.5
	if math.abs(n.Y) > math.max(math.abs(n.X), math.abs(n.Z)) then
		face = if n.Y > 0 then 5 else 6
		u, v = p.X / size.X + 0.5, if face == 5 then p.Z / size.Z + 0.5 else 0.5 - p.Z / size.Z
	elseif math.abs(n.X) > math.abs(n.Z) then
		face = if n.X < 0 then 3 else 4
		u, v = (if face == 3 then -p.Z else p.Z) / size.Z + 0.5, 0.5 - p.Y / size.Y
	else
		face = if n.Z < 0 then 1 else 2
		u, v = (if face == 1 then p.X else -p.X) / size.X + 0.5, 0.5 - p.Y / size.Y
	end
	return { part = part.Name, face = face, u = math.clamp(u, 0, 1), v = math.clamp(v, 0, 1) }
end
function Surface.CellAllowed(part: BasePart, face: number, x: number, y: number): boolean
	local mask = part:GetAttribute("PaintMask" .. face)
	if typeof(mask) ~= "string" then
		return true
	end
	local index = x * Config.PaintGrid + y + 1
	return string.sub(mask, index, index) == "1"
end
function Surface.Total(model: Model): number
	local total = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and Surface.IsBody(child) then
			if Curve.IsPart(child) then total+=Curve.Geometry(child).total;continue end
			for face = 1, 6 do
				if Surface.Allowed(child, face) then
					local d = Surface.Dimensions(child.Size, face)
					for x = 0, Config.PaintGrid - 1 do
						for y = 0, Config.PaintGrid - 1 do
							if Surface.CellAllowed(child, face, x, y) then
								total += d.X * d.Y / Config.PaintGrid ^ 2
							end
						end
					end
				end
			end
		end
	end
	return total
end
function Surface.FlatSideTotals(model: Model, excluded: { [string]: boolean }?): (number, number)
	if typeof(model) ~= "Instance" then
		return 0, 0
	end
	local frontSide = Curve.FlatSide(model, false)
	local frontFace = if frontSide == 1 then 2 else 1
	local front, back = 0, 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and Surface.IsBody(child) then
			if Curve.IsPart(child) then
				local f, b = Curve.FlatSideTotals(child, excluded, frontSide)
				front += f
				back += b
				continue
			end
			for _, face in { 1, 2 } do
				if Surface.Allowed(child, face) then
					local d = Surface.Dimensions(child.Size, face)
					local faceArea = 0
					for x = 0, Config.PaintGrid - 1 do
						for y = 0, Config.PaintGrid - 1 do
							if Surface.CellAllowed(child, face, x, y) then
								faceArea += d.X * d.Y / Config.PaintGrid ^ 2
							end
						end
					end
					if face == frontFace then
						front += faceArea
					else
						back += faceArea
					end
				end
			end
		end
	end
	return front, back
end
function Surface.FlatProgress(frontArea: number, backArea: number, frontTotal: number, backTotal: number, flipped: boolean): number
	local flipAt = math.clamp(Config.PaintAutoFlipProgress, 0.05, 0.95)
	local targetRatio = Config.PaintFlatTarget or Config.PaintTarget
	local frontTarget = math.max(frontTotal * targetRatio, 0.001)
	local backTarget = math.max(backTotal * targetRatio, 0.001)
	if not flipped then
		return math.clamp(frontArea / frontTarget, 0, 1) * flipAt
	end
	return math.min(1, flipAt + math.clamp(backArea / backTarget, 0, 1) * (1 - flipAt))
end
function Surface.Stamp(part: BasePart, sample: Types.Sample, covered: { [string]: boolean }, flatSide: number?): ({ string }, number)
	if Curve.IsPart(part) then return Curve.Stamp(part,sample,covered,Config.BrushRadius,flatSide) end
	local cells: { string } = {}
	if not Surface.IsBody(part) or not Surface.Allowed(part, sample.face) then
		return cells, 0
	end
	if flatSide ~= nil then
		local expectedFace = if flatSide == 1 then 2 else 1
		if sample.face ~= expectedFace then
			return cells, 0
		end
	end
	local d, grid = Surface.Dimensions(part.Size, sample.face), Config.PaintGrid
	local area = 0
	-- 旧平面模板仍使用 8×8 遮罩，每个粗格再细分，窄笔在粗格交界也能落墨。
	local subdivisions = math.max(1,math.ceil(math.max(d.X,d.Y)/(grid*Config.BrushRadius)))
	local resolution = grid*subdivisions
	local radius = Vector2.new(Config.BrushRadius/d.X,Config.BrushRadius/d.Y)
	for x=math.max(0,math.floor((sample.u-radius.X)*resolution)),math.min(resolution-1,math.floor((sample.u+radius.X)*resolution)) do
		for y=math.max(0,math.floor((sample.v-radius.Y)*resolution)),math.min(resolution-1,math.floor((sample.v+radius.Y)*resolution)) do
			local dx,dy = ((x+.5)/resolution-sample.u)*d.X, ((y+.5)/resolution-sample.v)*d.Y
			if dx*dx+dy*dy<=Config.BrushRadius^2 and Surface.CellAllowed(part,sample.face,math.floor(x/subdivisions),math.floor(y/subdivisions)) then
				local key = string.format("%s:%d:%d:%d",part.Name,sample.face,x,y)
				if not covered[key] then
					covered[key]=true
					table.insert(cells,key)
					area+=d.X*d.Y/resolution^2
				end
			end
		end
	end
	return cells, area
end
return Surface
