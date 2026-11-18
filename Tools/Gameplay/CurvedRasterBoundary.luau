-- 曲面栅格化离线边界：仅替换引擎图像、纹理绑定和可控时钟。
local R=require('@lune/roblox')
local Boundary={images={},time=0,step=0,clockReads=0,binds=0}
Boundary.workspace={CurrentCamera=nil}
Boundary.Content={none='none',fromObject=function(image) return image end}
Boundary.AssetService={CreateEditableImage=function(_,options)
 if Boundary.failNext then Boundary.failNext=false;return nil end
 local size=options.Size
 local image={size=size,pixels=buffer.create(size.X*size.Y*4),writes={},destroyed=false}
 function image:WritePixelsBuffer(position,dimensions,pixels)
  assert(not self.destroyed,'write to destroyed image')
  assert(buffer.len(pixels)==dimensions.X*dimensions.Y*4,'packed dirty region length')
  table.insert(self.writes,{position=position,size=dimensions})
  for row=0,dimensions.Y-1 do
   buffer.copy(self.pixels,((position.Y+row)*self.size.X+position.X)*4,pixels,row*dimensions.X*4,dimensions.X*4)
  end
 end
 function image:Destroy() self.destroyed=true end
 table.insert(Boundary.images,image)
 return image
end}
Boundary.os={clock=function()
 Boundary.clockReads+=1
 Boundary.time+=Boundary.step
 return Boundary.time
end}
-- Lune 无法把模拟 EditableImage 赋给真实 MeshPart.TextureContent；几何仍使用真实 Part。
function Boundary.Model(parts)
 local meshes={}
 for _,part in parts do
  local content='none'
  table.insert(meshes,setmetatable({
   Name=part.Name,Size=part.Size,
   IsA=function(_,kind) return kind=='MeshPart' or kind=='BasePart' end,
   GetAttribute=function(_,key) return part:GetAttribute(key) end,
  },{
   __index=function(_,key) if key=='TextureContent' then return content end end,
   __newindex=function(target,key,value)
    if key=='TextureContent' then content=value;Boundary.binds+=1 else rawset(target,key,value) end
   end,
  }))
 end
 return {
  Parent=true,meshes=meshes,
  GetChildren=function() return meshes end,
  GetPivot=function() return R.CFrame.identity end,
  FindFirstChild=function(_,name) for _,part in parts do if part.Name==name then return part end end end,
 }
end
return Boundary
