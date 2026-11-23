-- 玩家引导纯规则：根据携带物、共享工位与占用状态提供具体下一步
--!strict
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local GameTexts = require(script.Parent.GameTexts)
local Hints = {}
export type Potions = { stored: number, equipped: boolean }
type CarryLoad = { unfinished: boolean, painted: boolean, body: boolean, other: boolean }
local function Describe(textId: GameTexts.TextId, args: {string}?): GameTexts.Description
	return { textId = textId, args = args }
end
local function ReadCarry(held: Types.ItemView?, stack: { Types.ItemView }?): CarryLoad
	local list: { Types.ItemView } = {}
	if stack then
		for _, item in stack do
			table.insert(list, item)
		end
	elseif held then
		table.insert(list, held)
	end
	local load: CarryLoad = { unfinished = false, painted = false, body = false, other = false }
	for _, item in list do
		if item.kind == "Body" then
			load.body = true
			if item.stage == "Painted" then
				load.painted = true
			else
				load.unfinished = true
			end
		else
			load.other = true
		end
	end
	if stack and held and held.kind ~= "Body" then
		load.other = true
	end
	return load
end
function Hints.Next(snapshot: Types.Snapshot?, held: Types.ItemView?, potions: Potions?, stack: { Types.ItemView }?): GameTexts.Description
	local load = ReadCarry(held, stack)
	if load.body then return Describe("ThrowAim") end
	if potions and potions.equipped then return Describe("TakePotion", { tostring(Config.PotionReward) }) end
	if potions and potions.stored > 0 then return Describe("EquipPotion") end
	if snapshot then
		if snapshot.shelf > 0 then return Describe("PotionReady") end
		if snapshot.altarId then return Describe("AltarWorking") end
		if snapshot.tableId then return Describe("ReturnTable") end
		if snapshot.pool > 0 then return Describe("FetchPool") end
	end
	return Describe("StunNpc", { tostring(Config.StunHits) })
end
function Hints.Action(target: string, snapshot: Types.Snapshot?, held: Types.ItemView?, userId: number, potions: Potions?, stack: { Types.ItemView }?): GameTexts.Description
	local load = ReadCarry(held, stack)
	local carrying = load.body or load.other or held ~= nil
	if target == "Pool" then
		if load.unfinished and snapshot and snapshot.pool >= Config.PoolCapacity then return Describe("PoolFull") end
		if load.unfinished then return Describe("StoreBody") end
		if carrying then return Describe("PoolUnfinishedOnly") end
		return if snapshot and snapshot.pool > 0 then Describe("TakeSharedBody") else Describe("PoolEmpty")
	elseif target == "Table" then
		if snapshot and snapshot.painter and snapshot.painter ~= userId then return Describe("TableOtherPainter") end
		if carrying then
			if snapshot and snapshot.tableId then return Describe("TableOccupied") end
			return if load.unfinished then Describe("PlaceBody") else Describe("TableNeedsBody")
		end
		if snapshot and snapshot.tableId then
			for _, item in snapshot.items do
				if item.id == snapshot.tableId then return if item.stage == "Painted" then Describe("CollectRuneBody") else Describe("ContinuePainting") end
			end
		end
		return if snapshot and snapshot.pool > 0 then Describe("FetchAndPaint") else Describe("TableEmpty")
	elseif target == "Altar" then
		if load.painted then return Describe("InsertRuneBody") end
		if snapshot and snapshot.altarId then
			return if snapshot.shelf >= Config.ShelfCapacity then Describe("ShelfFull") else Describe("AltarBusy")
		end
		return Describe("AltarNeedsRuneBody")
	elseif target == "Shelf" then
		if load.body then return Describe("HandsFullHint") end
		return if snapshot and snapshot.shelf > 0 then Describe("CollectPotion") else Describe("NoPotion")
	elseif target == "Sigil" then
		if potions and potions.equipped then return Describe("OfferPotion", { tostring(Config.PotionReward) }) end
		return if potions and potions.stored > 0 then Describe("EquipPotion") else Describe("BringPotion")
	end
	return Describe("CarryBody")
end
return Hints
