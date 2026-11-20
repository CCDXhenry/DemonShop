-- 平面符文视图离线边界：真实 Lune GUI 实例，仅替换服务、共享 EditableImage 与模板查找
local Roblox = require('@lune/roblox')
local gui = Roblox.Instance.new('Folder')
gui.Name = 'PlayerGui'
local surface = Roblox.Instance.new('SurfaceGui')
local line = Roblox.Instance.new('Frame')
line.AnchorPoint = Roblox.Vector2.new(0.5, 0.5)
local rune = Roblox.Instance.new('ImageLabel')
rune.Name = 'PaintRuneImage'
rune.AnchorPoint = Roblox.Vector2.new(0.5, 0.5)
rune.BackgroundTransparency = 1
rune.ImageColor3 = Roblox.Color3.fromRGB(176, 63, 255)
rune.ImageTransparency = 0
local templates = { PaintFaceGui = surface, PaintCellFrame = line, PaintRuneImage = rune }
local images = {}
local AssetService = {
	CreateEditableImage = function(_, options)
		local image = {
			Size = options.Size,
			writes = {},
			destroyed = false,
		}
		function image:WritePixelsBuffer(offset, size, pixels)
			table.insert(self.writes, { offset = offset, size = size, len = buffer.len(pixels) })
		end
		function image:Destroy()
			self.destroyed = true
		end
		table.insert(images, image)
		return image
	end,
}
local Content = {
	fromObject = function(obj)
		return obj
	end,
	none = 'none',
}
return {
	gui = gui,
	images = images,
	AssetService = AssetService,
	Content = Content,
	Players = { LocalPlayer = { WaitForChild = function() return gui end } },
	ReplicatedStorage = { UI = { WaitForChild = function(_, name) return templates[name] end } },
}
