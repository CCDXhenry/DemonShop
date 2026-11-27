-- 客户端唯一启动入口：引导 ClientGameManager，并在后台预加载与预渲染
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameManager = require(clientScripts:FindFirstChild("ClientGameManager"))
local ClientPreloadManager = require(clientScripts:FindFirstChild("ClientPreloadManager"))

local manager = ClientGameManager.new()
local destroyed = false
local function OnRootDestroying(): ()
	destroyed = true
	ClientPreloadManager.Cancel()
	manager:Destroy()
end
local function PrepareGame(): ()
	if not destroyed then ClientPreloadManager.PrepareGame() end
end
script.Destroying:Connect(OnRootDestroying)
task.defer(PrepareGame)
manager:Init()
