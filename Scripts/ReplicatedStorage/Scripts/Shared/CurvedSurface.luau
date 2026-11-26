-- 曲面采样规则：稳定三角面重心坐标、邻域加速、真实面积及图集映射
--!strict
local Data = require(script.Parent.BodySurfaceData)
local Types = require(script.Parent.GameTypes)
local Curve = {}
Curve.Version = Data.Version
Curve.Neighbors = {
	Head = { "UpperTorso" },
	UpperTorso = { "Head", "LowerTorso", "LeftUpperArm", "RightUpperArm" },
	LowerTorso = { "UpperTorso", "LeftUpperLeg", "RightUpperLeg" },
	LeftUpperArm = { "UpperTorso", "LeftLowerArm" },
	LeftLowerArm = { "LeftUpperArm", "LeftHand" },
	LeftHand = { "LeftLowerArm" },
	RightUpperArm = { "UpperTorso", "RightLowerArm" },
	RightLowerArm = { "RightUpperArm", "RightHand" },
	RightHand = { "RightLowerArm" },
	LeftUpperLeg = { "LowerTorso", "LeftLowerLeg" },
	LeftLowerLeg = { "LeftUpperLeg", "LeftFoot" },
	LeftFoot = { "LeftLowerLeg" },
	RightUpperLeg = { "LowerTorso", "RightLowerLeg" },
	RightLowerLeg = { "RightUpperLeg", "RightFoot" },
	RightFoot = { "RightLowerLeg" },
} :: { [string]: { string } }

local neighborLookup: { [string]: { [string]: boolean } } = {}
for partName, list in Curve.Neighbors do
	local set: { [string]: boolean } = {}
	for _, neighbor in list do
		set[neighbor] = true
	end
	neighborLookup[partName] = set
end

function Curve.AreNeighbors(a: string, b: string): boolean
	local set = neighborLookup[a]
	return set ~= nil and set[b] == true
end

function Curve.RestOffset(fromPart: string, toPart: string): Vector3?
	local a = Data.Parts[fromPart] :: any
	local b = Data.Parts[toPart] :: any
	if not a or not b or typeof(a.restOffset) ~= "Vector3" or typeof(b.restOffset) ~= "Vector3" then
		return nil
	end
	return (a.restOffset :: Vector3) - (b.restOffset :: Vector3)
end

function Curve.ToModelRest(partName: string, localPoint: Vector3): Vector3
	local data = Data.Parts[partName] :: any
	if not data or typeof(data.restOffset) ~= "Vector3" then
		return localPoint
	end
	return localPoint + (data.restOffset :: Vector3)
end
type Triangle = {a: Vector3,b: Vector3,c: Vector3,normal: Vector3,area: number,allowed: boolean}
type Geometry = {size: Vector3,triangles: {Triangle},bins: {[number]: {number}},total: number}
local geometries: {[string]: Geometry} = {}
local BinCount=8
local BinKeyBase=BinCount+2
Curve.BinCount=BinCount
Curve.BinKeyBase=BinKeyBase
local function Bin(point: Vector3): Vector3
	return Vector3.new(math.floor((point.X+.5)*BinCount),math.floor((point.Y+.5)*BinCount),math.floor((point.Z+.5)*BinCount))
end
local function BinKey(x: number, y: number, z: number): number
	return ((x + 1) * BinKeyBase + (y + 1)) * BinKeyBase + (z + 1)
end
Curve.BinKey=BinKey
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
		local triangle: Triangle={a=a,b=b,c=c,normal=normal,area=cross.Magnitude*.5,allowed=true}
		geometry.triangles[index]=triangle
		geometry.total+=triangle.area
		local low=Bin(a:Min(b):Min(c)/part.Size)
		local high=Bin(a:Max(b):Max(c)/part.Size)
		for x=low.X,high.X do for y=low.Y,high.Y do for z=low.Z,high.Z do
			local binKey=BinKey(x,y,z)
			local bucket=geometry.bins[binKey] or {}
			geometry.bins[binKey]=bucket
			table.insert(bucket,index)
		end end end
	end
	geometries[key]=geometry
	return geometry
end
-- 裁到部件包围盒后，只遍历射线穿过的 8³ 空间格。
local function Slab(origin: number, direction: number, half: number): (number, number)
	if math.abs(direction) < 1e-9 then
		if math.abs(origin) > half then return math.huge, -math.huge end
		return -math.huge, math.huge
	end
	local a, b = (-half-origin)/direction, (half-origin)/direction
	return math.min(a,b), math.max(a,b)
end

local function NextBoundary(cell: number, origin: number, velocity: number): number
	if math.abs(velocity) < 1e-9 then return math.huge end
	return ((if velocity > 0 then cell+1 else cell)-origin)/velocity
end

function Curve.Intersect(part: BasePart, origin: Vector3, direction: Vector3, limit: number): (Types.Sample?, number)
	local size = part.Size
	local half = size * .5
	local x0,x1 = Slab(origin.X,direction.X,half.X)
	local y0,y1 = Slab(origin.Y,direction.Y,half.Y)
	local z0,z1 = Slab(origin.Z,direction.Z,half.Z)
	local enter, leave = math.max(0,x0,y0,z0), math.min(limit,x1,y1,z1)
	if enter > leave then return nil, limit end

	local geometry = Curve.Geometry(part)
	local gridOrigin = (origin/size + Vector3.one*.5)*BinCount
	local velocity = direction/size*BinCount
	local start = gridOrigin + velocity*enter
	local x = math.clamp(math.floor(start.X),0,BinCount-1)
	local y = math.clamp(math.floor(start.Y),0,BinCount-1)
	local z = math.clamp(math.floor(start.Z),0,BinCount-1)
	local best, bestIndex, u, v = limit, 0, 0, 0
	local visited: {[number]: boolean} = {}
	while x>=0 and x<BinCount and y>=0 and y<BinCount and z>=0 and z<BinCount do
		local bucket = geometry.bins[BinKey(x,y,z)]
		if bucket then
			for _,index in bucket do
				if visited[index] then continue end
				visited[index] = true
				local triangle = geometry.triangles[index]
				local ab, ac = triangle.b-triangle.a, triangle.c-triangle.a
				local perpendicular = direction:Cross(ac)
				local determinant = ab:Dot(perpendicular)
				if math.abs(determinant)<1e-10 then continue end
				local offset = origin-triangle.a
				local bu = offset:Dot(perpendicular)/determinant
				if bu < -1e-6 or bu > 1.000001 then continue end
				local cross = offset:Cross(ab)
				local bv = direction:Dot(cross)/determinant
				if bv < -1e-6 or bu+bv > 1.000001 then continue end
				local distance = ac:Dot(cross)/determinant
				if distance>=0 and distance<best then
					best,bestIndex = distance,index
					u = math.clamp(bu,0,1)
					v = math.clamp(bv,0,1-u)
				end
			end
		end
		local tx = NextBoundary(x,gridOrigin.X,velocity.X)
		local ty = NextBoundary(y,gridOrigin.Y,velocity.Y)
		local tz = NextBoundary(z,gridOrigin.Z,velocity.Z)
		local nextT = math.min(tx,ty,tz)
		if nextT>math.min(leave,best) then break end
		if tx==nextT then x+=math.sign(velocity.X) end
		if ty==nextT then y+=math.sign(velocity.Y) end
		if tz==nextT then z+=math.sign(velocity.Z) end
	end
	if bestIndex==0 then return nil,limit end
	return {part=part.Name,face=1,triangle=bestIndex,surfaceVersion=Curve.Version,u=u,v=v},best
end

export type BodyMesh = {{part: BasePart, frame: CFrame}}
function Curve.BodyMesh(model: Model): BodyMesh
	local parts: BodyMesh = {}
	for _,part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Paintable")==true and Curve.IsPart(part) then
			table.insert(parts,{part=part,frame=part.CFrame})
		end
	end
	return parts
end

function Curve.FirstHit(parts: BodyMesh, origin: Vector3, direction: Vector3, limit: number): (Types.Sample?, number)
	local result: Types.Sample? = nil
	for _,body in parts do
		local hit, depth = Curve.Intersect(body.part,body.frame:PointToObjectSpace(origin),body.frame:VectorToObjectSpace(direction),limit)
		if hit then result,limit = hit,depth end
	end
	return result,limit
end

function Curve.Candidates(part: BasePart, point: Vector3, radius: number): {number}
	local geometry=Curve.Geometry(part)
	local low=Bin((point-Vector3.one*radius)/part.Size)
	local high=Bin((point+Vector3.one*radius)/part.Size)
	local result,seen={},{} :: {[number]: boolean}
	for x=math.max(-1,low.X),math.min(BinCount,high.X) do for y=math.max(-1,low.Y),math.min(BinCount,high.Y) do for z=math.max(-1,low.Z),math.min(BinCount,high.Z) do
		local bucket=geometry.bins[BinKey(x,y,z)]
		if bucket then
			for _,index in ipairs(bucket) do
				if not seen[index] then seen[index]=true;table.insert(result,index) end
			end
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
function Curve.SharedEdgePoint(part: BasePart,first: number,last: number,near: Vector3): Vector3?
	local triangles=Curve.Geometry(part).triangles
	local a,b=triangles[first],triangles[last]
	local start: Vector3?=nil
	for _,point in {a.a,a.b,a.c} do
		if (point-b.a).Magnitude>1e-5 and (point-b.b).Magnitude>1e-5 and (point-b.c).Magnitude>1e-5 then continue end
		if not start then start=point;continue end
		local delta=point-start
		local lengthSquared=delta:Dot(delta)
		if lengthSquared<=1e-10 then continue end
		return start+delta*math.clamp((near-start):Dot(delta)/lengthSquared,0,1)
	end
	return nil
end
function Curve.UV(name: string,index: number,u: number,v: number): Vector2
	local source=Data.Parts[name]
	local face=source.triangles[index]
	local a,b,c=source.uvs[face[1]],source.uvs[face[2]],source.uvs[face[3]]
	return a+(b-a)*u+(c-a)*v
end
-- 长时间涂画后，每个三角面保留一份累加的笔印。24 等分使当前白膜的笔心误差小于 0.017 stud。
local InkSteps = 24
local InkNodes = (InkSteps+1)*(InkSteps+2)/2
local InkBytes = math.ceil(InkNodes/8)

function Curve.InkKey(part: string,triangle: number): string
	return "ink:"..part..":"..tostring(triangle)
end

function Curve.CopyInk(original: buffer?): buffer
	local ink = buffer.create(InkBytes)
	if original then buffer.copy(ink,0,original) end
	return ink
end

local function InkNode(u: number,v: number): (number,number)
	local x,y = math.round(u*InkSteps),math.round(v*InkSteps)
	if x+y>InkSteps then
		if x-u*InkSteps>y-v*InkSteps then x-=1 else y-=1 end
	end
	return x,y
end

function Curve.InkCenter(u: number,v: number): (number,number)
	local x,y = InkNode(u,v)
	return x/InkSteps,y/InkSteps
end

function Curve.MarkInk(ink: buffer,u: number,v: number): boolean
	local x,y = InkNode(u,v)
	local index = y*(InkSteps+1)-y*(y-1)/2+x
	local byte = math.floor(index/8)
	local before = buffer.readu8(ink,byte)
	local after = bit32.bor(before,bit32.lshift(1,index%8))
	buffer.writeu8(ink,byte,after)
	return after~=before
end

function Curve.ValidInk(part: string,triangle: number?,key: string,ink: unknown): boolean
	local mesh = Data.Parts[part]
	if not mesh or not triangle or not mesh.triangles[triangle] or key~=Curve.InkKey(part,triangle) then return false end
	return typeof(ink)=="buffer" and buffer.len(ink)==InkBytes and buffer.readu8(ink,InkBytes-1)<2^(InkNodes%8)
end

function Curve.MergeInk(old: buffer?,nextInk: buffer): (buffer,buffer?)
	if not old then local copy = Curve.CopyInk(nextInk); return copy, copy end
	local merged,added = Curve.CopyInk(old),buffer.create(InkBytes)
	local changed = false
	for i=0,InkBytes-1 do
		local before,nextByte = buffer.readu8(old,i),buffer.readu8(nextInk,i)
		local delta = bit32.band(nextByte,bit32.bnot(before))
		if delta~=0 then
			changed=true
			buffer.writeu8(added,i,delta)
			buffer.writeu8(merged,i,bit32.bor(before,delta))
		end
	end
	return merged,if changed then added else nil
end

function Curve.EachInk(ink: buffer,draw: (number,number)->())
	local index = 0
	for y=0,InkSteps do
		for x=0,InkSteps-y do
			if bit32.btest(buffer.readu8(ink,math.floor(index/8)),bit32.lshift(1,index%8)) then draw(x/InkSteps,y/InkSteps) end
			index+=1
		end
	end
end

local CellWeights = {Vector2.new(1/6,1/6),Vector2.new(2/3,1/6),Vector2.new(1/6,2/3),Vector2.new(1/3,1/3)}

-- 工位的相对肢体姿态固定。仅从分母中扣除确实落在其他闭合网格内部的覆盖单元。
function Curve.ExcludeInterior(model: Model, covered: {[string]: boolean}): number
	local parts = Curve.BodyMesh(model)
	local excluded = 0
	for _,body in parts do
		local geometry = Curve.Geometry(body.part)
		for _,other in parts do
			if other.part==body.part then continue end
			local transform = other.frame:ToObjectSpace(body.frame)
			local half = other.part.Size*.5
			local reach = body.part.Size.Magnitude*.5
			local origin = transform.Position:Abs()
			if origin.X>half.X+reach or origin.Y>half.Y+reach or origin.Z>half.Z+reach then continue end
			for index,triangle in geometry.triangles do
				local center = transform:PointToWorldSpace((triangle.a+triangle.b+triangle.c)/3)
				local radius = math.max((triangle.a-triangle.b).Magnitude,(triangle.a-triangle.c).Magnitude)
				if math.abs(center.X)>half.X+radius or math.abs(center.Y)>half.Y+radius or math.abs(center.Z)>half.Z+radius then continue end
				for cell,weights in CellWeights do
					local point = transform:PointToWorldSpace(triangle.a+(triangle.b-triangle.a)*weights.X+(triangle.c-triangle.a)*weights.Y)
					if math.abs(point.X)>=half.X or math.abs(point.Y)>=half.Y or math.abs(point.Z)>=half.Z then continue end
					local hit,depth = Curve.Intersect(other.part,point,Vector3.xAxis,other.part.Size.X+.001)
					if not hit or depth<1e-5 then continue end
					local exit = Curve.Geometry(other.part).triangles[hit.triangle :: number]
					if exit.normal.X<=0 then continue end
					local key = body.part.Name..":"..tostring(index)..":"..tostring(cell)
					if not covered[key] then
						covered[key]=true
						excluded+=triangle.area/#CellWeights
					end
				end
			end
		end
	end
	return excluded
end

type SliceChord = {
	tri: number,
	p1: Vector3,
	p2: Vector3,
	u1: number,
	v1: number,
	u2: number,
	v2: number,
}

local TwoPi = math.pi * 2

local function WrapPi(angle: number): number
	local wrapped = (angle + math.pi) % TwoPi - math.pi
	if wrapped <= -math.pi then
		return wrapped + TwoPi
	end
	return wrapped
end

local function WrapTwoPi(angle: number): number
	local wrapped = angle % TwoPi
	if wrapped < 0 then
		return wrapped + TwoPi
	end
	return wrapped
end

-- 沿 3D 旋转切平面直接与白膜三角网格求交，按扫过方位角扇区提取所有交线（含凹处与肢体遮挡内侧）。
function Curve.SliceCrossSection(
	parts: BodyMesh,
	pivotWorld: Vector3,
	planeNormal: Vector3,
	planeOffset: number,
	towardCamera: Vector3,
	tangent: Vector3,
	brushAzimuthStart: number,
	brushAzimuthEnd: number,
	deltaAngle: number,
	stepLength: number
): { Types.Sample }
	local samples: { Types.Sample } = {}
	local step = math.max(stepLength, 0.01)
	local slab = step
	local planeCenter = pivotWorld + planeNormal * planeOffset
	local deltaPhi = WrapPi(brushAzimuthEnd - brushAzimuthStart)
	local netSweep = deltaAngle - deltaPhi
	local fullCircle = math.abs(netSweep) >= TwoPi - 1e-4
	local arcLo = math.min(brushAzimuthEnd, brushAzimuthEnd + netSweep)
	local arcSpan = math.abs(netSweep)
	local axisRadius = step

	local function AzimuthAndRadius(worldPoint: Vector3): (number, number)
		local rel = worldPoint - planeCenter
		local cu = rel:Dot(towardCamera)
		local cv = rel:Dot(tangent)
		return math.atan2(cv, cu), math.sqrt(cu * cu + cv * cv)
	end

	local function PointInSweep(phi: number, r: number): boolean
		if fullCircle or r <= axisRadius then
			return true
		end
		local pad = math.min(0.08, (step * 0.5) / math.max(r, step))
		return WrapTwoPi(phi - (arcLo - pad)) <= arcSpan + pad * 2
	end

	local function ClipSegmentToSweep(
		w1: Vector3,
		w2: Vector3
	): (number?, number?)
		local phi1, r1 = AzimuthAndRadius(w1)
		local phi2, r2 = AzimuthAndRadius(w2)
		if fullCircle or r1 <= axisRadius or r2 <= axisRadius then
			return 0, 1
		end
		local dPhi = WrapPi(phi2 - phi1)
		local minR = math.min(r1, r2)
		local pad = math.min(0.08, (step * 0.5) / math.max(minR, step))
		local lo = arcLo - pad
		local span = arcSpan + pad * 2
		if math.abs(dPhi) < 1e-6 then
			if WrapTwoPi(phi1 - lo) <= span then
				return 0, 1
			end
			return nil, nil
		end
		-- 在 phi1 -> phi1 + dPhi 线段上求与 [lo + 2πk, lo + span + 2πk] 的重叠参数区间 [t0, t1]。
		local bestT0: number? = nil
		local bestT1: number? = nil
		local segMin = math.min(phi1, phi1 + dPhi)
		local segMax = math.max(phi1, phi1 + dPhi)
		local baseShift = math.floor((segMin - (lo + span)) / TwoPi) * TwoPi
		for k = 0, 2 do
			local winLo = lo + baseShift + k * TwoPi
			local winHi = winLo + span
			local ovLo = math.max(segMin, winLo)
			local ovHi = math.min(segMax, winHi)
			if ovLo <= ovHi then
				local ta = (ovLo - phi1) / dPhi
				local tb = (ovHi - phi1) / dPhi
				local t0 = math.clamp(math.min(ta, tb), 0, 1)
				local t1 = math.clamp(math.max(ta, tb), 0, 1)
				if bestT0 == nil or t0 < bestT0 then bestT0 = t0 end
				if bestT1 == nil or t1 > bestT1 then bestT1 = t1 end
			end
		end
		if bestT0 ~= nil and bestT1 ~= nil then
			return bestT0, bestT1
		end
		if PointInSweep(phi1, r1) or PointInSweep(phi2, r2) then
			return 0, 1
		end
		return nil, nil
	end

	local function EmitPoint(partName: string, tri: number, u: number, v: number, breakBefore: boolean): ()
		local cu = math.clamp(u, 0, 1)
		local cv = math.clamp(v, 0, 1 - cu)
		table.insert(samples, {
			part = partName,
			face = 1,
			u = cu,
			v = cv,
			triangle = tri,
			surfaceVersion = Data.Version,
			breakBefore = breakBefore,
			slice = true,
		})
	end

	local function EmitChain(partName: string, chain: { SliceChord }): ()
		local first = chain[1]
		EmitPoint(partName, first.tri, first.u1, first.v1, true)
		local lastPos = first.p1
		local minEmit = step * 0.75
		local chainLen = #chain
		for chainIndex, chord in chain do
			local dist = (chord.p2 - chord.p1).Magnitude
			if dist > step then
				local segs = math.ceil(dist / step)
				for i = 1, segs - 1 do
					local alpha = i / segs
					local pt = chord.p1 + (chord.p2 - chord.p1) * alpha
					if (pt - lastPos).Magnitude >= minEmit then
						EmitPoint(
							partName,
							chord.tri,
							chord.u1 + (chord.u2 - chord.u1) * alpha,
							chord.v1 + (chord.v2 - chord.v1) * alpha,
							false
						)
						lastPos = pt
					end
				end
			end
			if chainIndex == chainLen or (chord.p2 - lastPos).Magnitude >= minEmit then
				if (chord.p2 - lastPos).Magnitude > 1e-4 then
					EmitPoint(partName, chord.tri, chord.u2, chord.v2, false)
					lastPos = chord.p2
				end
			end
		end
	end

	local joinLimit = math.max(step * 0.75, 0.015)

	for _, body in parts do
		local part = body.part
		local frame = body.frame
		local size = part.Size
		local partDist = math.abs((frame.Position - planeCenter):Dot(planeNormal))
		if partDist > size.Magnitude * 0.5 + slab * 2 then
			continue
		end

		local localNormal = frame:VectorToObjectSpace(planeNormal)
		local localOrigin = frame:PointToObjectSpace(planeCenter)
		local localOffset = localOrigin:Dot(localNormal)
		local halfBin = size / (BinCount * 2)
		local binExtent = math.abs(localNormal.X) * halfBin.X
			+ math.abs(localNormal.Y) * halfBin.Y
			+ math.abs(localNormal.Z) * halfBin.Z
		local binThreshold = binExtent + slab

		local geometry = Curve.Geometry(part)
		local visited: { [number]: boolean } = {}
		local chords: { SliceChord } = {}

		local stepX = size.X / BinCount
		local stepY = size.Y / BinCount
		local stepZ = size.Z / BinCount
		local startX = -size.X * 0.5 + halfBin.X
		local startY = -size.Y * 0.5 + halfBin.Y
		local startZ = -size.Z * 0.5 + halfBin.Z

		for ix = 0, BinCount - 1 do
			local dotX = (startX + ix * stepX) * localNormal.X
			for iy = 0, BinCount - 1 do
				local dotXY = dotX + (startY + iy * stepY) * localNormal.Y
				for iz = 0, BinCount - 1 do
					local centerDot = dotXY + (startZ + iz * stepZ) * localNormal.Z
					if math.abs(centerDot - localOffset) > binThreshold then
						continue
					end
					local bucket = geometry.bins[BinKey(ix, iy, iz)]
					if not bucket then
						continue
					end
					for _, index in bucket do
						if visited[index] then
							continue
						end
						visited[index] = true
						local tri = geometry.triangles[index]
						if not tri.allowed then
							continue
						end
						local ha = tri.a:Dot(localNormal) - localOffset
						local hb = tri.b:Dot(localNormal) - localOffset
						local hc = tri.c:Dot(localNormal) - localOffset
						local minH = math.min(ha, hb, hc)
						local maxH = math.max(ha, hb, hc)

						local p1: Vector3? = nil
						local u1, v1 = 0, 0
						local p2: Vector3? = nil
						local u2, v2 = 0, 0

						if minH <= 1e-6 and maxH >= -1e-6 then
							local function AddCross(
								va: Vector3,
								vb: Vector3,
								da: number,
								db: number,
								ua: number,
								vaU: number,
								ub: number,
								vbU: number
							): ()
								if (da <= 1e-6 and db >= -1e-6) or (da >= -1e-6 and db <= 1e-6) then
									local denom = db - da
									local t = if math.abs(denom) > 1e-8 then math.clamp(-da / denom, 0, 1) else 0.5
									local pt = va + (vb - va) * t
									local pu = ua + (ub - ua) * t
									local pv = vaU + (vbU - vaU) * t
									if not p1 then
										p1, u1, v1 = pt, pu, pv
									elseif (pt - p1).Magnitude > 1e-5 then
										p2, u2, v2 = pt, pu, pv
									end
								end
							end
							AddCross(tri.a, tri.b, ha, hb, 0, 0, 1, 0)
							AddCross(tri.b, tri.c, hb, hc, 1, 0, 0, 1)
							AddCross(tri.c, tri.a, hc, ha, 0, 1, 0, 0)
							if p1 and not p2 then
								p2, u2, v2 = p1, u1, v1
							end
						elseif math.max(math.abs(ha), math.abs(hb), math.abs(hc)) <= slab then
							-- 平行紧贴切平面的封盖三角面（如肩顶/脚底）取重心补涂。
							local center = (tri.a + tri.b + tri.c) / 3
							p1, u1, v1 = center, 1 / 3, 1 / 3
							p2, u2, v2 = center, 1 / 3, 1 / 3
						end

						if p1 and p2 then
							local w1 = frame:PointToWorldSpace(p1)
							local w2 = frame:PointToWorldSpace(p2)
							local t0, t1 = ClipSegmentToSweep(w1, w2)
							if t0 ~= nil and t1 ~= nil then
								local cp1 = p1 + (p2 - p1) * t0
								local cp2 = p1 + (p2 - p1) * t1
								local cu1 = u1 + (u2 - u1) * t0
								local cv1 = v1 + (v2 - v1) * t0
								local cu2 = u1 + (u2 - u1) * t1
								local cv2 = v1 + (v2 - v1) * t1
								table.insert(chords, {
									tri = index,
									p1 = cp1,
									p2 = cp2,
									u1 = cu1,
									v1 = cv1,
									u2 = cu2,
									v2 = cv2,
								})
							end
						end
					end
				end
			end
		end

		if #chords == 0 then
			continue
		end

		-- 将同一部件上的截面短段按端点相邻关系串链，确保各轮廓连续不断且绝不跨空气拉线。
		local used: { [number]: boolean } = {}
		local remaining = #chords
		while remaining > 0 do
			local seedIndex: number? = nil
			for i = 1, #chords do
				if not used[i] then
					seedIndex = i
					break
				end
			end
			if not seedIndex then
				break
			end
			used[seedIndex] = true
			remaining -= 1
			local chain: { SliceChord } = { chords[seedIndex] }

			-- 先向尾部延伸，再向头部反向延伸。
			while remaining > 0 do
				local tail = chain[#chain]
				local bestIdx: number? = nil
				local bestDist = joinLimit
				local bestFlip = false
				for i = 1, #chords do
					if used[i] then continue end
					local c = chords[i]
					local d1 = (c.p1 - tail.p2).Magnitude
					if d1 < bestDist then
						bestDist, bestIdx, bestFlip = d1, i, false
					end
					local d2 = (c.p2 - tail.p2).Magnitude
					if d2 < bestDist then
						bestDist, bestIdx, bestFlip = d2, i, true
					end
				end
				if not bestIdx then
					break
				end
				used[bestIdx] = true
				remaining -= 1
				local chosen = chords[bestIdx]
				if bestFlip then
					table.insert(chain, {
						tri = chosen.tri,
						p1 = chosen.p2,
						p2 = chosen.p1,
						u1 = chosen.u2,
						v1 = chosen.v2,
						u2 = chosen.u1,
						v2 = chosen.v1,
					})
				else
					table.insert(chain, chosen)
				end
			end

			while remaining > 0 do
				local head = chain[1]
				local bestIdx: number? = nil
				local bestDist = joinLimit
				local bestFlip = false
				for i = 1, #chords do
					if used[i] then continue end
					local c = chords[i]
					local d2 = (c.p2 - head.p1).Magnitude
					if d2 < bestDist then
						bestDist, bestIdx, bestFlip = d2, i, false
					end
					local d1 = (c.p1 - head.p1).Magnitude
					if d1 < bestDist then
						bestDist, bestIdx, bestFlip = d1, i, true
					end
				end
				if not bestIdx then
					break
				end
				used[bestIdx] = true
				remaining -= 1
				local chosen = chords[bestIdx]
				if bestFlip then
					table.insert(chain, 1, {
						tri = chosen.tri,
						p1 = chosen.p2,
						p2 = chosen.p1,
						u1 = chosen.u2,
						v1 = chosen.v2,
						u2 = chosen.u1,
						v2 = chosen.v1,
					})
				else
					table.insert(chain, 1, chosen)
				end
			end

			EmitChain(part.Name, chain)
		end
	end

	return samples
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
		for cell,weights in CellWeights do
			local point=triangle.a+(triangle.b-triangle.a)*weights.X+(triangle.c-triangle.a)*weights.Y
			if (point-center).Magnitude>radius then continue end
			local key=part.Name..":"..tostring(index)..":"..tostring(cell)
			if not covered[key] then
				covered[key]=true;table.insert(cells,key);area+=triangle.area/4
			end
		end
	end
	return cells,area
end
return Curve
