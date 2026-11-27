-- 预加载与预热回归边界：记录下载批次、舞台复用、渲染帧临时实例与相机状态
local Roblox = require("@lune/roblox")
local Instance = Roblox.Instance
local Enum = Roblox.Enum

local Boundary = {
	Instance = Instance,
	Enum = Enum,
	CFrame = Roblox.CFrame,
	Vector3 = Roblox.Vector3,
	UDim2 = Roblox.UDim2,
	batches = {},
	preloadedUris = {},
	renderedImages = {},
	renderedDecals = {},
	renderedModels = {},
	renderedEffects = {},
	renderedSkies = {},
	warmedAnimations = {},
	warmedSounds = {},
	pivots = {},
	failures = {},
	stageCreateCount = 0,
	currentCamera = nil,
	asyncYield = false,
	sampleImage = "rbxassetid://9001",
	sampleAttributeImage = "rbxassetid://9002",
	sampleButtonImage = "rbxassetid://9003",
	guideImage = "rbxassetid://9004",
	addedImage = "rbxassetid://9005",
	shopImage = "rbxassetid://9006",
	newModelMesh = "rbxassetid://9007",
	lateImage = "rbxassetid://9008",
	alwaysFails = "rbxassetid://9009",
}

local task = require("@lune/task")
local lastStageGui = nil

local function GetUri(target)
	if typeof(target) == "string" then
		return target
	end
	if target:IsA("ImageLabel") then
		return target.Image
	end
	if target:IsA("Decal") then
		return target.Texture
	end
	if target:IsA("Sound") then
		return target.SoundId
	end
	if target:IsA("Animation") then
		return target.AnimationId
	end
	if target:IsA("SpecialMesh") then
		return target.MeshId
	end
	if target:IsA("MeshPart") then
		return target.MeshId
	end
	error("Unexpected download target " .. target.ClassName)
end

local ContentProvider = {}
function ContentProvider:PreloadAsync(targets, onAssetFetched)
	assert(#targets <= 12, "download batch exceeded limit")
	local batch = {}
	table.insert(Boundary.batches, batch)
	for _, target in targets do
		table.insert(batch, GetUri(target))
	end
	if Boundary.onFetch then
		Boundary.onFetch(targets)
	end
	for _, uri in batch do
		Boundary.preloadedUris[uri] = (Boundary.preloadedUris[uri] or 0) + 1
		local failures = Boundary.failures[uri] or 0
		Boundary.failures[uri] = math.max(failures - 1, 0)
		onAssetFetched(uri, if failures > 0 then Enum.AssetFetchStatus.Failure else Enum.AssetFetchStatus.Success)
	end
end
Boundary.ContentProvider = ContentProvider

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
Boundary.playerGui = playerGui

local workspace = Instance.new("Folder")
Boundary.workspace = workspace

function Boundary.GetCurrentCamera()
	return Boundary.currentCamera
end

function Boundary.PivotTo(instance, cframe)
	Boundary.pivots[instance] = cframe
end

local PreRender = {}
function PreRender:Wait()
	local gui = playerGui:FindFirstChild("PreloadImageWarmup")
	if gui ~= nil then
		if gui ~= lastStageGui then
			lastStageGui = gui
			Boundary.stageCreateCount += 1
		end
		local models = 0
		local skies = 0
		for _, node in gui:GetDescendants() do
			if node:IsA("ImageLabel") then
				Boundary.renderedImages[node.Image] = true
			elseif node:IsA("Decal") then
				Boundary.renderedDecals[node.Texture] = true
			elseif node:IsA("Model") and node.Parent and node.Parent.Name == "PreloadModel" then
				Boundary.renderedModels[node.Name] = true
				models += 1
			elseif node:IsA("Sky") then
				Boundary.renderedSkies[node.Name] = true
				skies += 1
			end
		end
		local effects = 0
		for _, node in workspace:GetChildren() do
			if node.Name == "PreloadEffectAnchor" then
				effects += 1
				table.insert(Boundary.renderedEffects, node.CFrame)
			end
		end
		assert(models + effects + skies <= 2, "heavy warmup limit")
	end
	if Boundary.onRender then
		Boundary.onRender()
	end
	if Boundary.asyncYield then
		task.wait()
	end
end

Boundary.RunService = {
	Heartbeat = {
		Wait = function()
			if Boundary.asyncYield then
				task.wait()
			end
		end,
	},
	PreRender = PreRender,
	IsStudio = function()
		return true
	end,
}

Boundary.Lighting = Instance.new("Folder")

Roblox.implementMethod("Model", "GetBoundingBox", function()
	return Roblox.CFrame.identity, Roblox.Vector3.one
end)
Roblox.implementMethod("Animator", "LoadAnimation", function(_, animation)
	Boundary.warmedAnimations[animation.AnimationId] = true
	return Instance.new("AnimationTrack")
end)
Roblox.implementMethod("AnimationTrack", "Play", function() end)
Roblox.implementMethod("Sound", "Play", function(sound)
	assert(sound.Volume == 0, "sound warmup must be muted")
	Boundary.warmedSounds[sound.SoundId] = true
end)
Roblox.implementMethod("ParticleEmitter", "Emit", function() end)

local function NewSignal()
	local signal = { callback = nil }
	function signal:Connect(callback)
		self.callback = callback
		return {
			Disconnect = function()
				self.callback = nil
			end,
		}
	end
	return signal
end

local characterAdded = NewSignal()
local localPlayer = { Character = nil, CharacterAdded = characterAdded }
function Boundary.Equip(name)
	local character = { ChildAdded = NewSignal(), GetChildren = function()
		return {}
	end }
	characterAdded.callback(character)
	local tool = Instance.new("Tool")
	tool.Name = name
	character.ChildAdded.callback(tool)
end
function localPlayer:FindFirstChild(name)
	return if name == "PlayerGui" then playerGui else nil
end
Boundary.Players = { LocalPlayer = localPlayer }

local replicatedStorage = Instance.new("Folder")
Boundary.ReplicatedStorage = replicatedStorage
local models = Instance.new("Folder")
models.Name = "Models"
models.Parent = replicatedStorage
local characters = Instance.new("Folder")
characters.Name = "Characters"
characters.Parent = models
local template = Instance.new("Model")
template.Name = "WhiteR15"
template.Parent = characters
local head = Instance.new("Part")
head.Name = "Head"
head.Parent = template
local hidden = Instance.new("Model")
hidden.Name = "HiddenTemplate"
hidden.Archivable = false
hidden.Parent = characters
local variants = Instance.new("Folder")
variants.Name = "CarryRigs"
variants.Parent = models
local newTemplate = Instance.new("Model")
newTemplate.Name = "NewCarryTemplate"
newTemplate.Parent = variants
local part = Instance.new("Part")
part.Parent = newTemplate
local mesh = Instance.new("SpecialMesh")
mesh.MeshId = Boundary.newModelMesh
mesh.TextureId = ""
mesh.Parent = part
Boundary.template = template
Boundary.hidden = hidden
Boundary.newTemplate = newTemplate

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
local shop = Instance.new("Frame")
shop.Name = "PersonalShopFrame"
shop.Parent = ui
local otherFrame = Instance.new("Frame")
otherFrame.Name = "ExtraUnusedFrame"
otherFrame.Parent = ui
local function AddImage(className, uri, parent)
	local icon = Instance.new(className)
	icon.Image = uri
	if icon:IsA("ImageButton") then
		icon.HoverImage = ""
		icon.PressedImage = ""
	end
	icon.Parent = parent
end
AddImage("ImageLabel", Boundary.sampleImage, screen)
AddImage("ImageButton", Boundary.sampleButtonImage, screen)
AddImage("ImageLabel", Boundary.guideImage, guide)
AddImage("ImageLabel", Boundary.shopImage, shop)
AddImage("ImageLabel", Boundary.addedImage, otherFrame)
AddImage("ImageLabel", Boundary.lateImage, otherFrame)
AddImage("ImageLabel", Boundary.alwaysFails, otherFrame)
local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
sounds.Parent = replicatedStorage
local sound = Instance.new("Sound")
sound.Name = "Click"
sound.SoundId = "rbxassetid://1"
sound.Parent = sounds

function Boundary.Reset()
	table.clear(Boundary.batches)
	table.clear(Boundary.preloadedUris)
	table.clear(Boundary.renderedImages)
	table.clear(Boundary.renderedDecals)
	table.clear(Boundary.renderedModels)
	table.clear(Boundary.renderedEffects)
	table.clear(Boundary.renderedSkies)
	table.clear(Boundary.warmedAnimations)
	table.clear(Boundary.warmedSounds)
	table.clear(Boundary.pivots)
	table.clear(Boundary.failures)
	Boundary.stageCreateCount = 0
	lastStageGui = nil
	Boundary.currentCamera = nil
	Boundary.asyncYield = false
	Boundary.onFetch = nil
	Boundary.onRender = nil
end

return Boundary
