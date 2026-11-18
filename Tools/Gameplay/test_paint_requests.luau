-- 正式加工请求入口回归：拒绝请求不广播，合法姿态与完成通知保持有效
local M = require('./PaintRequestManager')
local B = require('./PaintRequestBoundary')
local Config = require('./GameConfig')
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local player = {}
local session = {player = player, id = 'body', token = 'session', sequence = 0, last = B.now, yaw = 0, pitch = 0}
local item = {
	stage = 'Painting', model = {PivotTo = function() end}, covered = {}, area = 0,
	totalArea = 100, paintSeconds = 0, progress = 0, strokes = {}, strokePoints = 0,
}
local manager = setmetatable({
	players = {[player] = {}}, data = {IsActive = function() return true end},
	paint = session, items = {body = item}, Root = function() return {} end,
}, M)
local function send(sequence, token)
	manager:OnRequest(player, {action = 'Paint', session = token or session.token, sequence = sequence, samples = {}, yaw = .2})
end
for sequence = 1, 1000 do send(sequence) end
check(#B.broadcasts == 0, '1000 too-fast requests must produce no broadcasts')
check(session.last == 100 and item.progress == 0, 'rejected requests must not update coverage')
B.now += Config.PaintBatchInterval
send(1001)
check(#B.broadcasts == 1 and B.broadcasts[1].kind == 'PaintPose', 'accepted empty samples still broadcast pose')
check(math.abs(B.broadcasts[1].yaw - .2) < .00001, 'accepted pose payload is retained')
B.now += Config.PaintBatchInterval
send(1001)
check(#B.broadcasts == 1, 'duplicate sequence must not broadcast even after interval')
send(1002, 'wrong-session')
check(#B.broadcasts == 1 and session.sequence == 1001, 'wrong session is ignored')
item.area = item.totalArea * Config.PaintTarget
send(1002)
check(#B.broadcasts == 2, 'accepted completion broadcasts final pose')
check(session.finishing and #B.notices == 1 and B.notices[1].notice.kind == 'FinishPaint', 'completion still notifies painter once')
send(1003)
check(#B.broadcasts == 2 and #B.notices == 1, 'finishing session ignores later requests')
print('PASS: '..checks..' production paint request assertions (clock/scene/network boundaries mocked)')
