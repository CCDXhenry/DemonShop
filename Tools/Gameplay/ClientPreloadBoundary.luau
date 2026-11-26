-- 预加载回归边界：记录 ContentProvider 参数，并提供可克隆的模型模板
local Roblox = require("@lune/roblox")
local Instance = Roblox.Instance
local Boundary = {
	callCount = 0,
	targets = {},
	Instance = Instance,
	Vector3 = Roblox.Vector3,
	CFrame = Roblox.CFrame,
	Content = Roblox.Content,
	imageUris = {},
}
local ContentProvider = {}
function ContentProvider:PreloadAsync(targets, _onAssetFetched)
	Boundary.callCount += 1
	Boundary.targets = {}
	for _, target in targets do
		if typeof(target) == "Instance" and target:IsA("Decal") then
			table.insert(Boundary.imageUris, target.ColorMapContent.Uri)
		else
			table.insert(Boundary.targets, target)
		end
	end
end
local Heartbeat = {}
function Heartbeat:Wait() end
Boundary.ContentProvider = ContentProvider
Boundary.RunService = { Heartbeat = Heartbeat }
local characterAdded = {}
function characterAdded:Connect(_callback)
	return { Disconnect = function() end }
end
Boundary.Players = { LocalPlayer = { Character = nil, CharacterAdded = characterAdded } }
local replicatedStorage = Instance.new("Folder")
local models = Instance.new("Folder")
models.Name = "Models"
models.Parent = replicatedStorage
local characters = Instance.new("Folder")
characters.Name = "Characters"
characters.Parent = models
local template = Instance.new("Model")
template.Name = "WhiteR15"
template.Archivable = true
local part = Instance.new("Part")
part.Name = "Head"
part.Parent = template
template.Parent = characters
local hidden = Instance.new("Model")
hidden.Name = "HiddenTemplate"
hidden.Archivable = false
hidden.Parent = characters
local ui = Instance.new("Folder")
ui.Name = "UI"
ui.Parent = replicatedStorage
local guide = Instance.new("Frame")
guide.Name = "ScreenLayoutGuideFrame"
guide.Parent = ui
local screen = Instance.new("ScreenGui")
screen.Name = "GameScreenGui"
screen.Parent = ui
local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
sounds.Parent = replicatedStorage
local sound = Instance.new("Sound")
sound.Name = "Click"
sound.SoundId = "rbxassetid://1"
sound.Parent = sounds
Boundary.ReplicatedStorage = replicatedStorage
Boundary.workspace = Instance.new("Folder")
Boundary.template = template
Boundary.hidden = hidden
function Boundary.PivotTo(instance, pose)
	local part = instance:FindFirstChildWhichIsA("BasePart")
	if part then part.CFrame = pose end
end
function Boundary.CallCount()
	return Boundary.callCount
end
function Boundary.Targets()
	return Boundary.targets
end
return Boundary
