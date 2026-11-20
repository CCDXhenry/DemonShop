-- 完整三角面扫描参考：保留旧圆点算法，并以独立胶囊测距验证连续笔刷。
local R=require('@lune/roblox')
local Vector2=R.Vector2
local Curve=require('./CurvedSurface')
local Data=require('./BodySurfaceData')
local Config=require('./GameConfig')
local Reference={}
function Reference.Draw(texture,segment)
 local part=texture.model:FindFirstChild(segment.part)
 local function stamp(sample)
  if not Curve.Valid(part,sample) then return end
  local geometry=Curve.Geometry(part)
  local center=Curve.Point(part,sample)
  local normal=geometry.triangles[sample.triangle].normal
  local radius=Config.PaintVisualWidth*.5
  for _,index in Curve.Candidates(part,center,radius+.04) do
   texture.slices+=1
   local triangle=geometry.triangles[index]
   if not triangle.allowed or triangle.normal:Dot(normal)<.2 then continue end
   local source=Data.Parts[part.Name]
   local face=source.triangles[index]
   local a,b,c=source.uvs[face[1]],source.uvs[face[2]],source.uvs[face[3]]
   a,b,c=Vector2.new(a.X,1-a.Y)*texture.size,Vector2.new(b.X,1-b.Y)*texture.size,Vector2.new(c.X,1-c.Y)*texture.size
   local low,high=a:Min(b):Min(c),a:Max(b):Max(c)
   local ab,ac=b-a,c-a
   local determinant=ab.X*ac.Y-ab.Y*ac.X
   if math.abs(determinant)<1e-8 then continue end
   local scanned=0
   for y=math.max(0,math.floor(low.Y)),math.min(texture.size-1,math.ceil(high.Y)) do
    for x=math.max(0,math.floor(low.X)),math.min(texture.size-1,math.ceil(high.X)) do
     scanned+=1;texture.scanned+=1
     if scanned%64==0 then texture.slices+=1 end
     local p=Vector2.new(x+.5,y+.5)-a
     local u,v=(p.X*ac.Y-p.Y*ac.X)/determinant,(ab.X*p.Y-ab.Y*p.X)/determinant
     if u<-.005 or v<-.005 or u+v>1.005 then continue end
     local point=triangle.a+(triangle.b-triangle.a)*u+(triangle.c-triangle.a)*v
     if (point-center).Magnitude>radius then continue end
     local offset=(y*texture.size+x)*4
     buffer.writeu8(texture.pixels,offset,176);buffer.writeu8(texture.pixels,offset+1,63);buffer.writeu8(texture.pixels,offset+2,255)
    end
   end
  end
 end
 local first={part=part.Name,face=1,u=segment.u0,v=segment.v0,triangle=segment.triangle0,surfaceVersion=segment.surfaceVersion}
 local last={part=part.Name,face=1,u=segment.u1,v=segment.v1,triangle=segment.triangle1,surfaceVersion=segment.surfaceVersion}
 if not Curve.Valid(part,first) or not Curve.Valid(part,last) then return end
 local a,b=Curve.Point(part,first),Curve.Point(part,last)
 local distance=(b-a).Magnitude
 if distance>Config.BrushRadius*3 then stamp(last);return end
 local steps=math.max(1,math.ceil(distance/(Config.PaintVisualWidth*.3)))
 for index=0,steps do stamp(Curve.ProjectLocal(part,a:Lerp(b,index/steps))) end
end
Reference.DrawLegacy=Reference.Draw
function Reference.Draw(texture,segment)
 local part=texture.model:FindFirstChild(segment.part)
 local geometry=Curve.Geometry(part)
 local first={part=part.Name,face=1,u=segment.u0,v=segment.v0,triangle=segment.triangle0,surfaceVersion=segment.surfaceVersion}
 local last={part=part.Name,face=1,u=segment.u1,v=segment.v1,triangle=segment.triangle1,surfaceVersion=segment.surfaceVersion}
 if not Curve.Valid(part,first) or not Curve.Valid(part,last) then return end
 local a,b=Curve.Point(part,first),Curve.Point(part,last)
 local spans={}
 local function add(p,q,normal,lastNormal) table.insert(spans,{p=p,q=q,normal=normal,lastNormal=lastNormal or normal}) end
 local function seam(from, to)
  local t0,t1=geometry.triangles[from.triangle],geometry.triangles[to.triangle]
  local shared={}
  for _,p in {t0.a,t0.b,t0.c} do
   for _,q in {t1.a,t1.b,t1.c} do
    if (p-q).Magnitude<=1e-5 then table.insert(shared,p);break end
   end
  end
  if #shared~=2 then return nil end
  local midpoint=(Curve.Point(part,from)+Curve.Point(part,to))*.5
  local edge=shared[2]-shared[1]
  return shared[1]+edge*math.clamp((midpoint-shared[1]):Dot(edge)/edge:Dot(edge),0,1)
 end
 local function join(from,to,edge)
  local p,q=Curve.Point(part,from),Curve.Point(part,to)
  local n0,n1=geometry.triangles[from.triangle].normal,geometry.triangles[to.triangle].normal
  if from.triangle==to.triangle then add(p,q,n0)
  else add(p,edge or p,n0);add(edge or q,q,n1) end
 end
 local distance=(b-a).Magnitude
 if distance>Config.BrushRadius*3 then add(b,b,geometry.triangles[last.triangle].normal)
 elseif first.triangle==last.triangle then add(a,b,geometry.triangles[first.triangle].normal)
 else
  local direct=seam(first,last)
  if direct then join(first,last,direct) else
   local steps=math.max(1,math.ceil(distance/(Config.PaintVisualWidth*.3)))
   local previous=first
   for index=1,steps do
    local sample=if index==steps then last else Curve.ProjectLocal(part,a:Lerp(b,index/steps))
    if index<steps and not geometry.triangles[sample.triangle].allowed then previous=nil;continue end
    if previous then
     join(previous,sample,if previous.triangle~=sample.triangle then seam(previous,sample) else nil)
    else
     local point=Curve.Point(part,sample)
     add(point,point,geometry.triangles[sample.triangle].normal)
    end
    previous=sample
   end
  end
 end
 -- 不使用正式实现的网格候选、UV 包围盒或缓存。穷举所有允许三角面与像素。
 local source=Data.Parts[part.Name]
 local radiusSquared=(Config.PaintVisualWidth*.5)^2
 for index,triangle in geometry.triangles do
  if not triangle.allowed then continue end
  local eligible={}
  for _,span in spans do if math.max(triangle.normal:Dot(span.normal),triangle.normal:Dot(span.lastNormal))>=.2 then table.insert(eligible,span) end end
  if #eligible==0 then continue end
  local face=source.triangles[index]
  local uvA,uvB,uvC=source.uvs[face[1]],source.uvs[face[2]],source.uvs[face[3]]
  uvA,uvB,uvC=Vector2.new(uvA.X,1-uvA.Y)*texture.size,Vector2.new(uvB.X,1-uvB.Y)*texture.size,Vector2.new(uvC.X,1-uvC.Y)*texture.size
  local ab,ac=uvB-uvA,uvC-uvA
  local determinant=ab.X*ac.Y-ab.Y*ac.X
  if math.abs(determinant)<1e-8 then continue end
  local low,high=uvA:Min(uvB):Min(uvC),uvA:Max(uvB):Max(uvC)
  texture.slices+=1
  for y=math.max(0,math.floor(low.Y)),math.min(texture.size-1,math.ceil(high.Y)) do
   for x=math.max(0,math.floor(low.X)),math.min(texture.size-1,math.ceil(high.X)) do
    texture.scanned+=1
    if texture.scanned%64==0 then texture.slices+=1 end
    local offset=(y*texture.size+x)*4
    if buffer.readu8(texture.pixels,offset)==176 then continue end
    local p=Vector2.new(x+.5,y+.5)-uvA
    local u,v=(p.X*ac.Y-p.Y*ac.X)/determinant,(ab.X*p.Y-ab.Y*p.X)/determinant
    if u<-.005 or v<-.005 or u+v>1.005 then continue end
    local point=triangle.a+(triangle.b-triangle.a)*u+(triangle.c-triangle.a)*v
    for _,span in eligible do
     local direction=span.q-span.p
     local denominator=direction:Dot(direction)
     local t=if denominator>0 then math.clamp((point-span.p):Dot(direction)/denominator,0,1) else 0
     if triangle.normal:Dot(span.normal:Lerp(span.lastNormal,t))<.2 then continue end
     local delta=point-(span.p+direction*t)
     if delta:Dot(delta)<=radiusSquared then
      buffer.writeu8(texture.pixels,offset,176);buffer.writeu8(texture.pixels,offset+1,63);buffer.writeu8(texture.pixels,offset+2,255)
      break
     end
    end
   end
  end
 end
end
return Reference
