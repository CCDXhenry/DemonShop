-- 曲面规则回归：重心坐标、真实面积、接缝去重、协议拒绝及渲染数据映射
local Roblox=require('@lune/roblox')
local Vector2,Vector3=Roblox.Vector2,Roblox.Vector3
local Config=require('./GameConfig')
local Curve=require('./CurvedSurface')
local Data=require('./BodySurfaceData')
local Surface=require('./PaintSurface')
local Rules=require('./VisualRules')
local RuneRules=require('./RuneStampRules')
local count=0
local function check(value,message) assert(value,message);count+=1 end
local allArea=0
for name,data in Data.Parts do
 local part=Roblox.Instance.new('Part')
 part.Name,part.Size=name,data.size
 part:SetAttribute('SurfaceVersion',Curve.Version)
 part:SetAttribute('Paintable',true)
 local geometry=Curve.Geometry(part)
 check(#geometry.triangles==960,'triangle count '..name)
 check(geometry.total>0,'positive area '..name)
 allArea+=geometry.total
 for _,index in {97,321,511,741} do
  local sample={part=name,face=1,u=.2,v=.35,triangle=index,surfaceVersion=Curve.Version}
  check(Curve.Valid(part,sample),'valid barycentric '..name)
  local point=Curve.Point(part,sample)
  local projected=Curve.ProjectLocal(part,point)
  check((Curve.Point(part,projected)-point).Magnitude<.0001,'projection roundtrip '..name)
  local uv=Curve.UV(name,index,sample.u,sample.v)
  check(uv.X>=0 and uv.X<=1 and uv.Y>=0 and uv.Y<=1,'atlas bounds '..name)
 end
 for _,axis in {Vector3.xAxis,Vector3.yAxis,Vector3.zAxis,-Vector3.yAxis} do
  local hit,depth=Curve.Intersect(part,axis*4,-axis,8)
  check(hit and Surface.IsPaintSample(part,hit) and (Curve.Point(part,hit)-axis*(4-depth)).Magnitude<.0001,'visible mesh cap and exact intersection '..name)
 end
 local covered={}
 local sample=Curve.ProjectLocal(part,Vector3.new(0,0,-part.Size.Z/2))
 local _,first=Surface.Stamp(part,sample,covered)
 local _,second=Surface.Stamp(part,sample,covered)
 check(first>0 and second==0,'coverage idempotent '..name)
 local total=0
 for _,direction in {Vector3.xAxis,-Vector3.xAxis,Vector3.yAxis,-Vector3.yAxis,Vector3.zAxis,-Vector3.zAxis} do
  local facing=Curve.ProjectLocal(part,direction*part.Size*.5)
  local _,area=Curve.Stamp(part,facing,covered,10)
  total+=area
 end
 check(math.abs(total+first-geometry.total)<.0001,'true area conservation '..name)
 check(not Curve.Valid(part,{part=name,face=1,u=.8,v=.8,triangle=1,surfaceVersion=Curve.Version}),'reject outside triangle '..name)
 part:Destroy()
end
check(allArea>20 and allArea<60,'body area scale')
local body=Roblox.Instance.new('Model')
local function bodyPart(name,size,z)
 local p=Roblox.Instance.new('Part')
 p.Name,p.Size,p.CFrame=name,size,Roblox.CFrame.new(0,0,z)
 p:SetAttribute('Paintable',true);p:SetAttribute('SurfaceVersion',Curve.Version);p.Parent=body
 return p
end
local torso=bodyPart('UpperTorso',Vector3.new(2,2,2),0)
local hand=bodyPart('LeftHand',Vector3.one*.2,0)
local buried={}
check(math.abs(Curve.ExcludeInterior(body,buried)-Curve.Geometry(hand).total)<.0001,'fully enclosed hand excluded; outer torso remains drawable')
hand.CFrame=Roblox.CFrame.new(0,0,-2)
local hit=Curve.FirstHit(Curve.BodyMesh(body),Vector3.new(0,0,-5),Vector3.zAxis,10)
check(hit and hit.part=='LeftHand','frontmost visible limb wins')
body:Destroy()
local segment={key='s:1',version=1,gesture=1,part='Head',face=1,u=.1,v=.2,glyph=1,angle=0,scale=1,triangle=100,surfaceVersion=Curve.Version}
check(Rules.Validate(segment),'valid curved visual')
local state=Rules.New()
local accepted=Rules.Apply(state,{segment},'s')
check(accepted and accepted[1].triangle==100,'preserve surface coordinate on server')
local invalid=table.clone(segment);invalid.surfaceVersion=999
check(not Rules.Validate(invalid),'reject incompatible version')
invalid=table.clone(segment);invalid.triangle=0/0
check(not Rules.Validate(invalid),'reject NaN triangle')
invalid=table.clone(segment);invalid.u=.9;invalid.v=.9
check(not Rules.Validate(invalid),'reject barycentric outside triangle')
check(Config.BrushRadius == 0.18 and Config.RuneMinScale == 0.38,'brush radius and rune min scale match updated config')
local minScaled = table.clone(segment); minScaled.scale = 0.38
check(Rules.Validate(minScaled),'accept rune stamp at RuneMinScale = 0.38')
local tooSmall = table.clone(segment); tooSmall.scale = 0.37
check(not Rules.Validate(tooSmall),'reject rune stamp below RuneMinScale = 0.38')

local sampleTorso = Roblox.Instance.new('Part')
sampleTorso.Name, sampleTorso.Size = 'UpperTorso', Data.Parts.UpperTorso.size
sampleTorso:SetAttribute('SurfaceVersion', Curve.Version)
sampleTorso:SetAttribute('Paintable', true)
local centerSample = Curve.ProjectLocal(sampleTorso, Vector3.new(0, 0, -sampleTorso.Size.Z * 0.5))
local _, stampArea = Surface.Stamp(sampleTorso, centerSample, {})
local _, legacyArea = Curve.Stamp(sampleTorso, centerSample, {}, 0.08)
check(stampArea > 0.08 and stampArea > legacyArea * 3,'0.18 brush radius covers full rune footprint without thin-brush gaps')
sampleTorso:Destroy()

local maskedPart = Roblox.Instance.new('Part')
maskedPart.Name, maskedPart.Size = 'LeftHand', Vector3.new(0.6, 0.6, 0.6)
local maskRows = {}
for x = 0, 7 do
	for y = 0, 7 do
		table.insert(maskRows, if x >= 3 and x <= 4 and y >= 3 and y <= 4 then '1' else '0')
	end
end
maskedPart:SetAttribute('PaintMask1', table.concat(maskRows))
check(RuneRules.FitFlatScale(maskedPart, 1, 0.5, 0.5, Vector2.new(0.6, 0.6)) == 0.38,'masked flat edge falls back to 0.38 scale step')
maskedPart:Destroy()

local edgePart = Roblox.Instance.new('Part')
edgePart.Name, edgePart.Size = 'LeftHand', Vector3.new(0.54, 0.32, 0.67)
local fit40 = RuneRules.FitFlatScale(edgePart, 1, (Config.RuneStampSize * 0.2) / 0.54, 0.5, Vector2.new(0.54, 0.32))
check(fit40 ~= nil and math.abs(fit40 - 0.40) < 1e-4,'flat edge accepts 0.40 scale above 0.38 RuneMinScale')
check(RuneRules.FitFlatScale(edgePart, 1, 0.05 / 0.54, 0.5, Vector2.new(0.54, 0.32)) == nil,'flat edge skips below 0.38 RuneMinScale')
edgePart:Destroy()

for _, name in { 'Head', 'LeftHand', 'LeftFoot', 'LowerTorso' } do
	local p = Roblox.Instance.new('Part')
	p.Name, p.Size = name, Data.Parts[name].size
	p:SetAttribute('SurfaceVersion', Curve.Version)
	p:SetAttribute('Paintable', true)
	local rim = Curve.ProjectLocal(p, Vector3.new(p.Size.X * 0.35, p.Size.Y * 0.35, -p.Size.Z * 0.45))
	local rimPoint = Curve.Point(p, rim)
	local rimNormal = Curve.Geometry(p).triangles[rim.triangle].normal
	local sc = RuneRules.FitCurvedScale(p, rimPoint, rimNormal, 0)
	check(sc ~= nil and sc >= Config.RuneMinScale,'curved limb rim fits rune without returning nil: ' .. name)
	p:Destroy()
end
print('PASS: '..count..' curved surface assertions (production geometry and protocol)')
