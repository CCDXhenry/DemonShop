-- 工作台镜头：基于公共 FixedCamera 的可取消进出过渡、重入保护、运行期热调和角色复活后的相机归还
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local FixedCamera = require(ReplicatedStorage.Scripts.Shared.FixedCamera)

local Controller = {}
Controller.__index = Controller
export type Saved = FixedCamera.SavedCameraState
type TossFollow = { started: number, ends: number, duration: number, origin: CFrame, focus: Vector3, target: () -> Vector3? }
export type Controller = typeof(setmetatable({} :: {
	core: FixedCamera.Controller,
	saved: Saved?,
	ready: boolean,
	follow: TossFollow?,
}, Controller))

function Controller.new(): Controller
	local holder: { owner: Controller? } = { owner = nil }
	local core = FixedCamera.CreateController({
		defaultFov = 45,
		defaultDuration = Config.PaintCameraSeconds,
		enableHotReload = true,
		onReadyChanged = function(ready: boolean): ()
			if holder.owner then
				holder.owner.ready = ready
			end
		end,
		onRestored = function(): ()
			if holder.owner then
				holder.owner.saved = nil
				holder.owner.ready = false
			end
		end,
	})
	local self = setmetatable({
		core = core,
		saved = nil :: Saved?,
		ready = false,
		follow = nil :: TossFollow?,
	}, Controller)
	holder.owner = self
	return self
end

function Controller.Cancel(self: Controller): ()
	self.follow = nil
	self.core:Cancel()
end

function Controller.Restore(self: Controller): ()
	self.follow = nil
	self.core:Restore()
	self.saved = self.core.saved
	self.ready = self.core.ready
end

function Controller.Enter(self: Controller, pose: CFrame, fov: number?): ()
	self.follow = nil
	self.core:EnterPose(pose, fov or 45, Config.PaintCameraSeconds)
	self.saved = self.core.saved
	self.ready = self.core.ready
end

function Controller.EnterMarker(self: Controller, target: Instance?, fallbackPose: CFrame?, fallbackFov: number?): ()
	self.follow = nil
	self.core:Enter(target, fallbackPose, fallbackFov or 45, Config.PaintCameraSeconds)
	self.saved = self.core.saved
	self.ready = self.core.ready
end

function Controller.Exit(self: Controller, immediate: boolean?): ()
	self.follow = nil
	self.core:Exit(immediate)
	self.saved = self.core.saved
	self.ready = self.core.ready
end

function Controller.FollowToss(self: Controller, ends: number, target: () -> Vector3?): ()
	local saved = self.saved
	local focus = target()
	local now = workspace:GetServerTimeNow()
	if not saved or workspace.CurrentCamera ~= saved.camera or not focus or now >= ends then
		self:Exit()
		return
	end
	self.follow = nil
	self.core:Suspend()
	self.ready = self.core.ready
	self.follow = {
		started = now,
		ends = ends,
		duration = math.max(ends - now, 0.001),
		origin = saved.camera.CFrame,
		focus = focus,
		target = target,
	}
end

function Controller.StepToss(self: Controller, now: number, dt: number): ()
	local follow, saved = self.follow, self.saved
	if not follow or not saved then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if workspace.CurrentCamera ~= saved.camera or not humanoid or humanoid.Health <= 0 then
		self:Restore()
		return
	end
	local focus = follow.target()
	if now >= follow.ends or not focus then
		self:Exit(true)
		return
	end
	-- 限制镜头安全高度（避开地下室承重顶板 SouthFoundation_Side Y>=18.0），回拉并朝向飞往祭坛的白膜。
	local MaxSafeY = 15.8
	local duration = math.max(follow.duration, 0.001)
	local t = math.clamp(1 - (follow.ends - now) / duration, 0, 1)
	local pos = follow.origin.Position:Lerp(saved.pose.Position, t * 0.45)
	local camPos = Vector3.new(pos.X, math.min(pos.Y, MaxSafeY), pos.Z)
	local goal = if (focus - camPos).Magnitude > 1e-4
		then CFrame.lookAt(camPos, focus)
		else saved.camera.CFrame.Rotation + camPos
	saved.camera.CFrame = saved.camera.CFrame:Lerp(goal, 1 - math.exp(-12 * math.max(dt, 0)))
end

function Controller.Destroy(self: Controller): ()
	self:Restore()
end

return Controller
