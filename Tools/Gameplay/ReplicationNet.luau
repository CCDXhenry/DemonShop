-- 离线复制测试边界：只记录实际模块发出的通知，不模拟复制算法
local Net = { notices = {} }
function Net.Broadcast(notice) table.insert(Net.notices, notice) end
return Net
