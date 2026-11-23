-- 工位可视距离、跨玩家药水隔离、死亡重生保护、重生连接作用域与循环音效回归
local R = require('@lune/roblox')
local fs = require('@lune/fs')
local CFrame, Vector3, Instance = R.CFrame, R.Vector3, R.Instance
local B = require('./StationPotionBoundary')
local Config = require('./GameConfig')
local Scene = require('./StationScene')
local Manager = require('./StationProcessingManager')
local Replication = require('./StationReplication')
local SoundTool = require('./StationSoundTool')

local checks = 0
local function check(cond, msg)
	assert(cond, msg)
	checks += 1
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
	local foreignTool = B.ModelsFolder.Potion:Clone()
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

	local localPotion = B.ModelsFolder.Potion:Clone()
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

print(string.format('PASS: %d station distance, toolbar potion isolation, respawn rescue and audio loop assertions', checks))
