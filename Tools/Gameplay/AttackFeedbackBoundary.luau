-- 受击流程离线边界：时间、网络发送与服务端物理命中由测试控制
local B={now=10,notices={},broadcasts={},hits=0}
B.workspace={GetServerTimeNow=function() return B.now end}
B.task={wait=function() end}
B.Net={FireNotify=function(_,notice) table.insert(B.notices,notice) end,Broadcast=function(notice) table.insert(B.broadcasts,notice) end}
B.NPC={Hit=function(item, direction, damage, travel)
	B.hitDirection, B.hitTravel = direction, travel
	item.maxHp = 30
	item.hp = math.max(0, (item.hp or (30 - item.hits * 10)) - (damage or 10))
	item.hits = 3 - math.ceil(item.hp / 10)
	item.version+=1; B.hits+=1
end}
B.player={UserId=1}
B.healthHits={}
B.UIManager={GetTargetGuiManager=function()
	return {ShowHit=function(_, id, version, hits) table.insert(B.healthHits, {id=id,version=version,hits=hits}) end}
end}
B.Sound={Play=function() end}
return B
