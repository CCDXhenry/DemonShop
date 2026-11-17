-- 笔迹表面管理器：按身体及表面维护本地 SurfaceGui 和重绑定生命周期
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Manager = {}
Manager.__index = Manager
export type FaceRecord = { bodyId: string, gui: SurfaceGui }
export type Manager = typeof(setmetatable({} :: { faces: { [string]: FaceRecord } }, Manager))
function Manager.new(): Manager
	return setmetatable({ faces = {} }, Manager)
end
function Manager.Acquire(self: Manager, key: string, bodyId: string, part: BasePart, face: Enum.NormalId, canvasSize: Vector2): SurfaceGui
	local record = self.faces[key]
	if not record then
		local gui = (ReplicatedStorage.UI:WaitForChild("PaintFaceGui") :: SurfaceGui):Clone()
		gui.Name = "RuneStroke"
		record = { bodyId = bodyId, gui = gui }
		self.faces[key] = record
	end
	local gui = record.gui
	gui.Adornee, gui.Face, gui.CanvasSize = part, face, canvasSize
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end
function Manager.Remove(self: Manager, bodyId: string): ()
	for key, record in self.faces do
		if record.bodyId == bodyId then
			self.faces[key] = nil
			record.gui:Destroy()
		end
	end
end
function Manager.Destroy(self: Manager): ()
	for key, record in self.faces do
		self.faces[key] = nil
		record.gui:Destroy()
	end
end
return Manager
