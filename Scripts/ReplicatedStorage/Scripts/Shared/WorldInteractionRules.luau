-- 世界交互纯规则：按携带物与共享工位状态生成原生提示及长按状态签名
--!strict
local Config = require(script.Parent.GameConfig)
local Types = require(script.Parent.GameTypes)
local GameTexts = require(script.Parent.GameTexts)
local Rules = {}
export type Action = { target: string, version: number, action: GameTexts.TextId, object: GameTexts.TextId, signature: string }
export type Potions = { stored: number, equipped: boolean }
type CarryLoad = { unfinished: boolean, painted: boolean, body: boolean, other: boolean }
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
function Rules.Resolve(target: string, snapshot: Types.Snapshot?, items: {[string]: Types.ItemView}, held: Types.ItemView?, potions: Potions?, stack: { Types.ItemView }?): Action?
	if not snapshot then return nil end
	local action: GameTexts.TextId? = nil
	local object: GameTexts.TextId = "PromptBody"
	local version = snapshot.stationVersions[target]
	local load = ReadCarry(held, stack)
	local carrying = load.body or load.other or held ~= nil
	if target == "Pool" then
		object = "PromptPool"
		if load.unfinished then action = "StoreBody"
		elseif not carrying and snapshot.pool > 0 then action = "TakeSharedBody" end
	elseif target == "Table" then
		object = "PromptTable"
		if not snapshot.painter then
			if snapshot.tableId then
				local item = items[snapshot.tableId]
				if not carrying and item then action = if item.stage == "Painted" then "CollectRuneBody" else "ContinuePainting" end
			elseif load.unfinished then action = "PlaceBody"
			elseif not carrying and snapshot.pool > 0 then action = "FetchAndPaint" end
		end
	elseif target == "Altar" then
		object = "PromptAltar"
		if load.painted then action = "InsertRuneBody" end
	elseif target == "Shelf" then
		object = "PromptShelf"
		if snapshot.shelf > 0 and not load.body then action = "CollectPotion" end
	elseif target == "Sigil" then
		object = "PromptSigil"
		if potions and (potions.equipped or potions.stored > 0) then action = "PromptOffer" end
	elseif target == "Chute" then
		object = "PromptChute"
		if snapshot.unlockedFacilities and snapshot.unlockedFacilities.A00 and load.unfinished then action = "DepositBodies" end
	elseif target == "ChutePickup" then
		object = "PromptChuteLanding"
		if not load.other and (snapshot.chuteQueue or 0) > 0 then action = "TakeChuteBody" end
	elseif target == "AutoOutput" then
		object = "PromptAutoOutput"
		if not load.other and (snapshot.autoPaintedQueue or 0) > 0 then action = "TakeAutoRuneBody" end
	elseif target == "AutoShelf" then
		object = "PromptAutoShelf"
		if not load.body and (snapshot.autoShelfCount or 0) > 0 then action = "CollectAutoPotion" end
	else
		local item = items[target]
		local reachable = item and not item.holder and (item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits))
		if reachable and item then
			if item.kind == "Body" and not load.other then
				version = item.version
				object = "PromptBody"
				action = "PromptPickUp"
			elseif item.kind ~= "Body" and not load.body and not load.other then
				version = item.version
				object = "PromptPotion"
				action = "PromptPickUp"
			end
		end
	end
	if not action or not version then return nil end
	local tableItem = if target == "Table" and snapshot.tableId then items[snapshot.tableId] else nil
	local signature = table.concat({target, tostring(version), action, if held then held.id else "", tostring(if held then held.version else 0), tostring(if tableItem then tableItem.version else 0), tostring(if target == "Table" then snapshot.stationVersions.Pool else 0), if potions and (potions.equipped or potions.stored > 0) then "1" else "0"}, ":")
	return {target=target, version=version, action=action, object=object, signature=signature}
end
return Rules
