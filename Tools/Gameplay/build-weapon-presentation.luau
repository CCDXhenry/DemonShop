-- 给武器 Tool 补挥击动画和音效，并在 Effects 下生成范围攻击模板
--!strict
local DEFAULT_ANIM = "rbxassetid://18297503195"
local DEFAULT_SOUND = "rbxassetid://12222216"

local function EnsurePresentation(tool: Tool): ()
	local animation = tool:FindFirstChild("Slash")
	if not (animation and animation:IsA("Animation")) then
		if animation then
			animation:Destroy()
		end
		local created = Instance.new("Animation")
		created.Name = "Slash"
		created.AnimationId = DEFAULT_ANIM
		created.Parent = tool
	elseif animation.AnimationId == "" then
		animation.AnimationId = DEFAULT_ANIM
	end
	local sound = tool:FindFirstChild("SlashSound")
	if not (sound and sound:IsA("Sound")) then
		if sound then
			sound:Destroy()
		end
		local created = Instance.new("Sound")
		created.Name = "SlashSound"
		created.SoundId = DEFAULT_SOUND
		created.Volume = 0.85
		created.PlaybackSpeed = 1.05
		created.RollOffMode = Enum.RollOffMode.Inverse
		created.RollOffMinDistance = 10
		created.RollOffMaxDistance = 10000
		created.Looped = false
		created.Parent = tool
	elseif sound.SoundId == "" then
		sound.SoundId = DEFAULT_SOUND
	end
end

local function AddEnergy(model: Model, name: string, goal: CFrame, size: Vector3, color: Color3): ()
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = goal
	part.Size = size
	part.Transparency = 0.18
	part.Parent = model
end

local function BuildEffect(name: string, shape: string, range: number, width: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("DesignRange", range)
	if shape == "Line" then
		model:SetAttribute("DesignWidth", width)
		local finish = CFrame.new(0, 1, -range / 2)
		AddEnergy(model, "Lane", finish, Vector3.new(width, 0.14, range), Color3.fromRGB(113, 47, 192))
		AddEnergy(model, "Core", finish, Vector3.new(0.12, 0.16, range), Color3.fromRGB(211, 133, 255))
	else
		local cone, slam = shape == "Cone", shape == "Slam"
		local segments = if cone then 8 else 16
		local angle = if cone then math.rad(120) else math.pi * 2
		local color = if cone then Color3.fromRGB(237, 38, 67) elseif slam then Color3.fromRGB(253, 113, 53) else Color3.fromRGB(163, 61, 245)
		for index = 1, segments do
			local axis = CFrame.Angles(0, (index - 0.5) * angle / segments - angle / 2, 0)
			local span = 2 * math.sin(angle / segments / 2)
			AddEnergy(model, "Arc" .. tostring(index), axis * CFrame.new(0, 0, -range), Vector3.new(range * span, 0.08, 0.18), color)
			if slam then
				AddEnergy(model, "Spike" .. tostring(index), axis * CFrame.new(0, 0.5, -3), Vector3.new(0.09, 0.1, 1.2), Color3.fromRGB(172, 72, 255))
			end
		end
	end
	model.WorldPivot = CFrame.identity
	return model
end

local function Build(models: Folder): string
	local weapons = models:FindFirstChild("Weapons")
	assert(weapons and weapons:IsA("Folder"), "Models.Weapons folder is required")
	local createdSounds = 0
	for _, child in weapons:GetChildren() do
		if child:IsA("Tool") then
			local hadSound = child:FindFirstChild("SlashSound") ~= nil
			EnsurePresentation(child)
			if not hadSound then
				createdSounds += 1
			end
		end
	end
	local effects = models:FindFirstChild("Effects")
	if not effects then
		local folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = models
		effects = folder
	end
	assert(effects and effects:IsA("Folder"), "Models.Effects folder is required")
	local specs = {
		{ name = "W03_DemonScimitar", shape = "Cone", range = 8, width = 0 },
		{ name = "W04_ReaperScythe", shape = "Spin", range = 10, width = 0 },
		{ name = "W05_VoidCannon", shape = "Line", range = 20, width = 5 },
		{ name = "W06_AbyssalHammer", shape = "Slam", range = 18, width = 0 },
	}
	local createdEffects = 0
	for _, spec in specs do
		if not effects:FindFirstChild(spec.name) then
			local effect = BuildEffect(spec.name, spec.shape, spec.range, spec.width)
			effect.Parent = effects
			createdEffects += 1
		end
	end
	return string.format("weapon presentation ready: new sounds %d, new effects %d", createdSounds, createdEffects)
end

local function Run(): string
	local stored = game:GetService("ReplicatedStorage"):FindFirstChild("Models")
	assert(stored and stored:IsA("Folder") and not game:GetService("RunService"):IsRunning(), "Build weapon presentation under Models in Edit mode")
	return Build(stored)
end

if typeof(game) == "Instance" then
	return Run()
end
