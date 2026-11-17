-- 曲面采样规则：稳定三角面重心坐标、邻域加速、真实面积及图集映射
--!strict
local Data = require(script.Parent.BodySurfaceData)
local Types = require(script.Parent.GameTypes)
local Curve = {}
Curve.Version = Data.Version
type Triangle = {a: Vector3,b: Vector3,c: Vector3,normal: Vector3,area: number,allowed: boolean}
type Geometry = {size: Vector3,triangles: {Triangle},bins: {[string]: {number}},total: number}
local geometries: {[string]: Geometry} = {}
local BinCount=8
local function Bin(point: Vector3): Vector3
	return Vector3.new(math.floor((point.X+.5)*BinCount),math.floor((point.Y+.5)*BinCount),math.floor((point.Z+.5)*BinCount))
end
local function Key(point: Vector3): string return tostring(point.X)..":"..tostring(point.Y)..":"..tostring(point.Z) end
function Curve.IsPart(part: BasePart): boolean return part:GetAttribute("SurfaceVersion")==Data.Version and Data.Parts[part.Name]~=nil end
function Curve.Geometry(part: BasePart): Geometry
	local key=part.Name..":"..tostring(part.Size)
	local cached=geometries[key]
	if cached then return cached end
	local source=Data.Parts[part.Name]
	assert(source,"Unknown curved part")
	local geometry: Geometry={size=part.Size,triangles={},bins={},total=0}
	for index,face in source.triangles do
		local a,b,c=source.vertices[face[1]]*part.Size,source.vertices[face[2]]*part.Size,source.vertices[face[3]]*part.Size
		local cross=(b-a):Cross(c-a)
		local normal=cross.Unit
		local allowed=math.abs(normal.Y)<.86 or part.Name=="Head" or (string.find(part.Name,"Foot")~=nil and normal.Y<0)
		local triangle: Triangle={a=a,b=b,c=c,normal=normal,area=cross.Magnitude*.5,allowed=allowed}
		geometry.triangles[index]=triangle
		if allowed then geometry.total+=triangle.area end
		local low=Bin(a:Min(b):Min(c)/part.Size)
		local high=Bin(a:Max(b):Max(c)/part.Size)
		for x=low.X,high.X do for y=low.Y,high.Y do for z=low.Z,high.Z do
			local binKey=Key(Vector3.new(x,y,z))
			local bucket=geometry.bins[binKey] or {}
			geometry.bins[binKey]=bucket
			table.insert(bucket,index)
		end end end
	end
	geometries[key]=geometry
	return geometry
end
function Curve.Candidates(part: BasePart, point: Vector3, radius: number): {number}
	local geometry=Curve.Geometry(part)
	local low=Bin((point-Vector3.one*radius)/part.Size)
	local high=Bin((point+Vector3.one*radius)/part.Size)
	local result,seen={},{} :: {[number]: boolean}
	for x=math.max(-1,low.X),math.min(BinCount,high.X) do for y=math.max(-1,low.Y),math.min(BinCount,high.Y) do for z=math.max(-1,low.Z),math.min(BinCount,high.Z) do
		for _,index in ipairs(geometry.bins[Key(Vector3.new(x,y,z))] or {}) do
			if not seen[index] then seen[index]=true;table.insert(result,index) end
		end
	end end end
	return result
end
local function Closest(t: Triangle,p: Vector3): (Vector3,number,number)
	local ab,ac,ap=t.b-t.a,t.c-t.a,p-t.a
	local d1,d2=ab:Dot(ap),ac:Dot(ap)
	if d1<=0 and d2<=0 then return t.a,0,0 end
	local bp=p-t.b
	local d3,d4=ab:Dot(bp),ac:Dot(bp)
	if d3>=0 and d4<=d3 then return t.b,1,0 end
	local vc=d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0 then local u=d1/(d1-d3);return t.a+ab*u,u,0 end
	local cp=p-t.c
	local d5,d6=ab:Dot(cp),ac:Dot(cp)
	if d6>=0 and d5<=d6 then return t.c,0,1 end
	local vb=d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0 then local v=d2/(d2-d6);return t.a+ac*v,0,v end
	local va=d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0 then local v=(d4-d3)/((d4-d3)+(d5-d6));return t.b+(t.c-t.b)*v,1-v,v end
	local u,v=vb/(va+vb+vc),vc/(va+vb+vc)
	return t.a+ab*u+ac*v,u,v
end
function Curve.ProjectLocal(part: BasePart,p: Vector3): Types.Sample
	local geometry=Curve.Geometry(part)
	local best,u,v,distance=1,0,0,math.huge
	local candidates=Curve.Candidates(part,p,.12)
	if #candidates==0 then for index in geometry.triangles do table.insert(candidates,index) end end
	for _,index in candidates do
		local point,bu,bv=Closest(geometry.triangles[index],p)
		local d=(point-p).Magnitude
		if d<distance then best,u,v,distance=index,bu,bv,d end
	end
	return {part=part.Name,face=1,u=u,v=v,triangle=best,surfaceVersion=Data.Version}
end
function Curve.Valid(part: BasePart,sample: Types.Sample): boolean
	local index=sample.triangle
	return Curve.IsPart(part) and sample.surfaceVersion==Data.Version and index~=nil and index>=1 and index%1==0 and index<=#Data.Parts[part.Name].triangles and sample.u>=0 and sample.v>=0 and sample.u+sample.v<=1.00001
end
function Curve.Point(part: BasePart,sample: Types.Sample): Vector3
	assert(Curve.Valid(part,sample),"Invalid curved surface coordinate")
	local t=Curve.Geometry(part).triangles[sample.triangle :: number]
	return t.a+(t.b-t.a)*sample.u+(t.c-t.a)*sample.v
end
function Curve.UV(name: string,index: number,u: number,v: number): Vector2
	local source=Data.Parts[name]
	local face=source.triangles[index]
	local a,b,c=source.uvs[face[1]],source.uvs[face[2]],source.uvs[face[3]]
	return a+(b-a)*u+(c-a)*v
end
function Curve.Stamp(part: BasePart,sample: Types.Sample,covered: {[string]: boolean},radius: number): ({string},number)
	if not Curve.Valid(part,sample) then return {},0 end
	local geometry=Curve.Geometry(part)
	local center=Curve.Point(part,sample)
	local normal=geometry.triangles[sample.triangle :: number].normal
	local cells,area={},0
	for _,index in Curve.Candidates(part,center,radius) do
		local triangle=geometry.triangles[index]
		if not triangle.allowed or triangle.normal:Dot(normal)<.2 then continue end
		-- Four equal-area samples per triangle, independent of UV distortion and seams.
		for cell,weights in {Vector2.new(1/6,1/6),Vector2.new(2/3,1/6),Vector2.new(1/6,2/3),Vector2.new(1/3,1/3)} do
			local point=triangle.a+(triangle.b-triangle.a)*weights.X+(triangle.c-triangle.a)*weights.Y
			local key=part.Name..":"..tostring(index)..":"..tostring(cell)
			if (point-center).Magnitude<=radius and not covered[key] then
				covered[key]=true;table.insert(cells,key);area+=triangle.area/4
			end
		end
	end
	return cells,area
end
return Curve
