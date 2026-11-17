-- 玩家引导纯规则：根据携带物、共享工位与占用状态提供具体下一步
--!strict
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local Hints = {}
function Hints.Next(snapshot: Types.Snapshot?, held: Types.ItemView?): string
	if held then
		if held.kind == "Potion" then return "TAKE THE POTION TO THE SUMMONING SIGIL  (+100 COINS)" end
		if held.stage == "Painted" then return "TAKE THE RUNE BODY TO THE CONVERSION ALTAR" end
		return "TAKE THE BODY DOWNSTAIRS TO THE RUNE TABLE OR HOLDING POOL"
	end
	if snapshot then
		if snapshot.shelf > 0 then return "A POTION IS READY - COLLECT IT FROM THE SHELF" end
		if snapshot.altarId then return "THE ALTAR IS WORKING - CHECK THE COUNTDOWN" end
		if snapshot.tableId then return "RETURN TO THE RUNE TABLE TO CONTINUE OR COLLECT THE BODY" end
		if snapshot.pool > 0 then return "THE RUNE TABLE CAN FETCH A BODY FROM THE SHARED POOL" end
	end
	return "STUN A WHITE NPC WITH THREE CLUB HITS"
end
function Hints.Action(target: string, snapshot: Types.Snapshot?, held: Types.ItemView?, userId: number): string
	if target == "Pool" then
		if held and (held.kind ~= "Body" or held.stage == "Painted") then return "POOL ACCEPTS UNFINISHED BODIES ONLY" end
		return if held then "STORE UNFINISHED BODY" elseif snapshot and snapshot.pool > 0 then "TAKE FIRST SHARED BODY" else "POOL EMPTY - BRING A BODY"
	elseif target == "Table" then
		if snapshot and snapshot.painter and snapshot.painter ~= userId then return "TABLE IN USE - ANOTHER PLAYER IS PAINTING" end
		if held then
			if snapshot and snapshot.tableId then return "TABLE OCCUPIED - PUT DOWN YOUR ITEM FIRST" end
			return if held.kind == "Body" and held.stage ~= "Painted" then "PLACE BODY ON RUNE TABLE" else "TABLE NEEDS AN UNFINISHED BODY"
		end
		if snapshot and snapshot.tableId then
			for _, item in snapshot.items do
				if item.id == snapshot.tableId then return if item.stage == "Painted" then "COLLECT COMPLETED RUNE BODY" else "CONTINUE PAINTING THE BODY" end
			end
		end
		return if snapshot and snapshot.pool > 0 then "FETCH SHARED BODY AND PAINT" else "TABLE EMPTY - BRING A BODY"
	elseif target == "Altar" then
		if snapshot and snapshot.altarId then
			return if snapshot.shelf >= Config.ShelfCapacity then "POTION SHELF FULL - COLLECT A POTION" else "ALTAR BUSY - WAIT FOR CONVERSION"
		end
		return if held and held.kind == "Body" and held.stage == "Painted" then "INSERT COMPLETED RUNE BODY" else "ALTAR NEEDS A COMPLETED RUNE BODY"
	elseif target == "Shelf" then
		return if held then "HANDS FULL - PUT DOWN YOUR ITEM" elseif snapshot and snapshot.shelf > 0 then "COLLECT READY POTION" else "NO POTION READY - USE THE ALTAR FIRST"
	elseif target == "Sigil" then
		return if held and held.kind == "Potion" then "OFFER POTION  (+100 COINS)" else "BRING A POTION TO OFFER"
	end
	return "SHOULDER CARRY BODY"
end
return Hints
