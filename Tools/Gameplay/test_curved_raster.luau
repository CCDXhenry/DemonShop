-- 正式曲面符文渲染器回归：三枚字形光栅化、抗锯齿混合、献祭重着色、防背侧透印、UV 接缝、缓存与退出收尾
local R = require('@lune/roblox')
local View = require('./CurvedPaintView')
local Curve = require('./CurvedSurface')
local Data = require('./BodySurfaceData')
local Config = require('./GameConfig')
local B = require('./CurvedRasterBoundary')
local Upload = require('./VisualUpload')
local Net = require('./VisualNet')
local count = 0
local function check(value, message) assert(value, message); count += 1 end

local parts = {}
for _, name in { 'UpperTorso', 'Head', 'LeftHand', 'LeftFoot' } do
	local part = R.Instance.new('Part')
	part.Name, part.Size = name, Data.Parts[name].size
	part:SetAttribute('Paintable', true)
	part:SetAttribute('SurfaceVersion', Curve.Version)
	table.insert(parts, part)
end
local model = B.Model(parts)
local records = {}
local view = View.new()
view.diagnostics = { submitted = 0, completed = 0, scanned = 0, commits = 0, commitSeconds = 0 }
view:Bind('body', model, records)
view:Update('body')
local texture = view.textures.body
check(view:IsReady('body') and #texture.image.writes == 1, 'empty active texture initialized and ready')
check(texture.size == 1024 and model.meshes[1].TextureContent == texture.image, 'active texture attached at full resolution')

-- 副白膜共用中心图集。流送重绑和离开批次会重新绑定或解除引用。
local follower = B.Model(parts)
view:SetMirror('follower', 'body')
view:Bind('follower', follower, {})
check(follower.meshes[1].TextureContent == texture.image and view.textures.follower == nil, 'follower renders the same live pixels without an extra atlas')
view:Remove('follower')
local rebound = B.Model(parts)
view:Bind('follower', rebound, {})
check(rebound.meshes[1].TextureContent == texture.image, 'streaming rebind restores the shared atlas')
view:ReleaseMirrors('body')
check(rebound.meshes[1].TextureContent == B.Content.none and not texture.image.destroyed, 'unlink clears only the follower texture')
view:Remove('follower')

local serial = 0
local function runeStamp(part, sample, glyph, angle, scale)
	serial += 1
	return {
		key = 'session:1:' .. serial,
		version = 1,
		gesture = 1,
		part = part.Name,
		face = 1,
		u = sample.u,
		v = sample.v,
		glyph = glyph or (((serial - 1) % Config.RuneGlyphCount) + 1),
		angle = angle or 0,
		scale = scale or 1,
		triangle = sample.triangle,
		surfaceVersion = Curve.Version,
	}
end
local function projected(part, x, y, z)
	return Curve.ProjectLocal(part, R.Vector3.new(x, y, z) * part.Size)
end
local function add(s)
	records[s.key] = s
	view:Apply('body', s)
end

-- 在各部件正面、侧面及旋转角度放置三枚不同符文
for _, part in parts do
	add(runeStamp(part, projected(part, -0.15, 0.05, -0.49), 1, 0, 1))
	add(runeStamp(part, projected(part, 0.15, 0.05, -0.49), 2, 0.6, 1))
	add(runeStamp(part, projected(part, 0, -0.1, -0.49), 3, -0.8, 0.7))
end

-- 从实际资产查找位置相同、UV 分离的接缝顶点，验证符文跨 UV 接缝两侧贴印不断裂
local head = parts[2]
local source = Data.Parts.Head
local seamA, seamB
for first, a in source.vertices do
	for second = first + 1, #source.vertices do
		if (a - source.vertices[second]).Magnitude < 1e-5 and (source.uvs[first] - source.uvs[second]).Magnitude > 0.1 then
			seamA, seamB = first, second
			break
		end
	end
	if seamA then break end
end
check(seamA ~= nil and seamB ~= nil, 'fixture discovers a real duplicated-position UV seam')
local seam = Curve.ProjectLocal(head, source.vertices[seamA] * head.Size)
add(runeStamp(head, seam, 2, 0, 1))

local function drain(target, active)
	local frames = 0
	repeat
		target:Update(active)
		frames += 1
		assert(frames < 20000, 'raster queue failed to drain')
	until target:IsReady('body')
	return frames
end

B.step = 0.001
local writes = #texture.image.writes
view:Update('body')
local frames = drain(view, 'body')
local liveWriteEnd = #texture.image.writes
check(frames >= 1, 'curved rune batch completes cleanly')
check(buffer.tostring(texture.image.pixels) == buffer.tostring(texture.pixels), 'partial GPU writes reproduce complete CPU image')

-- 验证存在真实抗锯齿过渡像素（0 < alpha < 255）和饱和紫色核心像素（alpha == 255）
local fullCount, aaCount = 0, 0
for i = 0, texture.size * texture.size - 1 do
	local a = buffer.readu8(texture.alpha, i)
	if a == 255 then
		fullCount += 1
	elseif a > 0 then
		aaCount += 1
	end
end
check(fullCount > 200 and aaCount > 100, string.format('rendered runes have both solid core (%d) and anti-aliased edge pixels (%d)', fullCount, aaCount))

-- 验证 UV 接缝两侧均着色
for _, vertex in { seamA, seamB } do
	local uv = source.uvs[vertex]
	local x, y = math.floor(uv.X * texture.size), math.floor((1 - uv.Y) * texture.size)
	local painted = false
	for dy = -12, 12 do
		for dx = -12, 12 do
			local cx = math.clamp(x + dx, 0, texture.size - 1)
			local cy = math.clamp(y + dy, 0, texture.size - 1)
			if buffer.readu8(texture.alpha, cy * texture.size + cx) > 0 then
				painted = true
				break
			end
		end
		if painted then break end
	end
	check(painted, 'rune paints actual UV seam island ' .. vertex)
end

-- 验证献祭高亮：按 alpha 缓冲重着色，非空白像素平滑变亮且纯白背景不变
view:SetSacrifice('body', 1)
local highlight = Config.AltarStrokeHighlight
local hiR = math.floor(highlight.R * 255 + 0.5)
local tintedMatches, backgroundUntouched = 0, true
for i = 0, texture.size * texture.size - 1 do
	local a = buffer.readu8(texture.alpha, i)
	local r = buffer.readu8(texture.image.pixels, i * 4)
	if a == 255 and r == hiR then
		tintedMatches += 1
	elseif a == 0 and r ~= 255 then
		backgroundUntouched = false
	end
end
check(tintedMatches == fullCount and backgroundUntouched, 'sacrifice tint highlights rune pixels cleanly without altering white background')
view:SetSacrifice('body', 0)
check(buffer.tostring(texture.image.pixels) == buffer.tostring(texture.pixels), 'clearing sacrifice restores base purple pixels')

-- 验证防背侧透印：仅在躯干正面印一枚符文时，背面对应 UV 必须保持空白
local frontOnly = View.new()
local frontRecords = {}
frontOnly:Bind('body', model, frontRecords)
frontOnly:Update('body')
local frontSample = projected(parts[1], 0, 0, -0.49)
local frontRune = runeStamp(parts[1], frontSample, 1, 0, 1)
frontRecords[frontRune.key] = frontRune
frontOnly:Apply('body', frontRune)
drain(frontOnly, 'body')
local backSample = projected(parts[1], 0, 0, 0.49)
local backUv = Curve.UV(parts[1].Name, backSample.triangle, backSample.u, backSample.v)
local bx = math.clamp(math.floor(backUv.X * 1024), 0, 1023)
local by = math.clamp(math.floor((1 - backUv.Y) * 1024), 0, 1023)
check(buffer.readu8(frontOnly.textures.body.alpha, by * 1024 + bx) == 0, 'front-face rune does not bleed onto the opposite backside')
frontOnly:Destroy()

-- 验证躺平模式 side=2 (-Z) 印在曲面肢体边缘时，严格裁剪在 -Z 半球，+Z 对侧三角面像素保持 0
do
	local sideView = View.new()
	local sideRecords = {}
	local hand = parts[3]
	sideView:Bind('side', model, sideRecords)
	sideView:Update('side')
	local edgeSample = Curve.ProjectLocal(hand, R.Vector3.new(hand.Size.X * 0.48, 0, -hand.Size.Z * 0.18))
	local edgeRune = runeStamp(hand, edgeSample, 1, 0, 1)
	edgeRune.side = 2
	sideRecords[edgeRune.key] = edgeRune
	sideView:Apply('side', edgeRune)
	B.step = 0.001
	repeat sideView:Update('side') until sideView:IsReady('side')
	local tex = sideView.textures.side
	local handGeo = Curve.Geometry(hand)
	local activeInked, oppositeInked = 0, 0
	for idx, tri in handGeo.triangles do
		local uv = Curve.UV(hand.Name, idx, 1 / 3, 1 / 3)
		local px = math.clamp(math.floor(uv.X * tex.size), 0, tex.size - 1)
		local py = math.clamp(math.floor((1 - uv.Y) * tex.size), 0, tex.size - 1)
		if buffer.readu8(tex.alpha, py * tex.size + px) > 0 then
			if -tri.normal.Z >= Curve.FlatVisualClipMinDot then
				activeInked += 1
			elseif tri.normal.Z >= Curve.FlatVisualClipMinDot then
				oppositeInked += 1
			end
		end
	end
	check(activeInked > 0 and oppositeInked == 0, 'side=2 (-Z) rim rune inks -Z triangles and leaves zero pixels on +Z triangles')
	sideView:Destroy()
end

-- 验证局部脏矩形提交（按 64×64 分块，跨多部位 UV 岛不合并为整图拷贝）、驻留缓存与驱逐后重建
local partial, maxWriteDim = false, 0
for index = writes + 1, liveWriteEnd do
	local write = texture.image.writes[index]
	if write.size.X < texture.size or write.size.Y < texture.size then partial = true end
	maxWriteDim = math.max(maxWriteDim, write.size.X, write.size.Y)
end
check(partial and maxWriteDim <= 64, 'live runes submit bounded 64x64 dirty chunks instead of merging across UV islands')

local oldImage = texture.image
local replacement = B.Model(parts)
view:Bind('body', replacement, records)
check(replacement.meshes[1].TextureContent == oldImage, 'model replacement rebinds completed atlas')
view:RemoveTexture('body')
check(oldImage.destroyed, 'eviction destroys image')
view:Update(nil)
local rebuilt = view.textures.body
check(rebuilt.rebuilding and #rebuilt.image.writes == 0, 'history rebuild has no partial image submission')
drain(view, nil)
check(#rebuilt.image.writes == 1 and rebuilt.size == 512, 'observer atlas restores at observer resolution after complete rebuild')
view:Update('body'); drain(view, 'body')
check(view.textures.body.size == 1024, 'observer texture upgrades when painting resumes')

-- 验证 rebuilding 期间持续追加实时新笔迹不会锁死历史重建完成与 Attach
view:RemoveTexture('body')
B.step = 0.001
view:Update('body')
local liveRebuilding = view.textures.body
check(liveRebuilding ~= nil and liveRebuilding.rebuilding, 'rebuilding starts for existing history')
local unlocked = false
for frame = 1, 5000 do
	if frame <= 10 then
		local liveStamp = runeStamp(parts[1], projected(parts[1], 0, 0.1 + frame * 0.005, -0.49), 2, 0.2, 1)
		records[liveStamp.key] = liveStamp
		view:Apply('body', liveStamp)
	end
	view:Update('body')
	if not liveRebuilding.rebuilding and replacement.meshes[1].TextureContent == liveRebuilding.image then
		unlocked = true
		break
	end
end
check(unlocked, 'live strokes appended during history rebuild do not block rebuild completion or attach')
drain(view, 'body')
check(buffer.tostring(liveRebuilding.image.pixels) == buffer.tostring(liveRebuilding.pixels), 'live strokes after rebuild unlock commit cleanly to GPU')

-- 验证 Warmup 可在进入画符时立即预热 1024 活跃图集
local warmupView = View.new()
warmupView:Bind('warm', model, {})
B.step = 0
warmupView:Warmup('warm')
local warmed = warmupView.textures.warm
check(warmed ~= nil and warmed.size == 1024 and not warmed.rebuilding and warmupView:IsReady('warm'), 'Warmup pre-initializes ready 1024 active texture')
-- 验证新符文高亮渐隐动画：实时落印初始呈现高亮色，经过 RuneAppearSeconds 后平滑回落为常规魔力紫。
do
	local appearSample = projected(parts[1], 0, 0, -0.49)
	local appearStamp = runeStamp(parts[1], appearSample, 1, 0, 1)
	warmupView.records.warm[appearStamp.key] = appearStamp
	warmupView:Apply('warm', appearStamp)
	B.step = 0.001
	repeat warmupView:Update('warm') until warmupView:IsReady('warm')
	local appearR = math.floor(Config.RuneAppearHighlightColor.R * 255 + 0.5)
	local baseR = math.floor(Config.RuneBaseColor.R * 255 + 0.5)
	local sawHighlight = false
	for i = 0, warmed.size * warmed.size - 1 do
		if buffer.readu8(warmed.alpha, i) == 255 and buffer.readu8(warmed.pixels, i * 4) == appearR then
			sawHighlight = true
			break
		end
	end
	check(sawHighlight and #warmed.flashes > 0, 'newly stamped rune starts at bright appear highlight color')
	B.time += Config.RuneAppearSeconds + 0.1
	warmupView:Update('warm')
	local allBase = true
	for i = 0, warmed.size * warmed.size - 1 do
		if buffer.readu8(warmed.alpha, i) == 255 and buffer.readu8(warmed.pixels, i * 4) ~= baseR then
			allBase = false
			break
		end
	end
	check(allBase and #warmed.flashes == 0, 'appear highlight smoothly cools back to RuneBaseColor after RuneAppearSeconds')
end
warmupView:Destroy()

-- 验证 R15 直连邻接跨缝投影与非邻接部位隔离：UpperTorso/LowerTorso 接缝处符文同时渲染到两部位，LeftUpperLeg 内侧不误染 RightUpperLeg
do
	local seamParts = {}
	for _, name in { 'UpperTorso', 'LowerTorso', 'LeftUpperLeg', 'RightUpperLeg' } do
		local p = R.Instance.new('Part')
		p.Name, p.Size = name, Data.Parts[name].size
		p:SetAttribute('Paintable', true)
		p:SetAttribute('SurfaceVersion', Curve.Version)
		table.insert(seamParts, p)
	end
	local seamModel = B.Model(seamParts)
	local seamView = View.new()
	local seamRecords = {}
	seamView:Bind('seam', seamModel, seamRecords)
	seamView:Update('seam')
	local seamSample = Curve.ProjectLocal(seamParts[1], R.Vector3.new(0, -seamParts[1].Size.Y * 0.49, seamParts[1].Size.Z * 0.48))
	local seamStamp = runeStamp(seamParts[1], seamSample, 1, 0, 1)
	seamRecords[seamStamp.key] = seamStamp
	seamView:Apply('seam', seamStamp)
	B.step = 0.001
	repeat seamView:Update('seam') until seamView:IsReady('seam')

	local function TileHasInk(tex, tile)
		local sz = tex.size
		local x0 = math.floor(tile.X * sz / 4)
		local x1 = math.floor((tile.X + 1) * sz / 4) - 1
		local y0 = math.floor((3 - tile.Y) * sz / 4)
		local y1 = math.floor((4 - tile.Y) * sz / 4) - 1
		for py = y0, y1 do
			for px = x0, x1 do
				if buffer.readu8(tex.alpha, py * sz + px) > 0 then
					return true
				end
			end
		end
		return false
	end

	local seamTex = seamView.textures.seam
	check(TileHasInk(seamTex, Data.Parts.UpperTorso.tile) and TileHasInk(seamTex, Data.Parts.LowerTorso.tile), 'seam stamp projects seamlessly across UpperTorso and LowerTorso')
	check(not TileHasInk(seamTex, Data.Parts.RightUpperLeg.tile), 'seam stamp does not bleed onto non-adjacent RightUpperLeg')

	-- 单独测试 LeftUpperLeg 内侧落印不误染对侧 RightUpperLeg
	local legView = View.new()
	local legRecords = {}
	legView:Bind('leg', seamModel, legRecords)
	legView:Update('leg')
	local legSample = Curve.ProjectLocal(seamParts[3], R.Vector3.new(-seamParts[3].Size.X * 0.49, 0, seamParts[3].Size.Z * 0.3))
	local legStamp = runeStamp(seamParts[3], legSample, 2, 0, 1)
	legRecords[legStamp.key] = legStamp
	legView:Apply('leg', legStamp)
	repeat legView:Update('leg') until legView:IsReady('leg')
	check(TileHasInk(legView.textures.leg, Data.Parts.LeftUpperLeg.tile) and not TileHasInk(legView.textures.leg, Data.Parts.RightUpperLeg.tile), 'inner LeftUpperLeg stamp never bleeds across air to RightUpperLeg')

	seamView:Destroy(); legView:Destroy()
	for _, p in seamParts do p:Destroy() end
end

-- 网络已确认但本地未画完时不能结束会话
table.clear(Net.requests)
local upload = Upload.new(); upload:Begin('session'); upload.closing = true
upload:Update({}, 1, 1, true, nil, false)
check(#Net.requests == 0, 'exit waits for local raster even with no pending network batches')
upload:Update({}, 1.1, 1, true, nil, true)
check(#Net.requests == 1 and Net.requests[1].action == 'EndPaint', 'raster completion permits final EndPaint')

view:Destroy()
local failed = View.new()
failed:Bind('body', model, records)
B.failNext = true; failed:Update('body')
check(failed.failed and failed.textures.body == nil and failed:IsReady('body'), 'image API failure releases raster wait')
failed:Destroy()
for _, part in parts do part:Destroy() end
print('PASS: ' .. count .. ' production curved rune raster assertions')
