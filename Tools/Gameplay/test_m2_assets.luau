-- 阶段 M2 资产与 Edit 构建契约回归：反序列化 GameModels.rbxm 并核验 UnlockPad 规范与 build-automation-assets.luau
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
check(models:FindFirstChild("WhiteR15") ~= nil, "WhiteR15 preserved in GameModels.rbxm")
check(models:FindFirstChild("Club") ~= nil, "Club preserved in GameModels.rbxm")
check(models:FindFirstChild("Potion") ~= nil, "Potion preserved in GameModels.rbxm")
local bruteGlow = {}
for _, bruteName in { "HellBrute_1", "HellBrute_2" } do
	local brute = models:FindFirstChild(bruteName)
	check(brute ~= nil and brute:IsA("Model"), bruteName .. " template exists in GameModels.rbxm")
	check(brute:FindFirstChild("HumanoidRootPart") ~= nil, bruteName .. " has HumanoidRootPart")
	check(brute:FindFirstChildOfClass("Humanoid") ~= nil, bruteName .. " has Humanoid")
	check(brute:GetAttribute("Paintable") == nil and brute:GetAttribute("SurfaceVersion") == nil, bruteName .. " is not a paintable white body")
	for _, partName in { "HornLeft", "HornRight", "PauldronLeft", "PauldronRight", "ChestSigil", "BruteClubProp" } do
		check(brute:FindFirstChild(partName) ~= nil, bruteName .. " has baked part: " .. partName)
	end
	bruteGlow[bruteName] = brute.HornLeft.Color
end
check(bruteGlow.HellBrute_1 ~= bruteGlow.HellBrute_2, "HellBrute variants keep distinct baked colors")
local clerk = models:FindFirstChild("AutoClerk")
check(clerk ~= nil and clerk:IsA("Model"), "AutoClerk template exists in GameModels.rbxm")
check(clerk:FindFirstChild("HumanoidRootPart") ~= nil, "AutoClerk has HumanoidRootPart")
check(clerk:FindFirstChildOfClass("Humanoid") ~= nil, "AutoClerk has Humanoid")
check(clerk:GetAttribute("Paintable") == nil and clerk:GetAttribute("SurfaceVersion") == nil, "AutoClerk is not a paintable white body")
for _, partName in { "ClerkVisor", "ClerkBadge", "Bottle", "HeldPotionCore", "HeldPotionStopper" } do
	local part = clerk:FindFirstChild(partName)
	check(part ~= nil and part:IsA("BasePart"), "AutoClerk has baked part: " .. partName)
end
check(clerk.HeldPotionCore:FindFirstChildOfClass("PointLight") ~= nil, "AutoClerk potion core owns a PointLight")
check(clerk.Bottle.Transparency == 1 and clerk.ClerkVisor.Transparency == 0, "AutoClerk hides the carried potion and shows the visor")

local pad = models:FindFirstChild("UnlockPad")
check(pad ~= nil and pad:IsA("Model"), "UnlockPad template exists in GameModels.rbxm")
check(pad.PrimaryPart ~= nil and pad.PrimaryPart.Name == "RootPart", "UnlockPad PrimaryPart is RootPart")
for _, partName in { "OuterRim", "GlowRing", "InnerDisc", "CenterGlyph", "TriggerZone", "GuiAnchor" } do
	check(pad:FindFirstChild(partName) ~= nil, "UnlockPad has part: " .. partName)
end

for _, attr in { "FacilityId", "FacilityName", "FacilityDesc", "PrerequisiteId", "PrerequisiteLabel", "Cost", "PadState", "LockedColor", "InsufficientColor", "ReadyColor" } do
	check(pad:GetAttribute(attr) ~= nil, "UnlockPad declares attribute: " .. attr)
end

local guiAnchor = pad.GuiAnchor
local bb = guiAnchor:FindFirstChild("PadGui")
check(bb ~= nil and bb:IsA("BillboardGui"), "UnlockPad GuiAnchor owns PadGui BillboardGui")
check(bb.AutoLocalize == false, "PadGui disables Roblox native AutoLocalize for TranslationTool control")
check(bb.AlwaysOnTop == true and bb.LightInfluence == 0 and bb.MaxDistance == 55, "PadGui AlwaysOnTop=true, LightInfluence=0 and MaxDistance=55")
check(bb.Adornee == guiAnchor, "PadGui Adornee bound to GuiAnchor")

for _, attr in { "FacilityName", "FacilityDesc", "PrerequisiteLabel" } do
	check(string.match(tostring(pad:GetAttribute(attr)), "[^%z\1-\127]") == nil, "UnlockPad attribute is pure ASCII English: " .. attr)
end

local card = bb:FindFirstChild("CardFrame")
check(card ~= nil and card:IsA("Frame"), "PadGui owns CardFrame")
check(card.AnchorPoint == R.Vector2.new(0.5, 1) and card.Position == R.UDim2.fromScale(0.5, 1), "CardFrame bottom-center anchored")
check(card:FindFirstChildOfClass("UIScale") ~= nil, "CardFrame has UIScale")
for _, childName in { "TitleText", "DescText", "PrereqText", "PriceFrame" } do
	check(card:FindFirstChild(childName) ~= nil, "CardFrame has child: " .. childName)
end
check(card.PriceFrame:FindFirstChild("PriceText") ~= nil, "PriceFrame has PriceText")

local strokeCount = 0
local labelCount = 0
for _, desc in pad:GetDescendants() do
	check(not desc:IsA("LuaSourceContainer"), "UnlockPad contains no LuaSourceContainer")
	if desc:IsA("TextLabel") then
		labelCount += 1
		check(desc.AutoLocalize == false, "PadGui TextLabel sets AutoLocalize=false: " .. desc.Name)
		check(string.match(desc.Text, "[^%z\1-\127]") == nil, "PadGui TextLabel default text is ASCII English: " .. desc.Name)
		check(desc.TextScaled == true and desc.TextWrapped == true, "PadGui TextLabel enables TextScaled and TextWrapped: " .. desc.Name)
	elseif desc:IsA("UIStroke") then
		strokeCount += 1
		check(desc.StrokeSizingMode == R.Enum.StrokeSizingMode.ScaledSize, "UIStroke uses ScaledSize")
		check(desc.Thickness > 0 and desc.Thickness < 1, "UIStroke Thickness is fractional ScaledSize ratio")
	end
end
check(labelCount == 4, "All 4 PadGui TextLabels checked")
check(strokeCount >= 6, "All text and border UIStrokes present on UnlockPad")

local builder = fs.readFile("Tools/Gameplay/build-automation-assets.luau")
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
