-- 玩家引导纯规则：根据携带物、共享工位与占用状态提供具体下一步
--!strict
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local GameData = require(script.Parent.GameData)
local GameTexts = require(script.Parent.GameTexts)
local Hints = {}
export type Potions = { stored: number, equipped: boolean, reward: number? }
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
	if potions and (potions.equipped or potions.stored > 0) then return Describe("TakePotion", { tostring(potions.reward or Config.PotionReward) }) end
	if snapshot then
		if snapshot.shelf > 0 then return Describe("PotionReady") end
		if (snapshot.autoShelfCount or 0) > 0 then return Describe("CollectAutoPotion") end
		if snapshot.altarId then return Describe("AltarWorking") end
		if snapshot.tableId then return Describe("ReturnTable") end
		if snapshot.pool > 0 then return Describe("FetchPool") end
	end
	return Describe("StunNpc")
end
function Hints.Action(target: string, snapshot: Types.Snapshot?, held: Types.ItemView?, userId: number, potions: Potions?, stack: { Types.ItemView }?): GameTexts.Description
	local load = ReadCarry(held, stack)
	local carrying = load.body or load.other or held ~= nil
	if target == "Pool" then
		if load.unfinished then return Describe("StoreBody") end
		if carrying then return Describe("PoolUnfinishedOnly") end
		return if snapshot and snapshot.pool > 0 then Describe("TakeSharedBody") else Describe("PoolEmpty")
	elseif target == "Table" then
		if snapshot and snapshot.painter and snapshot.painter ~= userId then return Describe("TableOtherPainter") end
		if snapshot and snapshot.tableId then
			for _, item in snapshot.items do
				if item.id ~= snapshot.tableId then continue end
				if item.stage ~= "Painted" then return Describe("ContinuePainting") end
				return Describe(if carrying then "TableOccupied" else "CollectRuneBody")
			end
		end
		if carrying then return if load.unfinished then Describe("PlaceBody") else Describe("TableNeedsBody") end
		return if snapshot and snapshot.pool > 0 then Describe("FetchAndPaint") else Describe("TableEmpty")
	elseif target == "Altar" then
		if load.painted then return Describe("InsertRuneBody") end
		if snapshot and snapshot.altarId then
			return Describe("AltarBusy")
		end
		return Describe("AltarNeedsRuneBody")
	elseif target == "Shelf" then
		if load.body then return Describe("HandsFullHint") end
		return if snapshot and snapshot.shelf > 0 then Describe("CollectPotion") else Describe("NoPotion")
	elseif target == "Sigil" then
		if potions and (potions.equipped or potions.stored > 0) then return Describe("OfferPotion", { tostring(potions.reward or Config.PotionReward) }) end
		return Describe("BringPotion")
	elseif target == "Chute" then
		if not (snapshot and snapshot.unlockedFacilities and snapshot.unlockedFacilities[GameData.FacilityId.FastChute]) then return Describe("ChuteLocked") end
		if load.unfinished then return Describe("DepositBodies") end
		if carrying then return Describe("ChuteUnfinishedOnly") end
		return Describe("ChuteNeedsBody")
	elseif target == "ChutePickup" then
		if load.other then return Describe("HandsFullHint") end
		return if snapshot and (snapshot.chuteQueue or 0) > 0 then Describe("TakeChuteBody") else Describe("ChuteEmpty")
	elseif target == "AutoOutput" then
		if load.other then return Describe("HandsFullHint") end
		return if snapshot and (snapshot.autoPaintedQueue or 0) > 0 then Describe("TakeAutoRuneBody") else Describe("AutoOutputEmpty")
	elseif target == "AutoShelf" then
		if load.body then return Describe("HandsFullHint") end
		return if snapshot and (snapshot.autoShelfCount or 0) > 0 then Describe("CollectAutoPotion") else Describe("NoAutoPotion")
	end
	return Describe("CarryBody")
end
return Hints
