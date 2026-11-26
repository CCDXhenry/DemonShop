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
	UDim2 = Roblox.UDim2,
	imageUris = {},
	renderedImages = {},
	sampleImage = "rbxassetid://9001",
	sampleAttributeImage = "rbxassetid://9002",
	sampleButtonImage = "rbxassetid://9003",
	guideImage = "rbxassetid://9004",
}
local ContentProvider = {}
function ContentProvider:PreloadAsync(targets, _onAssetFetched)
	Boundary.callCount += 1
	Boundary.targets = {}
	Boundary.imageUris = {}
	for _, target in targets do
		if typeof(target) == "Instance" and target:IsA("ImageLabel") then
			table.insert(Boundary.imageUris, target.Image)
		else
			table.insert(Boundary.targets, target)
		end
	end
end
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
Boundary.playerGui = playerGui
local Heartbeat = {}
function Heartbeat:Wait()
	local gui = playerGui:FindFirstChild("PreloadImageWarmup")
	if gui == nil then
		return
	end
	for _, child in gui:GetChildren() do
		if child:IsA("ImageLabel") and child.Image ~= "" then
			Boundary.renderedImages[child.Image] = true
		end
	end
end
Boundary.ContentProvider = ContentProvider
Boundary.RunService = { Heartbeat = Heartbeat }
local characterAdded = {}
function characterAdded:Connect(_callback)
	return { Disconnect = function() end }
end
local localPlayer = { Character = nil, CharacterAdded = characterAdded }
function localPlayer:FindFirstChild(name)
	if name == "PlayerGui" then
		return playerGui
	end
	return nil
end
Boundary.Players = { LocalPlayer = localPlayer }
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
screen:SetAttribute("SampleImage", Boundary.sampleAttributeImage)
screen.Parent = ui
local sampleIcon = Instance.new("ImageLabel")
sampleIcon.Name = "SampleIcon"
sampleIcon.Image = Boundary.sampleImage
sampleIcon.Parent = screen
local sampleButton = Instance.new("ImageButton")
sampleButton.Name = "SampleButton"
sampleButton.Image = Boundary.sampleButtonImage
sampleButton.Parent = screen
local guideIcon = Instance.new("ImageLabel")
guideIcon.Name = "GuideIcon"
guideIcon.Image = Boundary.guideImage
guideIcon.Parent = guide
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
