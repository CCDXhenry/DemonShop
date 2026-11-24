-- M3 自动化解锁协议与双线加工状态机回归测试（踩踏解锁、并发互斥、无限断点+6实体、A00/A03/A04 及双线隔离）
local R = require('@lune/roblox')
local fs = require('@lune/fs')
local CFrame, Vector3, Color3, Instance = R.CFrame, R.Vector3, R.Color3, R.Instance
local B = require('./StationPotionBoundary')
local Config = require('./GameConfig')
local Rules = require('./AutomationRules')
local Scene = require('./StationScene')
local Manager = require('./StationProcessingManager')

local checks = 0
local function check(cond, msg)
	assert(cond, msg)
	checks += 1
end

-- 1. 配置表与依赖关系契约校验
check(Config.AutomationFacilities.A00.cost == 250 and Config.AutomationFacilities.A00.prerequisite == nil, 'A00 cost & no prereq')
check(Config.AutomationFacilities.A01.cost == 1000 and Config.AutomationFacilities.A01.prerequisite == 'A00', 'A01 cost & prereq A00')
check(Config.AutomationFacilities.A02.cost == 2500 and Config.AutomationFacilities.A02.prerequisite == 'A01', 'A02 cost & prereq A01')
check(Config.AutomationFacilities.A03.cost == 2000 and Config.AutomationFacilities.A03.prerequisite == 'A00', 'A03 cost & prereq A00')
check(Config.AutomationFacilities.A04.cost == 4500 and Config.AutomationFacilities.A04.prerequisite == 'A03', 'A04 cost & prereq A03')
check(Config.AutomationFacilities.A05.cost == 9000 and Config.AutomationFacilities.A05.prerequisite == nil, 'A05 cost & no prereq')
check(Config.AutoRuneSeconds == 2.0 and Config.AutoSmelterSeconds == 2.5 and Config.AutoQueueVisibleLimit == 6, 'automation cadence & limit')

-- 2. 三态规则与真实 GameModels.rbxm UnlockPad 视觉同步校验
check(Rules.ComputePadState('A00', {}, 249) == 'Insufficient', 'A00 insufficient coins -> red')
check(Rules.ComputePadState('A00', {}, 250) == 'Ready', 'A00 enough coins -> green')
check(Rules.ComputePadState('A03', {}, 9999) == 'Locked', 'A03 without A00 -> gray even with rich coins')
check(Rules.ComputePadState('A03', { A00 = true }, 1999) == 'Insufficient', 'A03 after A00 insufficient -> red')
check(Rules.ComputePadState('A03', { A00 = true }, 2000) == 'Ready', 'A03 after A00 enough -> green')
check(Rules.ComputePadState('A03', { A00 = true, A03 = true }, 0) == 'Unlocked', 'A03 unlocked state')

local roots = R.deserializeModel(fs.readFile('Assets/Models/GameModels.rbxm'))
local modelsFolder = roots[1]
local padTemplate = if modelsFolder then modelsFolder:FindFirstChild('UnlockPad') else nil
check(padTemplate ~= nil, 'GameModels.rbxm contains UnlockPad template')
if padTemplate then
	local pad = padTemplate:Clone()
	pad:SetAttribute('FacilityId', 'A03')
	pad:SetAttribute('PrerequisiteLabel', 'REQUIRES: FAST DROP CHUTE')
	Rules.ApplyPadVisual(pad, 'Locked', 'REQUIRES: FAST DROP CHUTE')
	check(pad.GlowRing.Color == pad:GetAttribute('LockedColor'), 'Locked applies LockedColor gray')
	check(pad.GuiAnchor.PadGui.CardFrame.BorderStroke.Color == pad:GetAttribute('LockedColor'), 'Locked border stroke matches gray')
	Rules.ApplyPadVisual(pad, 'Insufficient', 'REQUIRES: FAST DROP CHUTE')
	check(pad.GlowRing.Color == pad:GetAttribute('InsufficientColor'), 'Insufficient applies InsufficientColor red')
	check(pad.GuiAnchor.PadGui.CardFrame.PrereqText.Text == 'PRE-REQ: UNLOCKED', 'PrereqText updates when prereq cleared')
	pad.GuiAnchor.PadGui.CardFrame.PrereqText.Text = 'LOCALLY BOUND TEXT'
	Rules.ApplyPadVisual(pad, 'Ready', 'REQUIRES: FAST DROP CHUTE', { skipText = true })
	check(pad.GuiAnchor.PadGui.CardFrame.PrereqText.Text == 'LOCALLY BOUND TEXT', 'skipText keeps client localized label untouched')
	check(pad.GlowRing.Color == pad:GetAttribute('ReadyColor'), 'Ready applies ReadyColor green')
	Rules.ApplyPadVisual(pad, 'Unlocked', nil)
	check(pad.OuterRim.LocalTransparencyModifier == 1 and pad.TriggerZone.CanTouch == false and pad.GuiAnchor.PadGui.Enabled == false, 'Unlocked hides pad & disables touch/gui')
end
check(Rules.FormatCost(250) == '250' and Rules.FormatCost(2500) == '2,500' and Rules.FormatCost(1000000) == '1,000,000', 'FormatCost formats commas')
check(Rules.DescribeTitle('A00').textId == 'PadNameA00' and Rules.DescribeDesc('A03').textId == 'PadDescA03', 'DescribeTitle/Desc map to GameTexts ids')
local lockedReq = Rules.DescribePrereq('A03', 'Locked')
check(lockedReq.textId == 'PadPrereqRequires' and lockedReq.argTextIds and lockedReq.argTextIds[1] == 'PadNameA00', 'DescribePrereq binds nested argTextIds')
check(Rules.DescribePrereq('A00', 'Insufficient').textId == 'PadPrereqNone' and Rules.DescribePrereq('A03', 'Ready').textId == 'PadPrereqUnlocked', 'DescribePrereq handles none & cleared')
check(Rules.DescribePrice('A05').textId == 'PadPrice' and Rules.DescribePrice('A05').args[1] == '9,000', 'DescribePrice formats PadPrice description')

-- 工具函数：构造测试白膜与重置场景
local function makeTestBody(manager, stage)
	local model = B.ModelsFolder.WhiteR15:Clone()
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

local function makeTestManager()
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
	manager.initialized = true
	return manager, coinsEarned
end

-- 3. 踩踏解锁前置校验、防远距离作弊、并发防双扣与全房广播
do
	local manager = makeTestManager()
	local padA00Pos = Scene.UnlockPads.A00.TriggerZone.Position
	local padA03Pos = Scene.UnlockPads.A03.TriggerZone.Position
	local p1, _, _, root1 = B.CreatePlayer(101, Vector3.zero)
	local p2, _, _, root2 = B.CreatePlayer(102, padA00Pos)
	p1:SetAttribute('Coins', 5000)
	p2:SetAttribute('Coins', 500)
	manager:AddPlayer(p1)
	manager:AddPlayer(p2)

	-- 远距离欺诈请求必须拒绝且不扣款
	manager:OnRequest(p1, { action = 'UnlockFacility', target = 'A00' })
	check(not manager:IsFacilityUnlocked('A00') and p1:GetAttribute('Coins') == 5000, 'faraway UnlockFacility spoof rejected')

	-- 未解锁 A00 前踩 A03 即使金币充足也不得解锁
	root1.CFrame = CFrame.new(padA03Pos)
	root1.Position = padA03Pos
	check(not manager:TryUnlockFacility(p1, 'A03') and p1:GetAttribute('Coins') == 5000, 'A03 blocked until A00 unlocked')

	-- 互斥锁拦截同帧重入并发
	root1.CFrame = CFrame.new(padA00Pos)
	root1.Position = padA00Pos
	manager.unlockLocks.A00 = true
	check(not manager:TryUnlockFacility(p1, 'A00') and p1:GetAttribute('Coins') == 5000, 'facility mutex blocks re-entrant unlock')
	manager.unlockLocks.A00 = nil

	-- 双人同站在 A00 上连续触发解锁，仅扣款 1 次 250
	table.clear(B.broadcasts)
	local ok1 = manager:TryUnlockFacility(p1, 'A00')
	local ok2 = manager:TryUnlockFacility(p2, 'A00')
	check(ok1 and not ok2, 'only first player unlocks shared A00')
	check(p1:GetAttribute('Coins') == 4750 and p2:GetAttribute('Coins') == 500, 'second player never double-charged')

	-- A00 空洞开启与 Pad 隐藏 + 全房通知横幅
	local cover = Scene.FastChuteCover
	check(cover ~= nil and cover:GetAttribute('Unlocked') == true, 'FastChuteCover marked unlocked')
	for _, part in cover:GetDescendants() do
		if part:IsA('BasePart') then
			check(not part.CanCollide and not part.CanQuery and part.Transparency == 1, 'FastChuteCover collision & visibility cleared')
		end
	end
	local padA00 = Scene.UnlockPads.A00
	check(padA00.TriggerZone.CanTouch == false and padA00.GuiAnchor.PadGui.Enabled == false, 'unlocked pad hidden and touch disabled')

	local foundBanner, foundSnapshot = false, false
	for _, notice in B.broadcasts do
		if notice.kind == 'Message' and notice.textId == 'FacilityUnlocked' then
			foundBanner = notice.textArgs and notice.textArgs[1] == p1.Name and notice.textArgs[2] == 'FAST DROP CHUTE'
		elseif notice.kind == 'State' or notice.kind == 'Delta' then
			if notice.snapshot and notice.snapshot.unlockedFacilities and notice.snapshot.unlockedFacilities.A00 then
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
	check(manager:IsFacilityUnlocked('A03') and p1:GetAttribute('Coins') == 2750, 'Update step-on polling unlocks A03 automatically')

	-- 验证 A01 -> A02 与独立分支 A05 前置规则
	p1:SetAttribute('Coins', 15000)
	local padA01Pos = Scene.UnlockPads.A01.TriggerZone.Position
	local padA02Pos = Scene.UnlockPads.A02.TriggerZone.Position
	local padA05Pos = Scene.UnlockPads.A05.TriggerZone.Position
	root1.CFrame = CFrame.new(padA02Pos); root1.Position = padA02Pos
	check(not manager:TryUnlockFacility(p1, 'A02'), 'A02 blocked until A01 unlocked')
	root1.CFrame = CFrame.new(padA01Pos); root1.Position = padA01Pos
	check(manager:TryUnlockFacility(p1, 'A01') and p1:GetAttribute('Coins') == 14000, 'A01 unlocks after A00 for 1000 coins')
	root1.CFrame = CFrame.new(padA02Pos); root1.Position = padA02Pos
	check(manager:TryUnlockFacility(p1, 'A02') and p1:GetAttribute('Coins') == 11500, 'A02 unlocks after A01 for 2500 coins')
	root1.CFrame = CFrame.new(padA05Pos); root1.Position = padA05Pos
	check(manager:TryUnlockFacility(p1, 'A05') and p1:GetAttribute('Coins') == 2500, 'A05 unlocks independently for 9000 coins')
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
	local p1 = B.CreatePlayer(299, Scene.UnlockPads.A00.TriggerZone.Position)
	p1:SetAttribute('Coins', 10000)
	manager:AddPlayer(p1)
	manager:TryUnlockFacility(p1, 'A00')
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
	local padA00Pos = Scene.UnlockPads.A00.TriggerZone.Position
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
	thrownLocked.model.WorldPivot = CFrame.new(-47.0, 1.5, -26.0)
	thrownLocked.model.PrimaryPart.CFrame = CFrame.new(-47.0, 1.5, -26.0)
	thrownLocked.model.PrimaryPart.Position = Vector3.new(-47.0, 1.5, -26.0)
	thrownLocked.model.UpperTorso.CFrame = CFrame.new(-47.0, 1.5, -26.0)
	thrownLocked.model.UpperTorso.Position = Vector3.new(-47.0, 1.5, -26.0)
	manager:SettleThrown(thrownLocked)
	check(thrownLocked.location == 'Ground' and manager:ChuteCount() == 0, 'thrown into chute before A00 settles to Ground')

	-- 解锁 A00
	root1.CFrame = CFrame.new(padA00Pos)
	root1.Position = padA00Pos
	check(manager:TryUnlockFacility(p1, 'A00'), 'unlock A00')

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
	check(manager:ChuteCount() == 8 + 1 - 1 and #manager:Carried(p1) == 1 and manager:Carried(p1)[1] == paintedKept, 'A00 batch deposits 8 unfinished bodies (7 new + rawPre) and keeps painted body')
	check(#manager.chuteVisible == 6 and manager.chuteOverflowCount == 2, 'chuteQueue caps rendered world bodies at 6 and stores overflow')
	check(manager:PoolCount() == 0 and manager:ShelfCount() == 0 and manager.stationVersions.ChutePickup > verBeforeChute, 'manual pool/shelf untouched by chute deposit')

	-- 斜抛落入井筒与落地缓冲垫均转入 chuteQueue；已画符斜抛落地
	local thrownOpening = makeTestBody(manager, 'Unpainted')
	thrownOpening.location = 'Thrown'
	thrownOpening.model.UpperTorso.CFrame = CFrame.new(-47.0, 15.0, -26.0)
	thrownOpening.model.UpperTorso.Position = Vector3.new(-47.0, 15.0, -26.0)
	manager:SettleThrown(thrownOpening)
	check(manager:ChuteCount() == 9 and #manager.chuteVisible == 6 and manager.chuteOverflowCount == 3, 'thrown into shaft opening enters chuteQueue overflow cleanly')

	local thrownLanding = makeTestBody(manager, 'Unpainted')
	thrownLanding.location = 'Thrown'
	thrownLanding.model.UpperTorso.CFrame = CFrame.new(-47.0, 2.0, -26.0)
	thrownLanding.model.UpperTorso.Position = Vector3.new(-47.0, 2.0, -26.0)
	manager:SettleThrown(thrownLanding)
	check(manager:ChuteCount() == 10 and #manager.chuteVisible == 6 and manager.chuteOverflowCount == 4, 'thrown onto FastChuteLanding enters chuteQueue')

	local thrownPainted = makeTestBody(manager, 'Painted')
	thrownPainted.location = 'Thrown'
	thrownPainted.model.UpperTorso.CFrame = CFrame.new(-47.0, 2.0, -26.0)
	thrownPainted.model.UpperTorso.Position = Vector3.new(-47.0, 2.0, -26.0)
	manager:SettleThrown(thrownPainted)
	check(thrownPainted.location == 'Ground' and manager:ChuteCount() == 10, 'painted throw into chute lands on Ground')

	-- 地下 ChutePickup 断点手取 1 具：计数减 1，溢出处补位维持 6 实体
	root2.CFrame = CFrame.new(Scene.ChutePickup.Position)
	root2.Position = Scene.ChutePickup.Position
	manager:OnRequest(p2, { action = 'Interact', target = 'ChutePickup', version = manager.stationVersions.ChutePickup })
	check(manager:ChuteCount() == 9 and #manager.chuteVisible == 6 and manager.chuteOverflowCount == 3 and #manager:Carried(p2) == 1, 'ChutePickup takes 1 and replenishes 6th visible body from overflow')

	-- 5. A03 自动符文台 (2.0s/具) -> autoPaintedQueue (无限+6实体)
	B.now = 200
	p1:SetAttribute('Coins', 10000)
	root1.CFrame = CFrame.new(Scene.UnlockPads.A03.TriggerZone.Position)
	root1.Position = Scene.UnlockPads.A03.TriggerZone.Position
	check(manager:TryUnlockFacility(p1, 'A03'), 'unlock A03 pulls first chute body immediately')
	check(manager:ChuteCount() == 8 and manager.autoRuneItemId ~= nil and manager.autoRuneEnds == 202.0, 'A03 starts processing with 2.0s period')

	B.now = 201.9
	manager:Update()
	check(manager:AutoPaintedCount() == 0, 'A03 does not finish before 2.0s')

	B.now = 202.0
	manager:Update()
	check(manager:AutoPaintedCount() == 1 and manager:ChuteCount() == 7, 'A03 completes 1 painted body at 2.0s and feeds next')
	local firstOut = manager.items[manager.autoPaintedVisible[1]]
	check(firstOut ~= nil and firstOut.stage == 'Painted' and firstOut.model:GetAttribute('AutoPainted') == true, 'autoPainted body has Painted stage & AutoPainted attribute')

	-- 再推进 8 个 2.0s 节拍消化剩余 8 具（共 9 具全部画符完毕）-> autoPaintedQueue = 9 (6 实体 + 3 虚拟溢出)
	for step = 1, 8 do
		B.now = 202.0 + step * 2.0
		manager:Update()
	end
	check(manager:ChuteCount() == 0 and manager.autoRuneItemId == nil and manager:AutoPaintedCount() == 9 and #manager.autoPaintedVisible == 6 and manager.autoPaintedOverflowCount == 3, 'A03 produces 9 bodies into infinite autoPaintedQueue capped at 6 visible')
	check(manager:PoolCount() == 0 and manager.tableId == nil and manager.altarId == nil and manager:ShelfCount() == 0, 'strict isolation after A03 batch')

	-- 断点手取 1 具已画符白膜（剩 8 具）
	local emptyP, _, _, emptyRoot = B.CreatePlayer(203, Scene.AutoRuneOutputPrompt.Position)
	manager:AddPlayer(emptyP)
	local outVerBefore = manager.stationVersions.AutoOutput
	manager:OnRequest(emptyP, { action = 'Interact', target = 'AutoOutput', version = outVerBefore })
	check(manager:AutoPaintedCount() == 8 and #manager.autoPaintedVisible == 6 and manager.autoPaintedOverflowCount == 2 and #manager:Carried(emptyP) == 1 and manager:Carried(emptyP)[1].stage == 'Painted', 'AutoOutput pickup gives Painted body & replenishes from overflow')

	-- 6. A04 自动炼化台 (2.5s/瓶) -> autoShelfCount (无限+6瓶渲染) + 站内不打断长按版本测试 + 整批领取变现
	B.now = 300
	root1.CFrame = CFrame.new(Scene.UnlockPads.A04.TriggerZone.Position)
	root1.Position = Scene.UnlockPads.A04.TriggerZone.Position
	check(manager:TryUnlockFacility(p1, 'A04'), 'unlock A04 starts smelting immediately')
	check(manager:AutoPaintedCount() == 7, 'A04 pulled 1 leaving AutoPaintedCount==7, got ' .. tostring(manager:AutoPaintedCount()))
	check(manager.autoSmelterItemId ~= nil and manager.autoSmelterEnds == 302.5, 'A04 starts smelting with 2.5s period, got ' .. tostring(manager.autoSmelterEnds))

	local autoOutVerDuringRun = manager.stationVersions.AutoOutput
	for step = 1, 8 do
		B.now = 300 + step * 2.5
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
	manager:Destroy()
end

print('PASS: M3 automation checks =', checks)
