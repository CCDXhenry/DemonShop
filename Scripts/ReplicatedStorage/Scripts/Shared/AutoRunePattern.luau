-- 自动符文台落印：在朝上外表面生成稳定、可校验的符文笔段，并按部件朝向缓存
--!strict
local Config = require(script.Parent.GameConfig)
local Types = require(script.Parent.GameTypes)
local Surface = require(script.Parent.PaintSurface)
local Curve = require(script.Parent.CurvedSurface)
local RuneRules = require(script.Parent.RuneStampRules)
local VisualRules = require(script.Parent.VisualRules)

local Pattern = {}

local MaxStamps = 96
local MaxStampsPerPart = 24
local UpDot = 0.45
local PartOrder: { [string]: number } = { UpperTorso = 1, Head = 2, LowerTorso = 3 }

type Template = {
	token: string,
	face: number,
	u: number,
	v: number,
	angle: number,
	scale: number,
	triangle: number?,
	surfaceVersion: number?,
}

local cache: { [string]: { Template } } = {}

local function Quantize(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

local function CacheKey(part: BasePart): string
	local up = part.CFrame:VectorToObjectSpace(Vector3.yAxis)
	local size = part.Size
	return string.format(
		"%s|%.4f,%.4f,%.4f|%.2f,%.2f,%.2f",
		part.Name,
		size.X,
		size.Y,
		size.Z,
		Quantize(up.X),
		Quantize(up.Y),
		Quantize(up.Z)
	)
end

local function FacesUp(part: BasePart, normal: Vector3): boolean
	return part.CFrame:VectorToWorldSpace(normal):Dot(Vector3.yAxis) >= UpDot
end

local function FaceNormal(face: number): Vector3
	if face == 1 then
		return Vector3.new(0, 0, -1)
	end
	if face == 2 then
		return Vector3.new(0, 0, 1)
	end
	if face == 3 then
		return Vector3.new(-1, 0, 0)
	end
	if face == 4 then
		return Vector3.new(1, 0, 0)
	end
	if face == 5 then
		return Vector3.new(0, 1, 0)
	end
	return Vector3.new(0, -1, 0)
end

local function FlatAngle(face: number): number
	-- 与平面笔迹的 SurfaceGui 方向一致：沿面的 U 轴落印。
	return if face <= 4 then -math.pi / 2 else math.pi / 2
end

local function TangentAngle(normal: Vector3): number
	local right, up = RuneRules.Basis(normal)
	local tangent = Vector3.xAxis - normal * normal:Dot(Vector3.xAxis)
	if tangent.Magnitude < 1e-4 then
		tangent = Vector3.yAxis - normal * normal:Dot(Vector3.yAxis)
	end
	if tangent.Magnitude < 1e-4 then
		return 0
	end
	return RuneRules.AngleFromDirection(tangent.Unit, right, up)
end

local function FlatTemplates(part: BasePart): { Template }
	local templates: { Template } = {}
	local spacing = math.max(Config.RuneStampSpacing, 1e-3)
	for face = 1, 6 do
		if not FacesUp(part, FaceNormal(face)) then
			continue
		end
		local dimensions = Surface.Dimensions(part.Size, face)
		if dimensions.X < 1e-3 or dimensions.Y < 1e-3 then
			continue
		end
		local columns = math.max(1, math.floor(dimensions.X / spacing + 1e-4))
		local rows = math.max(1, math.floor(dimensions.Y / spacing + 1e-4))
		local angle = FlatAngle(face)
		for row = 1, rows do
			for column = 1, columns do
				if #templates >= MaxStampsPerPart then
					return templates
				end
				local along = (column - 0.5) / columns
				local across = (row - 0.5) / rows
				local scale = RuneRules.FitFlatScale(part, face, along, across, dimensions)
				if scale then
					table.insert(templates, {
						token = "f" .. tostring(face) .. ":" .. tostring(#templates + 1),
						face = face,
						u = along,
						v = across,
						angle = angle,
						scale = scale,
					})
				end
			end
		end
	end
	return templates
end

local function CurvedTemplates(part: BasePart): { Template }
	local geometry = Curve.Geometry(part)
	local spacing = math.max(Config.RuneStampSpacing, 1e-3)
	local spacingSq = spacing * spacing
	local candidates: { { index: number, center: Vector3, normal: Vector3 } } = {}
	for index, triangle in geometry.triangles do
		if triangle.area > 1e-6 and FacesUp(part, triangle.normal) then
			table.insert(candidates, {
				index = index,
				center = (triangle.a + triangle.b + triangle.c) / 3,
				normal = triangle.normal,
			})
		end
	end
	table.sort(candidates, function(a, b): boolean
		if math.abs(a.center.X - b.center.X) > 1e-4 then
			return a.center.X < b.center.X
		end
		if math.abs(a.center.Z - b.center.Z) > 1e-4 then
			return a.center.Z < b.center.Z
		end
		return a.index < b.index
	end)
	local templates: { Template } = {}
	local kept: { Vector3 } = {}
	for _, candidate in candidates do
		if #templates >= MaxStampsPerPart then
			break
		end
		local crowded = false
		for _, previous in kept do
			local delta = candidate.center - previous
			if delta:Dot(delta) < spacingSq then
				crowded = true
				break
			end
		end
		if crowded then
			continue
		end
		local angle = TangentAngle(candidate.normal)
		local scale = RuneRules.FitCurvedScale(part, candidate.center, candidate.normal, angle)
		if not scale then
			continue
		end
		table.insert(kept, candidate.center)
		table.insert(templates, {
			token = "t" .. tostring(candidate.index),
			face = 1,
			u = 1 / 3,
			v = 1 / 3,
			angle = angle,
			scale = scale,
			triangle = candidate.index,
			surfaceVersion = Curve.Version,
		})
	end
	return templates
end

local function TemplatesFor(part: BasePart): { Template }
	local key = CacheKey(part)
	local stored = cache[key]
	if stored then
		return stored
	end
	local templates = if Curve.IsPart(part) then CurvedTemplates(part) else FlatTemplates(part)
	cache[key] = templates
	return templates
end

function Pattern.Build(model: Model): { Types.VisualSegment }
	local parts: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and Surface.IsBody(child) then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a: BasePart, b: BasePart): boolean
		local left = PartOrder[a.Name] or 50
		local right = PartOrder[b.Name] or 50
		if left ~= right then
			return left < right
		end
		return a.Name < b.Name
	end)
	local segments: { Types.VisualSegment } = {}
	local glyph = 0
	for _, part in parts do
		if #segments >= MaxStamps then
			break
		end
		for _, template in TemplatesFor(part) do
			if #segments >= MaxStamps then
				break
			end
			glyph += 1
			local segment: Types.VisualSegment = {
				key = "auto:" .. part.Name .. ":" .. template.token,
				version = 1,
				gesture = 1,
				part = part.Name,
				face = template.face,
				u = template.u,
				v = template.v,
				glyph = ((glyph - 1) % Config.RuneGlyphCount) + 1,
				angle = template.angle,
				scale = template.scale,
				triangle = template.triangle,
				surfaceVersion = template.surfaceVersion,
			}
			if VisualRules.Validate(segment) then
				table.insert(segments, segment)
			end
		end
	end
	return segments
end

return Pattern
