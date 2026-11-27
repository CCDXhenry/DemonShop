-- 官方剑模板契约及正式动作模块的缓存、复制边界、失败与生命周期回归
local fs = require("@lune/fs")
local Roblox = require("@lune/roblox")
local Boundary = require("./WeaponPresentationBoundary")
local Presentation = require("./CharacterPresentation")
local Config = require("./GameConfig")
local assertions = 0
local function Check(value, message)
	assert(value, message)
	assertions += 1
end
local function CheckSword(sword)
	Check(sword and sword:IsA("Tool") and sword.Name == "Club", "stable tool contract")
	Check(sword:GetAttribute("SourceAssetId") == Config.WeaponSourceAsset, "official source")
	Check(tostring(sword.Handle.Mesh.MeshContent):find("rbxasset://fonts/sword.mesh", 1, true), "official mesh")
	Check(tostring(sword.Handle.SwordSlash.AudioContent):find(Config.WeaponSlashSound, 1, true), "configured sound")
	Check(not sword.CanBeDropped and not sword.Handle.CanTouch and not sword.Handle.CanCollide, "non-physical weapon")
	for _, child in sword:GetDescendants() do
		Check(not child:IsA("LuaSourceContainer") and not child:IsA("Camera"), "sanitized prefab")
	end
end
local single = Roblox.deserializeModel(fs.readFile("Assets/Models/ClassicSword.rbxm"))
local full = Roblox.deserializeModel(fs.readFile("Assets/Models/GameModels.rbxm"))
CheckSword(single[1])
Check(full[1]:FindFirstChild("Club") == nil, "retired Club excluded from GameModels.rbxm")
local weapons = full[1]:FindFirstChild("Weapons")
Check(weapons ~= nil and weapons:IsA("Folder"), "GameModels.rbxm contains Weapons folder")
for _, name in { "W01_RustyPan", "W02_IronCrowbar", "W03_DemonScimitar", "W04_ReaperScythe", "W05_VoidCannon", "W06_AbyssalHammer" } do
	local tool = weapons and weapons:FindFirstChild(name)
	Check(tool and tool:IsA("Tool") and not tool.CanBeDropped, "active weapon template exists under Weapons: " .. name)
	local slash = tool and tool:FindFirstChild("Slash")
	local slashSound = tool and tool:FindFirstChild("SlashSound")
	Check(slash and slash:IsA("Animation") and tostring(slash.AnimationContent):find(Config.WeaponSlashAnimation, 1, true) ~= nil, "weapon slash animation is on the tool: " .. name)
	Check(slashSound and slashSound:IsA("Sound") and tostring(slashSound.AudioContent):find(Config.WeaponSlashSound, 1, true) ~= nil, "weapon slash sound is on the tool: " .. name)
end
local effects = full[1]:FindFirstChild("Effects")
Check(effects and effects:IsA("Folder") and effects:FindFirstChild("ThrowAim"), "existing ThrowAim effect stays archived")
for _, spec in {
	{ name = "W03_DemonScimitar", range = 8, width = nil },
	{ name = "W04_ReaperScythe", range = 10, width = nil },
	{ name = "W05_VoidCannon", range = 20, width = 5 },
	{ name = "W06_AbyssalHammer", range = 18, width = nil },
} do
	local effect = effects and effects:FindFirstChild(spec.name)
	Check(effect and effect:IsA("Model") and effect.PrimaryPart ~= nil, "attack effect template exists: " .. spec.name)
	Check(effect and effect:GetAttribute("DesignRange") == spec.range, "attack effect design range: " .. spec.name)
	Check(effect and effect:GetAttribute("DesignWidth") == spec.width, "attack effect design width: " .. spec.name)
end

local character = Boundary.Character()
local view = Presentation.new()
view:Swing(2, 0)
Check(Boundary.loads == 0, "observers rely on animation replication")
view:Swing(1, 0)
local track = view.attack.track
Check(Boundary.loads == 1 and Boundary.plays == 1, "one immediate local playback")
view:HitStop(0.16,false)
Check(track.Speed==0,"predicted hit pauses swing")
view:Apply(0.16+Config.HitStopSeconds)
Check(track.Speed==1,"swing resumes original speed")
view:HitStop(0.16+Config.HitStopSeconds,true)
Check(track.Speed==0,"confirmed final can extend same stop")
view:Apply(0.16+Config.HitFinalStopSeconds)
Check(track.Speed==1,"extended stop restores speed")
Check(track.Priority == Roblox.Enum.AnimationPriority.Action and not track.Looped, "one-shot action priority")
view:Swing(1, Config.AttackCooldown)
Check(Boundary.loads == 1 and Boundary.plays == 2, "reuse track across attacks")
character.tool.Unequipped:Fire()
Check(view.attack == nil and not track.IsPlaying and Boundary.destroyed == 1, "unequip releases attack")
view:Swing(1, 1)
Boundary.Players.LocalPlayer.painting = true
Boundary.Players.LocalPlayer.paintingChanged:Fire()
Check(view.attack == nil, "painting interrupts attack")
local plays = Boundary.plays
view:Swing(1, 2)
Check(Boundary.plays == plays, "painting blocks prediction")
Boundary.Players.LocalPlayer.painting = false
view:Swing(1, 3)
character.humanoid.Health = 0
character.humanoid.Died:Fire()
Check(view.attack == nil, "death releases attack")
character = Boundary.Character()
view:Swing(1, 4)
Boundary.Players.LocalPlayer.CharacterRemoving:Fire()
Check(view.attack == nil, "respawn releases old track")
view:Swing(1, 5)
view.carriers[1] = true
view:Apply(5)
Check(view.attack and view.attack.track.IsPlaying, "starting carry keeps the current swing")
Check(view.attack.track.Priority == Roblox.Enum.AnimationPriority.Action2, "swing overrides carry pose when both tracks are playing")
Check(view.carry and view.carry.track and view.carry.track.IsPlaying, "carrying loads and plays carry animation")
Check(view.carry.track.Priority == Roblox.Enum.AnimationPriority.Action and view.carry.track.Looped, "carry track is looping action")
plays = Boundary.plays
view:Swing(1, 6)
Check(Boundary.plays == plays + 1 and view.attack.track.Priority == Roblox.Enum.AnimationPriority.Action2, "can swing while carrying")
view.carriers[1] = nil
view:Apply(6)
Check(view.carry == nil, "releasing carry stops and clears carry track")
Check(view.attack.track.Priority == Roblox.Enum.AnimationPriority.Action, "releasing carry restores normal swing priority")
view:StopSwing()
Boundary.failLoad = true
local ok = pcall(function() view:Swing(1, 7) end)
Check(ok and view.attack.track == nil, "unavailable animation does not block request caller")
local loads = Boundary.loads
view:Swing(1, 8)
Check(Boundary.loads == loads, "failed loads do not retry every attack")
Boundary.failLoad = false
view:Swing(1, 9, "rbxassetid://111111")
local loadsAfterFirstCustom = Boundary.loads
Check(loadsAfterFirstCustom == loads + 1, "loads first custom weapon animationId")
view:Swing(1, 10, "rbxassetid://222222")
Check(Boundary.loads == loadsAfterFirstCustom + 1, "loads second custom weapon animationId")
view:Swing(1, 11, "rbxassetid://111111")
Check(Boundary.loads == loadsAfterFirstCustom + 1, "reuses cached AnimationTrack when switching back")
local destroyedBeforeCleanup = Boundary.destroyed
view:Destroy()
Check(Boundary.destroyed == destroyedBeforeCleanup + 2, "releases all cached weapon tracks on destroy")
Check(view.attack == nil and view.preload == nil, "owner releases resources")
print(string.format("PASS: %d sword asset and presentation assertions (production module; mocked animator/events)", assertions))
