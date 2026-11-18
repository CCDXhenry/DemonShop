-- 玩家动作表现：肩扛原生动画与 Roblox 标准挥剑动画；本地播放由引擎复制
--!strict
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(game:GetService("ReplicatedStorage").Scripts.Shared.GameConfig)
local Presentation = {}
Presentation.__index = Presentation
type Joint = Motor6D | AnimationConstraint
type AttackCache = { character: Model, tool: Tool, humanoid: Humanoid, track: AnimationTrack?, connections: { RBXScriptConnection }, stopStarted: number?, stopEnds: number?, resumeSpeed: number? }
type CarryCache = { character: Model, humanoid: Humanoid, track: AnimationTrack?, connections: { RBXScriptConnection } }
type CharacterCache = { model: Model, joints: { Joint }, added: RBXScriptConnection }
export type Presentation = typeof(setmetatable({} :: {
	carriers: { [number]: boolean }, offsets: { [Joint]: CFrame },
	attack: AttackCache?, carry: CarryCache?, animation: Animation, carryAnimation: Animation, preload: thread?,
	characters: { [Player]: CharacterCache },
}, Presentation))
function Presentation.new(): Presentation
	local animation = Instance.new("Animation")
	animation.AnimationId = Config.WeaponSlashAnimation
	local carryAnimation = Instance.new("Animation")
	carryAnimation.AnimationId = Config.BodyCarryAnimation
	local self = setmetatable({ carriers = {}, offsets = {}, characters = {}, animation = animation, carryAnimation = carryAnimation, attack = nil :: AttackCache?, carry = nil :: CarryCache?, preload = nil :: thread? }, Presentation)
	self.preload = task.defer(function(): ()
		local ok, reason = pcall(function(): boolean
			ContentProvider:PreloadAsync({ animation, carryAnimation }, function(asset: string, status: Enum.AssetFetchStatus): ()
				if status ~= Enum.AssetFetchStatus.Success then warn("[Carry/Sword] 动画预加载失败", asset, status) end
			end)
			return true
		end)
		if not ok then warn("[Carry/Sword] 动画预加载失败", reason) end
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
function Presentation.StopCarry(self: Presentation): ()
	local carry = self.carry
	self.carry = nil
	if not carry then return end
	for _, connection in carry.connections do connection:Disconnect() end
	if carry.track then
		carry.track:Stop(Config.CarryAnimationFade)
		carry.track:Destroy()
	end
end
function Presentation.StartCarry(self: Presentation, character: Model, humanoid: Humanoid): ()
	local carry = self.carry
	if carry and carry.character == character and carry.track and carry.track.IsPlaying then return end
	self:StopCarry()
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then warn("[Carry] 缺少服务端 Animator，跳过肩扛动画"); return end
	local created: CarryCache = { character = character, humanoid = humanoid, track = nil, connections = {} }
	self.carry = created
	local function OnStop(): () self:StopCarry() end
	local player = Players.LocalPlayer
	table.insert(created.connections, humanoid.Died:Connect(OnStop))
	table.insert(created.connections, player.CharacterRemoving:Connect(OnStop))
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("[Carry] 肩扛动画需要 R15，跳过肩扛动画")
		return
	end
	local ok, result = pcall(function(): AnimationTrack return animator:LoadAnimation(self.carryAnimation) end)
	if not ok then warn("[Carry] 无法加载肩扛动画", result); return end
	result.Priority = Enum.AnimationPriority.Action
	result.Looped = true
	created.track = result
	result:Play(Config.CarryAnimationFade)
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
	if track and attack then
		attack.stopStarted, attack.stopEnds = nil, nil
		track:AdjustSpeed(1)
		track:Play(Config.WeaponAnimationFade)
		track.TimePosition = 0
	end
end
function Presentation.HitStop(self: Presentation, now: number, final: boolean): ()
	local attack = self.attack
	local track = if attack then attack.track else nil
	if not attack or not track or not track.IsPlaying then return end
	if not attack.stopStarted then
		attack.stopStarted = now
		attack.resumeSpeed = track.Speed
	end
	local ends = (attack.stopStarted :: number) + (if final then Config.HitFinalStopSeconds else Config.HitStopSeconds)
	if ends <= now then return end
	attack.stopEnds = ends
	track:AdjustSpeed(0)
end
function Presentation.Apply(self: Presentation, now: number): ()
	local attack = self.attack
	if attack and attack.stopEnds and now >= attack.stopEnds then
		if attack.track then attack.track:AdjustSpeed(attack.resumeSpeed or 1) end
		attack.stopEnds = nil
	end
	local localPlayer = Players.LocalPlayer
	local localChar = localPlayer.Character
	local localHumanoid = localChar and localChar:FindFirstChildOfClass("Humanoid")
	local isCarrier = self.carriers[localPlayer.UserId] == true
	if isCarrier and localChar and localHumanoid and localHumanoid.Health > 0 then
		self:StartCarry(localChar, localHumanoid)
	else
		if self.carry then self:StopCarry() end
	end
	if attack and (localChar ~= attack.character or attack.tool.Parent ~= attack.character
		or attack.humanoid.Health <= 0 or isCarrier) then self:StopSwing() end
	for player, cached in self.characters do
		if not player.Parent or player.Character ~= cached.model then
			cached.added:Disconnect()
			self.characters[player], self.carriers[player.UserId] = nil, nil
		end
	end
end
function Presentation.Destroy(self: Presentation): ()
	self:Restore()
	self:StopSwing()
	self:StopCarry()
	if self.preload then task.cancel(self.preload); self.preload = nil end
	self.animation:Destroy()
	self.carryAnimation:Destroy()
	for _, cached in self.characters do cached.added:Disconnect() end
	table.clear(self.characters)
	table.clear(self.carriers)
end
return Presentation
