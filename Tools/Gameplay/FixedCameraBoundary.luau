-- FixedCamera 与 PaintCamera 离线 Lune 测试边界桩（仅替换引擎服务与属性信号）
local R = require('@lune/roblox')
local Instance = R.Instance
local CFrame = R.CFrame
local Vector3 = R.Vector3
local Color3 = R.Color3
local Enum = R.Enum

local function CreateSignal()
	local listeners = {}
	return {
		Connect = function(_self, fn)
			local entry = { fn = fn, connected = true }
			table.insert(listeners, entry)
			return {
				Disconnect = function()
					entry.connected = false
				end,
			}
		end,
		Fire = function(_self, ...)
			for _, entry in listeners do
				if entry.connected then
					entry.fn(...)
				end
			end
		end,
		ActiveCount = function(_self)
			local n = 0
			for _, entry in listeners do
				if entry.connected then
					n += 1
				end
			end
			return n
		end,
	}
end

local Boundary = {}
Boundary.R = R
Boundary.Instance = Instance
Boundary.CFrame = CFrame
Boundary.Vector3 = Vector3
Boundary.Color3 = Color3
Boundary.Enum = Enum
Boundary.CreateSignal = CreateSignal

local serverTime = 100
function Boundary.SetServerTime(t: number)
	serverTime = t
end

local currentCamera = {
	CFrame = CFrame.new(0, 5, 10),
	FieldOfView = 70,
	CameraType = Enum.CameraType.Custom,
	CameraSubject = nil :: any,
}

local activeTweens = {} :: { any }

Boundary.TweenInfo = {
	new = function(duration, style, direction)
		return { Time = duration, EasingStyle = style, EasingDirection = direction }
	end,
}

Boundary.TweenService = {
	Create = function(_self, target, info, props)
		local completed = CreateSignal()
		local tween = {
			target = target,
			info = info,
			props = props,
			Completed = completed,
			cancelled = false,
			destroyed = false,
			playing = false,
		}
		function tween:Play()
			self.playing = true
			table.insert(activeTweens, self)
		end
		function tween:Cancel()
			if not self.cancelled then
				self.cancelled = true
				self.playing = false
				completed:Fire(Enum.PlaybackState.Cancelled)
			end
		end
		function tween:Destroy()
			self.destroyed = true
		end
		function tween:CompleteNow()
			if self.cancelled or self.destroyed then
				return
			end
			for k, v in self.props do
				self.target[k] = v
			end
			self.playing = false
			completed:Fire(Enum.PlaybackState.Completed)
		end
		return tween
	end,
}

function Boundary.CompletePendingTweens()
	local snapshot = table.clone(activeTweens)
	table.clear(activeTweens)
	for _, tw in snapshot do
		if tw.playing and not tw.cancelled and not tw.destroyed then
			tw:CompleteNow()
		end
	end
end

local localHumanoid = Instance.new('Humanoid')
localHumanoid.Health = 100
local localCharacter = Instance.new('Model')
localHumanoid.Parent = localCharacter

Boundary.Players = {
	LocalPlayer = {
		Character = localCharacter,
	},
}
Boundary.LocalHumanoid = localHumanoid

local rootFolder = Instance.new('Folder')
rootFolder.Name = 'Workspace'

local workspaceProxy = {}
setmetatable(workspaceProxy, {
	__index = function(_t, k)
		if k == 'CurrentCamera' then
			return currentCamera
		elseif k == 'GetServerTimeNow' then
			return function()
				return serverTime
			end
		elseif k == 'FindFirstChild' then
			return function(_self, name, rec)
				return rootFolder:FindFirstChild(name, rec)
			end
		elseif k == 'WaitForChild' then
			return function(_self, name)
				return rootFolder:FindFirstChild(name)
			end
		end
		return rootFolder:FindFirstChild(k)
	end,
	__newindex = function(_t, k, v)
		if k == 'CurrentCamera' then
			currentCamera = v
		else
			(rootFolder :: any)[k] = v
		end
	end,
})

Boundary.Workspace = workspaceProxy
Boundary.workspace = workspaceProxy
Boundary.WorkspaceRoot = rootFolder

function Boundary.SetCurrentCamera(cam)
	currentCamera = cam
end

function Boundary.WrapSignalHost(inst: any)
	local propSignals = {}
	local attrSignals = {}
	local wrapper = {}
	setmetatable(wrapper, {
		__index = function(_t, k)
			if k == 'GetPropertyChangedSignal' then
				return function(_self, propName: string)
					if not propSignals[propName] then
						propSignals[propName] = CreateSignal()
					end
					return propSignals[propName]
				end
			elseif k == 'GetAttributeChangedSignal' then
				return function(_self, attrName: string)
					if not attrSignals[attrName] then
						attrSignals[attrName] = CreateSignal()
					end
					return attrSignals[attrName]
				end
			end
			local val = inst[k]
			if type(val) == 'function' then
				return function(_self, ...)
					return val(inst, ...)
				end
			end
			return val
		end,
		__newindex = function(_t, k, v)
			inst[k] = v
			if propSignals[k] then
				propSignals[k]:Fire()
			end
		end,
	})
	return wrapper, propSignals, attrSignals
end

return Boundary
