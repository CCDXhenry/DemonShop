-- 阶段 M2 资产与 Edit 构建契约回归：反序列化分类后的 GameModels.rbxm 并核验 build-automation-assets.luau
local fs = require("@lune/fs")
local R = require("@lune/roblox")

local count = 0
local function check(value, label)
	assert(value, label)
	count += 1
end

local roots = R.deserializeModel(fs.readFile("Assets/Models/GameModels.rbxm"))
check(#roots == 1 and roots[1].Name == "Models", "GameModels.rbxm has Models root")
local models = roots[1]
local characters = models:FindFirstChild("Characters")
local items = models:FindFirstChild("Items")
check(characters ~= nil and characters:IsA("Folder"), "Models.Characters folder exists in GameModels.rbxm")
check(items ~= nil and items:IsA("Folder"), "Models.Items folder exists in GameModels.rbxm")
check(characters:FindFirstChild("WhiteR15") ~= nil, "WhiteR15 preserved under Characters in GameModels.rbxm")
local people = characters:FindFirstChild("WhiteR15-People")
check(people ~= nil and people:IsA("Model"), "WhiteR15-People template is archived")
check(people.PrimaryPart == people:FindFirstChild("HumanoidRootPart"), "WhiteR15-People has a rig root")
check(people:GetAttribute("SurfaceVersion") == 3, "WhiteR15-People uses its own paint geometry")
check(type(people:GetAttribute("PaintBaseTexture")) == "string", "WhiteR15-People has a base paint atlas")
local peopleParts, peopleJoints = 0, 0
for _, part in people:GetChildren() do
	if part:IsA("MeshPart") then
		peopleParts += 1
		check(part.Material == R.Enum.Material.Plastic, part.Name .. " retains the People material")
		check(part:GetAttribute("Paintable") == true and part:GetAttribute("SurfaceVersion") == 3, part.Name .. " is paintable")
	end
end
for _, joint in people:GetDescendants() do
	if joint:IsA("Motor6D") then
		peopleJoints += 1
		check(joint.Part0.Parent == people and joint.Part1.Parent == people, joint.Name .. " connects the People rig")
	end
end
check(peopleParts == 15 and peopleJoints == 15, "WhiteR15-People has a complete R15 mesh rig")
check(items:FindFirstChild("Potion") ~= nil, "Potion preserved under Items in GameModels.rbxm")
check(models:FindFirstChild("Club") == nil, "Retired Club removed from GameModels.rbxm")
check(models:FindFirstChild("UnlockPad") == nil, "Edit-only UnlockPad removed from GameModels.rbxm")
check(models:FindFirstChild("NeonContractDistrict") == nil, "Static NeonContractDistrict removed from GameModels.rbxm")
local bruteGlow = {}
for _, bruteName in { "HellBrute_1", "HellBrute_2" } do
	local brute = characters:FindFirstChild(bruteName)
	check(brute ~= nil and brute:IsA("Model"), bruteName .. " template exists under Characters in GameModels.rbxm")
	check(brute:FindFirstChild("HumanoidRootPart") ~= nil, bruteName .. " has HumanoidRootPart")
	check(brute:FindFirstChildOfClass("Humanoid") ~= nil, bruteName .. " has Humanoid")
	check(brute:GetAttribute("Paintable") == nil and brute:GetAttribute("SurfaceVersion") == nil, bruteName .. " is not a paintable white body")
	for _, partName in { "HornLeft", "HornRight", "PauldronLeft", "PauldronRight", "ChestSigil", "BruteClubProp" } do
		check(brute:FindFirstChild(partName) ~= nil, bruteName .. " has baked part: " .. partName)
	end
	bruteGlow[bruteName] = brute.HornLeft.Color
end
check(bruteGlow.HellBrute_1 ~= bruteGlow.HellBrute_2, "HellBrute variants keep distinct baked colors")
local clerk = characters:FindFirstChild("AutoClerk")
check(clerk ~= nil and clerk:IsA("Model"), "AutoClerk template exists under Characters in GameModels.rbxm")
check(clerk:FindFirstChild("HumanoidRootPart") ~= nil, "AutoClerk has HumanoidRootPart")
check(clerk:FindFirstChildOfClass("Humanoid") ~= nil, "AutoClerk has Humanoid")
check(clerk:GetAttribute("Paintable") == nil and clerk:GetAttribute("SurfaceVersion") == nil, "AutoClerk is not a paintable white body")
for _, partName in { "ClerkVisor", "ClerkBadge", "Bottle", "HeldPotionCore", "HeldPotionStopper" } do
	local part = clerk:FindFirstChild(partName)
	check(part ~= nil and part:IsA("BasePart"), "AutoClerk has baked part: " .. partName)
end
check(clerk.HeldPotionCore:FindFirstChildOfClass("PointLight") ~= nil, "AutoClerk potion core owns a PointLight")
check(clerk.Bottle.Transparency == 1 and clerk.ClerkVisor.Transparency == 0, "AutoClerk hides the carried potion and shows the visor")

local builder = fs.readFile("Tools/Gameplay/build-automation-assets.luau")
check(string.find(builder, 'workspace:WaitForChild("NeonContractDistrict")', 1, true) ~= nil, "build-automation-assets targets static Workspace.NeonContractDistrict")
check(string.find(builder, "pad.Parent = modelsFolder", 1, true) == nil, "build-automation-assets does not persist UnlockPad into ReplicatedStorage.Models")
check(string.find(builder, "TextWrapped = false", 1, true) == nil, "build-automation-assets does not reset TextScaled via TextWrapped=false")
for _, token in {
	"FastChuteCover",
	"FastChuteLanding",
	"BrutePost",
	"AutoRuneMachine",
	"AutoSmelterMachine",
	"AutoPotionRack",
	"AutoClerkStation",
	"Box_001_West",
	"Box_001_East",
	"Box_001_NorthStrip",
	"Box_001_SouthStrip",
	"SouthFoundation_Side",
	"PerimeterJumpBarrier",
	"FAST DROP CHUTE",
	"AutoLocalize = false",
	"A00_FastChute",
	"A01_Brute1",
	"A02_Brute2",
	"A03_AutoRune",
	"A04_AutoSmelter",
	"A05_AutoClerk",
} do
	check(string.find(builder, token, 1, true) ~= nil, "build-automation-assets contains: " .. token)
end

print(string.format("PASS: %d M2 RBXM and Edit recovery builder assertions", count))
