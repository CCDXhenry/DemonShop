-- 设计参考管理器：仅在显式请求时挂载禁放参考模板并负责清理
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Manager = {}
Manager.__index = Manager
export type Manager = typeof(setmetatable({} :: { frames: { [Frame]: RBXScriptConnection } }, Manager))
function Manager.new(): Manager
	return setmetatable({ frames = {} }, Manager)
end
function Manager.Create(self: Manager, parent: GuiBase2d): Frame
	local frame = (ReplicatedStorage.UI:WaitForChild("ScreenLayoutGuideFrame") :: Frame):Clone()
	self.frames[frame] = frame.Destroying:Connect(function(): ()
		local connection = self.frames[frame]
		self.frames[frame] = nil
		if connection then
			connection:Disconnect()
		end
	end)
	frame.Parent = parent
	return frame
end
function Manager.Remove(self: Manager, frame: Frame): ()
	local connection = self.frames[frame]
	if not connection then
		return
	end
	self.frames[frame] = nil
	connection:Disconnect()
	frame:Destroy()
end
function Manager.Destroy(self: Manager): ()
	for frame in self.frames do
		self:Remove(frame)
	end
end
return Manager
