-- 受击流程离线边界：时间、网络发送与服务端物理命中由测试控制
local B={now=10,notices={},broadcasts={},hits=0}
B.workspace={GetServerTimeNow=function() return B.now end}
B.task={wait=function() end}
B.Net={FireNotify=function(_,notice) table.insert(B.notices,notice) end,Broadcast=function(notice) table.insert(B.broadcasts,notice) end}
B.NPC={Hit=function(item)
	item.hits+=1; item.version+=1; B.hits+=1
end}
B.player={UserId=1}
B.Sound={Play=function() end}
return B
