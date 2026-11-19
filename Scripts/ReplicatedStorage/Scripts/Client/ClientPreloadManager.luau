-- 客户端资源预加载与离屏预渲染：下载动画、模型、界面和声音，并在使用前编译着色器
--!strict
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)

local Manager = {}

export type WarmupOptions = {
	offscreenPosition: Vector3?,
	warmupFrames: number?,
	hideAfterWarmup: boolean?,
}

local LogPrefix = "[ClientPreloadManager]"
local LayoutGuideName = "ScreenLayoutGuideFrame"
local SlashSoundName = "WeaponSlash"
local EffectAnchorName = "PreloadEffectAnchor"
local WarmupPosition = Vector3.new(0, -1000, 0)
local WarmupFrameCount = 2
local WarmupAnimationFade = 0
local WarmupAnimationWeight = 0.0001
local WarmupAnimationSpeed = 0.0001
local WarmupParticleCount = 1
local CharacterWaitSeconds = 5
local DummyPartSize = Vector3.one
local DummyPartTransparency = 1

local generation = 0
local characterConnection: RBXScriptConnection? = nil
local heldAnimations: { Animation } = {}
local heldSlashSound: Sound? = nil

local function IsCurrent(token: number): boolean
	return token == generation
end

local function ReleaseAssets(animations: { Animation }, sound: Sound?)
	for _, animation in animations do
		animation:Destroy()
	end
	if sound ~= nil then
		sound:Destroy()
	end
end

local function ResolvePosition(options: WarmupOptions?): Vector3
	if options ~= nil and options.offscreenPosition ~= nil then
		return options.offscreenPosition
	end
	return WarmupPosition
end

local function ResolveFrames(options: WarmupOptions?): number
	if options ~= nil and options.warmupFrames ~= nil then
		return math.max(1, options.warmupFrames)
	end
	return WarmupFrameCount
end

local function ResolveHide(options: WarmupOptions?): boolean
	if options ~= nil and options.hideAfterWarmup ~= nil then
		return options.hideAfterWarmup
	end
	return true
end

local function WaitFrames(frames: number)
	for _ = 1, frames do
		RunService.Heartbeat:Wait()
	end
end

local function EmitOnce(emitter: ParticleEmitter)
	emitter:Emit(WarmupParticleCount)
end

local function EmitParticles(root: Instance)
	if root:IsA("ParticleEmitter") then
		pcall(EmitOnce, root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			pcall(EmitOnce, descendant)
		end
	end
end

local function PlaceOffscreen(instance: Instance, position: Vector3): boolean
	local pose = CFrame.new(position)
	if instance:IsA("Model") then
		instance.Parent = workspace
		instance:PivotTo(pose)
		return true
	elseif instance:IsA("BasePart") then
		instance.Parent = workspace
		instance.CFrame = pose
		return true
	elseif instance:IsA("Tool") then
		instance.Parent = workspace
		local handle = instance:FindFirstChild("Handle") :: BasePart?
		if handle ~= nil then
			handle.CFrame = pose
		end
		return true
	end
	return false
end

local function RestoreParents(attached: { Instance }, parents: { [Instance]: Instance? })
	for _, instance in attached do
		if instance.Parent == workspace then
			instance.Parent = parents[instance]
		end
	end
end

local function FinishInstanceWarmup(frames: number, hideAfterWarmup: boolean, attached: { Instance }, parents: { [Instance]: Instance? })
	WaitFrames(frames)
	if hideAfterWarmup then
		RestoreParents(attached, parents)
	end
end

local function DestroyRoots(roots: { Instance })
	for _, instance in roots do
		instance:Destroy()
	end
end

local function FinishEffectWarmup(frames: number, roots: { Instance })
	WaitFrames(frames)
	DestroyRoots(roots)
end

local function CreateEffectAnchor(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = EffectAnchorName
	part.Size = DummyPartSize
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = DummyPartTransparency
	part.CFrame = CFrame.new(position)
	return part
end

local function LoadTrack(animator: Animator, animation: Animation): AnimationTrack
	return animator:LoadAnimation(animation)
end

local function PlayWarmup(track: AnimationTrack)
	track:Play(WarmupAnimationFade, WarmupAnimationWeight, WarmupAnimationSpeed)
end

local function StopWarmup(track: AnimationTrack)
	track:Stop(WarmupAnimationFade)
end

local function StopWarmupLater(track: AnimationTrack)
	pcall(StopWarmup, track)
end

local function RequestPreload(targets: { Instance | string }, onAssetFetched: ((string, Enum.AssetFetchStatus) -> ())?): boolean
	ContentProvider:PreloadAsync(targets, onAssetFetched)
	return true
end

local function CreateAnimation(animationId: string): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	return animation
end

local function CreateConfiguredAnimations(): { Animation }
	local animations: { Animation } = {}
	local animationIds = {
		Config.WeaponSlashAnimation,
		Config.BodyCarryAnimation,
		Config.IdleAnimation,
		Config.WalkAnimation,
	}
	for _, animationId in animationIds do
		if animationId ~= "" then
			table.insert(animations, CreateAnimation(animationId))
		end
	end
	return animations
end

local function CreateSlashSound(): Sound?
	if Config.WeaponSlashSound == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = SlashSoundName
	sound.SoundId = Config.WeaponSlashSound
	return sound
end

local function CollectModels(assets: { Instance }, templates: { Instance })
	local folder = ReplicatedStorage:FindFirstChild("Models")
	if folder == nil then
		warn(string.format("%s missing ReplicatedStorage.Models", LogPrefix))
		return
	end
	for _, child in folder:GetChildren() do
		if child.Archivable and (child:IsA("Model") or child:IsA("Tool")) then
			table.insert(assets, child)
			table.insert(templates, child)
		end
	end
end

local function CollectUserInterface(assets: { Instance })
	local folder = ReplicatedStorage:FindFirstChild("UI")
	if folder == nil then
		warn(string.format("%s missing ReplicatedStorage.UI", LogPrefix))
		return
	end
	for _, child in folder:GetChildren() do
		if child.Name ~= LayoutGuideName then
			table.insert(assets, child)
		end
	end
end

local function CollectSounds(assets: { Instance })
	local folder = ReplicatedStorage:FindFirstChild("Sounds")
	if folder == nil then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Sound") and child.SoundId ~= "" then
			table.insert(assets, child)
		end
	end
end

local function WarmupTemplates(templates: { Instance }, token: number)
	local clones: { Instance } = {}
	for _, template in templates do
		if not IsCurrent(token) then
			break
		end
		local clone = template:Clone()
		if PlaceOffscreen(clone, WarmupPosition) then
			EmitParticles(clone)
			table.insert(clones, clone)
		else
			clone:Destroy()
		end
	end
	if IsCurrent(token) then
		WaitFrames(WarmupFrameCount)
	end
	DestroyRoots(clones)
end

local function OnCharacterAdded(character: Model)
	local token = generation
	local humanoidInstance = character:WaitForChild("Humanoid", CharacterWaitSeconds)
	if not IsCurrent(token) or humanoidInstance == nil or not humanoidInstance:IsA("Humanoid") then
		return
	end
	local animatorInstance = humanoidInstance:WaitForChild("Animator", CharacterWaitSeconds)
	if not IsCurrent(token) or animatorInstance == nil or not animatorInstance:IsA("Animator") then
		return
	end
	local animations = table.clone(heldAnimations)
	if not IsCurrent(token) then
		return
	end
	Manager.WarmupAnimations(animatorInstance, animations)
end

local function BindCharacterWarmup(token: number)
	if not IsCurrent(token) then
		return
	end
	if characterConnection ~= nil then
		characterConnection:Disconnect()
	end
	characterConnection = Players.LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)
	local character = Players.LocalPlayer.Character
	if character ~= nil then
		task.spawn(OnCharacterAdded, character)
	end
end

-- 空列表直接成功；下载失败只警告，不阻止进入游戏。
function Manager.PreloadAsync(targets: { Instance | string }, onAssetFetched: ((string, Enum.AssetFetchStatus) -> ())?): boolean
	if #targets == 0 then
		return true
	end
	local success, reason = pcall(RequestPreload, targets, onAssetFetched)
	if not success then
		warn(string.format("%s PreloadAsync warning: %s", LogPrefix, tostring(reason)))
	end
	return success
end

-- 把模型、零件或工具挂到离屏位置渲染数帧。调用方传入的实例会被临时改挂父级。
function Manager.WarmupInstances(instances: { Instance }, options: WarmupOptions?)
	local position = ResolvePosition(options)
	local frames = ResolveFrames(options)
	local hideAfterWarmup = ResolveHide(options)
	local attached: { Instance } = {}
	local parents: { [Instance]: Instance? } = {}
	for _, instance in instances do
		if instance:IsA("Model") or instance:IsA("BasePart") or instance:IsA("Tool") then
			parents[instance] = instance.Parent
			if PlaceOffscreen(instance, position) then
				table.insert(attached, instance)
			end
		end
	end
	if #attached == 0 then
		return
	end
	task.spawn(FinishInstanceWarmup, frames, hideAfterWarmup, attached, parents)
end

-- 在目标 Animator 上以极小权重播放一帧，完成骨骼与动画资源的首次编译。
function Manager.WarmupAnimations(animator: Animator, animations: { Animation }): { AnimationTrack }
	local tracks: { AnimationTrack } = {}
	for _, animation in animations do
		local ok, result = pcall(LoadTrack, animator, animation)
		if ok and typeof(result) == "Instance" and result:IsA("AnimationTrack") then
			pcall(PlayWarmup, result)
			task.defer(StopWarmupLater, result)
			table.insert(tracks, result)
		end
	end
	return tracks
end

-- 克隆特效到离屏处，发射一颗粒子以编译粒子着色器，数帧后销毁克隆。
function Manager.WarmupEffects(effectTemplates: { Instance }, options: WarmupOptions?)
	local position = ResolvePosition(options)
	local frames = ResolveFrames(options)
	local roots: { Instance } = {}
	for _, template in effectTemplates do
		local cloned = template:Clone()
		if cloned:IsA("Model") or cloned:IsA("BasePart") then
			PlaceOffscreen(cloned, position)
			table.insert(roots, cloned)
		elseif cloned:IsA("Attachment") then
			local anchor = CreateEffectAnchor(position)
			cloned.Parent = anchor
			anchor.Parent = workspace
			table.insert(roots, anchor)
		else
			cloned:Destroy()
		end
	end
	if #roots == 0 then
		return
	end
	for _, root in roots do
		EmitParticles(root)
	end
	task.spawn(FinishEffectWarmup, frames, roots)
end

-- 后台收集本局资源并预渲染克隆。取消后在途任务不再继续挂载。
function Manager.PrepareGame()
	local token = generation
	local animations = CreateConfiguredAnimations()
	local slashSound = CreateSlashSound()
	heldAnimations = animations
	heldSlashSound = slashSound
	local assets: { Instance } = {}
	local templates: { Instance } = {}
	for _, animation in animations do
		table.insert(assets, animation)
	end
	CollectModels(assets, templates)
	CollectUserInterface(assets)
	CollectSounds(assets)
	if slashSound ~= nil then
		table.insert(assets, slashSound)
	end
	if not IsCurrent(token) then
		return
	end
	Manager.PreloadAsync(assets)
	if not IsCurrent(token) then
		return
	end
	WarmupTemplates(templates, token)
	BindCharacterWarmup(token)
end

function Manager.Cancel()
	generation += 1
	if characterConnection ~= nil then
		characterConnection:Disconnect()
		characterConnection = nil
	end
	ReleaseAssets(heldAnimations, heldSlashSound)
	table.clear(heldAnimations)
	heldSlashSound = nil
end

return Manager
