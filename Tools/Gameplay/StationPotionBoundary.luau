-- 工位距离、药水隔离、重生保护与循环音效离线边界
local R = require('@lune/roblox')
local CFrame, Vector3, Instance, Enum = R.CFrame, R.Vector3, R.Instance, R.Enum

local B = {
	now = 100,
	clock = 10,
	occluded = false,
	broadcasts = {},
	notices = {},
	requests = {},
	soundPlays = {},
	stoppedSounds = 0,
	waitOverride = nil :: ((any, string, number?) -> any)?,
	playerList = {},
	extraWorld = {},
	soundRoot = Instance.new('Folder'),
	_signals = setmetatable({}, { __mode = 'k' }),
	_attrs = setmetatable({}, { __mode = 'k' }),
}

function B.NewSignal()
	local listeners = {}
	local s = {}
	function s:Connect(callback)
		local c = { Connected = true }
		function c:Disconnect()
			self.Connected = false
		end
		table.insert(listeners, { callback = callback, connection = c, once = false })
		return c
	end
	function s:Once(callback)
		local c = { Connected = true }
		function c:Disconnect()
			self.Connected = false
		end
		table.insert(listeners, { callback = callback, connection = c, once = true })
		return c
	end
	function s:Fire(...)
		for _, entry in table.clone(listeners) do
			if entry.connection.Connected then
				if entry.once then
					entry.connection.Connected = false
				end
				entry.callback(...)
			end
		end
	end
	function s:Count()
		local n = 0
		for _, entry in listeners do
			if entry.connection.Connected then
				n += 1
			end
		end
		return n
	end
	return s
end

function B.Signal(obj, name)
	local map = B._signals[obj]
	if not map then
		map = {}
		B._signals[obj] = map
	end
	if not map[name] then
		map[name] = B.NewSignal()
	end
	return map[name]
end

function B.WaitForChild(obj, name, timeout)
	if B.waitOverride then
		return B.waitOverride(obj, name, timeout)
	end
	return obj:FindFirstChild(name)
end

function B.EquipTool(humanoid, tool)
	local character = humanoid and humanoid.Parent
	if not character then
		return
	end
	for _, child in character:GetChildren() do
		if child:IsA('Tool') and child ~= tool then
			local ownerId = child:GetAttribute('OwnerUserId')
			for _, player in B.playerList do
				if not ownerId or player.UserId == ownerId then
					local bp = player:FindFirstChildOfClass('Backpack')
					if bp then
						child.Parent = bp
						B.Signal(child, 'Unequipped'):Fire()
						break
					end
				end
			end
		end
	end
	if tool then
		tool.Parent = character
	end
end

function B.UnequipTools(humanoid)
	local character = humanoid and humanoid.Parent
	if not character then
		return
	end
	for _, child in character:GetChildren() do
		if child:IsA('Tool') then
			local owner = nil
			for _, p in B.playerList do
				if p.Character == character then
					owner = p
					break
				end
			end
			local bp = owner and owner:FindFirstChildOfClass('Backpack')
			if bp then
				child.Parent = bp
				B.Signal(child, 'Unequipped'):Fire()
			end
		end
	end
end

function B.StopSound(_sound)
	B.stoppedSounds += 1
end

local function makePart(parent, name, pos, size)
	local p = Instance.new('Part')
	p.Name = name
	p.Size = size or Vector3.new(2, 2, 2)
	p.Position = pos
	p.CFrame = CFrame.new(pos)
	p.Parent = parent
	return p
end

local function attachPrompt(part, distance)
	if distance == nil then
		return nil
	end
	local prompt = Instance.new('ProximityPrompt')
	prompt.Name = 'WorldInteractionPrompt'
	prompt.MaxActivationDistance = distance
	prompt.Parent = part
	return prompt
end

function B.BuildDistrict(ranges)
	ranges = ranges or {}
	local d = Instance.new('Folder')
	d.Name = 'NeonContractDistrict'

	local pool = Instance.new('Folder')
	pool.Name = 'SoulHoldingPool'
	pool.Parent = d
	makePart(pool, 'DropPointAnchor', Vector3.new(-20, 2, 0))
	local poolPickup = makePart(pool, 'PickupPointAnchor', Vector3.new(-20, 2, 0))
	attachPrompt(poolPickup, ranges.Pool)
	makePart(pool, 'PoolFloor', Vector3.new(-20, 0, 0), Vector3.new(12, 1, 12))

	local tableFolder = Instance.new('Folder')
	tableFolder.Name = 'RuneBodyTable'
	tableFolder.Parent = d
	makePart(tableFolder, 'BodyPlacementAnchor', Vector3.new(0, 2, 0))
	local tableInteract = makePart(tableFolder, 'TransferStartAnchor', Vector3.new(0, 2, 0))
	attachPrompt(tableInteract, ranges.Table)

	local altar = Instance.new('Folder')
	altar.Name = 'SoulConversionAltar'
	altar.Parent = d
	local altarAnchor = makePart(altar, 'BodyArrivalAnchor', Vector3.new(20, 2, 0))
	attachPrompt(altarAnchor, ranges.Altar)
	makePart(altar, 'BodyRest', Vector3.new(20, 1.25, 0), Vector3.new(9, 0.5, 5))

	local display = Instance.new('Folder')
	display.Name = 'SoulCrystalDisplay'
	display.Parent = d
	local shelfAnchor = makePart(display, 'StockPickupAnchor', Vector3.new(40, 2, 0))
	attachPrompt(shelfAnchor, ranges.Shelf)
	local points = Instance.new('Folder')
	points.Name = 'PotionPoints'
	points.Parent = display
	makePart(points, 'Point1', Vector3.new(40, 3, 0))

	local sigil = makePart(d, 'SummoningSubmitAnchor', Vector3.new(60, 2, 0))
	attachPrompt(sigil, ranges.Sigil)

	makePart(d, 'StreetSpawn', Vector3.new(0, 2, 20))

	local deck = Instance.new('Folder'); deck.Name = 'deck'; deck.Parent = d
	local gen = Instance.new('Folder'); gen.Name = 'Generated'; gen.Parent = deck
	local street = Instance.new('Folder'); street.Name = 'Street'; street.Parent = gen
	local void = Instance.new('Folder'); void.Name = 'Raised Street Deck With Stair Void'; void.Parent = street
	makePart(void, 'Box_005', Vector3.new(0, 0, 0), Vector3.new(40, 1, 40))

	B.district = d
	B.wallPart = makePart(d, 'OccludingWall', Vector3.new(0, 100, 0), Vector3.new(4, 4, 4))
	return d
end

B.BuildDistrict({ Pool = 12, Table = 6, Altar = 10, Shelf = 5, Sigil = 14 })

B.workspace = {
	GetServerTimeNow = function()
		return B.now
	end,
	FindFirstChild = function(_, name)
		if name == 'NeonContractDistrict' then
			return B.district
		end
		return B.extraWorld[name]
	end,
	WaitForChild = function(_, name)
		if name == 'NeonContractDistrict' then
			return B.district
		end
		return B.extraWorld[name]
	end,
	Raycast = function(_, origin, direction, _params)
		if B.occluded then
			return {
				Instance = B.wallPart,
				Position = origin + direction * 0.5,
				Normal = if direction.Magnitude > 0 then -direction.Unit else Vector3.yAxis,
			}
		end
		return nil
	end,
	GetPartBoundsInBox = function()
		return {}
	end,
	GetPartsInPart = function()
		return {}
	end,
}

B.os = {
	clock = function()
		return B.clock
	end,
}

B.RaycastParams = {
	new = function()
		return {}
	end,
}

B.OverlapParams = {
	new = function()
		return {}
	end,
}

B.PhysicsService = {
	IsCollisionGroupRegistered = function()
		return false
	end,
	CollisionGroupSetCollidable = function() end,
}

local modelsFolder = Instance.new('Folder')
modelsFolder.Name = 'Models'
local potionTemplate = Instance.new('Tool')
potionTemplate.Name = 'Potion'
local potionHandle = Instance.new('Part')
potionHandle.Name = 'Handle'
potionHandle.Parent = potionTemplate
potionTemplate.Parent = modelsFolder

local clubTemplate = Instance.new('Tool')
clubTemplate.Name = 'Club'
local clubHandle = Instance.new('Part')
clubHandle.Name = 'Handle'
clubHandle.Parent = clubTemplate
local slashSound = Instance.new('Sound')
slashSound.Name = 'SwordSlash'
slashSound.Parent = clubHandle
clubTemplate.Parent = modelsFolder

B.ModelsFolder = modelsFolder

local sounds = {}
function B.MakeSoundTemplate(name, looped)
	local s = {
		Name = name,
		ClassName = 'Sound',
		SoundId = 'rbxassetid://123456',
		Volume = 0.8,
		PlaybackSpeed = 1,
		TimePosition = 0,
		Looped = looped == true,
		SoundGroup = nil,
		Parent = nil,
		Playing = false,
		Ended = B.NewSignal(),
		Stopped = B.NewSignal(),
	}
	function s:IsA(cls)
		return cls == 'Sound'
	end
	function s:Play()
		self.Playing = true
	end
	function s:Stop()
		if self.Playing then
			self.Playing = false
			self.Stopped:Fire()
		end
	end
	function s:Destroy()
		self.Playing = false
		self.Parent = nil
	end
	function s:Clone()
		local c = B.MakeSoundTemplate(self.Name, self.Looped)
		c.SoundId = self.SoundId
		c.Volume = self.Volume
		c.PlaybackSpeed = self.PlaybackSpeed
		return c
	end
	sounds[name] = s
	return s
end

B.MakeSoundTemplate('AltarLoop', false)
B.MakeSoundTemplate('AltarComplete', false)
B.MakeSoundTemplate('OneShot', false)
B.MakeSoundTemplate('PresetLoop', true)

B.SoundsFolder = {
	FindFirstChild = function(_, name)
		return sounds[name]
	end,
}

local bgmGroup = { Name = 'BGM', Volume = 1 }
function bgmGroup:IsA(cls) return cls == 'SoundGroup' end
local sfxGroup = { Name = 'SoundEffects', Volume = 1 }
function sfxGroup:IsA(cls) return cls == 'SoundGroup' end
local soundGroupsFolder = {
	FindFirstChild = function(_, name)
		if name == 'BGM' then return bgmGroup elseif name == 'SoundEffects' then return sfxGroup end
		return nil
	end,
}
B.SoundService = {
	FindFirstChild = function(_, name)
		return if name == 'SoundGroups' then soundGroupsFolder else nil
	end,
}

B.ReplicatedStorage = {
	Models = modelsFolder,
	FindFirstChild = function(_, name)
		if name == 'Models' then
			return modelsFolder
		elseif name == 'Sounds' then
			return B.SoundsFolder
		end
		return nil
	end,
}

local guidCounter = 0
B.HttpService = {
	GenerateGUID = function()
		guidCounter += 1
		return 'guid-' .. tostring(guidCounter)
	end,
}

B.RunService = {
	Heartbeat = B.NewSignal(),
	IsStudio = function()
		return true
	end,
}

B.Players = {
	LocalPlayer = nil,
	GetPlayers = function()
		return B.playerList
	end,
	GetPlayerByUserId = function(_, userId)
		for _, p in B.playerList do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end,
}

function B.CreateCharacter(player, pos)
	local char = Instance.new('Model')
	char.Name = 'Char_' .. tostring(player.UserId)
	local root = makePart(char, 'HumanoidRootPart', pos)
	makePart(char, 'Head', pos + Vector3.new(0, 1.5, 0))
	makePart(char, 'UpperTorso', pos)
	local hum = Instance.new('Humanoid')
	hum.Health = 100
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.JumpHeight = 7.2
	hum.Parent = char
	char.PrimaryPart = root
	player.Character = char
	return char, hum, root
end

function B.CreatePlayer(userId, pos)
	local player = Instance.new('Player')
	player.Name = 'Player_' .. tostring(userId)
	player.UserId = userId
	local backpack = Instance.new('Backpack')
	backpack.Parent = player
	table.insert(B.playerList, player)
	local char, hum, root = B.CreateCharacter(player, pos or Vector3.zero)
	return player, char, hum, root, backpack
end

function B.ResetPlayers()
	table.clear(B.playerList)
end

B.Net = {
	Broadcast = function(notice)
		table.insert(B.broadcasts, notice)
	end,
	FireNotify = function(player, notice)
		table.insert(B.notices, { player = player, notice = notice })
	end,
	FireRequest = function(request)
		table.insert(B.requests, request)
	end,
	ConnectRequest = function(cb)
		B.requestHandler = cb
		return { Connected = true, Disconnect = function() end }
	end,
}

B.Info = {
	IsActive = function() return true end,
	CanAddCoins = function() return true end,
	AddCoins = function() return true end,
}

B.NPC = {
	StopMotion = function() end,
	Update = function() end,
	Hit = function() end,
	Spawn = function() return nil end,
}

B.Ragdoll = {
	Init = function() end,
	SetMode = function() end,
	LimitVelocity = function() end,
}

B.Ground = {
	Init = function() end,
	Place = function() end,
}

B.Door = {
	Init = function() end,
}

B.Carry = {
	Take = function(item, player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass('Humanoid')
		if hum then
			B.UnequipTools(hum)
		end
		item.holder = player
		item.location = 'Carried'
		item.version += 1
		return true
	end,
	Static = function(item, pose)
		item.holder = nil
		if item.model and item.model.PrimaryPart then
			item.model.PrimaryPart.CFrame = pose
		end
	end,
	Detach = function(item)
		item.holder = nil
	end,
	Restack = function() end,
	TossIntoPool = function(item)
		item.holder = nil
		item.location = 'Pool'
	end,
	BeginAltarToss = function(item, _layer, _fromTable, now)
		item.holder = nil
		item.altarToss = {
			from = CFrame.identity,
			rest = CFrame.identity,
			started = now,
			flightStarts = now,
			landEnds = now + 1,
		}
	end,
	Drop = function(item)
		item.holder = nil
		item.location = 'Ground'
		item.version += 1
	end,
	AdvanceTransition = function() end,
	AdvanceAltarToss = function() return false end,
	AdvancePoolToss = function() return false end,
	RecoverPool = function() end,
	Update = function() return false end,
}

B.Random = {
	NextNumber = function(_, a, b)
		return (a + b) * 0.5
	end,
}

B.SoundMock = {
	Play = function(name, position, multiplier, looped)
		local entry = {
			name = name,
			position = position,
			multiplier = multiplier,
			looped = looped,
			stopped = false,
		}
		function entry:Stop()
			self.stopped = true
		end
		table.insert(B.soundPlays, entry)
		return entry
	end,
}

return B
