-- 玩家引导纯规则：根据携带物、共享工位与占用状态提供具体下一步
--!strict
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local GameTexts = require(script.Parent.GameTexts)
local Hints = {}
local function Describe(textId: GameTexts.TextId, args: {string}?): GameTexts.Description
	return { textId = textId, args = args }
end
function Hints.Next(snapshot: Types.Snapshot?, held: Types.ItemView?): GameTexts.Description
	if held then
		if held.kind == "Potion" then return Describe("TakePotion", { tostring(Config.PotionReward) }) end
		if held.stage == "Painted" then return Describe("TakeRuneBody") end
		return Describe("TakeBody")
	end
	if snapshot then
		if snapshot.shelf > 0 then return Describe("PotionReady") end
		if snapshot.altarId then return Describe("AltarWorking") end
		if snapshot.tableId then return Describe("ReturnTable") end
		if snapshot.pool > 0 then return Describe("FetchPool") end
	end
	return Describe("StunNpc", { tostring(Config.StunHits) })
end
function Hints.Action(target: string, snapshot: Types.Snapshot?, held: Types.ItemView?, userId: number): GameTexts.Description
	if target == "Pool" then
		if held and (held.kind ~= "Body" or held.stage == "Painted") then return Describe("PoolUnfinishedOnly") end
		return if held then Describe("StoreBody") elseif snapshot and snapshot.pool > 0 then Describe("TakeSharedBody") else Describe("PoolEmpty")
	elseif target == "Table" then
		if snapshot and snapshot.painter and snapshot.painter ~= userId then return Describe("TableOtherPainter") end
		if held then
			if snapshot and snapshot.tableId then return Describe("TableOccupied") end
			return if held.kind == "Body" and held.stage ~= "Painted" then Describe("PlaceBody") else Describe("TableNeedsBody")
		end
		if snapshot and snapshot.tableId then
			for _, item in snapshot.items do
				if item.id == snapshot.tableId then return if item.stage == "Painted" then Describe("CollectRuneBody") else Describe("ContinuePainting") end
			end
		end
		return if snapshot and snapshot.pool > 0 then Describe("FetchAndPaint") else Describe("TableEmpty")
	elseif target == "Altar" then
		if snapshot and snapshot.altarId then
			return if snapshot.shelf >= Config.ShelfCapacity then Describe("ShelfFull") else Describe("AltarBusy")
		end
		return if held and held.kind == "Body" and held.stage == "Painted" then Describe("InsertRuneBody") else Describe("AltarNeedsRuneBody")
	elseif target == "Shelf" then
		return if held then Describe("HandsFullHint") elseif snapshot and snapshot.shelf > 0 then Describe("CollectPotion") else Describe("NoPotion")
	elseif target == "Sigil" then
		return if held and held.kind == "Potion" then Describe("OfferPotion", { tostring(Config.PotionReward) }) else Describe("BringPotion")
	end
	return Describe("CarryBody")
end
return Hints
