-- 玩家设置管理器：校验请求频率，更新统一资料并补发客户端设置
--!strict
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Net = require(Shared.NetMsg)
local Config = require(Shared.GameConfig)
local Lifecycle = require(Shared.LifecycleTool)
local Info = require(script.Parent.Parent.ServerGameInfo)
local Manager = {}
Manager.__index = Manager
export type Manager = typeof(setmetatable({} :: { scope: Lifecycle.Lifecycle?, lastRequest: { [Player]: number } }, Manager))
function Manager.new(): Manager
	return setmetatable({ scope = nil, lastRequest = {} }, Manager)
end
function Manager.RemovePlayer(self: Manager, player: Player): ()
	self.lastRequest[player] = nil
end
function Manager.Init(self: Manager): ()
	if self.scope then
		return
	end
	local scope = Lifecycle.new()
	self.scope = scope
	local function Handle(player: Player, key: string?, value: unknown): ()
		if not Info.IsActive(player) then
			return
		end
		local now = os.clock()
		if now - (self.lastRequest[player] or -math.huge) < Config.SettingRequestInterval then
			return
		end
		self.lastRequest[player] = now
		if key then
			Info.UpdateSetting(player, key, value)
		else
			Info.SendPlayerInfo(player)
		end
	end
	scope:Connect(Net.ConnectRequestPlayerInfoInit(function(p: Player): ()
		Handle(p, nil, nil)
	end))
	scope:Connect(Net.ConnectRequestSetBGMVolume(function(p: Player, v: number): ()
		Handle(p, "bgmVolume", v)
	end))
	scope:Connect(Net.ConnectRequestSetSoundEffectVolume(function(p: Player, v: number): ()
		Handle(p, "soundEffectVolume", v)
	end))
	scope:Connect(Net.ConnectRequestSetVibrationsOnOffState(function(p: Player, v: boolean): ()
		Handle(p, "vibrationOn", v)
	end))
end
function Manager.Destroy(self: Manager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	table.clear(self.lastRequest)
end
export type ServerPlayerSettingManager = Manager
return Manager
