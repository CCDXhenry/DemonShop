-- M4 AI 代理闭环回归测试：A01/A02 打手互锁防抢怪与节拍、A05 自动售货员结算、MaximumBodies 解耦及双线严格隔离
local R = require('@lune/roblox')
local CFrame, Vector3 = R.CFrame, R.Vector3
local B = require('./StationPotionBoundary')
local Config = require('./GameConfig')
local NumberExtension = require('./NumberExtension')
local GameData = require('./GameData')
local F = GameData.FacilityId
local baselineAgentSpeed = 20
local bruteWindowScale = math.max(1, baselineAgentSpeed / Config.BruteWalkSpeed)
local clerkWindowScale = math.max(1, baselineAgentSpeed / Config.AutoClerkWalkSpeed)
local Scene = require('./StationScene')
local Manager = require('./StationProcessingManager')
local Replication = require('./StationReplication')
local InteractionRules = require('./WorldInteractionRules')

local checks = 0
local function check(cond, msg)
	assert(cond, msg)
	checks += 1
end

local function makeStreetBody(manager, pos, hits)
	local model = B.ModelsFolder.Characters["WhiteR15-People"]:Clone()
	local id = B.HttpService.GenerateGUID(false)
	model.Name = 'WhiteNPC'
	model:SetAttribute('ItemId', id)
	model.Parent = manager.runtime
	model.WorldPivot = CFrame.new(pos)
	if model.PrimaryPart then
		model.PrimaryPart.CFrame = CFrame.new(pos)
		model.PrimaryPart.Position = pos
	end
	local item = {
		id = id,
		kind = 'Body',
		stage = 'Unpainted',
		location = 'Street',
		version = 1,
		model = model,
		holder = nil,
		hits = hits or 0,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = 10,
		progress = 0,
		paintSeconds = 0,
		streetSlot = true,
		nextWalk = 0,
	}
	manager.items[id] = item
	return item
end

local function makeManualBody(manager, stage, location)
	local model = B.ModelsFolder.Characters["WhiteR15-People"]:Clone()
	local id = B.HttpService.GenerateGUID(false)
	model:SetAttribute('ItemId', id)
	model.Parent = manager.runtime
	local item = {
		id = id,
		kind = 'Body',
		stage = stage or 'Unpainted',
		location = location or 'Pool',
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

local function makeTestManager(isActiveFn)
	B.ResetPlayers()
	table.clear(B.broadcasts)
	table.clear(B.notices)
	local coinsEarned = {}
	local manager = Manager.new({
		IsActive = isActiveFn or function() return true end,
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
	manager.replication = Replication.new()
	manager.initialized = true
	return manager, coinsEarned
end

local function stepSeconds(manager, seconds, stepDt)
	local dt = stepDt or 0.1
	local steps = math.floor(seconds / dt + 0.5)
	for _ = 1, steps do
		B.now += dt
		manager:Update()
	end
end

-- 1. 配置参数与 M2 场景锚点契约
check(Config.BruteWalkSpeed > 0 and Config.BruteHitInterval > 0 and Config.BruteHitRange > 0, 'Brute AI config parameters present')
check(Config.AutoClerkWalkSpeed > 0 and Config.AutoClerkPickupRange > 0 and Config.AutoClerkSubmitRange > 0, 'AutoClerk AI config parameters present')
check(Scene.Brute1Spawn ~= nil and Scene.Brute2Spawn ~= nil, 'Scene exposes BrutePost spawn anchors')
check(Scene.ClerkSpawn ~= nil and Scene.AutoShelfPickup ~= nil and Scene.ChuteTopDrop ~= nil, 'Scene exposes AutoClerkStation, AutoShelfPickup and ChuteTopDrop anchors')

-- 2. A01 地狱打手 1 号生成、模型碰撞隔离、击晕搬运、防玩家抢夺与合法穿过 NewShop_Noodles 投料入 chuteQueue
do
	B.now = 100
	local manager = makeTestManager()
	local p1, _, _, root1 = B.CreatePlayer(101, Scene.UnlockPads[F.FastChute].TriggerZone.Position)
	p1:SetAttribute('Coins', 10000)
	manager:AddPlayer(p1)

	check(manager:TryUnlockFacility(p1, F.FastChute), 'unlock A00')
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute1].TriggerZone.Position)
	root1.Position = Scene.UnlockPads[F.Brute1].TriggerZone.Position
	check(manager:TryUnlockFacility(p1, F.Brute1), 'unlock A01')

	check(manager.agents ~= nil and manager.agents.brutes.Brute1 ~= nil, 'Brute1 spawns upon unlocking A01')
	local brute1 = manager.agents.brutes.Brute1
	check(brute1.model.Parent == manager.agents.folder and manager.agents.folder.Parent == manager.runtime, 'Brute1 model resides inside AutomationAgents folder')
	check((brute1.floorPos - Scene.Brute1Spawn.Position).Magnitude < 1.0, 'Brute1 spawns at Brute1SpawnAnchor')
	for _, desc in brute1.model:GetDescendants() do
		if desc:IsA('BasePart') then
			check(desc.CanCollide == false and desc.CanTouch == false and desc.CanQuery == false, 'Brute1 part disables CanCollide/CanTouch/CanQuery: ' .. desc.Name)
			if desc == brute1.root then
				check(desc.Anchored == true, 'Brute1 root is anchored')
			else
				check(desc.Anchored == false and desc.Massless == true, 'Brute1 limb/accessory unanchored & massless: ' .. desc.Name)
			end
		end
	end

	-- 放置街区目标，验证击晕、搬运锁定防抢、合法路径进店门与投料入 chuteQueue
	local npc1 = makeStreetBody(manager, Vector3.new(-35, 23.0, -60), 0)
	local observedCarried = false
	local observedDoorway = false
	local observedChuteStand = false
	local rejectedPlayerSteal = false
	local liftStart: Vector3? = nil
	local liftFeet: Vector3? = nil
	local observedIntermediateLift = false
	local observedShoulderHandoff = false
	local observedBend = false

	for _ = 1, 140 do
		B.now += 0.1
		manager:Update()
		if npc1.location == 'BruteCarried' and not observedCarried then
			observedCarried = true
			check(brute1.state == 'LiftBody', 'Brute claims the body before walking to the chute')
			check((npc1.model.WorldPivot.Position - Vector3.new(-35, 23, -60)).Magnitude < 0.01, 'lift begins at the current world pose without a snap')
			liftStart = npc1.model.WorldPivot.Position
			liftFeet = brute1.floorPos
			check(npc1.hits >= Config.StunHits and npc1.model:GetAttribute('BruteCarrier') == 'Brute1', 'Brute1 marks carried body with BruteCarrier')
			-- 确认客户端提示规则和服务端交互请求均拒绝玩家抢夺打手搬运中的白膜
			local snap = manager:Snapshot()
			local snapItems = {}
			for _, iv in snap.items do
				snapItems[iv.id] = iv
			end
			check(InteractionRules.Resolve(npc1.id, snap, snapItems, nil, { stored = 0, equipped = false }, {}) == nil, 'WorldInteractionRules hides pickup prompt while Brute carries body')
			root1.CFrame = CFrame.new(npc1.model.PrimaryPart.Position)
			root1.Position = npc1.model.PrimaryPart.Position
			table.clear(B.notices)
			manager:OnRequest(p1, { action = 'Interact', target = npc1.id, version = npc1.version })
			rejectedPlayerSteal = #B.notices == 1 and B.notices[1].notice.textId == 'ItemUnavailable'
		end
		if brute1.state == 'LiftBody' and liftStart and liftFeet then
			check(brute1.floorPos == liftFeet, 'Brute stays planted until the body reaches its shoulder')
			if brute1.model.WorldPivot.Position.Y < liftFeet.Y + Config.AgentRootHeight - 0.05 then observedBend = true end
			local liftHeight = npc1.model.WorldPivot.Position.Y - liftStart.Y
			if liftHeight > 0.05 then observedIntermediateLift = true end
		end
		if brute1.state == 'CarryToChute' then
			if not observedShoulderHandoff then
				check(brute1.floorPos == liftFeet and npc1.model.WorldPivot.Position.Y > (liftStart :: Vector3).Y, 'first carry frame has already completed the lift')
				observedShoulderHandoff = true
			end
			local p = brute1.floorPos
			if math.abs(p.Z - (-39.0)) < 1 and p.X >= -62.5 and p.X <= -55.5 then
				observedDoorway = true
			end
			if (p - Vector3.new(-58.8, 21.397, -37.25)).Magnitude < 0.75 then
				observedChuteStand = true
			end
		end
		if manager:ChuteCount() == 1 then
			break
		end
	end

	check(observedCarried and rejectedPlayerSteal, 'Brute1 stuns, carries and blocks player steal attempt')
	check(observedBend and observedIntermediateLift and observedShoulderHandoff, 'Brute1 bends, lifts the body across simulation steps and then carries it')
	check(observedDoorway and observedChuteStand, 'Brute1 carries body legally through NewShop_Noodles doorway to the new standing strip')
	check(manager:ChuteCount() == 1 and manager:PoolCount() == 0 and manager:ShelfCount() == 0, 'Brute1 deposits directly into chuteQueue with zero manual pool/shelf touch')
	check(manager.agents.targetLocks[npc1.id] == nil, 'Brute1 releases target lock after deposit')

	local hitBroadcasts = 0
	for _, n in B.broadcasts do
		if n.kind == 'Hit' and n.id == npc1.id then
			hitBroadcasts += 1
		end
	end
	check(hitBroadcasts == Config.StunHits, 'Brute1 emits 3 authoritative Hit broadcasts during stun')
	manager:Destroy()
end

-- 3. A01 + A02 目标互锁防抢怪 & 玩家先手拾取让渡测试
do
	B.now = 200
	local manager = makeTestManager()
	local p1, _, _, root1 = B.CreatePlayer(102, Scene.UnlockPads[F.FastChute].TriggerZone.Position)
	p1:SetAttribute('Coins', 20000)
	manager:AddPlayer(p1)
	manager:TryUnlockFacility(p1, F.FastChute)
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute1].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.Brute1].TriggerZone.Position
	manager:TryUnlockFacility(p1, F.Brute1)
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute2].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.Brute2].TriggerZone.Position
	manager:TryUnlockFacility(p1, F.Brute2)

	check(manager.agents.brutes.Brute1 ~= nil and manager.agents.brutes.Brute2 ~= nil, 'Both Brute1 and Brute2 spawned')
	check((manager.agents.brutes.Brute2.floorPos - Scene.Brute2Spawn.Position).Magnitude < 1.0, 'Brute2 spawns at Brute2SpawnAnchor')

	-- 3a. 唯一 1 名街区市民：只能由 1 名打手锁定追击，另一名待命，禁止双打手抢怪
	local solo = makeStreetBody(manager, Vector3.new(-20, 23.0, -62), 0)
	stepSeconds(manager, 0.2, 0.1)
	local b1, b2 = manager.agents.brutes.Brute1, manager.agents.brutes.Brute2
	local claimedCount = (if b1.targetId == solo.id then 1 else 0) + (if b2.targetId == solo.id then 1 else 0)
	check(claimedCount == 1, 'only one Brute claims solo street NPC while the other stays idle/unclaimed')
	local idleBrute = if b1.targetId == solo.id then b2 else b1
	check(idleBrute.targetId == nil and idleBrute.state == 'IdleAtPost', 'second Brute stays at post without contesting locked solo target')

	-- 3b. 玩家抢先击晕并扛起正在被追击的目标 -> 打手立刻释放互锁、绝不从玩家肩上抢人
	local activeBrute = if b1.targetId == solo.id then b1 else b2
	solo.hits = Config.StunHits
	B.Carry.Take(solo, p1)
	stepSeconds(manager, 0.2, 0.1)
	check(solo.holder == p1 and solo.location == 'Carried', 'player retains carried body')
	check(activeBrute.targetId == nil and manager.agents.targetLocks[solo.id] == nil, 'Brute immediately releases lock when player picks up target')

	-- 3c. 两名街区市民同时存在：两名打手互锁分配不同目标，并行协同送入快速通道
	local tA = makeStreetBody(manager, Vector3.new(-30, 23.0, -60), 0)
	local tB = makeStreetBody(manager, Vector3.new(-10, 23.0, -62), 0)
	stepSeconds(manager, 0.2, 0.1)
	check(b1.targetId ~= nil and b2.targetId ~= nil and b1.targetId ~= b2.targetId, 'Brute1 and Brute2 lock distinct targets via interlock table')
	check(manager.agents.targetLocks[tA.id] ~= nil and manager.agents.targetLocks[tB.id] ~= nil, 'targetLocks tracks both distinct claims')

	stepSeconds(manager, 16.0 * bruteWindowScale, 0.1)
	check(manager:ChuteCount() == 2 and manager:PoolCount() == 0, 'both Brutes deposit their distinct targets into chuteQueue cleanly')
	manager:Destroy()
end

-- 4. 效率节拍对比：单打手 (~12s/人) vs 双打手并行协同 (~6s/人)
do
	local function simulateThroughput(enableSecondBrute)
		B.now = 300
		local manager = makeTestManager()
		local p1, _, _, root1 = B.CreatePlayer(103, Scene.UnlockPads[F.FastChute].TriggerZone.Position)
		p1:SetAttribute('Coins', 20000)
		manager:AddPlayer(p1)
		manager:TryUnlockFacility(p1, F.FastChute)
		root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute1].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.Brute1].TriggerZone.Position
		manager:TryUnlockFacility(p1, F.Brute1)
		if enableSecondBrute then
			root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute2].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.Brute2].TriggerZone.Position
			manager:TryUnlockFacility(p1, F.Brute2)
		end

		local spawnOffsets = {
			Vector3.new(10, 23.0, -63),
			Vector3.new(10, 23.0, -63),
			Vector3.new(5, 23.0, -63),
			Vector3.new(15, 23.0, -63),
			Vector3.new(0, 23.0, -63),
			Vector3.new(20, 23.0, -63),
		}
		local spawnCursor = 0
		local prevSpawn = B.NPC.Spawn
		B.NPC.Spawn = function()
			spawnCursor = (spawnCursor % #spawnOffsets) + 1
			return makeStreetBody(manager, spawnOffsets[spawnCursor], 0)
		end

		for i = 1, Config.StreetPopulation do
			makeStreetBody(manager, spawnOffsets[(i - 1) % #spawnOffsets + 1], 0)
		end

		local duration = 48.0
		stepSeconds(manager, duration, 0.1)
		local produced = manager:ChuteCount()
		B.NPC.Spawn = prevSpawn
		manager:Destroy()
		return produced, duration / math.max(1, produced)
	end

	-- 固定旧节拍基准，仅在本段比较单双打手吞吐量。
	local walkSpeed = Config.BruteWalkSpeed
	Config.BruteWalkSpeed = baselineAgentSpeed
	local singleCount, singleSecPerBody = simulateThroughput(false)
	local dualCount, dualSecPerBody = simulateThroughput(true)
	Config.BruteWalkSpeed = walkSpeed
	check(singleCount >= 3 and singleSecPerBody >= 9.0 and singleSecPerBody <= 15.0,
		'single Brute cadence matches ~12s/person (got ' .. string.format('%.2fs/body, count=%d', singleSecPerBody, singleCount) .. ')')
	check(dualCount >= 6 and dualSecPerBody >= 4.0 and dualSecPerBody <= 8.0 and dualCount >= singleCount * 1.7,
		'dual Brutes parallel synergy matches ~6s/person (got ' .. string.format('%.2fs/body, count=%d', dualSecPerBody, dualCount) .. ')')
end

-- 5. MaximumBodies 配额隔离 + Destroy / scope:Destroy() 彻底清理模型与连接
do
	B.now = 400
	local manager = makeTestManager()
	local p1, _, _, root1 = B.CreatePlayer(104, Scene.UnlockPads[F.FastChute].TriggerZone.Position)
	p1:SetAttribute('Coins', 30000)
	manager:AddPlayer(p1)
	manager:TryUnlockFacility(p1, F.FastChute)
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute1].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.Brute1].TriggerZone.Position
	manager:TryUnlockFacility(p1, F.Brute1)
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute2].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.Brute2].TriggerZone.Position
	manager:TryUnlockFacility(p1, F.Brute2)
	root1.CFrame = CFrame.new(Scene.UnlockPads[F.AutoClerk].TriggerZone.Position); root1.Position = Scene.UnlockPads[F.AutoClerk].TriggerZone.Position
	manager:TryUnlockFacility(p1, F.AutoClerk)

	local agentsState = manager.agents
	local b1Model = agentsState.brutes.Brute1.model
	local b2Model = agentsState.brutes.Brute2.model
	local clerkModel = agentsState.clerk.model

	-- 创建 2 具 BruteCarried 态白膜 + (MaximumBodies - 1) 具普通白膜 -> 仍应允许街区刷怪
	for _ = 1, 2 do
		makeManualBody(manager, 'Unpainted', 'BruteCarried')
	end
	for _ = 1, Config.MaximumBodies - 1 do
		makeManualBody(manager, 'Unpainted', 'Ground')
	end
	local spawned = 0
	local prevSpawn = B.NPC.Spawn
	B.NPC.Spawn = function()
		spawned += 1
		return nil
	end
	B.now += 5
	manager.nextUpdate = 0
	manager.nextSpawn = 0
	manager:Update()
	B.NPC.Spawn = prevSpawn
	check(spawned == 1, 'AI models and BruteCarried bodies do not consume Config.MaximumBodies street spawn quota')

	manager:Destroy()
	check(agentsState.destroyed == true and b1Model.Parent == nil and b2Model.Parent == nil and clerkModel.Parent == nil,
		'ProcessingManager.Destroy destroys all AI models and marks state destroyed')
	check(next(agentsState.targetLocks) == nil and next(agentsState.brutes) == nil and agentsState.clerk == nil,
		'ProcessingManager.Destroy clears all AI references and targetLocks')

	-- 单独验证直接销毁 manager.scope 时也能彻底销毁 AI 模型
	B.now = 450
	local mScope = makeTestManager()
	local ps, _, _, roots = B.CreatePlayer(105, Scene.UnlockPads[F.AutoClerk].TriggerZone.Position)
	ps:SetAttribute('Coins', 20000)
	mScope:AddPlayer(ps)
	mScope:TryUnlockFacility(ps, F.AutoClerk)
	local clerkRef = mScope.agents.clerk.model
	check(clerkRef.Parent ~= nil, 'AutoClerk spawned before scope destroy')
	mScope.scope:Destroy()
	check(clerkRef.Parent == nil, 'scope:Destroy() destroys owned AI models cleanly')
end

-- 6. A05 自动售货员自动全额结算、活跃玩家过滤 & 严格双线隔离（全链路联动）
do
	B.now = 500
	local inactivePlayer = nil
	local manager, coinsEarned = makeTestManager(function(p)
		return p ~= inactivePlayer
	end)
	local pActive1, _, _, rootA1 = B.CreatePlayer(201, Scene.UnlockPads[F.AutoClerk].TriggerZone.Position)
	local pActive2 = B.CreatePlayer(202, Vector3.zero)
	local pLeft = B.CreatePlayer(203, Vector3.zero)
	inactivePlayer = pLeft
	pActive1:SetAttribute('Coins', 25000)
	manager:AddPlayer(pActive1)
	manager:AddPlayer(pActive2)
	manager.players[pActive2].levels.sellBonus = 5
	manager:AddPlayer(pLeft)

	check(manager:TryUnlockFacility(pActive1, F.AutoClerk), 'unlock A05 independently')
	local clerk = manager.agents.clerk
	check(clerk ~= nil and (clerk.floorPos - Scene.ClerkSpawn.Position).Magnitude < 1.0, 'AutoClerk spawns at ClerkSpawnAnchor')
	for _, desc in clerk.model:GetDescendants() do
		if desc:IsA('BasePart') then
			check(desc.CanCollide == false and desc.CanTouch == false and desc.CanQuery == false, 'AutoClerk parts disable collision/query: ' .. desc.Name)
		end
	end

	-- 手动线放 2 具存放池白膜 + 5 瓶手动药水架库存，自动药水架为空 -> AutoClerk 绝不触碰手动线
	makeManualBody(manager, 'Unpainted', 'Pool')
	table.insert(manager.pool, 'manual-p1')
	manager.poolOverflowCount = 1
	manager.shelfCounts[Config.DefaultPotionQuality] = 5
	manager.shelfVisible[Config.DefaultPotionQuality] = { 'm1', 'm2', 'm3', 'm4', 'm5' }

	stepSeconds(manager, 10.0, 0.1)
	check(clerk.state == 'IdleAtStation' and clerk.carryingPotions == 0, 'AutoClerk stays idle when autoShelfCount == 0 despite manual shelf having 5 potions')
	check(manager:ShelfCount() == 5 and manager:PoolCount() == 2, 'manual shelf and pool remain untouched')
	check((coinsEarned[pActive1] or 0) == 0 and (coinsEarned[pActive2] or 0) == 0, 'no coins awarded from manual shelf')

	-- 往自动药水架放入 4 瓶自动药水 -> AutoClerk 前往取走全部 4 瓶并在 Sigil 结算给全服活跃玩家，随后返回待命
	manager.autoShelfCount = 4
	manager:SyncAutoShelfVisible()
	local autoShelfVerBefore = manager.stationVersions.AutoShelf
	table.clear(B.notices)

	local sawZeroRack = false
	local sawReturnedIdle = false
	for _ = 1, math.ceil(150 * clerkWindowScale) do
		B.now += 0.1
		manager:Update()
		if manager:AutoShelfCount() == 0 and #manager.autoShelfVisible == 0 and clerk.state == 'GoToSigil' then
			sawZeroRack = true
		end
		if sawZeroRack and clerk.state == 'IdleAtStation' and (clerk.floorPos - Scene.ClerkSpawn.Position).Magnitude < 1.0 then
			sawReturnedIdle = true
			break
		end
	end

	check(sawZeroRack, 'AutoClerk clears autoShelfCount and autoShelfVisible at AutoShelfPickupAnchor')
	check(manager.stationVersions.AutoShelf > autoShelfVerBefore, 'AutoClerk pickup increments AutoShelf station version and broadcasts Changed')
	check(sawReturnedIdle, 'AutoClerk returns to AutoClerkStation IdleAtStation after delivery')
	check(coinsEarned[pActive1] == 4 * Config.PotionReward and coinsEarned[pActive2] == 8 * Config.PotionReward,
		'AutoClerk applies each recipient multiplier via AddCoins')
	check((coinsEarned[pLeft] or 0) == 0, 'AutoClerk skips inactive player')
	check(manager:ShelfCount() == 5 and manager:PoolCount() == 2, 'strict isolation: manual ShelfCount(5) and PoolCount(2) remain untouched')

	local awardedCount1, awardedCount2 = 0, 0
	for _, entry in B.notices do
		if entry.notice.kind == 'Message' and entry.notice.textId == 'CoinsAwarded' and entry.notice.textArgs then
			if entry.player == pActive1 and entry.notice.textArgs[1] == NumberExtension.FormatBigNumberAA(4 * Config.PotionReward) then
				awardedCount1 += 1
			elseif entry.player == pActive2 and entry.notice.textArgs[1] == NumberExtension.FormatBigNumberAA(8 * Config.PotionReward) then
				awardedCount2 += 1
			end
		end
	end
	check(awardedCount1 == 1 and awardedCount2 == 1, 'AutoClerk sends CoinsAwarded notification to every active player')

	-- 6b. A00~A05 全套全自动流水线端到端闭环验证（打手抓人 -> 井口 -> 自动画符 -> 自动炼化 -> 自动售货员发钱，手动线全程零损耗）
	rootA1.CFrame = CFrame.new(Scene.UnlockPads[F.FastChute].TriggerZone.Position); rootA1.Position = Scene.UnlockPads[F.FastChute].TriggerZone.Position
	check(manager:TryUnlockFacility(pActive1, F.FastChute), 'unlock A00 for full pipeline')
	rootA1.CFrame = CFrame.new(Scene.UnlockPads[F.Brute1].TriggerZone.Position); rootA1.Position = Scene.UnlockPads[F.Brute1].TriggerZone.Position
	check(manager:TryUnlockFacility(pActive1, F.Brute1), 'unlock A01 for full pipeline')
	rootA1.CFrame = CFrame.new(Scene.UnlockPads[F.AutoRune].TriggerZone.Position); rootA1.Position = Scene.UnlockPads[F.AutoRune].TriggerZone.Position
	check(manager:TryUnlockFacility(pActive1, F.AutoRune), 'unlock A03 for full pipeline')
	rootA1.CFrame = CFrame.new(Scene.UnlockPads[F.AutoSmelter].TriggerZone.Position); rootA1.Position = Scene.UnlockPads[F.AutoSmelter].TriggerZone.Position
	check(manager:TryUnlockFacility(pActive1, F.AutoSmelter), 'unlock A04 for full pipeline')

	makeStreetBody(manager, Vector3.new(-35, 23.0, -60), 0)
	stepSeconds(manager, 26.0 * math.max(bruteWindowScale, clerkWindowScale), 0.1)
	check(coinsEarned[pActive1] == 5 * Config.PotionReward and coinsEarned[pActive2] == 10 * Config.PotionReward,
		'full A00->A01->A03->A04->A05 pipeline applies personal payout for one street NPC')
	check(manager:ShelfCount() == 5 and manager:PoolCount() == 2,
		'manual shelf and pool remain completely untouched across full automation pipeline')
	manager:Destroy()
end

print('PASS: M4 automation checks =', checks)
