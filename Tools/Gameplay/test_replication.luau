-- 复制协议回归：首次快照、增量、删除及会话元数据由生产模块计算
local Replication = require('./Replication')
local Net = require('./ReplicationNet')
local replication = Replication.new()
local count = 0
local function check(value, message)
	assert(value, message)
	count += 1
end
local function item(id, version)
	return {id=id,version=version,kind='Body',stage='Unpainted',location='Ground',hits=3,progress=0}
end
local function snapshot(items, revision)
	return {items=items,revision=revision,stationVersions={Table=1},pool=0,shelf=0,altarEnds=0}
end
replication:Broadcast(snapshot({item('a',1),item('b',1)},1))
check(Net.notices[1].kind == 'State' and #Net.notices[1].snapshot.items == 2, 'initial full snapshot')
replication:Broadcast(snapshot({item('a',1),item('b',1)},2))
check(Net.notices[2].kind == 'Delta' and #Net.notices[2].snapshot.items == 0, 'unchanged items omitted')
local current = snapshot({item('a',2),item('b',1),item('c',1)},3)
current.painter,current.session,current.poseYaw = 17,'session',0.7
replication:Broadcast(current)
check(#Net.notices[3].snapshot.items == 2, 'changed and newly created items included')
check(Net.notices[3].snapshot.session == 'session' and Net.notices[3].snapshot.poseYaw == 0.7, 'session and observer pose retained')
replication:Broadcast(snapshot({item('a',2),item('c',1)},4))
check(#Net.notices[4].removed == 1 and Net.notices[4].removed[1] == 'b', 'removed item id included')
local progress = item('a',2)
progress.progress = 0.45
replication:Broadcast(snapshot({progress,item('c',1)},5))
check(#Net.notices[5].snapshot.items == 1 and Net.notices[5].snapshot.items[1].progress == 0.45, 'paint progress repaired on next state change')
replication:Broadcast(snapshot({},6))
check(#Net.notices[6].removed == 2, 'all remaining items removed')
print(string.format('PASS: %d replication assertions (production module; captured network boundary)',count))
