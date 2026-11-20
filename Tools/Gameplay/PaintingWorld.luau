-- 离线射线边界：以定向盒求出第一处碰撞，不替代正式覆盖率或会话规则。
local Vector3 = require('@lune/roblox').Vector3
local World = { visible = true, part = nil }
local axes = {Vector3.xAxis, Vector3.yAxis, Vector3.zAxis}
function World:Raycast(origin, direction)
 if not self.visible then return nil end
 local part = self.part
 if not part then return nil end
 local start = part.CFrame:PointToObjectSpace(origin)
 local delta = part.CFrame:VectorToObjectSpace(direction)
 local half = part.Size * 0.5
 local first = math.huge
 local normal
 for _, axis in axes do
  if math.abs(delta:Dot(axis)) < 0.000001 then continue end
  for _, sign in {-1, 1} do
   local fraction = (half:Dot(axis) * sign - start:Dot(axis)) / delta:Dot(axis)
   if fraction < 0 or fraction > 1 or fraction >= first then continue end
   local hit = start + delta * fraction
   if math.abs(hit.X) > half.X + 0.00001 or math.abs(hit.Y) > half.Y + 0.00001 or math.abs(hit.Z) > half.Z + 0.00001 then continue end
   first, normal = fraction, axis * sign
  end
 end
 if not normal then return nil end
 return { Instance = part, Position = origin + direction * first, Normal = part.CFrame:VectorToWorldSpace(normal) }
end
return World
