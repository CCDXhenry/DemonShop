-- 测试服务边界：内存 DataStore 与可注入失败，不接触线上存档
local Mock={}
local serial=0
Mock.HttpService={GenerateGUID=function() serial+=1;return "test-"..serial end}
Mock.DataStoreTool={SafeUpdate=function(store,key,transform)
 if store.fail then return false,nil end
 local current=store.values[key]
 local metadata=store.metadata[key] or {}
 local info={GetMetadata=function() return table.clone(metadata) end,GetUserIds=function() return {} end}
 local value,_,nextMetadata=transform(current,info)
 if value~=nil then store.values[key]=value;store.metadata[key]=nextMetadata end
 return true,store.values[key]
end}
function Mock.NewStore() return {values={},metadata={},fail=false} end
return Mock
