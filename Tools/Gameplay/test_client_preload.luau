-- 预加载与预渲染回归：空列表、动画实例提交、源模板父级保持不变
local Manager = require("./ClientPreloadManager")
local Boundary = require("./ClientPreloadBoundary")
local Config = require("./GameConfig")
local GameData = require("./GameData")
local assertions = 0
local function Check(value, message)
	assert(value, message)
	assertions += 1
end
local callsBefore = Boundary.CallCount()
Check(Manager.PreloadAsync({}) == true, "empty preload succeeds")
Check(Boundary.CallCount() == callsBefore, "empty preload does not call ContentProvider")
local parent = Boundary.template.Parent
Manager.PrepareGame()
Check(Boundary.template.Parent == parent, "warmup keeps the source template parent")
Check(Boundary.workspace:FindFirstChild(Boundary.template.Name) == nil, "warmup clone is destroyed")
local sawString = false
local sawSlash = false
local sawCarry = false
local sawIdle = false
local sawWalk = false
local sawModel = false
local sawHidden = false
local sawGuide = false
local sawScreen = false
local sawSlashSound = false
local seenAnims = {}
local seenSounds = {}
for _, asset in Boundary.Targets() do
	if typeof(asset) == "string" then
		sawString = true
	elseif asset:IsA("Animation") then
		assert(not seenAnims[asset.AnimationId], "duplicate animation preloaded: " .. asset.AnimationId)
		seenAnims[asset.AnimationId] = true
		if asset.AnimationId == Config.WeaponSlashAnimation then sawSlash = true end
		if asset.AnimationId == Config.BodyCarryAnimation then sawCarry = true end
		if asset.AnimationId == Config.IdleAnimation then sawIdle = true end
		if asset.AnimationId == Config.WalkAnimation then sawWalk = true end
	elseif asset == Boundary.template then
		sawModel = true
	elseif asset == Boundary.hidden then
		sawHidden = true
	elseif asset.Name == "ScreenLayoutGuideFrame" then
		sawGuide = true
	elseif asset.Name == "GameScreenGui" then
		sawScreen = true
	elseif asset:IsA("Sound") then
		assert(not seenSounds[asset.SoundId], "duplicate sound preloaded: " .. asset.SoundId)
		seenSounds[asset.SoundId] = true
		if asset.SoundId == Config.WeaponSlashSound then
			sawSlashSound = true
		end
	end
end
for _, weapon in GameData.GetAllWeapons() do
	Check(seenAnims[weapon.slashAnim] == true, "weapon slashAnim preloaded: " .. weapon.id)
	Check(seenSounds[weapon.slashSound] == true, "weapon slashSound preloaded: " .. weapon.id)
end
Check(not sawString, "preload list contains instances")
Check(#Boundary.imageUris == 12, "shop and potion icon decals are submitted")
Check(table.find(Boundary.imageUris, Config.PotionIcon) ~= nil, "potion icon is preloaded")
for _, weapon in GameData.GetAllWeapons() do
	Check(table.find(Boundary.imageUris, weapon.icon) ~= nil, "shop icon submitted: " .. weapon.icon)
end
for _, carryTool in GameData.GetAllCarryTools() do
	Check(table.find(Boundary.imageUris, carryTool.icon) ~= nil, "shop icon submitted: " .. carryTool.icon)
end
Check(sawSlash and sawCarry and sawIdle and sawWalk, "configured animations are Animation instances")
Check(sawModel, "archivable model template is preloaded")
Check(not sawHidden, "non-archivable model is excluded")
Check(sawScreen, "runtime ui is preloaded")
Check(not sawGuide, "layout guide is excluded")
Check(sawSlashSound, "slash sound is a Sound instance")
print(string.format("PASS: %d client preload assertions", assertions))
