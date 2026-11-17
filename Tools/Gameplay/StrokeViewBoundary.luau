-- 连续笔迹视图离线边界：真实 Lune GUI 实例，仅替换服务和模板查找
local Roblox = require('@lune/roblox')
local gui = Roblox.Instance.new('Folder')
gui.Name = 'PlayerGui'
local surface = Roblox.Instance.new('SurfaceGui')
local line = Roblox.Instance.new('Frame')
line.AnchorPoint = Roblox.Vector2.new(.5,.5)
local templates = {PaintFaceGui=surface,PaintCellFrame=line}
return {
 gui=gui,
 Players={LocalPlayer={WaitForChild=function() return gui end}},
 ReplicatedStorage={UI={WaitForChild=function(_,name) return templates[name] end}},
}
