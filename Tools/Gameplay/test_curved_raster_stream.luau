-- 持续符文输入压力回归：真实时钟测量正式曲面符文渲染器帧延迟
local R = require('@lune/roblox')
local Process = require('@lune/process')
local View = require('./CurvedPaintView')
local Curve = require('./CurvedSurface')
local Data = require('./BodySurfaceData')
local Config = require('./GameConfig')
local B = require('./CurvedRasterBoundary')

local part = R.Instance.new('Part')
part.Name, part.Size = 'UpperTorso', Data.Parts.UpperTorso.size
part:SetAttribute('SurfaceVersion', Curve.Version)

-- 按符文真实落印间距 0.38 stud 在躯干正面生成循环路径样本
local samples = {}
local previous = R.Vector2.new(0, part.Size.Y * 0.28)
local remaining = 0
for index = 1, 2048 do
	local phase = index / 2048 * math.pi * 2
	local point = R.Vector2.new(math.sin(phase) * part.Size.X * 0.36, math.cos(phase * 3) * part.Size.Y * 0.28)
	local distance = (point - previous).Magnitude
	while remaining <= distance do
		local p = previous:Lerp(point, if distance > 0 then remaining / distance else 0)
		table.insert(samples, Curve.ProjectLocal(part, R.Vector3.new(p.X, p.Y, -part.Size.Z * 0.5)))
		remaining += Config.RuneStampSpacing
	end
	remaining -= distance
	previous = point
end

local function runeSegment(serial, sample, gesture)
	return {
		key = 'stream:' .. serial,
		version = 1,
		gesture = gesture,
		part = part.Name,
		face = 1,
		u = sample.u,
		v = sample.v,
		glyph = ((serial - 1) % Config.RuneGlyphCount) + 1,
		angle = (serial % 8) * 0.4 - 1.4,
		scale = 1,
		triangle = sample.triangle,
		surfaceVersion = Curve.Version,
	}
end

local count = 0
for _, fps in { 30, 60 } do
	for _, pixels in { 100, 300 } do
		if Process.args[1] and (fps ~= tonumber(Process.args[1]) or pixels ~= tonumber(Process.args[2])) then continue end
		local records = {}
		local view = View.new()
		view.diagnostics = { submitted = 0, completed = 0, scanned = 0, commits = 0, commitSeconds = 0 }
		view:Bind('body', B.Model({ part }), records)
		B.os.clock = os.clock
		view:Update('body')
		local serial, cursor, oldest, maxPending, maxWait, updateSeconds = 0, 0, 1, 0, 0, 0
		local submittedAt, waits = {}, {}
		local frameCount = fps * 10
		local maxUpdate = 0
		local carryStuds = 0
		for frame = 1, frameCount do
			carryStuds += pixels / 160 -- 160 屏幕像素/stud
			local gesture = math.floor(frame / (fps * 2)) + 1
			while carryStuds >= Config.RuneStampSpacing do
				carryStuds -= Config.RuneStampSpacing
				cursor += 1
				serial += 1
				local s = runeSegment(serial, samples[(cursor - 1) % #samples + 1], gesture)
				records[s.key] = s
				view:Apply('body', s)
				submittedAt[serial] = frame
			end
			local before = os.clock()
			view:Update('body')
			local duration = os.clock() - before
			updateSeconds += duration
			maxUpdate = math.max(maxUpdate, duration)
			local completed = view.diagnostics.completed
			while oldest <= completed do
				table.insert(waits, frame - submittedAt[oldest])
				oldest += 1
			end
			local pending = serial - completed
			maxPending = math.max(maxPending, pending)
			if pending > 0 then
				maxWait = math.max(maxWait, frame - submittedAt[oldest])
			end
		end
		local tail = 0
		while not view:IsReady('body') and tail < 600 do
			view:Update('body')
			tail += 1
		end
		table.sort(waits)
		local p95 = waits[math.max(1, math.ceil(#waits * 0.95))] or frameCount
		local d = view.diagnostics
		print(string.format('STREAM runes %dfps %dpx/frame: input=%d peakPending=%d oldest=%dframes completedP95=%dframes tail=%d ready=%s updateCPU=%.3fs maxUpdate=%.4fs scanned=%d commitCPU=%.4fs',
			fps, pixels, serial, maxPending, maxWait, p95, tail, tostring(view:IsReady('body')), updateSeconds, maxUpdate, d.scanned, d.commitSeconds))
		assert(view:IsReady('body') and d.completed == serial, 'every submitted rune must finish without loss')
		assert(p95 <= 2 and tail <= 2, 'sustained Lune rune input exceeded two-frame latency target')
		count += 2
		view:Destroy()
		table.clear(B.images)
	end
end
part:Destroy()
print('PASS: ' .. count .. ' sustained curved rune raster assertions (Lune CPU and mocked image writes; not Studio FPS)')
