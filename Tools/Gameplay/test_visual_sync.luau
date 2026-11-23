-- 符文视觉同步回归：字段校验、幂等保存、预算、限频队列、确认延迟及收尾
local Rules = require('./VisualRules')
local Upload = require('./VisualUpload')
local Net = require('./VisualNet')
local Config = require('./GameConfig')
local Protocol = require('./VisualProtocol')
local checks = 0
local function check(v, m) assert(v, m); checks += 1 end

local function stamp(index, version)
	return {
		key = 'session:1:' .. index,
		gesture = 1,
		version = version or 1,
		part = 'UpperTorso',
		face = 1,
		u = 0.5,
		v = 0.5,
		glyph = ((index - 1) % Config.RuneGlyphCount) + 1,
		angle = 0.25,
		scale = 1,
	}
end

check(Config.PaintTarget > 0 and Config.PaintTarget <= 1 and Config.PaintFlatTarget > 0 and Config.PaintFlatTarget <= 1, 'server completion targets stay within valid (0, 1] range')
local state = Rules.New()
local first = stamp(1)
check(Rules.Validate(first), 'valid rune stamp accepted')
local accepted = Rules.Apply(state, { first }, 'session')
check(accepted and #accepted == 1 and state.count == 1 and state.segments[first.key].glyph == 1, 'canonical rune stamp saved')
local duplicate = Rules.Apply(state, { first }, 'session')
check(duplicate and #duplicate == 0 and state.count == 1, 'duplicates are idempotent')

local invalid = stamp(2); invalid.u = 0 / 0
check(not Rules.Validate(invalid), 'NaN coordinate rejected')
invalid = stamp(2); invalid.u = 1.1
check(not Rules.Validate(invalid), 'out-of-face coordinate rejected')
invalid = stamp(2); invalid.glyph = 4
check(not Rules.Validate(invalid), 'out-of-range glyph rejected')
invalid = stamp(2); invalid.glyph = 1.5
check(not Rules.Validate(invalid), 'fractional glyph rejected')
invalid = stamp(2); invalid.scale = 0.4
check(Rules.Validate(invalid), 'scale at or above RuneMinScale accepted')
invalid = stamp(2); invalid.scale = Config.RuneMinScale - 0.05
check(not Rules.Validate(invalid), 'scale below RuneMinScale rejected')
invalid = stamp(2); invalid.scale = 1.2
check(not Rules.Validate(invalid), 'scale above 1 rejected')
invalid = stamp(2); invalid.angle = 4
check(not Rules.Validate(invalid), 'angle outside [-pi, pi] rejected')

check(Rules.Apply(state, { stamp(2) }, 'wrong-session') == nil, 'wrong session key rejected')
local mutated = stamp(1, 2); mutated.glyph = 2
check(Rules.Apply(state, { mutated }, 'session') == nil, 'stable rune glyph/origin enforced')
state.count = Config.PaintLocalSegmentBudget
check(Rules.Apply(state, { stamp(2) }, 'session') == nil, 'whole-body budget enforced')

local upload = Upload.new(); upload:Begin('session')
local s1, s2 = stamp(1), stamp(2)
upload:Update({ [s1.key] = s1 }, 0.01, 10, false)
upload:Update({ [s2.key] = s2 }, 0.02, 10, false)
check(#Net.requests == 0, 'rendering updates do not send each frame')
upload:Update({}, 0.1, 10, false)
check(#Net.requests == 1 and #Net.requests[1].segments == 2, 'queue batches rune stamps within interval')
upload.closing = true
upload:Update({}, 0.2, 10, true)
check(#Net.requests == 1, 'exit waits for acknowledgement')
upload:Update({}, 1.2, 11, true)
check(#Net.requests == 2 and Net.requests[2].sequence == 1, 'unacknowledged batch retries with original sequence')
upload:Ack(1)
upload:Update({}, 1.3, 11, true)
check(Net.requests[3].action == 'EndPaint' and Net.requests[3].sequence == 1, 'finish references fully acknowledged final batch')
upload:Update({}, 1.4, 11, true)
check(#Net.requests == 3, 'finish submitted once')

table.clear(Net.requests); upload:Begin('session')
local many = {}
for i = 1, 130 do local s = stamp(i); many[s.key] = s end
upload:Update(many, 2, 12, true)
check(#Net.requests == 3 and #Net.requests[1].segments == 64 and #Net.requests[3].segments == 2, 'large flush splits into bounded packets')
upload.closing = true; upload:Ack(2)
upload:Update({}, 2.2, 12, true)
check(#Net.requests == 3, 'delayed final acknowledgement cannot release ownership early')
upload:Ack(3); upload:Update({}, 2.3, 12, true)
check(Net.requests[4].action == 'EndPaint', 'final acknowledgement releases closing session')
upload:Clear()
check(next(upload.pending) == nil and next(upload.flight) == nil and upload.session == nil, 'session destruction clears upload resources')

do
	table.clear(Net.requests)
	upload:Begin('retry-order')
	local function sendTenPackets(indexBase, timeBase, forceFirst)
		for tick = 0, 2 do
			local batch = {}
			local perTick = if tick < 2 then 4 else 2
			for packet = 0, perTick - 1 do
				local base = indexBase + (tick * 4 + packet) * Config.PaintVisualBatchSize
				local count = if packet == perTick - 1 and tick == 2 then 1 else Config.PaintVisualBatchSize
				for offset = 1, count do
					local s = stamp(base + offset)
					batch[s.key] = s
				end
			end
			upload:Update(batch, timeBase + tick * Config.PaintBatchInterval, 12, forceFirst and tick == 0)
		end
	end
	-- 发送 10 批（1..10），确认前 8 批后再发 10 批（11..20），触发 Luau flight 哈希表乱序风险
	sendTenPackets(0, 2, true)
	check(upload.sequence == 10 and #Net.requests == 10, 'ten initial packets queued')
	upload:Ack(8)
	sendTenPackets(1000, 2.3, false)
	check(upload.sequence == 20 and #Net.requests == 20, 'twenty total packets queued across flight rehash')
	table.clear(Net.requests)
	local timeoutAt = 2.3 + 2 * Config.PaintBatchInterval + Config.PaintVisualRetrySeconds
	upload:Update({}, timeoutAt, 12, false)
	check(#Net.requests == 12, 'all twelve timed-out unacknowledged packets retransmit together')
	local serverSequence = 8
	for _, req in ipairs(Net.requests) do
		check(req.sequence == serverSequence + 1, 'timed-out packets retransmit in ascending sequence without PaintOutOfSequence')
		serverSequence = req.sequence
	end
	upload:Clear()
end

local packet = { action = 'PaintVisual', session = 'session', sequence = 1, started = 10, segments = { stamp(1) } }
check(Protocol.Validate(packet), 'visual wire packet accepted')
packet.segments = { unexpected = stamp(1) }
check(not Protocol.Validate(packet), 'dictionary cannot bypass array packet limit')
packet.segments = { [1] = stamp(1), [4] = stamp(4) }
check(not Protocol.Validate(packet), 'sparse visual packet rejected')
packet.segments = {}
for i = 1, 65 do table.insert(packet.segments, stamp(i)) end
check(not Protocol.Validate(packet), 'wire packet capped at 64 stamps')
packet.segments = { stamp(1) }; packet.started = math.huge
check(not Protocol.Validate(packet), 'nonfinite presentation timestamp rejected')
packet.started = 10; packet.sequence = 1.5
check(not Protocol.Validate(packet), 'fractional wire sequence rejected')

local extra = stamp(1); extra.unrecognized = 'must not be retained'
local cleanState = Rules.New(); Rules.Apply(cleanState, { extra }, 'session')
check(cleanState.segments[extra.key].unrecognized == nil, 'canonical storage strips fields outside visual protocol')
print(string.format('PASS: %d rune visual protocol and queue assertions (production modules)', checks))
