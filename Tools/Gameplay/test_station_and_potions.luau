-- 工位可视距离、跨玩家药水隔离、死亡重生保护、重生连接作用域与循环音效回归
local R = require('@lune/roblox')
local fs = require('@lune/fs')
local CFrame, Vector3, Instance = R.CFrame, R.Vector3, R.Instance
local B = require('./StationPotionBoundary')
local Config = require('./GameConfig')
local Scene = require('./StationScene')
local Manager = require('./StationProcessingManager')
local Movement = require('./PersonalMovement')
local Replication = require('./StationReplication')
local SoundTool = require('./StationSoundTool')

local checks = 0
local function check(cond, msg)
	assert(cond, msg)
	checks += 1
end

-- M5：直接执行权威角色移动规则，仅替换物理和属性边界。
do
	local hum = {Health = 100, WalkSpeed = 999}
	local root = {
		Anchored = false, Position = Vector3.zero, CFrame = CFrame.identity,
		AssemblyLinearVelocity = Vector3.new(16, 0, 0),
		IsA = function(_, name) return name == 'BasePart' end,
	}
	local attrs = {}
	local character = {
		FindFirstChildOfClass = function() return hum end,
		FindFirstChild = function() return root end,
		SetAttribute = function(_, key, value) attrs[key] = value end,
	}
	local state = Movement.New()
	Movement.Step(state, character, 1, false, 0, 0)
	check(hum.WalkSpeed == 16, 'server restores the lawful walk speed')
	state.wanted = true
	Movement.Step(state, character, 1, false, 0.1, 0.1)
	check(hum.WalkSpeed == 22 and attrs.PersonalSprinting and state.stamina < 100, 'sprint moves faster and consumes stamina')
	for tick = 2, 41 do Movement.Step(state, character, 1, false, tick * 0.1, 0.1) end
	check(state.exhausted and hum.WalkSpeed == 16, 'exhaustion forces walking')
	state.wanted = false
	for tick = 42, 60 do Movement.Step(state, character, 1, false, tick * 0.1, 0.1) end
	check(not state.exhausted and state.stamina >= Config.Sprint.restartStamina, 'stamina recharges and permits another sprint')
	state.wanted = true
	Movement.Step(state, character, 5, false, 6.1, 0.1)
	check(hum.WalkSpeed == 38 and state.stamina == Config.Sprint.stamina, 'maximum tier sprints without stamina cost')
	Movement.Step(state, character, 5, true, 6.2, 0.1)
	check(hum.WalkSpeed == 0 and not state.wanted, 'painting stops sprint and locks movement')
	Movement.Step(state, character, 5, false, 6.5, 0.1)
	check(hum.WalkSpeed == 28, 'leaving paint restores the latest tier speed')
	root.Position = Vector3.new(50, 0, 0)
	root.CFrame = CFrame.new(root.Position)
	Movement.Step(state, character, 5, false, 6.8, 0.3)
	check(root.CFrame.X < 20 and root.AssemblyLinearVelocity.X == 0, 'server bounds excessive horizontal displacement')
end

-- 1. P1-01 & P3: Scene.StationRange 读取各工位 WorldInteractionPrompt.MaxActivationDistance 及缺省回退与槽位钳位
check(Scene.StationRange('Pool') == 12, 'Pool station reads MaxActivationDistance = 12 from prompt')
check(Scene.StationRange('Table') == 6, 'Table station reads MaxActivationDistance = 6 from prompt')
check(Scene.StationRange('Altar') == 10, 'Altar station reads MaxActivationDistance = 10 from prompt')
check(Scene.StationRange('Shelf') == 5, 'Shelf station reads MaxActivationDistance = 5 from prompt')
check(Scene.StationRange('Sigil') == 14, 'Sigil station reads MaxActivationDistance = 14 from prompt')
check(Scene.StationRange('UnknownStation') == Config.InteractionRange, 'unknown station falls back to Config.InteractionRange')

B.BuildDistrict({ Pool = 12, Table = 6, Altar = nil, Shelf = 0, Sigil = -5 })
local FallbackScene = require('./StationSceneFallback')
check(FallbackScene.StationRange('Pool') == 12 and FallbackScene.StationRange('Table') == 6, 'valid station prompt distances preserved')
check(FallbackScene.StationRange('Altar') == Config.InteractionRange, 'missing WorldInteractionPrompt falls back to Config.InteractionRange')
check(FallbackScene.StationRange('Shelf') == Config.InteractionRange, 'zero MaxActivationDistance falls back to Config.InteractionRange')
check(FallbackScene.StationRange('Sigil') == Config.InteractionRange, 'negative MaxActivationDistance falls back to Config.InteractionRange')

local poseLow = Scene.ShelfPose(1, 0)
local poseFirst = Scene.ShelfPose(1, 1)
local poseSixth = Scene.ShelfPose(1, 6)
local poseHigh = Scene.ShelfPose(1, 99)
check(poseLow == poseFirst and poseHigh == poseSixth, 'Scene.ShelfPose clamps out-of-range slot indices safely')

-- 2. P1-01 & P2-11: 5 大工位与 TakeTable 距离/视线校验，拒绝分支零冗余 Delta 广播
B.ResetPlayers()
table.clear(B.broadcasts)
table.clear(B.notices)
local manager = Manager.new({
	IsActive = function() return true end,
	CanAddCoins = function() return true end,
	AddCoins = function() return true end,
})
manager.replication = Replication.new()
local playerA, charA, humA, rootA, backpackA = B.CreatePlayer(101, Vector3.zero)
local playerB, charB, _humB, _rootB, _backpackB = B.CreatePlayer(202, Vector3.zero)
manager:AddPlayer(playerA)
manager:AddPlayer(playerB)
manager:Changed() -- 建立初始 State 基线，后续 Changed() 均产生 Delta
table.clear(B.broadcasts)
table.clear(B.notices)

local function movePlayer(root, pos)
	root.Position = pos
	root.CFrame = CFrame.new(pos)
	local char = root.Parent
	local head = char and char:FindFirstChild('Head')
	if head then
		head.Position = pos + Vector3.new(0, 1.5, 0)
		head.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	end
end

local function makeBodyItem(id, stage, location)
	local m = Instance.new('Model')
	m.Name = id
	local rp = Instance.new('Part')
	rp.Name = 'HumanoidRootPart'
	rp.Size = Vector3.new(2, 2, 1)
	rp.Position = Vector3.zero
	rp.CFrame = CFrame.identity
	rp.Parent = m
	local ut = Instance.new('Part')
	ut.Name = 'UpperTorso'
	ut.Size = Vector3.new(2, 2, 1)
	ut.Position = Vector3.zero
	ut.CFrame = CFrame.identity
	ut.Parent = m
	m.PrimaryPart = rp
	local item = {
		id = id,
		kind = 'Body',
		stage = stage or 'Raw',
		location = location or 'Pool',
		version = 1,
		model = m,
		holder = nil,
		hits = Config.StunHits,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = 100,
		progress = if stage == 'Painted' then 1 else 0,
		paintSeconds = 0,
		streetSlot = false,
		nextWalk = 0,
	}
	manager.items[id] = item
	return item
end

local function sendRequest(player, req)
	B.now += 0.2
	manager:OnRequest(player, req)
end

-- 2a. 超距拒绝（含 <= Config.InteractionRange(8) 但 > 工位专属距离如 Table=6、Shelf=5 的边界！）
local stationPositions = {
	Pool = Scene.PoolPickup.Position,
	Table = Scene.TableInteract.Position,
	Altar = Scene.Altar.Position,
	Shelf = Scene.Shelf.Position,
	Sigil = Scene.SigilPosition,
}
local outOfRangeOffsets = {
	Pool = Vector3.new(0, 0, 12.5),  -- > 12
	Table = Vector3.new(0, 0, 7.0),  -- <= 8 但 > 6
	Altar = Vector3.new(0, 0, 10.5), -- > 10
	Shelf = Vector3.new(0, 0, 5.5),  -- <= 8 但 > 5
	Sigil = Vector3.new(0, 0, 14.5), -- > 14
}
for _, station in { 'Pool', 'Table', 'Altar', 'Shelf', 'Sigil' } do
	table.clear(B.broadcasts)
	table.clear(B.notices)
	movePlayer(rootA, stationPositions[station] + outOfRangeOffsets[station])
	sendRequest(playerA, {
		action = 'Interact',
		target = station,
		version = manager.stationVersions[station],
	})
	check(#B.notices == 1 and B.notices[1].notice.textId == 'StationTooFar', station .. ' out-of-range rejected with StationTooFar')
	check(#B.broadcasts == 0, station .. ' out-of-range rejection emits zero Delta broadcasts')
end

-- TakeTable 超距（距离 7 > Table 距离 6）
local tableBody = makeBodyItem('body-on-table', 'Painted', 'Table')
manager.tableId = tableBody.id
table.clear(B.broadcasts)
table.clear(B.notices)
movePlayer(rootA, stationPositions.Table + Vector3.new(0, 0, 7.0))
sendRequest(playerA, { action = 'TakeTable' })
check(#B.notices == 1 and B.notices[1].notice.textId == 'StationTooFar', 'TakeTable at 7 studs (> 6) rejected with StationTooFar')
check(#B.broadcasts == 0 and manager.tableId == tableBody.id, 'TakeTable rejection leaves tableId intact and emits zero Delta broadcasts')

-- 2b. 穿墙/视线遮挡拒绝（距离仅 2 studs，但 B.occluded = true）
B.occluded = true
for _, station in { 'Pool', 'Table', 'Altar', 'Shelf', 'Sigil' } do
	table.clear(B.broadcasts)
	table.clear(B.notices)
	movePlayer(rootA, stationPositions[station] + Vector3.new(0, 0, 2))
	sendRequest(playerA, {
		action = 'Interact',
		target = station,
		version = manager.stationVersions[station],
	})
	check(#B.notices == 1 and B.notices[1].notice.textId == 'StationTooFar', station .. ' occluded line-of-sight rejected with StationTooFar')
	check(#B.broadcasts == 0, station .. ' occluded rejection emits zero Delta broadcasts')
end
table.clear(B.broadcasts)
table.clear(B.notices)
movePlayer(rootA, stationPositions.Table + Vector3.new(0, 0, 2))
sendRequest(playerA, { action = 'TakeTable' })
check(#B.notices == 1 and B.notices[1].notice.textId == 'StationTooFar' and #B.broadcasts == 0, 'TakeTable occluded rejected without Delta broadcast')
B.occluded = false

-- 2c. 版本不匹配或业务条件不满足时同样不发出冗余 Delta 广播
table.clear(B.broadcasts)
table.clear(B.notices)
movePlayer(rootA, stationPositions.Pool + Vector3.new(0, 0, 4))
sendRequest(playerA, { action = 'Interact', target = 'Pool', version = 999 })
check(#B.notices == 1 and B.notices[1].notice.textId == 'StationChanged' and #B.broadcasts == 0, 'StationChanged emits zero Delta broadcasts')

table.clear(B.broadcasts)
table.clear(B.notices)
sendRequest(playerA, { action = 'Interact', target = 'Pool', version = manager.stationVersions.Pool })
check(#B.notices == 1 and B.notices[1].notice.textId == 'PoolIsEmpty' and #B.broadcasts == 0, 'empty Pool rejection emits zero Delta broadcasts')

-- 2d. 可视距离内（含 > 8 但 <= 工位自定义距离，如 Pool=11<=12, Altar=9.5<=10, Sigil=13<=14）正常通过
-- TakeTable 在 5.5 studs (<= 6) 取走台上已完成白膜
table.clear(B.broadcasts)
table.clear(B.notices)
movePlayer(rootA, stationPositions.Table + Vector3.new(0, 0, 5.5))
sendRequest(playerA, { action = 'TakeTable' })
check(manager.tableId == nil and tableBody.holder == playerA and #B.broadcasts == 1, 'TakeTable within 6 studs succeeds and broadcasts Delta once')

-- Altar 在 9.5 studs (<= 10) 投入已完成白膜
table.clear(B.broadcasts)
table.clear(B.notices)
movePlayer(rootA, stationPositions.Altar + Vector3.new(0, 0, 9.5))
sendRequest(playerA, { action = 'Interact', target = 'Altar', version = manager.stationVersions.Altar })
check(tableBody.location == 'Altar' and tableBody.stage == 'Converting' and #B.broadcasts == 1, 'Altar within 10 studs accepts painted body')

-- Pool 在 11 studs (<= 12) 存入并取出未完成白膜
local rawBody = makeBodyItem('raw-pool-body', 'Raw', 'Carried')
rawBody.holder = playerA
table.clear(B.broadcasts)
movePlayer(rootA, stationPositions.Pool + Vector3.new(0, 0, 11))
sendRequest(playerA, { action = 'Interact', target = 'Pool', version = manager.stationVersions.Pool })
check(#manager.pool == 1 and rawBody.location == 'Pool' and #B.broadcasts == 1, 'Pool within 12 studs stores unfinished body')

-- Table 在 5.5 studs (<= 6) 从共享池拉取白膜上台
table.clear(B.broadcasts)
movePlayer(rootA, stationPositions.Table + Vector3.new(0, 0, 5.5))
sendRequest(playerA, { action = 'Interact', target = 'Table', version = manager.stationVersions.Table })
check(manager.tableId == rawBody.id and rawBody.location == 'Table' and #B.broadcasts == 1, 'Table within 6 studs fetches body from pool and begins paint')
manager:EndPaint(playerA)

-- M6：已有中心白膜仍按接手者等级，从肩扛和共享池补料。
do
	local carried = makeBodyItem('batch-carried', 'Unpainted', 'Carried')
	carried.holder = playerA
	local pooled = makeBodyItem('batch-pooled', 'Unpainted', 'Pool')
	table.insert(manager.pool, pooled.id)
	manager.players[playerA].levels.runeBatch = 5
	check(manager:Table(playerA), 'batch resumes the center while carrying a body')
	check(manager.tableId == rawBody.id and carried.paintSlot == 2 and pooled.paintSlot == 3, 'batch fills from carry before pool')
	check(manager:PoolCount() == 0, 'batch works with fewer bodies than the upgrade allows')
	rawBody.model.UpperTorso:SetAttribute('Paintable', true)
	local token = manager.paint.token
	local stroke = {key = token .. ':1:1', version = 1, gesture = 1, part = 'UpperTorso', face = 1, u = 0.5, v = 0.5, glyph = 1, angle = 0, scale = 1}
	manager:PaintVisual(playerA, {session = token, sequence = 1, segments = {stroke}})
	check(rawBody.visualState.count == 1 and pooled.visualState == rawBody.visualState and carried.visualState == rawBody.visualState, 'one accepted network stroke mirrors to all tables')
	rawBody.progress = 0.55
	manager:EndPaint(playerA)
	check(rawBody.progress == 0.55 and rawBody.visualState.count == 1 and manager.tableId == rawBody.id and manager:PoolCount() == 2, 'abort keeps center progress and ink and returns both followers')
	check(pooled.paintSlot == nil and pooled.visualState == nil, 'abort clears temporary follower paint')
	manager.players[playerA].levels.runeBatch = 1
	check(manager:Table(playerA) and #manager.paint.batch == 0, 'level one resumes only the center')
	manager:EndPaint(playerA)
	manager.players[playerA].levels.runeBatch = 3
	check(manager:Table(playerA) and #manager.paint.batch == 2, 'level three reserves both returned bodies')
	manager:ReleasePlayer(playerA)
	check(manager.paint == nil and manager:PoolCount() == 2 and rawBody.progress == 0.55, 'player release clears the batch and keeps center progress')
	check(manager:Table(playerA) and #manager.paint.batch == 2, 'the returned batch can be reserved again')
	rawBody.progress = 1
	manager:EndPaint(playerA)
	check(manager.tableId == nil and rawBody.location == 'Altar' and carried.location == 'Altar' and pooled.location == 'Altar', 'completion launches every body to the altar')
	check(carried.progress == 1 and pooled.visualState == rawBody.visualState and manager:PoolCount() == 0, 'finish retains center ink on every body')
	check(carried.altarToss.started == rawBody.altarToss.started and pooled.altarToss.started == rawBody.altarToss.started, 'batch shares one altar launch timestamp')
	manager.players[playerA].levels.runeBatch = 1
	manager.items[carried.id], manager.items[pooled.id], manager.items[rawBody.id] = nil, nil, nil
	carried.model:Destroy()
	pooled.model:Destroy()
	rawBody.model:Destroy()
end

-- Shelf 在 4.5 studs (<= 5) 领取成品药水
manager:SpawnAltarPotion(tableBody)
check(manager:ShelfCount() == 1, 'SpawnAltarPotion places potion on shelf')
table.clear(B.broadcasts)
movePlayer(rootA, stationPositions.Shelf + Vector3.new(0, 0, 4.5))
sendRequest(playerA, { action = 'Interact', target = 'Shelf', version = manager.stationVersions.Shelf })
check(manager:ShelfCount() == 0 and manager:EquippedPotion(playerA) ~= nil and #B.broadcasts == 1, 'Shelf within 5 studs grants and equips potion')

-- 3. P1-02: 跨玩家 Toolbar 药水隔离（服务端 Snapshot 与客户端 Potions / missingModel）
local snap = manager:Snapshot()
local hasToolbarOrShelf = false
for _, item in snap.items do
	if item.location == 'Toolbar' or item.location == 'Shelf' then
		hasToolbarOrShelf = true
	end
end
check(not hasToolbarOrShelf, 'Server Snapshot() excludes all Toolbar and Shelf items')

-- Sigil 在 13 studs (<= 14) 提交已装备药水
table.clear(B.broadcasts)
table.clear(B.notices)
movePlayer(rootA, stationPositions.Sigil + Vector3.new(0, 0, 13))
sendRequest(playerA, { action = 'Interact', target = 'Sigil', version = manager.stationVersions.Sigil })
check(manager:EquippedPotion(playerA) == nil and #B.broadcasts == 1, 'Sigil within 14 studs consumes equipped potion and broadcasts Delta')

-- 客户端 Potions() 仅统计本地 Backpack / Character，忽略 self.items 中他人药水；missingModel 跳过 Toolbar/Shelf
local Client = nil
do
	playerA:SetAttribute('GameReady', true)
	B.Players.LocalPlayer = playerA
	Client = require('./StationClient')
	local foreignTool = B.ModelsFolder.Items.Potion:Clone()
	foreignTool:SetAttribute('StackCount', 4)
	foreignTool:SetAttribute('OwnerUserId', playerB.UserId)
	foreignTool.Parent = charB

	local client = setmetatable({
		items = {
			foreignToolbar = { id = 'foreignToolbar', kind = 'Potion', location = 'Toolbar', model = foreignTool },
			nilToolbar = { id = 'nilToolbar', kind = 'Potion', location = 'Toolbar', model = nil },
			nilShelf = { id = 'nilShelf', kind = 'Potion', location = 'Shelf', model = nil },
		},
		synced = true,
		lastSync = 0,
		lastHint = 10,
		messageEnds = math.huge,
		view = { Update = function() end },
		paintCamera = { follow = nil },
		Text = function() end,
	}, Client)

	local p0 = client:Potions()
	check(p0.stored == 0 and p0.equipped == false, 'Client:Potions() ignores other players Toolbar potions in self.items')

	local localPotion = B.ModelsFolder.Items.Potion:Clone()
	localPotion:SetAttribute('StackCount', 3)
	localPotion.Parent = backpackA
	local p1 = client:Potions()
	check(p1.stored == 3 and p1.equipped == false, 'Client:Potions() counts unequipped local Backpack potion stack')

	localPotion.Parent = charA
	local p2 = client:Potions()
	check(p2.stored == 3 and p2.equipped == true, 'Client:Potions() detects equipped local Character potion')
	localPotion:Destroy()

	table.clear(B.requests)
	B.clock = 10
	client:Update(1 / 60)
	check(#B.requests == 0, 'missingModel in Client:Update() skips Toolbar and Shelf items without firing Sync')

	client.items.missingStreet = { id = 'missingStreet', kind = 'Body', location = 'Street', model = nil }
	client:Update(1 / 60)
	check(#B.requests == 1 and B.requests[1].action == 'Sync', 'missingModel still fires Sync when a world body model is missing')
end

-- 4. P1-03 & P2-08: 死亡重生 Backpack 药水保护、僵尸 OwnedPotion 清理与 characterScope 连接不泄漏
do
	-- 先给 playerA 发放 2 瓶药水并切回木棒（使药水处于 Backpack 未装备状态）
	local grantedTool = manager:GrantStack(playerA, Config.DefaultPotionQuality, 2)
	check(grantedTool ~= nil and grantedTool.Parent == backpackA and grantedTool:GetAttribute('StackCount') == 2, 'potion granted into Backpack')

	-- 首次 OnCharacter 建立角色作用域
	manager:OnCharacter(playerA, charA)
	local record = manager.players[playerA]
	local baseConnCount = #record.scope.connections
	check(record.characterScope ~= nil and record.characterScope.alive, 'OnCharacter creates dedicated characterScope')

	-- 确认药水在 Backpack 中（OnCharacter 自动装备了新 Club）
	check(grantedTool.Parent == backpackA, 'unequipped potion resides in Backpack before death')

	-- 模拟角色死亡移除：触发 CharacterRemoving -> RescuePotions，随后旧 Character 与旧 Backpack 被引擎销毁
	local firstCharScope = record.characterScope
	B.Signal(playerA, 'CharacterRemoving'):Fire(charA)
	check(not firstCharScope.alive, 'CharacterRemoving destroys previous characterScope')
	charA:Destroy()
	backpackA:Destroy()

	local reserve = playerA:FindFirstChild('PotionReserve')
	check(reserve ~= nil and grantedTool.Parent == reserve, 'RescuePotions rescues unequipped Backpack potion into PotionReserve before Backpack destruction')

	-- 重生新角色与新 Backpack
	local newBackpack = Instance.new('Backpack')
	newBackpack.Parent = playerA
	backpackA = newBackpack
	charA, humA, rootA = B.CreateCharacter(playerA, Vector3.zero)
	manager:OnCharacter(playerA, charA)
	check(grantedTool.Parent == backpackA and grantedTool:GetAttribute('StackCount') == 2, 'OnCharacter restores rescued potion back to new Backpack')

	-- 连续多次重生，验证 record.scope.connections 不随重生累加泄漏
	for _ = 1, 5 do
		local prevScope = record.characterScope
		B.Signal(playerA, 'CharacterRemoving'):Fire(charA)
		check(prevScope ~= nil and not prevScope.alive, 'each respawn disposes old characterScope')
		charA:Destroy()
		backpackA:Destroy()
		backpackA = Instance.new('Backpack')
		backpackA.Parent = playerA
		charA, humA, rootA = B.CreateCharacter(playerA, Vector3.zero)
		manager:OnCharacter(playerA, charA)
	end
	check(#record.scope.connections == baseConnCount, 'repeated respawns do not leak connections into player record.scope')
	check(grantedTool.Parent == backpackA and grantedTool:GetAttribute('StackCount') == 2, 'potion survives 5 consecutive respawns')

	-- 外部意外销毁 OwnedPotion 模型（模拟锁定 Parent = nil 僵尸实例），再次从 Shelf 领同品质药水不抛错
	local zombieId = grantedTool:GetAttribute('ItemId')
	grantedTool:Destroy()
	check(manager.items[zombieId] ~= nil, 'item entry exists before OwnedPotion cleanup')
	check(manager:OwnedPotion(playerA, Config.DefaultPotionQuality) == nil, 'OwnedPotion returns nil for destroyed tool')
	check(manager.items[zombieId] == nil, 'OwnedPotion cleans destroyed zombie entry from manager.items')

	local bodyForShelf = makeBodyItem('body-for-shelf-2', 'Converting', 'Altar')
	manager:SpawnAltarPotion(bodyForShelf)
	movePlayer(rootA, stationPositions.Shelf + Vector3.new(0, 0, 3))
	local ok, err = pcall(function()
		sendRequest(playerA, { action = 'Interact', target = 'Shelf', version = manager.stationVersions.Shelf })
	end)
	check(ok, 'collecting same-quality potion from Shelf after zombie destruction does not throw: ' .. tostring(err))
	local freshPotion = manager:OwnedPotion(playerA, Config.DefaultPotionQuality)
	check(freshPotion ~= nil and freshPotion.model.Parent == charA and freshPotion.stack == 1, 'fresh potion granted and equipped cleanly after zombie cleanup')
end

-- 5. P2-09: GameSoundTool.Play 支持 looped = true 且不强改 Looped = false，Client.UpdateAltar 多尸体单具完成即播音效
do
	local loopedLocal = SoundTool.Play('AltarLoop', Vector3.new(1, 2, 3), nil, true)
	check(loopedLocal ~= nil and loopedLocal.Looped == true and loopedLocal.Playing == true, 'GameSoundTool.Play(name, pos, nil, true) preserves Looped = true')

	local loopedGlobal = SoundTool.Play('AltarLoop', nil, 0.5, true)
	check(loopedGlobal ~= nil and loopedGlobal.Looped == true and math.abs(loopedGlobal.Volume - 0.4) < 1e-6, 'GameSoundTool.Play global looped sound applies volume multiplier and Looped = true')

	local inheritedLoop = SoundTool.Play('PresetLoop', Vector3.zero)
	check(inheritedLoop ~= nil and inheritedLoop.Looped == true, 'GameSoundTool.Play 3-arg call inherits template.Looped == true when looped is nil')

	local forcedNonLoop = SoundTool.Play('PresetLoop', Vector3.zero, 1, false)
	check(forcedNonLoop ~= nil and forcedNonLoop.Looped == false, 'GameSoundTool.Play explicit looped = false overrides template.Looped')

	local defaultOneShot = SoundTool.Play('OneShot', Vector3.zero)
	check(defaultOneShot ~= nil and defaultOneShot.Looped == false, 'GameSoundTool.Play one-shot template defaults to Looped = false')
	SoundTool.Destroy()

	-- 验证 Client:UpdateAltar 传 looped = true，且两具白膜在祭坛时第一具完成即触发 AltarComplete
	table.clear(B.soundPlays)
	local dummyModel = Instance.new('Model')
	local altarClient = setmetatable({
		items = {
			a1 = { id = 'a1', kind = 'Body', location = 'Altar', convertEnds = 20 },
			a2 = { id = 'a2', kind = 'Body', location = 'Altar', convertEnds = 25 },
		},
		altarViews = {},
		altarBodyId = nil,
		altarLoopSound = nil,
		snapshot = { shelf = 0 },
		bodies = {
			GetAltarModel = function() return dummyModel end,
			IsAltarTossing = function() return false end,
			Fly = function() end,
		},
		view = {
			ClearSacrifice = function() end,
			SetSacrifice = function() end,
		},
	}, Client)

	altarClient:UpdateAltar(10)
	check(#B.soundPlays == 1 and B.soundPlays[1].name == 'AltarLoop' and B.soundPlays[1].looped == true, 'UpdateAltar starts AltarLoop with looped = true')

	-- 第一具完成转化离开祭坛，第二具仍在转化
	altarClient.items.a1 = nil
	altarClient:UpdateAltar(20)
	local completeCount = 0
	for _, s in B.soundPlays do
		if s.name == 'AltarComplete' then
			completeCount += 1
		end
	end
	check(completeCount == 1 and altarClient.altarLoopSound ~= nil and not altarClient.altarLoopSound.stopped,
		'UpdateAltar plays AltarComplete when first body finishes while keeping AltarLoop active for remaining body')

	-- 第二具也完成转化
	local loopHandle = altarClient.altarLoopSound
	altarClient.items.a2 = nil
	altarClient:UpdateAltar(25)
	completeCount = 0
	for _, s in B.soundPlays do
		if s.name == 'AltarComplete' then
			completeCount += 1
		end
	end
	check(completeCount == 2 and loopHandle.stopped and altarClient.altarLoopSound == nil,
		'UpdateAltar stops AltarLoop and plays AltarComplete when final body finishes')
end

-- 6. P2-10: 校验 build-game-assets.luau 严禁在 legacy 表中包含任何基础框架事件或共享 UI 音效
do
	local buildSource = fs.readFile('Tools/Gameplay/build-game-assets.luau')
	local legacySection = string.sub(buildSource, string.find(buildSource, 'local legacy=', 1, true) or 1)
	local forbidden = {
		'NotifyPlayerInfoInit',
		'NotifyPlayersOtherPlayerInfoInit',
		'NotifyPlayerAcquiredGamePass',
		'RequestSetBGMVolume',
		'RequestSetSoundEffectVolume',
		'RequestSetVibrationsOnOffState',
		'CloseWindow',
		'OpenWindow',
		'LocalPlayerInfoInit',
		'OtherPlayerInfoInit',
		'LocalPlayerAcquiredGamePass',
		'PlayerInfoInit',
		'UIClick',
		'UIOpen',
		'UIClose',
	}
	for _, name in forbidden do
		check(not string.find(legacySection, '"' .. name .. '"', 1, true), 'build-game-assets legacy cleanup must not destroy foundation asset: ' .. name)
	end
end

-- 7. M1: 无限存放池(8可见+补位+MaximumBodies解耦)、无限药水架(6可见+不卡祭坛)、召唤法阵一键全卖
do
	B.ResetPlayers()
	table.clear(B.broadcasts)
	table.clear(B.notices)
	local coinTotals = {}
	local spendable = {}
	local m1 = Manager.new({
		IsActive = function() return true end,
		CanAddCoins = function() return true end,
		AddCoins = function(p, amount)
			coinTotals[p] = (coinTotals[p] or 0) + amount
			return true
		end,
		TrySpendCoins = function(p, amount)
			local balance = spendable[p] or 0
			if balance < amount then return false end
			spendable[p] = balance - amount
			return true
		end,
	})
	m1.replication = Replication.new()
	local p1, p1Char, _, p1Root, p1Bp = B.CreatePlayer(301, Vector3.zero)
	local p2, _, _, p2Root, _ = B.CreatePlayer(302, Vector3.zero)
	m1:AddPlayer(p1)
	m1:AddPlayer(p2)
	local function Buy(player, level)
		B.now += 0.2
		m1:OnRequest(player, {action = 'PersonalUpgrade', category = 'sellBonus', expectedNextLevel = level})
	end
	spendable[p2] = 150
	Buy(p2, 3)
	check(spendable[p2] == 150 and m1.players[p2].levels.sellBonus == 1, 'out-of-sequence purchase is rejected before debit')
	Buy(p2, 2)
	Buy(p2, 2)
	Buy(p2, 3)
	check(spendable[p2] == 0 and m1.players[p2].levels.sellBonus == 2, 'purchase charges once, replay and insufficient funds are rejected')
	check(m1.players[p1].levels.sellBonus == 1 and p1Char:GetAttribute('Upgrade_sellBonus') == 1, 'purchase leaves teammate at level one')
	check(p2.Character:GetAttribute('Upgrade_sellBonus') == 2, 'successful upgrade mirrors to the current character')
	for _, entry in B.notices do
		if entry.notice.kind == 'PersonalUpgrades' and entry.notice.personalLevels.sellBonus == 2 then
			check(entry.player == p2, 'upgraded state is sent only to the buyer')
		end
	end
	m1:Changed()
	table.clear(B.broadcasts)
	table.clear(B.notices)

	local function makeWorldBody(id, stage, location)
		local m = Instance.new('Model')
		m.Name = id
		local rp = Instance.new('Part')
		rp.Name = 'HumanoidRootPart'
		rp.Size = Vector3.new(2, 2, 1)
		rp.Position = Vector3.new(-20, 2, 0)
		rp.CFrame = CFrame.new(-20, 2, 0)
		rp.Parent = m
		local ut = Instance.new('Part')
		ut.Name = 'UpperTorso'
		ut.Size = Vector3.new(2, 2, 1)
		ut.Position = Vector3.new(-20, 2, 0)
		ut.CFrame = CFrame.new(-20, 2, 0)
		ut.Parent = m
		m.PrimaryPart = rp
		m.WorldPivot = rp.CFrame
		m.Parent = m1.runtime
		local item = {
			id = id,
			kind = 'Body',
			stage = stage or 'Unpainted',
			location = location or 'Carried',
			version = 1,
			model = m,
			holder = nil,
			hits = Config.StunHits,
			covered = {},
			strokes = {},
			strokePoints = 0,
			area = 0,
			totalArea = 100,
			progress = if stage == 'Painted' then 1 else 0,
			paintSeconds = 0,
			streetSlot = false,
			nextWalk = 0,
		}
		m1.items[id] = item
		return item
	end

	local function sendM1(player, req)
		B.now += 0.2
		m1:OnRequest(player, req)
	end

	-- M7: use the same server pickup and station requests as a player.
	local function pickUp(id)
		local body = makeWorldBody(id, 'Unpainted', 'Ground')
		movePlayer(p1Root, body.model.PrimaryPart.Position + Vector3.new(0, 0, 2))
		sendM1(p1, {action = 'Interact', target = id, version = body.version})
		return body
	end
	pickUp('m7-first')
	local extra = pickUp('m7-over-capacity')
	check(#m1:Carried(p1) == 1 and extra.holder == nil, 'T0 refuses a second white body')
	m1.players[p1].levels.carryTool = 4
	for i = 2, 15 do pickUp('m7-tier3-' .. i) end
	check(#m1:Carried(p1) == 8 and m1.players[p1].carryOverflowCount == 7, 'T3 stores seven virtual bodies after eight visible')
	local top = m1:Carried(p1)[1]
	sendM1(p1, {action = 'Throw', target = top.id, version = top.version, direction = Vector3.zero})
	check(top.holder == p1 and top.poolToss == nil, 'invalid throw keeps the top body in hand')
	B.now += 1
	sendM1(p1, {action = 'Throw', target = top.id, version = top.version, direction = Vector3.zAxis})
	check(top.holder == nil and #m1:Carried(p1) == 8 and m1.players[p1].carryOverflowCount == 6, 'throw removes one logical body and replenishes the visible slot')
	movePlayer(p1Root, stationPositions.Pool + Vector3.new(0, 0, 4))
	sendM1(p1, {action = 'Interact', target = 'Pool', version = m1.stationVersions.Pool})
	check(#m1:Carried(p1) == 0 and m1.players[p1].carryOverflowCount == 0 and m1:PoolCount() == 14, 'one pool request deposits the full remaining load')
	check(p1:GetAttribute('CarryBodyCount') == 0 and #m1.pool == 14 and m1.poolOverflowCount == 0, 'HUD count resets and all 14 bodies materialize in the pool')
	for _, item in m1.items do item.model:Destroy() end
	table.clear(m1.items)
	table.clear(m1.pool)
	m1.poolOverflowCount = 0
	m1.players[p1].levels.carryTool = 4
	for i = 1, 12 do pickUp('m7-death-' .. i) end
	spendable[p1] = 6000
	sendM1(p1, {action = 'PersonalUpgrade', category = 'carryTool', expectedNextLevel = 5})
	check(p1:GetAttribute('CarryCapacity') == 30 and m1:CarryCount(p1) == 12, 'upgrading keeps visible and virtual bodies while increasing capacity')
	for i = 13, 31 do pickUp('m7-death-' .. i) end
	check(m1:CarryCount(p1) == 30 and #m1:Carried(p1) == 8 and p1:GetAttribute('CarryBodyCount') == 30, 'T4 caps pickup at thirty and replicates the logical count')
	m1:ReleasePlayer(p1)
	local released = 0
	for id, item in m1.items do
		if id ~= 'm7-death-31' and item.location == 'Ground' and item.holder == nil then released += 1 end
		item.model:Destroy()
	end
	check(released == 30 and m1:CarryCount(p1) == 0, 'death release restores all virtual bodies as ground items exactly once')
	table.clear(m1.items)
	m1.players[p1].levels.carryTool = 1
	m1:Changed()

	-- 7a. 存放池不限制实体显示数量、全程 Loose 活布娃娃堆叠、边界双向归属、且不阻塞街道刷怪
	movePlayer(p1Root, stationPositions.Pool + Vector3.new(0, 0, 4))
	local poolBodies = {}
	for i = 1, 10 do
		local b = makeWorldBody('m1-pool-' .. tostring(i), 'Unpainted', 'Carried')
		b.holder = p1
		sendM1(p1, { action = 'Interact', target = 'Pool', version = m1.stationVersions.Pool })
		table.insert(poolBodies, b)
		if b.model.UpperTorso then
			b.model.UpperTorso.Position = stationPositions.Pool
			b.model.UpperTorso.CFrame = CFrame.new(stationPositions.Pool)
		end
	end
	check(#m1.pool == 10 and m1.poolOverflowCount == 0, 'pool renders all 10 deposited entities without visible cap')
	check(m1:PoolCount() == 10 and m1:Snapshot().pool == 10, 'Snapshot reports total logical pool count (10)')
	for _, pb in poolBodies do
		check(pb.model.Parent ~= nil and m1.items[pb.id] == pb, 'pool body model remains in workspace and m1.items')
	end

	-- 斜抛入池第 11 具：同样保持 Loose 活布娃娃实体存入池中，不销毁、不锚定
	local thrownBody = makeWorldBody('m1-thrown-11', 'Unpainted', 'Thrown')
	B.PivotTo(thrownBody.model, CFrame.new(stationPositions.Pool))
	local thrownTorso = thrownBody.model:FindFirstChild('UpperTorso')
	if thrownTorso and thrownTorso:IsA('BasePart') then
		thrownTorso.Position = stationPositions.Pool
		thrownTorso.CFrame = CFrame.new(stationPositions.Pool)
	end
	thrownBody.poolToss = { kind = 'Manual', from = CFrame.identity, target = CFrame.new(stationPositions.Pool), started = B.now, owner = p1.UserId }
	m1:SettleThrown(thrownBody)
	check(#m1.pool == 11 and m1.poolOverflowCount == 0 and m1:PoolCount() == 11, 'SettleThrown keeps 11th body in pool without overflow destroy')
	check(thrownBody.model.Parent ~= nil and m1.items[thrownBody.id] == thrownBody and thrownBody.model:GetAttribute('PhysicsMode') == 'Loose', 'SettleThrown keeps body as live Loose ragdoll')

	-- 取出 1 具
	sendM1(p1, { action = 'Interact', target = 'Pool', version = m1.stationVersions.Pool })
	check(m1:PoolCount() == 10 and #m1.pool == 10 and m1.poolOverflowCount == 0, 'taking from pool decrements pool list directly')
	local carriedFromPool = m1:Carried(p1)[1]
	check(carriedFromPool ~= nil, 'player carries body taken from pool')

	-- 另一名玩家从工作台取料
	movePlayer(p2Root, stationPositions.Table + Vector3.new(0, 0, 3))
	sendM1(p2, { action = 'Interact', target = 'Table', version = m1.stationVersions.Table })
	check(m1:PoolCount() == 9 and #m1.pool == 9 and m1.poolOverflowCount == 0, 'Table fetch takes directly from pool list')
	m1:EndPaint(p2)

	-- 滚出池外自动退回 Ground，未涂符 Ground 落入池内自动吸纳
	local knockedOut = m1.items[m1.pool[#m1.pool]]
	knockedOut.model.UpperTorso.Position = stationPositions.Pool + Vector3.new(30, 0, 0)
	m1.nextUpdate = 0
	m1:Update()
	check(knockedOut.location == 'Ground' and m1:PoolCount() == 8, 'pool body knocked outside reverts to pickable Ground')
	knockedOut.model.UpperTorso.Position = stationPositions.Pool
	m1.nextUpdate = 0
	m1:Update()
	check(knockedOut.location == 'Pool' and m1:PoolCount() == 9, 'unpainted Ground body settled inside pool is absorbed into pool')

	-- 池内大量实体白膜（>= 40 具）不占用 MaximumBodies(32) 街道刷怪配额
	for i = 1, 35 do
		local extra = makeWorldBody('m1-pool-extra-' .. tostring(i), 'Unpainted', 'Pool')
		extra.model.UpperTorso.Position = stationPositions.Pool
		table.insert(m1.pool, extra.id)
	end
	local spawnCalls = 0
	local prevSpawn = B.NPC.Spawn
	B.NPC.Spawn = function()
		spawnCalls += 1
		return nil
	end
	m1.nextUpdate = 0
	m1.nextSpawn = 0
	m1:Update()
	B.NPC.Spawn = prevSpawn
	check(spawnCalls == 1, '44 real Pool bodies do not block street NPC spawn under MaximumBodies=32')

	-- 7b. 手动药水架逻辑无限 + 6 实体渲染 + 祭坛不阻塞
	for i = 1, 8 do
		local altarBody = makeWorldBody('m1-altar-' .. tostring(i), 'Converting', 'Altar')
		altarBody.convertEnds = B.now - 1
	end
	m1.nextUpdate = 0
	m1:Update()
	local snapShelf = m1:Snapshot()
	local visibleShelfCount = 0
	for _ in snapShelf.shelfItems do
		visibleShelfCount += 1
	end
	check(m1:ShelfCount() == 8 and m1:QualityCount(Config.DefaultPotionQuality) == 8 and snapShelf.shelf == 8, 'shelf counts all 8 potions past ShelfVisibleLimit without blocking altar')
	check(visibleShelfCount == Config.ShelfVisibleLimit, 'Snapshot.shelfItems caps rendered bottles at ShelfVisibleLimit (6)')
	check(m1.altarId == nil, 'no altar body left waiting or held when shelf exceeds 6')

	-- p1 先丢掉肩上白膜再去药水架领取全部 8 瓶
	B.Carry.Drop(carriedFromPool)
	movePlayer(p1Root, stationPositions.Shelf + Vector3.new(0, 0, 3))
	sendM1(p1, { action = 'Interact', target = 'Shelf', version = m1.stationVersions.Shelf })
	check(m1:ShelfCount() == 0 and m1:Snapshot().shelf == 0, 'Shelf collect empties logical shelf count')
	local eqPotion = m1:EquippedPotion(p1)
	check(eqPotion ~= nil and eqPotion.stack == 8, 'Shelf grants full 8-stack potion to player')

	-- 7c. 召唤法阵一键全卖（同时包含手持与背包多格药水，以及仅背包未装备药水）
	local bpExtra = m1:GrantStack(p1, 2, 3)
	check(bpExtra ~= nil and bpExtra.Parent == p1Bp, 'extra quality stack placed in Backpack')
	table.clear(coinTotals)
	table.clear(B.notices)
	movePlayer(p1Root, stationPositions.Sigil + Vector3.new(0, 0, 4))
	sendM1(p1, { action = 'Interact', target = 'Sigil', version = m1.stationVersions.Sigil })
	local remList, remCount = m1:OwnedPotions(p1)
	check(#remList == 0 and remCount == 0, 'Sigil sell-all consumes both equipped Character potion and unequipped Backpack potion')
	check(coinTotals[p1] == 11 * Config.PotionReward and coinTotals[p2] == 1210, 'Sigil sell-all applies each recipient multiplier')

	-- 仅背包未装备药水（不需先切出）直接靠近法阵一键全卖
	local bpOnly = m1:GrantStack(p1, Config.DefaultPotionQuality, 4)
	check(bpOnly ~= nil and bpOnly.Parent == p1Bp and m1:EquippedPotion(p1) == nil, 'Backpack-only potion is unequipped')
	table.clear(coinTotals)
	sendM1(p1, { action = 'Interact', target = 'Sigil', version = m1.stationVersions.Sigil })
	local remList2, remCount2 = m1:OwnedPotions(p1)
	check(#remList2 == 0 and remCount2 == 0, 'Sigil sell-all consumes unequipped Backpack potions directly')
	check(coinTotals[p1] == 4 * Config.PotionReward and coinTotals[p2] == 440, 'Backpack-only sale applies each recipient multiplier')
end

-- 8. 多白膜肩扛堆叠 carryOrder 同步、Delta 增量检测与抛掷一致性
do
	B.ResetPlayers()
	table.clear(B.broadcasts)
	table.clear(B.notices)
	local m2 = Manager.new({
		IsActive = function() return true end,
		CanAddCoins = function() return true end,
		AddCoins = function() return true end,
	})
	m2.replication = Replication.new()
	local tp = B.CreatePlayer(101, Vector3.zero)
	m2:AddPlayer(tp)
	m2:Changed()
	table.clear(B.broadcasts)
	table.clear(B.notices)

	local function makeCarried(id, order)
		local m = Instance.new('Model')
		m.Name = id
		m.WorldPivot = CFrame.identity
		local rp = Instance.new('Part')
		rp.Name = 'HumanoidRootPart'
		rp.Size = Vector3.new(2, 2, 1)
		rp.Position = Vector3.zero
		rp.CFrame = CFrame.identity
		rp.Parent = m
		local ut = Instance.new('Part')
		ut.Name = 'UpperTorso'
		ut.Size = Vector3.new(2, 2, 1)
		ut.Position = Vector3.zero
		ut.CFrame = CFrame.identity
		ut.Parent = m
		m.PrimaryPart = rp
		m.Parent = m2.runtime
		local item = {
			id = id,
			kind = 'Body',
			stage = 'Unpainted',
			location = 'Carried',
			version = 1,
			model = m,
			holder = tp,
			carryOrder = order,
			hits = Config.StunHits,
			covered = {},
			strokes = {},
			strokePoints = 0,
			area = 0,
			totalArea = 100,
			progress = 0,
			paintSeconds = 0,
			streetSlot = false,
			nextWalk = 0,
		}
		m2.items[id] = item
		return item
	end

	local b1 = makeCarried('aaa-first', 1)
	local b2 = makeCarried('mmm-second', 2)
	local b3 = makeCarried('zzz-third', 3)

	-- 验证 Replication.Broadcast 对 carryOrder 变更敏感
	local rep = Replication.new()
	rep:Broadcast(m2:Snapshot())
	table.clear(B.broadcasts)
	b2.carryOrder = 5
	rep:Broadcast(m2:Snapshot())
	check(#B.broadcasts == 1 and B.broadcasts[1].kind == 'Delta' and #B.broadcasts[1].snapshot.items == 1 and B.broadcasts[1].snapshot.items[1].id == b2.id and B.broadcasts[1].snapshot.items[1].carryOrder == 5,
		'Replication.Broadcast emits Delta when carryOrder changes')
	b2.carryOrder = 2

	-- 验证 Client:Carried() 与服务端 Manager:Carried() 顶层顺序一致且抛掷不被 ItemChanged 拒绝
	local snap = m2:Snapshot()
	local clientItems = {}
	for _, iv in snap.items do
		clientItems[iv.id] = iv
	end
	check(clientItems[b1.id].carryOrder == 1 and clientItems[b2.id].carryOrder == 2 and clientItems[b3.id].carryOrder == 3,
		'Snapshot replicates carryOrder for carried bodies')

	B.Players.LocalPlayer = tp
	local Client = require('./StationClient')
	local client2 = setmetatable({ items = clientItems }, Client)
	local clientCarried = client2:Carried()
	local serverCarried = m2:Carried(tp)
	check(#clientCarried == 3 and #serverCarried == 3, 'both client and server see 3 carried bodies')
	check(clientCarried[1].id == b3.id and serverCarried[1].id == b3.id, 'top carried body matches highest carryOrder on both peers')
	check(clientCarried[2].id == b2.id and clientCarried[3].id == b1.id, 'remaining carried stack order matches carryOrder descending')

	table.clear(B.notices)
	B.now += 1
	m2:OnRequest(tp, {
		action = 'Throw',
		target = clientCarried[1].id,
		version = clientCarried[1].version,
		direction = Vector3.zAxis,
	})
	check(#B.notices == 0, 'Throw using Client:Carried()[1] succeeds without ItemChanged rejection')
	check(b3.location == 'Thrown' and b3.holder == nil, 'top carried body transitions to Thrown on server')
	check(m2:Carried(tp)[1].id == b2.id, 'next highest carryOrder body becomes top of shoulder stack')
end

print(string.format('PASS: %d station distance, toolbar potion isolation, respawn rescue and audio loop assertions', checks))
