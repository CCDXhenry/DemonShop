-- 曲面符文端到端回归：正式渲染器生成等距符文，经上传队列和服务端规则保存后重建与接手
local Roblox = require('@lune/roblox')
local View = require('./PaintView')
local Curve = require('./CurvedSurface')
local Data = require('./BodySurfaceData')
local Config = require('./GameConfig')
local Rules = require('./VisualRules')
local Protocol = require('./VisualProtocol')
local Upload = require('./VisualUpload')
local Net = require('./VisualNet')
local count = 0
local function check(value, message) assert(value, message); count += 1 end

local model = Roblox.Instance.new('Model')
model:SetAttribute('SurfaceVersion', Curve.Version)
local part = Roblox.Instance.new('Part')
part.Name, part.Size = 'UpperTorso', Data.Parts.UpperTorso.size
part:SetAttribute('Paintable', true)
part:SetAttribute('SurfaceVersion', Curve.Version)
part.Parent = model

local bodyId = '1314d4e7-f70a-4f54-a2d9-d0e1612bf7ec'
local session = '7d1516b7-104c-4ab3-91ba-a17d51bb7bd4'
local view = View.new()
view:Bind(bodyId, model)

-- 沿躯干正面横拖约 0.80 stud：首枚正向 + 约每 0.38 stud 放一枚（共 3 枚：0, 0.38, 0.76）
local path = {}
for i = 0, 8 do
	local x = -0.4 + i * 0.1
	table.insert(path, Curve.ProjectLocal(part, Roblox.Vector3.new(x, 0.05, -part.Size.Z * 0.5)))
end
view:DrawLocal(bodyId, session, 1, path)
local dirty = view:Drain(bodyId)
local state = Rules.New()
table.clear(Net.requests)
local upload = Upload.new()
upload:Begin(session)
upload:Update(dirty, 0.1, 10, false)
check(#Net.requests == 1, 'first curved rune drag produces one upload')
local request = Net.requests[1]
check(Protocol.Validate(request), 'actual generated curved rune packet passes boundary validation')
local accepted, reason = Rules.Apply(state, request.segments, session)
check(accepted ~= nil, 'curved rune stamps accepted: ' .. tostring(reason))
check(state.count >= 2 and state.count <= 4, '0.8 stud drag produces ~3 equidistant runes, got ' .. tostring(state.count))

local firstStamp = accepted[1]
for _, segment in accepted do
	check(string.sub(segment.key, 1, #session + 1) == session .. ':', 'session owns generated rune key')
	check(segment.surfaceVersion == Curve.Version and segment.triangle ~= nil, 'server retains curve triangle coordinate')
	check(segment.glyph >= 1 and segment.glyph <= Config.RuneGlyphCount, 'glyph index valid')
	check(segment.scale >= Config.RuneMinScale and segment.scale <= 1, 'scale within [0.5, 1]')
end
check(firstStamp.angle == 0, 'first stamp of stroke is upright')

upload:Ack(request.sequence)
upload.closing = true
upload:Update({}, 0.2, 10, true)
check(Net.requests[2].action == 'EndPaint' and Net.requests[2].sequence == 1, 'intentional exit waits for stored rune acknowledgement')

local observer = View.new()
observer:Bind(bodyId, model)
observer:Apply(bodyId, accepted)
check(observer.counts[bodyId] == state.count, 'observer rebuild restores all saved runes')
local replacement = model:Clone()
observer:Bind(bodyId, replacement)
check(observer.counts[bodyId] == state.count, 'reenter/rebind keeps canonical rune history')
observer:Apply(bodyId, accepted)
check(observer.counts[bodyId] == state.count, 'sync replay does not duplicate runes')

-- 换人接手可继续追加符文，原会话被拒
local secondSession = '8796426c-7ee0-4ea8-a0cf-2f29eaf840b4'
local nextHit = Curve.ProjectLocal(part, Roblox.Vector3.new(0, 0.2, -part.Size.Z * 0.5))
view:DrawLocal(bodyId, secondSession, 1, { nextHit })
local nextBatch = {}
for _, segment in view:Drain(bodyId) do table.insert(nextBatch, segment) end
check(#nextBatch == 1, 'new session click generates one rune')
check(Rules.Apply(state, nextBatch, secondSession) ~= nil, 'new painting session can append to existing body')
check(Rules.Apply(state, nextBatch, session) == nil, 'foreign session remains rejected')

view:Destroy(); observer:Destroy(); model:Destroy(); replacement:Destroy()
print('PASS: ' .. count .. ' curved rune pipeline assertions (production renderer, queue, protocol and server storage; GPU boundary mocked)')
