-- 工作台镜头：可取消的进出过渡、重入保护和角色复活后的相机归还
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Controller = {}
Controller.__index = Controller
type Saved = { camera: Camera, kind: Enum.CameraType, subject: Instance?, pose: CFrame, fov: number }
export type Controller = typeof(setmetatable({} :: {
	saved: Saved?, tween: Tween?, completed: RBXScriptConnection?, ready: boolean,
}, Controller))
function Controller.new(): Controller
	return setmetatable({saved=nil,tween=nil,completed=nil,ready=false}, Controller)
end
function Controller.Cancel(self: Controller): ()
	if self.completed then self.completed:Disconnect(); self.completed = nil end
	if self.tween then self.tween:Cancel(); self.tween:Destroy(); self.tween = nil end
end
function Controller.Restore(self: Controller): ()
	self:Cancel()
	local saved = self.saved
	self.saved, self.ready = nil, false
	if not saved or workspace.CurrentCamera ~= saved.camera then return end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	saved.camera.CFrame = saved.pose
	saved.camera.FieldOfView = saved.fov
	saved.camera.CameraSubject = humanoid or saved.subject
	saved.camera.CameraType = saved.kind
end
function Controller.Enter(self: Controller, pose: CFrame): ()
	self:Restore()
	local camera = workspace.CurrentCamera
	if not camera then return end
	self.saved = {camera=camera,kind=camera.CameraType,subject=camera.CameraSubject,pose=camera.CFrame,fov=camera.FieldOfView}
	camera.CameraType = Enum.CameraType.Scriptable
	local tween = TweenService:Create(camera,TweenInfo.new(Config.PaintCameraSeconds,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{CFrame=pose,FieldOfView=45})
	self.tween = tween
	self.completed = tween.Completed:Connect(function(state: Enum.PlaybackState): ()
		if state == Enum.PlaybackState.Completed then self.ready = true end
		self:Cancel()
	end)
	tween:Play()
end
function Controller.Exit(self: Controller, immediate: boolean?): ()
	self:Cancel()
	self.ready = false
	local saved = self.saved
	if not saved then return end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if immediate or not humanoid or humanoid.Health <= 0 or workspace.CurrentCamera ~= saved.camera then self:Restore(); return end
	local tween = TweenService:Create(saved.camera,TweenInfo.new(Config.PaintCameraSeconds,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{CFrame=saved.pose,FieldOfView=saved.fov})
	self.tween = tween
	self.completed = tween.Completed:Connect(function(state: Enum.PlaybackState): ()
		if state == Enum.PlaybackState.Completed then self:Restore() end
	end)
	tween:Play()
end
function Controller.Destroy(self: Controller): () self:Restore() end
return Controller
