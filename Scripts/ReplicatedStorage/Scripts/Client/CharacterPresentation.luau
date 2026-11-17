-- 玩家动作表现：肩扛关节叠加与 Roblox 标准挥剑动画；本地播放由引擎复制
--!strict
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(game:GetService("ReplicatedStorage").Scripts.Shared.GameConfig)
local Presentation = {}
Presentation.__index = Presentation
type Joint = Motor6D | AnimationConstraint
type AttackCache = { character: Model, tool: Tool, humanoid: Humanoid, track: AnimationTrack?, connections: { RBXScriptConnection } }
type CharacterCache = { model: Model, joints: { Joint }, added: RBXScriptConnection }
export type Presentation = typeof(setmetatable({} :: {
	carriers: { [number]: boolean }, offsets: { [Joint]: CFrame },
	attack: AttackCache?, animation: Animation, preload: thread?,
	characters: { [Player]: CharacterCache },
}, Presentation))
function Presentation.new(): Presentation
	local animation = Instance.new("Animation")
	animation.AnimationId = Config.WeaponSlashAnimation
	local self = setmetatable({ carriers = {}, offsets = {}, characters = {}, animation = animation, attack = nil :: AttackCache?, preload = nil :: thread? }, Presentation)
	self.preload = task.defer(function(): ()
		local ok, reason = pcall(function(): boolean
			ContentProvider:PreloadAsync({ animation }, function(asset: string, status: Enum.AssetFetchStatus): ()
				if status ~= Enum.AssetFetchStatus.Success then warn("[Sword] 动画预加载失败", asset, status) end
			end)
			return true
		end)
		if not ok then warn("[Sword] 动画预加载失败", reason) end
		self.preload = nil
	end)
	return self
end
function Presentation.Joints(self: Presentation, player: Player, character: Model): { Joint }
	local cached = self.characters[player]
	if cached and cached.model == character then return cached.joints end
	if cached then cached.added:Disconnect() end
	local joints: { Joint } = {}
	local function OnJoint(instance: Instance): ()
		if instance:IsA("Motor6D") or instance:IsA("AnimationConstraint") then table.insert(joints, instance) end
	end
	for _, instance in character:GetDescendants() do OnJoint(instance) end
	self.characters[player] = {model=character,joints=joints,added=character.DescendantAdded:Connect(OnJoint)}
	return joints
end
function Presentation.Restore(self: Presentation): ()
	for joint, offset in self.offsets do
		if joint.Parent then
			if joint:IsA("Motor6D") then joint.Transform = offset:Inverse() * joint.Transform
			elseif joint:IsA("AnimationConstraint") then joint.Transform = offset:Inverse() * joint.Transform end
		end
	end
	table.clear(self.offsets)
end
function Presentation.StopSwing(self: Presentation): ()
	local attack = self.attack
	self.attack = nil
	if not attack then return end
	for _, connection in attack.connections do connection:Disconnect() end
	if attack.track then
		attack.track:Stop(Config.WeaponAnimationFade)
		attack.track:Destroy()
	end
end
function Presentation.Swing(self: Presentation, userId: number, _started: number): ()
	local player = Players.LocalPlayer
	if userId ~= player.UserId then return end
	local character = player.Character
	local tool = character and character:FindFirstChild("Club")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not tool or not tool:IsA("Tool") or not humanoid or humanoid.Health <= 0
		or self.carriers[userId] or player:GetAttribute("Painting") == true then return end
	local attack = self.attack
	if attack and (attack.character ~= character or attack.tool ~= tool) then self:StopSwing(); attack = nil end
	if not attack then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then warn("[Sword] 缺少服务端 Animator，跳过攻击动画"); return end
		local created: AttackCache = { character = character, tool = tool, humanoid = humanoid, track = nil, connections = {} }
		self.attack, attack = created, created
		local function OnStop(): () self:StopSwing() end
		table.insert(created.connections, tool.Unequipped:Connect(OnStop))
		table.insert(created.connections, humanoid.Died:Connect(OnStop))
		table.insert(created.connections, player.CharacterRemoving:Connect(OnStop))
		table.insert(created.connections, player:GetAttributeChangedSignal("Painting"):Connect(function(): ()
			if player:GetAttribute("Painting") == true then OnStop() end
		end))
		if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			warn("[Sword] 官方挥剑动画需要 R15，跳过攻击动画")
			return
		end
		local ok, result = pcall(function(): AnimationTrack return animator:LoadAnimation(self.animation) end)
		if not ok then warn("[Sword] 无法加载标准挥剑动画", result); return end
		result.Priority = Enum.AnimationPriority.Action
		result.Looped = false
		created.track = result
	end
	local track = if attack then attack.track else nil
	if track then
		track:Play(Config.WeaponAnimationFade)
		track.TimePosition = 0
	end
end
function Presentation.Apply(self: Presentation, _now: number): ()
	local attack = self.attack
	if attack and (Players.LocalPlayer.Character ~= attack.character or attack.tool.Parent ~= attack.character
		or attack.humanoid.Health <= 0 or self.carriers[Players.LocalPlayer.UserId]) then self:StopSwing() end
	for player, cached in self.characters do
		if not player.Parent or player.Character ~= cached.model then
			cached.added:Disconnect()
			self.characters[player], self.carriers[player.UserId] = nil, nil
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then continue end
		local offsets: { [string]: CFrame } = {}
		if self.carriers[player.UserId] then
			offsets.RightShoulder = CFrame.Angles(math.rad(-105), 0, math.rad(25))
			offsets.RightElbow = CFrame.Angles(math.rad(-65), 0, 0)
			offsets.LeftShoulder = CFrame.Angles(math.rad(-70), 0, math.rad(-25))
			offsets.Waist = CFrame.Angles(0, 0, math.rad(-6))
		end
		if next(offsets) then
			for _, joint in self:Joints(player, character) do
				local offset = offsets[joint.Name]
				if offset and joint.Parent then
					if joint:IsA("Motor6D") then joint.Transform = offset * joint.Transform
					elseif joint:IsA("AnimationConstraint") then joint.Transform = offset * joint.Transform end
					self.offsets[joint] = offset
				end
			end
		end
	end
end
function Presentation.Destroy(self: Presentation): ()
	self:Restore()
	self:StopSwing()
	if self.preload then task.cancel(self.preload); self.preload = nil end
	self.animation:Destroy()
	for _, cached in self.characters do cached.added:Disconnect() end
	table.clear(self.characters)
	table.clear(self.carriers)
end
return Presentation
