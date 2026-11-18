-- 世界交互纯规则：按携带物与共享工位状态生成原生提示及长按状态签名
--!strict
local Config = require(script.Parent.GameConfig)
local Types = require(script.Parent.GameTypes)
local GameTexts = require(script.Parent.GameTexts)
local Rules = {}
export type Action = { target: string, version: number, action: GameTexts.TextId, object: GameTexts.TextId, signature: string }
export type Potions = { stored: number, equipped: boolean }
function Rules.Resolve(target: string, snapshot: Types.Snapshot?, items: {[string]: Types.ItemView}, held: Types.ItemView?, potions: Potions?): Action?
	if not snapshot then return nil end
	local action: GameTexts.TextId? = nil
	local object: GameTexts.TextId = "PromptBody"
	local version = snapshot.stationVersions[target]
	local unfinished = held ~= nil and held.kind == "Body" and held.stage ~= "Painted"
	if target == "Pool" then
		object = "PromptPool"
		if held then
			if unfinished and snapshot.pool < Config.PoolCapacity then action = "StoreBody" end
		elseif snapshot.pool > 0 then action = "TakeSharedBody" end
	elseif target == "Table" then
		object = "PromptTable"
		if not snapshot.painter then
			if snapshot.tableId then
				local item = items[snapshot.tableId]
				if not held and item then action = if item.stage == "Painted" then "CollectRuneBody" else "ContinuePainting" end
			elseif unfinished then action = "PlaceBody"
			elseif not held and snapshot.pool > 0 then action = "FetchAndPaint" end
		end
	elseif target == "Altar" then
		object = "PromptAltar"
		if not snapshot.altarId and held and held.kind == "Body" and held.stage == "Painted" then action = "InsertRuneBody" end
	elseif target == "Shelf" then
		object = "PromptShelf"
		if snapshot.shelf > 0 then action = "CollectPotion" end
	elseif target == "Sigil" then
		object = "PromptSigil"
		if potions and potions.equipped then action = "PromptOffer" end
	else
		local item = items[target]
		if item and not held and not item.holder and (item.location == "Ground" or (item.location == "Street" and item.hits >= Config.StunHits)) then
			version = item.version
			object = if item.kind == "Potion" then "PromptPotion" else "PromptBody"
			action = "PromptPickUp"
		end
	end
	if not action or not version then return nil end
	local tableItem = if target == "Table" and snapshot.tableId then items[snapshot.tableId] else nil
	local signature = table.concat({target, tostring(version), action, if held then held.id else "", tostring(if held then held.version else 0), tostring(if tableItem then tableItem.version else 0), tostring(if target == "Table" then snapshot.stationVersions.Pool else 0), if potions and potions.equipped then "1" else "0"}, ":")
	return {target=target, version=version, action=action, object=object, signature=signature}
end
return Rules
