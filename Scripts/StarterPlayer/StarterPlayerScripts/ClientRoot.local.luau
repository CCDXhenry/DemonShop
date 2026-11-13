--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameManager = require(clientScripts:FindFirstChild("ClientGameManager"))

ClientGameManager.new():Init()
