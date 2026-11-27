-- 客户端业务资产预加载与预热装配层：声明 DemonShop 资源清单并串联 AssetPreloader 与 AssetWarmup
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local AssetPreloader = require(script.Parent.AssetPreloader)
local AssetWarmup = require(script.Parent.AssetWarmup)
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local GameData = require(ReplicatedStorage.Scripts.Shared.GameData)
local ModelTemplates = require(ReplicatedStorage.Scripts.Shared.ModelTemplates)

local Manager = {}

type Priority = number
type UnitWarmupKind = "Model" | "Effect" | "Sky"
export type TierStats = {
	collected: number,
	downloaded: number,
	failed: number,
	warmups: number,
	warmed: number,
	warmupFailed: number,
}
type Session = {
	preloader: AssetPreloader.Preloader,
	warmup: AssetWarmup.Warmup,
	unitWarmups: { [Instance]: UnitWarmupKind },
	connections: { RBXScriptConnection },
	toolConnection: RBXScriptConnection?,
}

local WarmupUriKinds: { [AssetPreloader.AssetKind]: boolean } = {
	Image = true,
	Decal = true,
	Animation = true,
	Sound = true,
	Video = true,
}

local DefaultSounds: { [string]: Priority } = {
	UIClick = 1,
	UIOpen = 1,
	UIClose = 1,
	BGM = 1,
	AttackSwing = 1,
	HitImpact = 1,
	BodyStun = 1,
	BodyPickup = 2,
	BodyDrop = 2,
	PotionPickup = 2,
}

local ProcessingSounds: { [string]: boolean } = {
	PaintComplete = true,
	PaintStroke = true,
	PoolRetrieve = true,
	PoolDeposit = true,
	AltarLoop = true,
	AltarComplete = true,
	AltarPlace = true,
	CoinReward = true,
}

local UiScopes: { [string]: { priority: Priority, group: string? } } = {
	GameScreenGui = { priority = 1 },
	PersonalHudFrame = { priority = 1 },
	TargetGui = { priority = 1 },
	WorldInteractionPrompt = { priority = 1 },
	PersonalShopFrame = { priority = 2, group = "Shop" },
	PaintFaceGui = { priority = 2, group = "Processing" },
	PaintCellFrame = { priority = 2, group = "Processing" },
	PaintRuneImage = { priority = 2, group = "Processing" },
}

local session: Session? = nil
local earlyPromotions: { [string]: boolean } = {}

local function GroupsToList(groups: { [string]: boolean }): { string }
	local list: { string } = {}
	for group in groups do
		table.insert(list, group)
	end
	return list
end

local function SkipLayoutGuide(node: Instance): boolean
	return node.Name ~= "ScreenLayoutGuideFrame"
end

local function ResolveModelWarmupKind(root: Instance): UnitWarmupKind?
	if not (root:IsA("Model") or root:IsA("Tool") or root:IsA("BasePart") or root:IsA("Attachment")) then
		return nil
	end
	for _, node in root:GetDescendants() do
		if node:IsA("ParticleEmitter") or node:IsA("Beam") or node:IsA("Trail") then
			return "Effect" :: UnitWarmupKind
		end
	end
	return "Model" :: UnitWarmupKind
end

local function RegisterBusinessAssets(run: Session): ()
	local preloader = run.preloader
	local starterWeapon = GameData.GetWeaponByLevel(1).model

	-- 1. 模型模板（ReplicatedStorage.Models）
	for _, category in ModelTemplates.Categories do
		local folder = ModelTemplates.GetCategory(category :: ModelTemplates.Category)
		if not folder or not folder.Archivable then
			continue
		end
		for _, root in folder:GetChildren() do
			if not root.Archivable then
				continue
			end
			local priority = 3
			local groups: { string } = {}
			if category == "Weapons" or category == "CarryRigs" then
				priority = if root.Name == starterWeapon then 1 else 2
				groups = { "Shop", "Equipment:" .. root.Name }
			elseif category == "Effects" then
				priority = if root.Name == "ThrowAim" then 2 else 3
				groups = { "Equipment:" .. root.Name }
			elseif category == "Items" then
				priority = 2
				groups = { "Equipment:" .. root.Name }
			elseif category == "Previews" then
				priority = 2
				groups = { "Shop" }
			elseif category == "Characters" and (root.Name == "WhiteR15" or root.Name == "WhiteR15-People") then
				priority = 1
			end
			local warmupKind: UnitWarmupKind? = ResolveModelWarmupKind(root)
			if warmupKind == "Effect" then
				run.unitWarmups[root] = "Effect"
			elseif warmupKind == "Model" then
				run.unitWarmups[root] = "Model"
			end
			preloader:AddTree(root, { priority = priority, groups = groups })
		end
	end

	-- 2. UI 模板（拆出 Image 单图预热，跳过设计参考与整棵 Gui 重克隆）
	local ui = ReplicatedStorage:FindFirstChild("UI")
	if ui then
		for _, root in ui:GetChildren() do
			if root.Name == "ScreenLayoutGuideFrame" then
				continue
			end
			local spec = UiScopes[root.Name]
			local priority = if spec then spec.priority else 3
			local groups = if spec and spec.group then { spec.group } else nil
			preloader:AddTree(root, { priority = priority, groups = groups, filter = SkipLayoutGuide })
		end
	end

	-- 3. 音效目录（ReplicatedStorage.Sounds）
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	if sounds then
		for _, root in sounds:GetChildren() do
			local priority = if ProcessingSounds[root.Name] then 2 else (DefaultSounds[root.Name] or 3)
			local groups = if ProcessingSounds[root.Name] then { "Processing" } else nil
			preloader:AddTree(root, { priority = priority, groups = groups })
		end
	end

	-- 4. 天空盒（Lighting.Sky）
	for _, root in Lighting:GetChildren() do
		if root:IsA("Sky") and root.Archivable then
			run.unitWarmups[root] = "Sky"
			preloader:AddTree(root, { priority = 1 })
		end
	end

	-- 5. 显式 GameConfig 常量资产
	local faces = Config.NpcFaceTextures :: { [string]: string }?
	if faces then
		for key, uri in faces do
			local isPainting = key == "Painting"
			preloader:AddUri(uri, "Decal", {
				priority = if isPainting then 2 else 1,
				groups = if isPainting then { "Processing" } else nil,
			})
		end
	end
	for _, uri in {
		Config.WeaponSlashAnimation,
		Config.BodyCarryAnimation,
		Config.IdleAnimation,
		Config.WalkAnimation,
		Config.NpcRunAnimation,
	} do
		preloader:AddUri(uri, "Animation", { priority = 1 })
	end
	preloader:AddUri(Config.WeaponSlashSound, "Sound", { priority = 1 })
	preloader:AddUri(Config.PotionIcon, "Image", { priority = 2, groups = { "Equipment:Potion" } })

	-- 6. GameData 武器与搬运工具表资产
	local shopGroup = { "Shop" }
	for _, weapon in GameData.GetAllWeapons() do
		local weaponPriority = if weapon.level == 1 then 1 else 3
		local weaponGroups = { "Equipment:" .. weapon.model }
		local animUri = if weapon.slashAnimation then weapon.slashAnimation.AnimationId else weapon.slashAnim
		local soundUri = if weapon.slashSoundTemplate then weapon.slashSoundTemplate.SoundId else weapon.slashSound
		preloader:AddUri(animUri, "Animation", { priority = weaponPriority, groups = weaponGroups })
		preloader:AddUri(soundUri, "Sound", { priority = weaponPriority, groups = weaponGroups })
		preloader:AddUri(weapon.icon, "Image", { priority = 2, groups = shopGroup })
	end
	for _, carryTool in GameData.GetAllCarryTools() do
		preloader:AddUri(carryTool.icon, "Image", { priority = 2, groups = shopGroup })
	end
end

local function BindEquipment(run: Session): ()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local function OnChildAdded(child: Instance)
		if session == run and child:IsA("Tool") then
			Manager.Promote("Equipment:" .. child.Name)
		end
	end
	local function OnCharacterAdded(character: Model)
		if run.toolConnection then
			run.toolConnection:Disconnect()
		end
		run.toolConnection = character.ChildAdded:Connect(OnChildAdded)
		for _, child in character:GetChildren() do
			OnChildAdded(child)
		end
	end
	table.insert(run.connections, player.CharacterAdded:Connect(OnCharacterAdded))
	if player.Character then
		OnCharacterAdded(player.Character)
	end
end

function Manager.PreloadAsync(targets: { Instance | string }, onAssetFetched: ((string, Enum.AssetFetchStatus) -> ())?): boolean
	return AssetPreloader.PreloadAsync(targets, onAssetFetched)
end

function Manager.Promote(group: string): ()
	if session then
		session.preloader:Promote(group)
		session.warmup:Promote(group)
	elseif group ~= "" then
		earlyPromotions[group] = true
	end
end

function Manager.GetStats(): { TierStats }
	local snapshot: { TierStats } = {}
	local run = session
	if not run then
		return snapshot
	end
	local progress = run.preloader:GetProgress()
	local warmupStats = run.warmup:GetStats()
	for index = 1, 3 do
		local dl = progress.byPriority[index]
		local wm = warmupStats.byPriority[index]
		snapshot[index] = {
			collected = if dl then dl.total else 0,
			downloaded = if dl then dl.succeeded else 0,
			failed = if dl then dl.failed else 0,
			warmups = if wm then wm.queued else 0,
			warmed = if wm then wm.warmed else 0,
			warmupFailed = if wm then wm.failed else 0,
		}
	end
	return snapshot
end

function Manager.Cancel(): ()
	local run = session
	session = nil
	table.clear(earlyPromotions)
	if not run then
		return
	end
	if run.toolConnection then
		run.toolConnection:Disconnect()
		run.toolConnection = nil
	end
	for _, connection in run.connections do
		connection:Disconnect()
	end
	table.clear(run.connections)
	run.preloader:Cancel()
	run.warmup:Cancel()
end

function Manager.PrepareGame(): ()
	if session then
		Manager.Cancel()
	end
	local warmup = AssetWarmup.new()
	local unitWarmups: { [Instance]: UnitWarmupKind } = {}

	local preloader = AssetPreloader.new({
		onUriReady = function(uri: string, kind: AssetPreloader.AssetKind, success: boolean, groups: { [string]: boolean }, priority: number)
			if not success or not WarmupUriKinds[kind] then
				return
			end
			warmup:Enqueue({
				key = kind .. ":" .. uri,
				kind = kind,
				uri = uri,
				priority = priority,
				groups = GroupsToList(groups),
			})
		end,
		onUnitReady = function(_unitId: string, root: Instance?, allSucceeded: boolean, groups: { [string]: boolean }, priority: number)
			if not allSucceeded or not root then
				return
			end
			local warmupKind = unitWarmups[root]
			if not warmupKind then
				return
			end
			warmup:Enqueue({
				key = root,
				kind = warmupKind,
				source = root,
				priority = priority,
				groups = GroupsToList(groups),
			})
		end,
	})

	for group in earlyPromotions do
		preloader:Promote(group)
		warmup:Promote(group)
	end
	table.clear(earlyPromotions)

	local run: Session = {
		preloader = preloader,
		warmup = warmup,
		unitWarmups = unitWarmups,
		connections = {},
		toolConnection = nil,
	}
	session = run

	RegisterBusinessAssets(run)
	BindEquipment(run)
	warmup:Start()
	preloader:Start()

	if not preloader:WaitForIdle() or session ~= run then
		return
	end
	warmup:WaitForIdle()
end

return Manager
