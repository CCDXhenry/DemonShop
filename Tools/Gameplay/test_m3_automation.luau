-- M3 自动化解锁协议与双线加工状态机回归测试（踩踏解锁、并发互斥、无限断点+6实体、A00/A03/A04 及双线隔离）
local R = require('@lune/roblox')
local fs = require('@lune/fs')
local CFrame, Vector3, Color3, Instance = R.CFrame, R.Vector3, R.Color3, R.Instance
local B = require('./StationPotionBoundary')
local Config = require('./GameConfig')
local GameData = require('./GameData')
local Physics = require('./PhysicsConfig')
local Rules = require('./AutomationRules')
local Scene = require('./StationScene')
local Manager = require('./StationProcessingManager')

local checks = 0
local function check(cond, msg)
	assert(cond, msg)
	checks += 1
end

-- 1. 配置表与依赖关系契约校验
local F = GameData.FacilityId
check(Scene.AutoPotionRack ~= nil and Scene.AutoPotionRack.Parent == Scene.AutoSmelterMachine, 'AutoPotionRack is a direct child of AutoSmelterMachine')
check(GameData.GetFacility(F.FastChute).cost == 250 and GameData.GetFacility(F.FastChute).prerequisite == nil, 'A00 cost & no prereq')
check(GameData.GetFacility(F.Brute1).cost == 1000 and GameData.GetFacility(F.Brute1).prerequisite == F.FastChute, 'A01 cost & prereq A00')
check(GameData.GetFacility(F.Brute2).cost == 2500 and GameData.GetFacility(F.Brute2).prerequisite == F.Brute1, 'A02 cost & prereq A01')
check(GameData.GetFacility(F.AutoRune).cost == 2000 and GameData.GetFacility(F.AutoRune).prerequisite == F.FastChute, 'A03 cost & prereq A00')
check(GameData.GetFacility(F.AutoSmelter).cost == 4500 and GameData.GetFacility(F.AutoSmelter).prerequisite == F.AutoRune, 'A04 cost & prereq A03')
check(GameData.GetFacility(F.AutoClerk).cost == 9000 and GameData.GetFacility(F.AutoClerk).prerequisite == nil, 'A05 cost & no prereq')
check(table.concat(GameData.GetFacilityOrder(), ',') == '1,2,3,4,5,6', 'facility order matches excel order')
check(#GameData.GetAllFacilities() == 6, 'all 6 facilities loaded')
check(Config.AutoRuneSeconds == 2.0 and Config.AutoSmelterSeconds == 2.5 and Config.AutoQueueVisibleLimit == 6, 'automation cadence & limit')

-- 2. 解锁按钮状态、视觉同步与模型归档校验
check(Rules.ComputePadState(F.FastChute, {}, 249) == 'Insufficient', 'A00 insufficient coins -> red')
check(Rules.ComputePadState(F.FastChute, {}, 250) == 'Ready', 'A00 enough coins -> green')
check(Rules.ComputePadState(F.AutoRune, {}, 9999) == 'Locked', 'A03 without A00 stays locked even with enough coins')
check(Rules.ComputePadState(F.AutoRune, { [F.FastChute] = true }, 1999) == 'Insufficient', 'A03 after A00 insufficient -> red')
check(Rules.ComputePadState(F.AutoRune, { [F.FastChute] = true }, 2000) == 'Ready', 'A03 after A00 enough -> green')
check(Rules.ComputePadState(F.AutoRune, { [F.FastChute] = true, [F.AutoRune] = true }, 0) == 'Unlocked', 'A03 unlocked state')

local roots = R.deserializeModel(fs.readFile('Assets/Models/GameModels.rbxm'))
local modelsFolder = roots[1]
check(modelsFolder ~= nil and modelsFolder:FindFirstChild('UnlockPad') == nil and modelsFolder:FindFirstChild('NeonContractDistrict') == nil, 'GameModels.rbxm excludes static district and edit-only UnlockPad')

local function makeTestPad()
	local pad = Instance.new('Model')
	pad.Name = 'A03_AutoRune'
	pad:SetAttribute('FacilityId', F.AutoRune)
	pad:SetAttribute('InsufficientColor', Color3.fromRGB(255, 76, 98))
	pad:SetAttribute('ReadyColor', Color3.fromRGB(72, 245, 146))
	for _, name in { 'OuterRim', 'GlowRing', 'InnerDisc', 'CenterGlyph', 'TriggerZone' } do
		local p = Instance.new('Part')
		p.Name = name
		p.Parent = pad
	end
	local guiAnchor = Instance.new('Part')
	guiAnchor.Name = 'GuiAnchor'
	guiAnchor.Parent = pad
	local bb = Instance.new('BillboardGui')
	bb.Name = 'PadGui'
	bb.Parent = guiAnchor
	local card = Instance.new('Frame')
	card.Name = 'CardFrame'
	card.Parent = bb
	local stroke = Instance.new('UIStroke')
	stroke.Name = 'BorderStroke'
	stroke.Parent = card
	local prereq = Instance.new('TextLabel')
	prereq.Name = 'PrereqText'
	prereq.Text = 'REQUIRES: FAST DROP CHUTE'
	prereq.Parent = card
	return pad
end

do
	local pad = makeTestPad()
	local gui = pad.GuiAnchor.PadGui
	local light = Instance.new('PointLight')
	light.Parent = pad.CenterGlyph
	local unlocked = {}

	check(Rules.SyncPad(pad, unlocked, 9999) == 'Locked', 'A03 remains locked even with enough coins')
	check(pad.OuterRim.LocalTransparencyModifier == 1 and not gui.Enabled and not light.Enabled, 'Unmet prerequisite hides the pad, card, and light')
	check(pad.TriggerZone.CanTouch, 'Hidden pad keeps the existing touch trigger available')
	check(pad:GetAttribute('Unlocked') == false, 'Hidden prerequisite pad stays marked as unpurchased')

	unlocked[F.FastChute] = true
	check(Rules.SyncPad(pad, unlocked, 1999) == 'Insufficient', 'A03 becomes visible before the player can afford it')
	check(pad.OuterRim.LocalTransparencyModifier == 0 and gui.Enabled and light.Enabled, 'Meeting the prerequisite reveals the pad, card, and light')
	check(pad.GlowRing.Color == pad:GetAttribute('InsufficientColor'), 'Insufficient applies InsufficientColor red')
	check(not gui.CardFrame.PrereqText.Visible, 'Visible card hides old prerequisite label')

	check(Rules.SyncPad(pad, unlocked, 2000) == 'Ready', 'A03 is ready once affordable')
	check(pad.GlowRing.Color == pad:GetAttribute('ReadyColor'), 'Ready applies ReadyColor green')
	check(gui.Enabled and not gui.CardFrame.PrereqText.Visible, 'Ready card still hides prerequisite label')

	unlocked[F.AutoRune] = true
	check(Rules.SyncPad(pad, unlocked, 0) == 'Unlocked', 'Purchased facility is unlocked')
	check(pad.OuterRim.LocalTransparencyModifier == 1 and not pad.TriggerZone.CanTouch and not gui.Enabled and not light.Enabled, 'Unlocked hides pad, card, and light and disables touch')
end

do
	local pad = makeTestPad()
	pad:SetAttribute('FacilityId', F.FastChute)
	check(Rules.SyncPad(pad, nil, 0) == 'Insufficient', 'A00 is available before the initial snapshot')
	check(pad.OuterRim.LocalTransparencyModifier == 0 and pad.GuiAnchor.PadGui.Enabled, 'Pad without a prerequisite is visible from the start')
	check(not pad.GuiAnchor.PadGui.CardFrame.PrereqText.Visible, 'Pad without a prerequisite hides old prerequisite label')
end
check(Rules.FormatCost(250) == '250' and Rules.FormatCost(2500) == '2.5K' and Rules.FormatCost(1000000) == '1M', 'FormatCost formats AA suffixes')
check(Rules.DescribeTitle(F.FastChute) == 'FAST DROP CHUTE' and Rules.DescribeDesc(F.AutoRune) == 'AUTO-PULLS BODIES AND ENGRAVES RUNES', 'DescribeTitle/Desc return source text from GameData')
check(Rules.DescribePrice(F.AutoClerk).textId == 'PadPrice' and Rules.DescribePrice(F.AutoClerk).args[1] == '9K', 'DescribePrice formats PadPrice description')

-- 工具函数：构造测试白膜与重置场景
local function makeTestBody(manager, stage)
	local model = B.ModelsFolder.Characters["WhiteR15-People"]:Clone()
	local id = B.HttpService.GenerateGUID(false)
	model:SetAttribute('ItemId', id)
	model.Parent = manager.runtime
	local item = {
		id = id,
		kind = 'Body',
		stage = stage or 'Unpainted',
		location = 'Ground',
		version = 1,
		model = model,
		holder = nil,
		hits = Config.StunHits,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = 10,
		progress = if stage == 'Painted' then 1 else 0,
		paintSeconds = 0,
		streetSlot = false,
		nextWalk = 0,
	}
	manager.items[id] = item
	return item
end

local function makeTestManager(runInit)
	B.ResetPlayers()
	table.clear(B.broadcasts)
	table.clear(B.notices)
	local coinsEarned = {}
	local manager = Manager.new({
		IsActive = function() return true end,
		CanAddCoins = function() return true end,
		AddCoins = function(player, amount)
			coinsEarned[player] = (coinsEarned[player] or 0) + amount
			player:SetAttribute('Coins', (player:GetAttribute('Coins') or 0) + amount)
			return true
		end,
		CanSpendCoins = B.Info.CanSpendCoins,
		SpendCoins = B.Info.SpendCoins,
		TrySpendCoins = B.Info.TrySpendCoins,
	})
	if runInit then
		manager:Init()
	else
		manager.initialized = true
	end
	return manager, coinsEarned
end

-- 3. 踩踏解锁前置校验、防远距离作弊、并发防双扣与全房广播
do
	local facilities = {
		[F.FastChute] = Scene.AutomationLine.FastChuteLanding,
		[F.Brute1] = Scene.BrutePost,
		[F.AutoRune] = Scene.AutoRuneMachine,
		[F.AutoSmelter] = Scene.AutoPotionRack,
		[F.AutoClerk] = Scene.AutoClerkStation,
	}
	local parts = {}
	for id, model in facilities do
		local part = Instance.new('Part')
		part.Transparency = 0.25
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = true
		part.Parent = model
		parts[id] = part
	end
	local runeAnchor = Scene.AutoRuneWorkBed
	runeAnchor.Transparency = 1
	runeAnchor.CanCollide = false
	runeAnchor.CanQuery = false
	runeAnchor.CanTouch = false
	local sign = Instance.new('SurfaceGui')
	sign.Enabled = true
	sign.Parent = parts[F.AutoRune]
	local light = Instance.new('PointLight')
	light.Enabled = true
	light.Parent = parts[F.AutoRune]
	local effect = Instance.new('ParticleEmitter')
	effect.Enabled = true
	effect.Parent = parts[F.AutoRune]
	local disabledEffect = Instance.new('ParticleEmitter')
	disabledEffect.Enabled = false
	disabledEffect.Parent = parts[F.AutoRune]
	local function isHidden(part)
		return part.Transparency == 1 and not part.CanCollide and not part.CanQuery and not part.CanTouch
	end
	local function isRestored(part)
		return part.Transparency == 0.25 and part.CanCollide and part.CanQuery and part.CanTouch
	end

	local manager = makeTestManager(true)
	for id, part in parts do
		check(isHidden(part), 'startup hides facility without leaving collisions: ' .. id)
	end
	check(not sign.Enabled and not light.Enabled and not effect.Enabled, 'startup hides signs, lights and effects')
	check(Scene.FastChuteCover.CoverPlate.CanCollide, 'chute remains covered at startup')
	check(Scene.PoolAirWalls:GetAttribute('SoftCageEnabled') == true and not Scene.PoolAirWalls.West.CanCollide and Scene.ChuteAirWalls:GetAttribute('SoftCageEnabled') == false and not Scene.ChuteAirWalls.West.CanCollide, 'pool soft cage enabled, chute soft cage locked, and air walls stay non-collidable')
	check(not Scene.ChuteBaffles.West.CanCollide and not Scene.ChuteBaffles.West.CanQuery, 'locked baffles ignore bodies and preview')
	check(Scene.UnlockPads[F.FastChute].TriggerZone.CanTouch and Scene.UnlockPads[F.FastChute].GuiAnchor.PadGui.Enabled, 'locked pad stays visible and usable')
	local padA00Pos = Scene.UnlockPads[F.FastChute].TriggerZone.Position
	local padA03Pos = Scene.UnlockPads[F.AutoRune].TriggerZone.Position
	local p1, _, _, root1 = B.CreatePlayer(101, Vector3.zero)
	local p2, _, _, root2 = B.CreatePlayer(102, padA00Pos)
	p1:SetAttribute('Coins', 5000)
	p2:SetAttribute('Coins', 500)
	manager:AddPlayer(p1)
	manager:AddPlayer(p2)

	-- 远距离欺诈请求必须拒绝且不扣款
	manager:OnRequest(p1, { action = 'UnlockFacility', facilityId = F.FastChute })
	check(not manager:IsFacilityUnlocked(F.FastChute) and p1:GetAttribute('Coins') == 5000, 'faraway UnlockFacility spoof rejected')

	-- 未解锁 A00 前踩 A03 即使金币充足也不得解锁
	root1.CFrame = CFrame.new(padA03Pos)
	root1.Position = padA03Pos
	check(not manager:TryUnlockFacility(p1, F.AutoRune) and p1:GetAttribute('Coins') == 5000, 'A03 blocked until A00 unlocked')
	check(isHidden(parts[F.AutoRune]), 'failed purchase leaves A03 hidden')

	-- 互斥锁拦截同帧重入并发
	root1.CFrame = CFrame.new(padA00Pos)
	root1.Position = padA00Pos
	manager.unlockLocks[F.FastChute] = true
	check(not manager:TryUnlockFacility(p1, F.FastChute) and p1:GetAttribute('Coins') == 5000, 'facility mutex blocks re-entrant unlock')
	manager.unlockLocks[F.FastChute] = nil

	-- 双人同站在 A00 上连续触发解锁，仅扣款 1 次 250
	table.clear(B.broadcasts)
	local ok1 = manager:TryUnlockFacility(p1, F.FastChute)
	local ok2 = manager:TryUnlockFacility(p2, F.FastChute)
	check(ok1 and not ok2, 'only first player unlocks shared A00')
	check(isRestored(parts[F.FastChute]) and isHidden(parts[F.AutoRune]), 'A00 restores its landing without revealing A03')
	check(p1:GetAttribute('Coins') == 4750 and p2:GetAttribute('Coins') == 500, 'second player never double-charged')

	-- A00 空洞开启与 Pad 隐藏 + 全房通知横幅
	local cover = Scene.FastChuteCover
	check(Scene.ChuteAirWalls:GetAttribute('SoftCageEnabled') == true and not Scene.ChuteAirWalls.West.CanCollide, 'unlocked landing enables soft cage without rigid air wall collision')
	check(Scene.ChuteBaffles.West.CanCollide and Scene.ChuteBaffles.West.CanQuery and Scene.ChuteBaffles.West.CanTouch, 'A00 enables baffle physics, preview, and local touch')
	check(cover ~= nil and cover:GetAttribute('Unlocked') == true, 'FastChuteCover marked unlocked')
	local impactItem = makeTestBody(manager, 'Unpainted')
	local limb = impactItem.model.UpperTorso
	limb.Position, limb.CanCollide = root1.Position, true
	limb.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
	local baffleSignal = B.Signal(Scene.ChuteBaffles.West, 'Touched')
	local poolSignal = B.Signal(Scene.PoolAirWalls.West, 'Touched')
	local function impacts()
		local count = 0
		for _, entry in B.notices do
			if entry.player == p1 and entry.notice.kind == 'CageImpact' then count += 1 end
		end
		return count
	end
	baffleSignal:Fire(limb)
	poolSignal:Fire(limb)
	check(impacts() == 0, 'impact flashes run locally on clients with zero server CageImpact packets')
	manager.items[impactItem.id] = nil
	impactItem.model:Destroy()

	for _, part in cover:GetDescendants() do
		if part:IsA('BasePart') then
			check(not part.CanCollide and not part.CanQuery and part.Transparency == 1, 'FastChuteCover collision & visibility cleared')
		end
	end
	local padA00 = Scene.UnlockPads[F.FastChute]
	check(padA00.TriggerZone.CanTouch == false and padA00.GuiAnchor.PadGui.Enabled == false, 'unlocked pad hidden and touch disabled')

	local foundBanner, foundSnapshot = false, false
	for _, notice in B.broadcasts do
		if notice.kind == 'Message' and notice.textId == 'FacilityUnlocked' then
			foundBanner = notice.textArgs and notice.textArgs[1] == p1.Name and notice.textArgs[2] == 'FAST DROP CHUTE'
		elseif notice.kind == 'State' or notice.kind == 'Delta' then
			if notice.snapshot and notice.snapshot.unlockedFacilities and notice.snapshot.unlockedFacilities[F.FastChute] then
				foundSnapshot = true
			end
		end
	end
	check(foundBanner == true and foundSnapshot == true, 'room broadcast banner & snapshot sync unlockedFacilities')

	-- Update 轮询：p1 移到 A03 底盘直接自动踩踏解锁（无需按键）
	root1.CFrame = CFrame.new(padA03Pos)
	root1.Position = padA03Pos
	B.now += 0.2
	manager:Update()
	check(manager:IsFacilityUnlocked(F.AutoRune) and p1:GetAttribute('Coins') == 2750, 'Update step-on polling unlocks A03 automatically')
	check(isRestored(parts[F.AutoRune]) and isHidden(runeAnchor), 'A03 restores authored part properties and preserves transparent anchors')
	check(sign.Enabled and light.Enabled and effect.Enabled and not disabledEffect.Enabled, 'A03 restores enabled and disabled presentation properties')
	local smelterPos = Scene.UnlockPads[F.AutoSmelter].TriggerZone.Position
	root1.CFrame = CFrame.new(smelterPos); root1.Position = smelterPos
	check(not manager:TryUnlockFacility(p1, F.AutoSmelter) and isHidden(parts[F.AutoSmelter]), 'unaffordable A04 leaves its rack hidden')
	p1:SetAttribute('Coins', 4500)
	check(manager:TryUnlockFacility(p1, F.AutoSmelter) and isRestored(parts[F.AutoSmelter]), 'A04 restores the nested potion rack')

	-- 验证 A01 -> A02 与独立分支 A05 前置规则
	p1:SetAttribute('Coins', 15000)
	local padA01Pos = Scene.UnlockPads[F.Brute1].TriggerZone.Position
	local padA02Pos = Scene.UnlockPads[F.Brute2].TriggerZone.Position
	local padA05Pos = Scene.UnlockPads[F.AutoClerk].TriggerZone.Position
	root1.CFrame = CFrame.new(padA02Pos); root1.Position = padA02Pos
	check(not manager:TryUnlockFacility(p1, F.Brute2), 'A02 blocked until A01 unlocked')
	root1.CFrame = CFrame.new(padA01Pos); root1.Position = padA01Pos
	check(manager:TryUnlockFacility(p1, F.Brute1) and p1:GetAttribute('Coins') == 14000, 'A01 unlocks after A00 for 1000 coins')
	check(isRestored(parts[F.Brute1]), 'first brute reveals the shared post')
	root1.CFrame = CFrame.new(padA02Pos); root1.Position = padA02Pos
	check(manager:TryUnlockFacility(p1, F.Brute2) and p1:GetAttribute('Coins') == 11500, 'A02 unlocks after A01 for 2500 coins')
	check(isRestored(parts[F.Brute1]), 'second brute keeps the shared post visible')
	root1.CFrame = CFrame.new(padA05Pos); root1.Position = padA05Pos
	check(manager:TryUnlockFacility(p1, F.AutoClerk) and p1:GetAttribute('Coins') == 2500, 'A05 unlocks independently for 9000 coins')
	check(isRestored(parts[F.AutoClerk]), 'A05 restores the clerk station')
	manager:Destroy()
end

-- 4B. 独立验证：自动化实体不占用 MaximumBodies 世界配额
do
	local manager = makeTestManager()
	local spawnedStreet = 0
	local oldSpawn = B.NPC.Spawn
	B.NPC.Spawn = function()
		spawnedStreet += 1
		return nil
	end
	local p1 = B.CreatePlayer(299, Scene.UnlockPads[F.FastChute].TriggerZone.Position)
	p1:SetAttribute('Coins', 10000)
	manager:AddPlayer(p1)
	manager:TryUnlockFacility(p1, F.FastChute)
	for _ = 1, 6 do
		local b1 = makeTestBody(manager, 'Unpainted')
		manager:PushChuteItem(b1, false)
		local b2 = makeTestBody(manager, 'Painted')
		manager:PushAutoPaintedItem(b2)
	end
	for _ = 1, Config.MaximumBodies - 1 do
		makeTestBody(manager, 'Unpainted')
	end
	B.now += 5
	manager.nextUpdate = 0
	manager.nextSpawn = 0
	manager:Update()
	check(spawnedStreet == 1, '12 automation entities do not consume MaximumBodies street spawn quota')
	B.NPC.Spawn = oldSpawn
	manager:Destroy()
end

-- 4. 整批投料、斜抛落井、3 断点 6 实体+无限队列、MaximumBodies 隔离与双线严格隔离
do
	local manager, coinsEarned = makeTestManager()
	local padA00Pos = Scene.UnlockPads[F.FastChute].TriggerZone.Position
	local p1, _, _, root1 = B.CreatePlayer(201, padA00Pos)
	local p2, _, _, root2 = B.CreatePlayer(202, Vector3.new(-47.0, 1.8, -20.2))
	p1:SetAttribute('Coins', 1000)
	manager:AddPlayer(p1)
	manager:AddPlayer(p2)

	-- 未解锁 A00 时，E 井口与斜抛均拒绝入井
	local rawPre = makeTestBody(manager, 'Unpainted')
	B.Carry.Take(rawPre, p1)
	root1.CFrame = CFrame.new(Scene.ChutePrompt.Position)
	root1.Position = Scene.ChutePrompt.Position
	check(not manager:Chute(p1), 'Chute rejects deposit before A00 unlock')

	local thrownLocked = makeTestBody(manager, 'Unpainted')
	thrownLocked.location = 'Thrown'
	thrownLocked.model.WorldPivot = CFrame.new(-58.8, 1.5, -28.5)
	thrownLocked.model.PrimaryPart.CFrame = CFrame.new(-58.8, 1.5, -28.5)
	thrownLocked.model.PrimaryPart.Position = Vector3.new(-58.8, 1.5, -28.5)
	thrownLocked.model.UpperTorso.CFrame = CFrame.new(-58.8, 1.5, -28.5)
	thrownLocked.model.UpperTorso.Position = Vector3.new(-58.8, 1.5, -28.5)
	manager:SettleThrown(thrownLocked)
	check(thrownLocked.location == 'Ground' and manager:ChuteCount() == 0, 'thrown into chute before A00 settles to Ground')
	manager.items[thrownLocked.id] = nil
	thrownLocked.model:Destroy()

	-- 解锁 A00
	root1.CFrame = CFrame.new(padA00Pos)
	root1.Position = padA00Pos
	check(manager:TryUnlockFacility(p1, F.FastChute), 'unlock A00')

	-- 身上 8 具未画符白膜 + 1 具已画符白膜 -> 靠近井口按 E 整批倒入未画符 8 具，已画符保留身上
	root1.CFrame = CFrame.new(Scene.ChutePrompt.Position)
	root1.Position = Scene.ChutePrompt.Position
	local unpaintedCount = 0
	for i = 1, 7 do
		local b = makeTestBody(manager, 'Unpainted')
		B.Carry.Take(b, p1)
		b.carryOrder = i + 10
		unpaintedCount += 1
	end
	local paintedKept = makeTestBody(manager, 'Painted')
	B.Carry.Take(paintedKept, p1)
	paintedKept.carryOrder = 99

	local verBeforeChute = manager.stationVersions.ChutePickup
	manager:OnRequest(p1, { action = 'Interact', target = 'Chute', version = manager.stationVersions.Chute })
	for _ = 1, 20 do
		if not manager.players[p1].depositQueue then break end
		B.now += 0.1
		manager:Update()
	end
	check(manager.players[p1].depositQueue == nil and manager:ChuteCount() == 8 + 1 - 1 and #manager:Carried(p1) == 1 and manager:Carried(p1)[1] == paintedKept, 'A00 batch deposits 8 unfinished bodies (7 new + rawPre) and keeps painted body')
	check(#manager.chuteVisible == 8 and manager.chuteOverflowCount == 0, 'chuteQueue renders all deposited bodies without cap or virtual overflow')
	for _, id in manager.chuteVisible do
		local item = manager.items[id]
		local primary = item.model.PrimaryPart
		local torso = item.model:FindFirstChild('UpperTorso')
		if primary and torso and torso:IsA('BasePart') then
			torso.CFrame = primary.CFrame
			torso.Position = primary.Position
		end
		local pm = item.model:GetAttribute('PhysicsMode')
		check(pm == 'Loose' or pm == 'CageSleep', 'each visible body enters physical chute storage')
	end
	check(manager:PoolCount() == 0 and manager:ShelfCount() == 0 and manager.stationVersions.ChutePickup > verBeforeChute, 'manual pool/shelf untouched by chute deposit')

	-- 井口半空不截停，落入 FastChuteLanding 才进入队列；已涂符仍落 Ground；未涂符 Ground 落入垫内自动吸纳
	local thrownOpening = makeTestBody(manager, 'Unpainted')
	thrownOpening.location = 'Thrown'
	thrownOpening.model.UpperTorso.CFrame = CFrame.new(-58.8, 20.0, -28.5)
	thrownOpening.model.UpperTorso.Position = Vector3.new(-58.8, 20.0, -28.5)
	manager:SettleThrown(thrownOpening)
	check(thrownOpening.location == 'Ground' and manager:ChuteCount() == 8, 'mid-air shaft opening does not intercept throw into chute')

	-- 模拟该 Ground 白膜继续自由下落并停在 FastChuteLanding 垫内，Update 自动吸纳进队列
	thrownOpening.model.UpperTorso.CFrame = CFrame.new(-58.8, 2.0, -28.5)
	thrownOpening.model.UpperTorso.Position = Vector3.new(-58.8, 2.0, -28.5)
	B.now += 0.2
	manager:Update()
	check(thrownOpening.location == 'Chute' and manager:ChuteCount() == 9 and #manager.chuteVisible == 9, 'unpainted Ground body resting on FastChuteLanding is absorbed into chuteVisible')

	local thrownLanding = makeTestBody(manager, 'Unpainted')
	thrownLanding.location = 'Thrown'
	thrownLanding.model.UpperTorso.CFrame = CFrame.new(-58.8, 2.0, -28.5)
	thrownLanding.model.UpperTorso.Position = Vector3.new(-58.8, 2.0, -28.5)
	manager:SettleThrown(thrownLanding)
	check(manager:ChuteCount() == 10 and #manager.chuteVisible == 10 and manager.chuteOverflowCount == 0 and thrownLanding.model:GetAttribute('PhysicsMode') == 'Loose', 'thrown onto FastChuteLanding enters live chuteVisible without overflow')

	local thrownPainted = makeTestBody(manager, 'Painted')
	thrownPainted.location = 'Thrown'
	thrownPainted.model.UpperTorso.CFrame = CFrame.new(-58.8, 2.0, -28.5)
	thrownPainted.model.UpperTorso.Position = Vector3.new(-58.8, 2.0, -28.5)
	manager:SettleThrown(thrownPainted)
	check(thrownPainted.location == 'Ground' and manager:ChuteCount() == 10, 'painted throw into chute lands on Ground')

	-- 快投区按 ID 拾取非队首白膜，队首和其他实体留在原地。
	local nextInChute = manager:PeekChuteItem()
	local picked = manager.items[manager.chuteVisible[2]]
	local nextChutePose, nextChuteVersion = nextInChute.model.WorldPivot, nextInChute.version
	root2.CFrame = CFrame.new(Scene.ChutePickup.Position)
	root2.Position = Scene.ChutePickup.Position
	manager.chuteOverflowCount = 1
	local chuteVersion = manager.stationVersions.ChutePickup
	manager:OnRequest(p2, { action = 'Interact', target = 'ChutePickup', version = chuteVersion })
	check(manager:ChuteCount() == 11 and #manager:Carried(p2) == 0, 'legacy chute anchor cannot take a body')
	root2.Position = picked.model.PrimaryPart.Position + Vector3.new(0, 0, 3)
	root2.CFrame = CFrame.new(root2.Position)
	B.now += 0.2
	B.cageOccluder = Scene.ChuteAirWalls.West
	manager:OnRequest(p2, { action = 'Interact', target = picked.id, version = picked.version })
	B.cageOccluder = nil
	check(manager:ChuteCount() == 10 and #manager.chuteVisible == 10 and manager:Carried(p2)[1] == picked, 'specific chute pickup removes the selected body')
	local replenishedChuteId = manager.chuteVisible[#manager.chuteVisible]
	local replenishedChuteItem = manager.items[replenishedChuteId]
	check(manager.chuteOverflowCount == 0 and replenishedChuteItem and replenishedChuteItem.location == 'Chute', 'chute overflow materializes after successful pickup')
	check(not table.find(manager.chuteVisible, picked.id) and manager.stationVersions.ChutePickup > chuteVersion, 'specific chute pickup updates queue and station version')
	check(nextInChute == manager:PeekChuteItem() and nextInChute.model.WorldPivot == nextChutePose and nextInChute.version == nextChuteVersion, 'specific pickup leaves the queue head in place')

	-- 清理本用例额外补出的白膜，继续原有的出界和自动画符回归。
	table.remove(manager.chuteVisible)
	manager.items[replenishedChuteId] = nil
	replenishedChuteItem.model:Destroy()
	local escapedBody = manager.items[manager.chuteVisible[#manager.chuteVisible]]
	escapedBody.model.UpperTorso.Position = Vector3.new(-100, 2, -90)
	B.now += 0.2
	manager:Update()
	check(escapedBody.location == 'Chute' and escapedBody.model:GetAttribute('CageContained') == 'Chute' and manager:ChuteCount() == 9, 'chute body knocked outside recovers back into FastChuteLanding instead of Ground')

	-- 5. A03 自动符文台 (2.0s/具) -> autoPaintedQueue (无限+6实体)
	-- 落稳门控：模拟刚落入落料池（未满停留时长且未到兜底上限）时，不得被 A03 提前抽走
	B.now = 199.9
	for _, id in manager.chuteVisible do
		local chuteItem = manager.items[id]
		if chuteItem then
			chuteItem.chuteEnteredAt = B.now
			chuteItem.chuteSettledSince = nil
		end
	end
	p1:SetAttribute('Coins', 10000)
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.AutoRune].TriggerZone.Position)
	root1.Position = Scene.UnlockPads[F.AutoRune].TriggerZone.Position
	check(manager:TryUnlockFacility(p1, F.AutoRune), 'unlock A03 does not pull unsettled chute body immediately')
	check(manager:ChuteCount() == 9 and manager.autoRuneItemId == nil, 'chute body waits to settle before entering AutoRune')

	-- 模拟落料池落稳停留时长 (AutoChuteDwellSeconds = 0.65s) 到期后拉入绘画机
	B.now = 200.65
	manager:Update()
	check(manager:ChuteCount() == 8 and manager.autoRuneItemId == nextInChute.id and manager.autoRuneEnds == 202.65, 'A03 pulls settled body after dwell and starts 2.0s period')

	-- 进床滑入阶段 (0 ~ 0.50s) 处于池与床之间，尚未瞬移到 WorkBed
	B.now = 200.9
	manager:Update()
	local midIntakePos = nextInChute.model.WorldPivot.Position
	check((midIntakePos - Scene.AutoRunePose().Position).Magnitude > 1.0, 'intake smoothly slides body toward WorkBed instead of teleporting')

	-- 进床完成后进入画符阶段，在 1.9s 后（202.55s）仍未完工，且已开始打符
	B.now = 202.55
	manager:Update()
	check(manager:AutoPaintedCount() == 0, 'A03 does not finish before 2.0s')
	local working = manager.items[manager.autoRuneItemId]
	check(working ~= nil and working.location == 'AutoRune' and working.visualState ~= nil and working.visualState.count > 0, 'A03 stamps runes onto the membrane before completion')
	local midCount = working.visualState.count
	local sawStamp = false
	for _, notice in B.broadcasts do
		if notice.kind == 'VisualDelta' and notice.id == working.id and notice.segments and #notice.segments > 0 then
			sawStamp = true
		end
	end
	check(sawStamp, 'A03 broadcasts rune stamps for clients')

	B.now = 202.65
	manager:Update()
	check(manager:AutoPaintedCount() == 1 and manager:ChuteCount() == 7, 'A03 completes 1 painted body at 2.0s and feeds next')
	local firstOut = manager.items[manager.autoPaintedVisible[1]]
	check(firstOut ~= nil and firstOut.stage == 'Painted' and firstOut.model:GetAttribute('AutoPainted') == true, 'autoPainted body has Painted stage & AutoPainted attribute')
	check(firstOut.visualState ~= nil and firstOut.visualState.count > midCount, 'A03 finishes the remaining rune stamps')
	check(firstOut.model.UpperTorso.Color ~= Config.AutoPaintedColor, 'auto rune keeps the membrane color')

	-- 并行斜坡过渡验证：刚画完第 0 帧留在 WorkBed，0.4s 时沿斜坡上行，0.85s 到达摆放台槽位
	check((firstOut.model.WorldPivot.Position - Scene.AutoRunePose().Position).Magnitude < 0.05, 'output body starts ramp climb from WorkBed instead of teleporting')
	B.now = 203.10
	manager:Update()
	local midRampPos = firstOut.model.WorldPivot.Position
	check((midRampPos - Scene.AutoRunePose().Position).Magnitude > 1.0 and (midRampPos - Scene.AutoOutputPose(1).Position).Magnitude > 0.5, 'output body smoothly climbs ramp mid-transition')
	B.now = 203.55
	manager:Update()
	check((firstOut.model.WorldPivot.Position - Scene.AutoOutputPose(1).Position).Magnitude < 0.05, 'output body settles cleanly at AutoOutputPose(1)')

	-- 再推进 8 个 2.0s 节拍消化剩余 8 具（共 9 具全部画符完毕）-> autoPaintedQueue = 9 (6 实体 + 3 虚拟溢出)
	for step = 1, 8 do
		B.now = 202.65 + step * 2.0
		manager:Update()
	end
	-- 等最后一具爬坡到达摆放台
	B.now = 202.65 + 8 * 2.0 + 1.0
	manager:Update()
	check(manager:ChuteCount() == 0 and manager.autoRuneItemId == nil and manager:AutoPaintedCount() == 9 and #manager.autoPaintedVisible == 6 and manager.autoPaintedOverflowCount == 3, 'A03 produces 9 bodies into infinite autoPaintedQueue capped at 6 visible')
	check(manager:PoolCount() == 0 and manager.tableId == nil and manager.altarId == nil and manager:ShelfCount() == 0, 'strict isolation after A03 batch')

	-- 断点手取 1 具已画符白膜（剩 8 具），并验证队列平滑补位（非瞬移）
	local secondOutBeforePick = manager.items[manager.autoPaintedVisible[2]]
	local emptyP, _, _, emptyRoot = B.CreatePlayer(203, Scene.AutoRuneOutputPrompt.Position)
	manager:AddPlayer(emptyP)
	local outVerBefore = manager.stationVersions.AutoOutput
	manager:OnRequest(emptyP, { action = 'Interact', target = 'AutoOutput', version = outVerBefore })
	check(manager:AutoPaintedCount() == 8 and #manager.autoPaintedVisible == 6 and manager.autoPaintedOverflowCount == 2 and #manager:Carried(emptyP) == 1 and manager:Carried(emptyP)[1].stage == 'Painted', 'AutoOutput pickup gives Painted body & replenishes from overflow')
	check((secondOutBeforePick.model.WorldPivot.Position - Scene.AutoOutputPose(2).Position).Magnitude < 0.1, 'queued body slides instead of snapping immediately on pickup')
	B.now += 0.15
	manager:Update()
	local midShiftX = secondOutBeforePick.model.WorldPivot.Position.X
	local pos1X, pos2X = Scene.AutoOutputPose(1).Position.X, Scene.AutoOutputPose(2).Position.X
	check(midShiftX > math.min(pos1X, pos2X) and midShiftX < math.max(pos1X, pos2X), 'queued body smoothly shifts between slot 2 and slot 1')
	B.now += 0.25
	manager:Update()
	check((secondOutBeforePick.model.WorldPivot.Position - Scene.AutoOutputPose(1).Position).Magnitude < 0.05, 'queued body finishes smooth shift to slot 1')
	local replenished = manager.items[manager.autoPaintedVisible[#manager.autoPaintedVisible]]
	check(replenished ~= nil and replenished.visualState ~= nil and replenished.visualState.count == firstOut.visualState.count and replenished.model:GetAttribute('AutoPainted') == true and replenished.model.UpperTorso.Color ~= Config.AutoPaintedColor, 'overflow respawn carries the full rune pattern')

	-- 6. A04 自动炼化台 (2.5s/瓶) -> autoShelfCount (无限+6瓶渲染) + 站内不打断长按版本测试 + 整批领取变现
	B.now = 300
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.AutoSmelter].TriggerZone.Position)
	root1.Position = Scene.UnlockPads[F.AutoSmelter].TriggerZone.Position
	check(manager:TryUnlockFacility(p1, F.AutoSmelter), 'unlock A04 immediately reserves a body for transport')
	check(manager:AutoPaintedCount() == 7, 'A04 pulled 1 leaving AutoPaintedCount==7, got ' .. tostring(manager:AutoPaintedCount()))
	check(manager.autoSmelterItemId ~= nil and manager.autoSmelterEnds == 0, 'A04 reserves a body for travel before starting the furnace timer')

	local autoOutVerDuringRun = manager.stationVersions.AutoOutput
	local firstId = manager.autoSmelterItemId
	local firstBody = manager.items[firstId]
	local passLight = Scene.AutoTransferPass.TransferPassLight
	check(firstBody.stage == 'Painted' and not passLight.Enabled, 'queued body is reserved and lamp begins off')
	B.now = 300.15
	manager:Update()
	local position = firstBody.model.WorldPivot.Position
	check(math.abs(position.X - Scene.AutoTransferPass.Position.X) < 2.2 and position.Y > 4,
		'queued body aligns on the transfer station without returning to the ramp')
	check(manager:PeekAutoPaintedItem().id ~= firstId, 'player pickup queue excludes the body reserved for transfer')
	B.now = 300.4
	manager:Update()
	check(passLight.Enabled and math.abs(passLight.Brightness - Config.AutoTransferLightBrightness) < 0.01 and firstBody.stage == 'Painted' and manager.autoSmelterEnds == 0, 'lamp indicates passage with softened brightness before furnace timer')
	check((firstBody.model.WorldPivot.Position - Scene.AutoTransferPass.Position).Magnitude < 0.01, 'body waits at lit pass point')
	B.now = 301.0
	manager:Update()
	check(not passLight.Enabled and firstBody.stage == 'Painted' and manager:AutoShelfCount() == 0, 'body travels from pass toward furnace without producing a potion')
	B.now = 301.6
	manager:Update()
	check(firstBody.stage == 'Converting' and math.abs(manager.autoSmelterEnds - 304.05) < 0.001, 'furnace timer starts at arrival')
	for step = 1, 8 do
		-- 每轮略过截止时间再采样，避免浮点误差落在同一截止点两侧。
		B.now = 300 + step * 4.07
		manager:Update()
		if step < 7 then
			check(manager.stationVersions.AutoOutput == autoOutVerDuringRun, 'A04 ticks keep AutoOutput version stable while queue remains non-empty')
		elseif step == 7 then
			check(manager:AutoPaintedCount() == 0 and manager.stationVersions.AutoOutput > autoOutVerDuringRun, 'A04 pulling last body bumps AutoOutput version on empty')
		end
	end
	local snap = manager:Snapshot()
	check(manager:AutoPaintedCount() == 0 and manager:AutoShelfCount() == 8 and snap.autoShelfCount == 8, 'A04 converts all 8 bodies into 8 auto potions')
	local rackBottleCount = 0
	for _ in snap.autoShelfItems or {} do
		rackBottleCount += 1
	end
	check(#manager.autoShelfVisible == 6 and rackBottleCount == 6, 'AutoPotionRack caps visible bottles at 6 while autoShelfCount stays 8')
	check(manager:ShelfCount() == 0 and manager:PoolCount() == 0, 'strict isolation: manual ShelfCount & PoolCount remain 0')

	-- 玩家按 E 取走全部 8 瓶自动药水并前往 Sigil 提交变现
	emptyP.Character:Destroy()
	B.CreatePlayer(204, Scene.AutoShelfPickup.Position)
	local p4 = B.playerList[#B.playerList]
	manager:AddPlayer(p4)
	manager:OnRequest(p4, { action = 'Interact', target = 'AutoShelf', version = manager.stationVersions.AutoShelf })
	check(manager:AutoShelfCount() == 0 and #manager.autoShelfVisible == 0, 'AutoShelf grants entire auto potion stack and clears rack')
	local _, heldCount = manager:OwnedPotions(p4)
	check(heldCount == 8, 'player holds 8 auto potions in single stack')

	B.now += 0.2
	p4.Character.HumanoidRootPart.CFrame = CFrame.new(Scene.SigilPosition)
	p4.Character.HumanoidRootPart.Position = Scene.SigilPosition
	manager:OnRequest(p4, { action = 'Interact', target = 'Sigil', version = manager.stationVersions.Sigil })
	check(coinsEarned[p4] == 8 * Config.PotionReward, 'Sigil sells auto-shelf potions using standard economy reward')
	local fresh = makeTestBody(manager)
	manager:PushChuteItem(fresh, false)
	-- 模拟刚投入时速度未降稳，即使经过 Dwell 时长也不得被抽走
	fresh.model.UpperTorso.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
	manager:Update()
	check(fresh.location == 'Chute' and manager.autoRuneItemId == nil, 'fresh chute body is not pulled immediately before settling')
	B.now += Config.AutoChuteDwellSeconds + 0.1
	manager:Update()
	check(fresh.location == 'Chute' and manager.autoRuneItemId == nil, 'fast-moving chute body stays in chute until speed settles')
	-- 速度降稳后再经过 Dwell 时长，正式拉入 AutoRune
	fresh.model.UpperTorso.AssemblyLinearVelocity = Vector3.zero
	manager:Update()
	check(fresh.location == 'Chute', 'just-settled body still waits for dwell duration')
	B.now += Config.AutoChuteDwellSeconds + 0.05
	manager:Update()
	check(fresh.location == 'AutoRune', 'settled body enters AutoRune after dwell')
	local paintStart = B.now
	B.now = paintStart + 1.5
	manager:Update()
	check(fresh.location == 'AutoRune' and manager.autoSmelterItemId == nil, 'incomplete body remains at the drawing bed')
	B.now = paintStart + 2.1
	manager:Update()
	check(manager.autoSmelterItemId == fresh.id and manager:AutoPaintedCount() == 0, 'painted body moves straight from bed to transfer when the furnace is free')
	check((fresh.model.WorldPivot.Position - Scene.AutoRunePose().Position).Magnitude < 0.01, 'direct transfer starts at the painting bed')
	B.now += 0.35
	manager:Update()
	check((fresh.model.WorldPivot.Position - Scene.AutoTransferRamp.Position).Magnitude < 0.1, 'direct transfer reaches ramp base before climbing')
	B.now += 0.37
	manager:Update()
	check((fresh.model.WorldPivot.Position - Scene.AutoTransferRampTop.Position).Magnitude < 0.1, 'direct transfer climbs to ramp top before the pass station')
	manager:Destroy()
end

print('PASS: M3 automation checks =', checks)
