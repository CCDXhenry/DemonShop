-- 离线射线边界替身：仅控制遮挡结果，不替代正式覆盖率或会话规则
local World = { visible = true, part = nil }
function World:Raycast(origin, direction)
 if not self.visible then return nil end
 return { Instance = self.part, Position = origin + direction.Unit * (direction.Magnitude - 0.1) }
end
return World
