-- 平面符文印记管理器：克隆预制 ImageLabel、共享三张客户端 EditableImage 及有界对象池
--!strict
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Parent.Shared.GameConfig)
local RuneGlyphs = require(script.Parent.Parent.Parent.Shared.RuneGlyphData)
local Manager = {}
Manager.__index = Manager
export type CellState = {
	key: string,
	version: number,
	glyph: number,
	position: Vector2,
	size: Vector2,
	rotation: number,
	parent: SurfaceGui,
}
export type CellRecord = {
	bodyId: string,
	node: GuiObject,
	baseColor: Color3?,
	baseTransparency: number?,
}
export type Manager = typeof(setmetatable({} :: {
	cells: { [string]: CellRecord },
	pool: { ImageLabel },
	glyphImages: { [number]: EditableImage },
	serial: number,
}, Manager))

function Manager.new(): Manager
	return setmetatable({ cells = {}, pool = {}, glyphImages = {}, serial = 0 }, Manager)
end

local function EnsureGlyphImage(self: Manager, glyph: number): EditableImage?
	local existing = self.glyphImages[glyph]
	if existing then
		return existing
	end
	local size = RuneGlyphs.Size
	local ok, image = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
	end)
	if not ok or not image then
		return nil
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(size, size), RuneGlyphs.CreateRgbaBuffer(glyph))
	self.glyphImages[glyph] = image
	return image
end

function Manager.Create(self: Manager, parent: GuiBase2d?, zIndex: number?): Frame
	local frame = (ReplicatedStorage.UI:WaitForChild("PaintCellFrame") :: Frame):Clone()
	self.serial += 1
	self.cells["standalone:" .. tostring(self.serial)] = { bodyId = "", node = frame }
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
	local node = record.node
	if node:IsA("ImageLabel") then
		node.ImageColor3 = baseColor
		node.ImageTransparency = record.baseTransparency or 0
	else
		node.BackgroundColor3 = baseColor
		node.BackgroundTransparency = record.baseTransparency or 0
	end
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
		local node = record.node
		if node:IsA("ImageLabel") then
			if not record.baseColor then
				record.baseColor = node.ImageColor3
				record.baseTransparency = node.ImageTransparency
			end
			local baseColor = record.baseColor :: Color3
			local baseTransparency = record.baseTransparency or 0
			node.ImageColor3 = baseColor:Lerp(highlight, brightness)
			node.ImageTransparency = baseTransparency + (1 - baseTransparency) * transparency
		else
			if not record.baseColor then
				record.baseColor = node.BackgroundColor3
				record.baseTransparency = node.BackgroundTransparency
			end
			local baseColor = record.baseColor :: Color3
			local baseTransparency = record.baseTransparency or 0
			node.BackgroundColor3 = baseColor:Lerp(highlight, brightness)
			node.BackgroundTransparency = baseTransparency + (1 - baseTransparency) * transparency
		end
	end
end

function Manager.Update(self: Manager, id: string, bodyId: string, state: CellState): ()
	local record = self.cells[id]
	local label: ImageLabel
	if not record then
		local reused = table.remove(self.pool)
		if reused then
			label = reused
		else
			local template = ReplicatedStorage.UI:WaitForChild("PaintRuneImage") :: ImageLabel
			label = template:Clone()
		end
		record = { bodyId = bodyId, node = label }
		self.cells[id] = record
	else
		label = record.node :: ImageLabel
	end
	label.Name = "RuneStamp"
	label:SetAttribute("VisualKey", state.key)
	label:SetAttribute("VisualVersion", state.version)
	label:SetAttribute("RuneGlyph", state.glyph)
	local glyphImage = EnsureGlyphImage(self, state.glyph)
	if glyphImage then
		pcall(function(): ()
			label.ImageContent = Content.fromObject(glyphImage)
		end)
	end
	label.ImageColor3 = Config.RuneBaseColor
	label.ImageTransparency = 0
	label.Position = UDim2.fromOffset(state.position.X, state.position.Y)
	label.Size = UDim2.fromOffset(state.size.X, state.size.Y)
	label.Rotation = state.rotation
	label.Parent = state.parent
end

function Manager.Remove(self: Manager, bodyId: string): ()
	for id, record in self.cells do
		if record.bodyId == bodyId then
			self.cells[id] = nil
			Restore(record)
			local node = record.node
			node.Parent = nil
			node:SetAttribute("VisualKey", nil)
			node:SetAttribute("VisualVersion", nil)
			node:SetAttribute("RuneGlyph", nil)
			if node:IsA("ImageLabel") and #self.pool < Config.PaintPreviewPoolBudget then
				table.insert(self.pool, node)
			else
				node:Destroy()
			end
		end
	end
end

function Manager.Destroy(self: Manager): ()
	for id, record in self.cells do
		self.cells[id] = nil
		record.node:Destroy()
	end
	for _, label in self.pool do
		label:Destroy()
	end
	table.clear(self.pool)
	for glyph, image in self.glyphImages do
		self.glyphImages[glyph] = nil
		image:Destroy()
	end
end

return Manager
