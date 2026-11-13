--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameManager = require(serverScripts:FindFirstChild("ServerGameManager"))

ServerGameManager.new():Init()