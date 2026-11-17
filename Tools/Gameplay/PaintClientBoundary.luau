-- 绘画客户端离线边界：输入、相机和通知服务；业务方法取自正式模块。
local R=require('@lune/roblox')
local B={time=10}
B.os={clock=function() return B.time end}
B.player={UserId=1,GetAttribute=function() return true end,WaitForChild=function() return {FindFirstChild=function() return nil end} end}
B.workspace={CurrentCamera=nil,GetServerTimeNow=function() return B.time end}
B.UserInputService={TouchEnabled=false}
return B
