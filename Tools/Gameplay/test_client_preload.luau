-- 回归 AssetPreloader、AssetWarmup 独立单测及 ClientPreloadManager 业务集成
local AssetPreloader = require("./AssetPreloader")
local AssetWarmup = require("./AssetWarmup")
local Manager = require("./ClientPreloadManager")
local Boundary = require("./ClientPreloadBoundary")
local Config = require("./GameConfig")
local GameData = require("./GameData")

local assertions = 0
local function Check(value, message)
	assert(value, message)
	assertions += 1
end

local function FindBatch(uri)
	for index, batch in Boundary.batches do
		if table.find(batch, uri) then
			return index
		end
	end
	error("Missing URI " .. uri)
end

-- =========================================================================
-- 1. AssetPreloader 独立单元测试
-- =========================================================================
Check(AssetPreloader.PreloadAsync({}) == true, "empty PreloadAsync succeeds")
Check(#Boundary.batches == 0, "empty PreloadAsync does not call ContentProvider")

do
	Boundary.Reset()
	local readyEvents = {}
	local unitEvents = {}
	local progressSnapshots = {}
	local preloader = AssetPreloader.new({
		batchSize = 2,
		maxRetries = 1,
		onProgress = function(snapshot)
			table.insert(progressSnapshots, snapshot)
		end,
		onUriReady = function(uri, kind, success, groups, priority)
			table.insert(readyEvents, { uri = uri, kind = kind, success = success, groups = groups, priority = priority })
		end,
		onUnitReady = function(unitId, root, allSucceeded, groups, priority)
			table.insert(unitEvents, { id = unitId, root = root, success = allSucceeded, groups = groups, priority = priority })
		end,
	})

	-- URL 归一化去重 + 同 URI 多 Kind 分流 + P1 合并优先
	preloader:AddUri("https://www.roblox.com/asset/?id=101", "Image", { priority = 3, groups = { "Shop" } })
	preloader:AddUri("rbxassetid://101", "Decal", { priority = 1, groups = { "Opening" } })
	preloader:AddUri("rbxassetid://102", "Sound", { priority = 3, groups = { "LateGroup" } })
	preloader:AddUri("rbxassetid://103", "Image", { priority = 2 })
	Boundary.failures["rbxassetid://104"] = 2
	local unitFolder = Boundary.Instance.new("Model")
	unitFolder.Name = "FailedUnit"
	local decal = Boundary.Instance.new("Decal")
	decal.Texture = "rbxassetid://104"
	decal.Parent = unitFolder
	preloader:AddTree(unitFolder, { priority = 3, id = "FailedUnitId" })

	preloader:Promote("LateGroup")
	preloader:Start()
	Check(preloader:WaitForPriority(1) == true, "WaitForPriority completes")
	Check(preloader:WaitForIdle() == true, "WaitForIdle completes")

	Check(Boundary.preloadedUris["rbxassetid://101"] == 1, "normalized URI preloaded once")
	local kinds101 = {}
	for _, ev in readyEvents do
		if ev.uri == "rbxassetid://101" then
			kinds101[ev.kind] = ev
		end
	end
	Check(kinds101.Image ~= nil and kinds101.Decal ~= nil, "same URI fires callback per registered kind")
	Check(kinds101.Image.priority == 1 and kinds101.Image.groups.Shop and kinds101.Image.groups.Opening, "duplicate URI merges priority and groups")
	Check(FindBatch("rbxassetid://101") < FindBatch("rbxassetid://102"), "P1 outranks promoted group")
	Check(FindBatch("rbxassetid://102") < FindBatch("rbxassetid://103"), "promoted group outranks unpromoted P2")
	Check(#progressSnapshots > 0 and progressSnapshots[#progressSnapshots].total == 4, "progress snapshots report total")

	local failedUnitFound = false
	for _, ev in unitEvents do
		if ev.id == "FailedUnitId" then
			failedUnitFound = true
			Check(ev.success == false, "unit fails when dependency permanently fails")
		end
	end
	Check(failedUnitFound, "onUnitReady triggered for unit with failed dependency")

	-- 运行期动态追加（idle 后再 AddUri 自动唤醒）
	preloader:AddUri("rbxassetid://105", "Image", { priority = 2, groups = { "Dynamic" } })
	Check(preloader:WaitForGroup("Dynamic") == true, "WaitForGroup completes dynamically added asset")
	Check(Boundary.preloadedUris["rbxassetid://105"] == 1, "idle preloader wakes up for newly added asset")
	preloader:Destroy()
end

-- =========================================================================
-- 2. AssetWarmup 独立单元测试
-- =========================================================================
do
	Boundary.Reset()
	local customCalled = 0
	local warmup = AssetWarmup.new({
		batchSize = 2,
		heavyPerBatch = 2,
		holdFrames = 1,
	})
	warmup:RegisterHandler("CustomAtlas", function(taskItem, context)
		customCalled += 1
		local label = Boundary.Instance.new("ImageLabel")
		label.Image = taskItem.uri or ""
		label.Parent = context.slot
	end)

	-- 入队 3 个轻量 + 3 个重型，验证跨批次复用同一舞台 + 重型每批上限 2
	warmup:Enqueue({ key = "img1", kind = "Image", uri = "rbxassetid://201", priority = 1 })
	warmup:Enqueue({ key = "img2", kind = "Image", uri = "rbxassetid://202", priority = 1 })
	warmup:Enqueue({ key = "custom", kind = "CustomAtlas", uri = "rbxassetid://203", priority = 2 })
	for i = 1, 3 do
		local m = Boundary.Instance.new("Model")
		m.Name = "HeavyModel" .. tostring(i)
		warmup:Enqueue({ key = m, kind = "Model", source = m, priority = 2 })
	end

	-- Effect 在有 CurrentCamera 时放到视锥前方 (-10)，无相机时安全回退
	Boundary.currentCamera = { CFrame = Boundary.CFrame.new(10, 20, 30) }
	local fx = Boundary.Instance.new("Model")
	fx.Name = "SampleFx"
	local emitter = Boundary.Instance.new("ParticleEmitter")
	emitter.Parent = fx
	warmup:Enqueue({ key = fx, kind = "Effect", source = fx, priority = 3 })

	warmup:Start()
	Check(warmup:WaitForIdle() == true, "AssetWarmup WaitForIdle succeeds")
	Check(Boundary.stageCreateCount == 1, "AssetWarmup reuses single stage across multiple batches")
	Check(customCalled == 1, "RegisterHandler executes custom warmup")
	Check(Boundary.renderedImages["rbxassetid://203"] == true, "custom handler uses context slot")
	Check(#Boundary.renderedEffects == 1 and Boundary.renderedEffects[1].Z == 20, "Effect stages in front of CurrentCamera")
	Check(#Boundary.playerGui:GetChildren() == 0 and #Boundary.workspace:GetChildren() == 0, "AssetWarmup releases stage after idle")

	local wstats = warmup:GetStats()
	Check(wstats.queued == 7 and wstats.warmed == 7 and wstats.failed == 0, "AssetWarmup stats match queued and warmed")
	warmup:Destroy()
end

-- =========================================================================
-- 3. ClientPreloadManager 业务装配集成回归
-- =========================================================================
Boundary.Reset()
local decal = Boundary.Instance.new("Decal")
decal.Texture = Config.NpcFaceTextures.Normal
decal.Parent = Boundary.template.Head
local sharedImage = Boundary.Instance.new("ImageLabel")
sharedImage.Image = decal.Texture
sharedImage.Parent = Boundary.ReplicatedStorage.UI.GameScreenGui

local parent = Boundary.template.Parent
local promoted = false
Boundary.onFetch = function()
	if not promoted then
		promoted = true
		Manager.Promote("Shop")
		Manager.Promote("Shop")
		Boundary.Equip(GameData.GetAllWeapons()[#GameData.GetAllWeapons()].model)
	end
end
Boundary.failures[Boundary.lateImage] = 1
Boundary.failures[Boundary.alwaysFails] = 2
Manager.PrepareGame()

Check(Boundary.template.Parent == parent, "warmup keeps the source template parent")
Check(#Boundary.workspace:GetChildren() == 0, "warmup releases all world instances")
Check(#Boundary.playerGui:GetChildren() == 0, "warmup releases all GUI instances")
for key, uri in Config.NpcFaceTextures do
	Check(Boundary.preloadedUris[uri] == 1, "face preloaded once: " .. key)
	Check(Boundary.renderedDecals[uri] == true, "face decal rendered: " .. key)
end
Check(Boundary.renderedImages[Config.NpcFaceTextures.Normal], "same URI keeps separate image and decal warmups")
for _, weapon in GameData.GetAllWeapons() do
	Check(Boundary.preloadedUris[weapon.slashAnim] == 1, "weapon animation loaded: " .. weapon.id)
	Check(Boundary.preloadedUris[weapon.slashSound] == 1, "weapon sound loaded: " .. weapon.id)
	Check(Boundary.preloadedUris[weapon.icon] == 1 and Boundary.renderedImages[weapon.icon], "weapon icon warmed: " .. weapon.id)
end
for _, carryTool in GameData.GetAllCarryTools() do
	Check(Boundary.preloadedUris[carryTool.icon] == 1 and Boundary.renderedImages[carryTool.icon], "carry tool icon warmed: " .. carryTool.id)
end
for _, uri in { Config.WeaponSlashAnimation, Config.BodyCarryAnimation, Config.IdleAnimation, Config.WalkAnimation, Config.WeaponSlashSound } do
	Check(Boundary.preloadedUris[uri] == 1, "configured resource submitted once: " .. uri)
end
for _, uri in { Config.PotionIcon, Boundary.sampleImage, Boundary.sampleAttributeImage, Boundary.sampleButtonImage, Boundary.addedImage } do
	Check(Boundary.preloadedUris[uri] == 1 and Boundary.renderedImages[uri], "image loaded and drawn: " .. uri)
end
Check(Boundary.preloadedUris[Boundary.guideImage] == nil, "layout guide image excluded")
Check(Boundary.renderedModels[Boundary.template.Name], "character template rendered")
Check(not Boundary.renderedModels[Boundary.hidden.Name], "non-archivable template excluded")
Check(Boundary.preloadedUris[Boundary.newModelMesh] == 1 and Boundary.renderedModels[Boundary.newTemplate.Name], "new model contents automatically collected")
Check(FindBatch(Boundary.sampleButtonImage) < FindBatch(Boundary.shopImage), "first screen outranks an early shop promotion")
Check(FindBatch(Boundary.shopImage) < FindBatch(Config.NpcFaceTextures.Painting), "promoted shop precedes ordinary gameplay")
local upgraded = GameData.GetAllWeapons()[#GameData.GetAllWeapons()]
Check(FindBatch(upgraded.slashAnim) < FindBatch(Config.NpcFaceTextures.Painting), "promoted equipment precedes ordinary gameplay")
Check(Boundary.preloadedUris[Boundary.lateImage] == 2 and Boundary.renderedImages[Boundary.lateImage], "a transient failure retries and warms")
Check(Boundary.preloadedUris[Boundary.alwaysFails] == 2, "permanent failure retries once")
Check(Boundary.renderedImages[Boundary.alwaysFails] == nil, "permanent failure does not trigger warmup")
Check(Boundary.preloadedUris[Boundary.addedImage] == 1, "failure did not stop remaining downloads")
local stats = Manager.GetStats()
Check(stats[3].failed == 1 and stats[3].downloaded > 0, "download totals report failure and success")
Check(stats[1].warmups == stats[1].warmed and stats[1].warmups > 0, "opening warmup totals")
Manager.Cancel()

Boundary.Reset()
Boundary.onFetch = function()
	Manager.Cancel()
end
Manager.PrepareGame()
Check(#Boundary.batches == 1, "cancelling an in-flight download prevents remaining batches")
Check(next(Boundary.renderedDecals) == nil, "cancel ignores late download callbacks")
Check(#Manager.GetStats() == 0 and #Boundary.playerGui:GetChildren() == 0, "cancel clears session and GUI")

Boundary.Reset()
Boundary.onRender = function()
	Manager.Cancel()
end
Manager.PrepareGame()
Check(#Boundary.playerGui:GetChildren() == 0 and #Boundary.workspace:GetChildren() == 0, "cancel releases live warmup instances")
print(string.format("PASS: %d client preload assertions", assertions))
