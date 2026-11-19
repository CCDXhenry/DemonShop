-- 笔迹单元管理器：持有线段 Frame、几何更新和有界对象池
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Parent.Shared.GameConfig)
local Manager = {}
Manager.__index = Manager
export type CellState = { key: string, version: number, position: Vector2, size: Vector2, rotation: number, parent: SurfaceGui }
export type CellRecord = { bodyId: string, frame: Frame, baseColor: Color3?, baseTransparency: number? }
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
local function Restore(record: CellRecord): ()
	local baseColor = record.baseColor
	if not baseColor then
		return
	end
	record.frame.BackgroundColor3 = baseColor
	record.frame.BackgroundTransparency = record.baseTransparency or 0
	record.baseColor = nil
	record.baseTransparency = nil
end
function Manager.SetSacrifice(self: Manager, bodyId: string, brightness: number, transparency: number): ()
	local highlight = Config.AltarStrokeHighlight
	for _, record in self.cells do
		if record.bodyId ~= bodyId then
			continue
		end
		if brightness <= 0 and transparency <= 0 then
			Restore(record)
			continue
		end
		local frame = record.frame
		if not record.baseColor then
			record.baseColor = frame.BackgroundColor3
			record.baseTransparency = frame.BackgroundTransparency
		end
		local baseColor = record.baseColor :: Color3
		local baseTransparency = record.baseTransparency or 0
		frame.BackgroundColor3 = baseColor:Lerp(highlight, brightness)
		frame.BackgroundTransparency = baseTransparency + (1 - baseTransparency) * transparency
	end
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
			Restore(record)
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
