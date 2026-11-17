-- 笔迹单元管理器：持有线段 Frame、几何更新和有界对象池
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Parent.Shared.GameConfig)
local Manager = {}
Manager.__index = Manager
export type CellState = { key: string, version: number, position: Vector2, size: Vector2, rotation: number, parent: SurfaceGui }
export type CellRecord = { bodyId: string, frame: Frame }
export type Manager = typeof(setmetatable({} :: { cells: { [string]: CellRecord }, pool: { Frame }, serial: number }, Manager))
function Manager.new(): Manager
	return setmetatable({ cells = {}, pool = {}, serial = 0 }, Manager)
end
function Manager.Create(self: Manager, parent: GuiBase2d?, zIndex: number?): Frame
	local frame = (ReplicatedStorage.UI:WaitForChild("PaintCellFrame") :: Frame):Clone()
	self.serial += 1
	self.cells["standalone:" .. tostring(self.serial)] = { bodyId = "", frame = frame }
	if zIndex then
		frame.ZIndex = zIndex
	end
	frame.Parent = parent
	return frame
end
function Manager.Update(self: Manager, id: string, bodyId: string, state: CellState): ()
	local record = self.cells[id]
	if not record then
		local frame = table.remove(self.pool) or (ReplicatedStorage.UI:WaitForChild("PaintCellFrame") :: Frame):Clone()
		record = { bodyId = bodyId, frame = frame }
		self.cells[id] = record
	end
	local frame = record.frame
	frame.Name = "StrokeSegment"
	frame:SetAttribute("VisualKey", state.key)
	frame:SetAttribute("VisualVersion", state.version)
	frame.Position = UDim2.fromOffset(state.position.X, state.position.Y)
	frame.Size = UDim2.fromOffset(state.size.X, state.size.Y)
	frame.Rotation = state.rotation
	frame.Parent = state.parent
end
function Manager.Remove(self: Manager, bodyId: string): ()
	for id, record in self.cells do
		if record.bodyId == bodyId then
			self.cells[id] = nil
			local frame = record.frame
			frame.Parent = nil
			frame:SetAttribute("VisualKey", nil)
			frame:SetAttribute("VisualVersion", nil)
			if #self.pool < Config.PaintPreviewPoolBudget then
				table.insert(self.pool, frame)
			else
				frame:Destroy()
			end
		end
	end
end
function Manager.Destroy(self: Manager): ()
	for id, record in self.cells do
		self.cells[id] = nil
		record.frame:Destroy()
	end
	for _, frame in self.pool do
		frame:Destroy()
	end
	table.clear(self.pool)
end
return Manager
