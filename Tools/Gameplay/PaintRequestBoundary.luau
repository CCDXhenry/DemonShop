-- 绘画请求回归边界：可控时钟、场景锚点与通知收集
local R = require('@lune/roblox')
local B = { now = 100, broadcasts = {}, notices = {} }
B.workspace = { GetServerTimeNow = function() return B.now end }
B.Scene = {
	TablePose = function() return R.CFrame.identity end,
	CameraPose = function() return R.CFrame.new(0, 0, -10) end,
}
B.Net = {
	Broadcast = function(notice) table.insert(B.broadcasts, notice) end,
	FireNotify = function(player, notice) table.insert(B.notices, {player = player, notice = notice}) end,
}
return B
