-- 修复前的完整三角面扫描算法，独立保留作像素一致性基准。
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
return Reference
