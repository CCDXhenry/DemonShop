-- 离线受击验证环境：只替换 Workspace，相机与模型使用真实 Lune 实例
local R=require("@lune/roblox")
local world=R.Instance.new("Folder")
local camera=R.Instance.new("Camera")
camera.CFrame=R.CFrame.new(0,0,10)
-- Parent assignment requires an Instance; workspace.CurrentCamera is emulated by a property.
world:SetAttribute("TestWorld",true)
return setmetatable({CurrentCamera=camera,world=world},{})
