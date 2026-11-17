-- 服务端基础入口：唯一装配玩家生命周期、资料保存、商城、设置和加工业务
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Lifecycle = require(Shared.LifecycleTool)
local Config = require(Shared.GameConfig)
local Info = require(script.Parent.ServerGameInfo)
local Store = require(script.Parent.ServerPlayerSaveStore)
local Processing = require(script.Parent.ProcessingManager)
local Analytics = require(script.Parent.AnalyticsTool)
local Settings = require(script.ServerPlayerSettingManager)
local Marketplace = require(script.ServerMarketplaceManager)
local Chat = require(script.ServerPlayerChatCommandManager)
local Context = require(script.Parent.PlayerContextTool)
local Manager = {}
Manager.__index = Manager
export type Manager = typeof(setmetatable(
	{} :: {
		initialized: boolean,
		closing: boolean,
		scope: Lifecycle.Lifecycle,
		store: Store.ServerPlayerSaveStore,
		processing: Processing.Manager,
		marketplaceManager: Marketplace.Manager,
		playerSettingManager: Settings.Manager,
		playerChatCommandManager: Chat.Manager,
		settings: Settings.Manager,
		marketplace: Marketplace.Manager,
		chat: Chat.Manager,
		players: { [Player]: boolean },
		loading: { [Player]: boolean },
		removing: { [Player]: boolean },
		nextSave: number,
	},
	Manager
))
export type ServerGameManager = Manager

local activeManager: Manager? = nil
local closeBound = false
function Manager.new(): Manager
	local self = setmetatable({
		initialized = false,
		closing = false,
		scope = Lifecycle.new(),
		store = Store.new(DataStoreService:GetDataStore("PlayerInfo")),
		processing = Processing.new(),
		settings = Settings.new(),
		marketplace = Marketplace.new(),
		chat = Chat.new(),
		players = {},
		loading = {},
		removing = {},
		nextSave = 0,
	}, Manager)
	self.marketplaceManager = self.marketplace
	self.playerSettingManager = self.settings
	self.playerChatCommandManager = self.chat
	return self
end
function Manager.AddPlayer(self: Manager, player: Player): ()
	if self.closing or self.loading[player] or self.players[player] then
		return
	end
	self.loading[player] = true
	player:SetAttribute("GameReady", false)
	local region, config = Context.Get(player)
	if self.closing or not player.Parent then
		self.loading[player] = nil
		return
	end
	local ok, reason = Info.Load(player, region, config)
	if not ok then
		self.loading[player] = nil
		if player.Parent then
			warn("[ServerGameManager] Load failed", player.UserId, reason)
			player:Kick("Saved data unavailable. Please rejoin.")
		end
		return
	end
	local record = Info.GetPlayerInfo(player)
	if record then
		record.playerConfigInfo = Context.ResolveConfig(player, record.profile.firstEnterVersion)
	end
	if self.closing or not player.Parent then
		Info.RemovePlayerInfo(player)
		self.loading[player] = nil
		return
	end
	self.loading[player] = nil
	self.players[player] = true
	self.processing:AddPlayer(player)
	player:SetAttribute("GameReady", true)
	Info.SendPlayerInfo(player)
	self.marketplace:CheckOwnedGamePasses(player)
	Analytics.AddPlayer(player)
end
function Manager.SavePlayer(self: Manager, player: Player): ()
	local ok, reason = Info.Save(player)
	if not ok then
		warn("[ServerGameManager] Save failed", player.UserId, reason)
	end
end
function Manager.RemovePlayer(self: Manager, player: Player): ()
	if self.removing[player] or not self.players[player] then
		return
	end
	self.removing[player] = true
	Info.Freeze(player)
	self.processing:RemovePlayer(player)
	self.settings:RemovePlayer(player)
	Analytics.RemovePlayer(player)
	self:SavePlayer(player)
	Info.RemovePlayerInfo(player)
	self.players[player] = nil
	self.removing[player] = nil
end
function Manager.Update(self: Manager, seconds: number): ()
	if self.closing then
		return
	end
	for player in self.players do
		if self.removing[player] then
			continue
		end
		if not Info.IsActive(player) then
			Info.Freeze(player)
			self.processing:RemovePlayer(player)
			player:Kick("Your data session expired. Please rejoin.")
			continue
		end
		Info.Tick(player, seconds)
	end
	local now = os.clock()
	if now < self.nextSave then
		return
	end
	self.nextSave = now + Config.SaveInterval
	for player in self.players do
		if not self.removing[player] and not self.store:IsBusy(player.UserId) then
			self.scope:Spawn(function(): ()
				self:SavePlayer(player)
			end)
		end
	end
end
function Manager.Close(self: Manager): ()
	self.closing = true
	for player in self.players do
		task.spawn(function(): ()
			self:RemovePlayer(player)
		end)
	end
	local deadline = os.clock() + 25
	while (next(self.players) or next(self.loading)) and os.clock() < deadline do
		task.wait(0.1)
	end
	if next(self.players) or next(self.loading) then
		warn("[ServerGameManager] Shutdown timed out with pending data operations")
	end
end
function Manager.Init(self: Manager): ()
	if self.initialized then
		return
	end
	assert(activeManager == nil, "Only one server foundation manager may run")
	activeManager = self
	self.initialized = true
	Info.Init(self.store)
	Analytics.Init()
	self.settings:Init()
	self.marketplace:Init()
	self.chat:Init()
	self.processing:Init()
	self.nextSave = os.clock() + Config.SaveInterval
	self.scope:Connect(Players.PlayerAdded:Connect(function(player: Player): ()
		self.scope:Spawn(function(): ()
			self:AddPlayer(player)
		end)
	end))
	self.scope:Connect(Players.PlayerRemoving:Connect(function(player: Player): ()
		self:RemovePlayer(player)
	end))
	self.scope:Connect(RunService.Heartbeat:Connect(function(seconds: number): ()
		self:Update(seconds)
	end))
	if not closeBound then
		closeBound = true
		game:BindToClose(function(): ()
			local manager = activeManager
			if manager then
				manager:Close()
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		self.scope:Spawn(function(): ()
			self:AddPlayer(player)
		end)
	end
end
function Manager.Destroy(self: Manager): ()
	if not self.initialized then
		return
	end
	self:Close()
	self.processing:Destroy()
	self.settings:Destroy()
	self.marketplace:Destroy()
	self.chat:Destroy()
	Analytics.Destroy()
	self.scope:Destroy()
	if not next(self.players) and not next(self.loading) then
		Info.Reset()
	end
	activeManager = nil
	self.initialized = false
end
return Manager
