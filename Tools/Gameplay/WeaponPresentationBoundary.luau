-- 标准挥剑离线验证边界：模拟角色事件与动画播放器，不模拟业务分支
local Roblox = require("@lune/roblox")
local Boundary = { Instance = Roblox.Instance, Enum = Roblox.Enum, CFrame = Roblox.CFrame, loads = 0, plays = 0, destroyed = 0, failLoad = false }
local function Signal()
	local signal = { listeners = {} }
	function signal:Connect(callback)
		local connection = { Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(self.listeners, { callback = callback, connection = connection })
		return connection
	end
	function signal:Fire()
		for _, entry in table.clone(self.listeners) do
			if entry.connection.Connected then entry.callback() end
		end
	end
	return signal
end
local player = { UserId = 1, CharacterRemoving = Signal(), painting = false, paintingChanged = Signal() }
function player:GetAttribute(_name) return self.painting end
function player:GetAttributeChangedSignal(_name) return self.paintingChanged end
Boundary.Players = { LocalPlayer = player, GetPlayers = function() return { player } end }
Boundary.ContentProvider = { PreloadAsync = function() end }
function Boundary.Character()
	local animator = {}
	function animator:LoadAnimation(animation)
		Boundary.loads += 1
		assert(animation.AnimationId ~= "")
		if Boundary.failLoad then error("test unavailable animation") end
		local track = { IsPlaying = false, Speed = 1 }
		function track:AdjustSpeed(speed) self.Speed = speed end
		function track:Play() self.IsPlaying = true; Boundary.plays += 1 end
		function track:Stop() self.IsPlaying = false end
		function track:Destroy() Boundary.destroyed += 1 end
		return track
	end
	local humanoid = { Health = 100, RigType = Roblox.Enum.HumanoidRigType.R15, Died = Signal() }
	function humanoid:FindFirstChildOfClass(class) return if class == "Animator" then animator else nil end
	local tool = { Name = "W01_RustyPan", Unequipped = Signal() }
	function tool:IsA(class) return class == "Tool" end
	local character = { DescendantAdded = Signal(), humanoid = humanoid, tool = tool }
	tool.Parent = character
	function character:GetChildren() return if tool.Parent == self then {tool} else {} end
	function character:FindFirstChildOfClass(class) return if class == "Humanoid" then humanoid else nil end
	function character:GetDescendants() return {} end
	player.Character, player.painting = character, false
	return character
end
return Boundary
