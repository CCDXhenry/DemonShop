-- 共享状态复制：首次完整快照、正常物品增量与删除通知，画符高频通知独立发送
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Net = require(ReplicatedStorage.Scripts.Shared.ProcessingNet)
local Replication = {}
Replication.__index = Replication
export type Replication = typeof(setmetatable({} :: { previous: { [string]: Types.ItemView }? }, Replication))
function Replication.new(): Replication
	return setmetatable({ previous = nil }, Replication)
end
function Replication.Broadcast(self: Replication, snapshot: Types.Snapshot): ()
	local current: { [string]: Types.ItemView } = {}
	local changed: { Types.ItemView } = {}
	local previous = self.previous
	for _, item in snapshot.items do
		current[item.id] = item
		local old = previous and previous[item.id]
		if not old or old.version ~= item.version or old.location ~= item.location or old.holder ~= item.holder or old.carryOrder ~= item.carryOrder or old.stage ~= item.stage or old.hits ~= item.hits or old.progress ~= item.progress or old.model ~= item.model or old.altarTossStarted ~= item.altarTossStarted or old.convertEnds ~= item.convertEnds then table.insert(changed, item) end
	end
	self.previous = current
	if not previous then Net.Broadcast({ kind = "State", snapshot = snapshot }); return end
	local removed: { string } = {}
	for id in previous do if not current[id] then table.insert(removed, id) end end
	snapshot.items = changed
	Net.Broadcast({ kind = "Delta", snapshot = snapshot, removed = removed })
end
return Replication
