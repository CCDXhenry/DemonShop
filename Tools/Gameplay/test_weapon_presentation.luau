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
CheckSword(full[1]:FindFirstChild("Club"))
Check(single[1].Grip == full[1].Club.Grip, "restore archives share grip")

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
Check(view.attack == nil, "carry interrupts attack")
Check(view.carry and view.carry.track and view.carry.track.IsPlaying, "carrying loads and plays carry animation")
Check(view.carry.track.Priority == Roblox.Enum.AnimationPriority.Action and view.carry.track.Looped, "carry track is looping action")
plays = Boundary.plays
view:Swing(1, 6)
Check(Boundary.plays == plays, "carry blocks prediction")
view.carriers[1] = nil
view:Apply(6)
Check(view.carry == nil, "releasing carry stops and clears carry track")
Boundary.failLoad = true
local ok = pcall(function() view:Swing(1, 7) end)
Check(ok and view.attack.track == nil, "unavailable animation does not block request caller")
local loads = Boundary.loads
view:Swing(1, 8)
Check(Boundary.loads == loads, "failed loads do not retry every attack")
view:Destroy()
Check(view.attack == nil and view.preload == nil, "owner releases resources")
print(string.format("PASS: %d sword asset and presentation assertions (production module; mocked animator/events)", assertions))
