-- 视觉上传回归边界：捕获生产上传队列发出的请求
local Net={requests={}}
function Net.FireRequest(request) table.insert(Net.requests,request) end
return Net
