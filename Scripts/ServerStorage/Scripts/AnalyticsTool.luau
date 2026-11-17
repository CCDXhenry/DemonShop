-- 基础统计：玩家批量队列、失败重试与同一关服期限内的最终发送
--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Config = require(Shared.GameConfig)
local Lifecycle = require(Shared.LifecycleTool)
local Info = require(script.Parent.ServerGameInfo)
local GameAnalytics = require(game:GetService("ReplicatedStorage").GameAnalytics)
local ServerConfig = require(script.Parent.ServerConfig)
local Analytics = {}
type EventParam = { filed: string, value: string }
type Event = { event_name: string, event_time: number, total_time: number, event_params: { EventParam } }
type Batch =
	{ proj_id: string, user_id: string, first_time: number, version: string, country: string, events: { Event }, removed: boolean, inFlight: boolean, retryAt: number }
local batches: { [Player]: Batch } = {}
local scope: Lifecycle.Lifecycle? = nil
local closing = false
local gaReady = false
local nextFlush = 0
local function Enabled(): boolean
	return Config.AnalyticsEnabled and not RunService:IsStudio() and Config.AnalyticsEndpoint ~= "" and Config.AnalyticsProjectId ~= ""
end
function Analytics.GetPendingEventCount(): number
	local count = 0
	for _, batch in batches do
		count += #batch.events
	end
	return count
end
function Analytics.Flush(): boolean
	local active = scope
	if not active or not Enabled() then
		return true
	end
	for player, batch in batches do
		if batch.inFlight or batch.retryAt > os.clock() then
			continue
		end
		local count = #batch.events
		if count == 0 then
			if batch.removed then
				batches[player] = nil
			end
			continue
		end
		local events: { Event } = {}
		for i = 1, count do
			events[i] = batch.events[i]
		end
		local body = HttpService:JSONEncode({
			proj_id = batch.proj_id,
			user_id = batch.user_id,
			first_time = batch.first_time,
			version = batch.version,
			country = batch.country,
			events = events,
		})
		batch.inFlight = true
		active:Spawn(function(): ()
			local ok, result = pcall(function(): boolean
				local response =
					HttpService:RequestAsync({ Url = Config.AnalyticsEndpoint, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
				return response.Success
			end)
			if ok and result then
				local remaining: { Event } = {}
				for i = count + 1, #batch.events do
					table.insert(remaining, batch.events[i])
				end
				batch.events = remaining
				batch.retryAt = 0
			else
				batch.retryAt = os.clock() + Config.AnalyticsFlushInterval
				warn("[Analytics] Batch retained for retry", batch.user_id, result)
			end
			batch.inFlight = false
			if batch.removed and #batch.events == 0 then
				batches[player] = nil
			end
		end)
	end
	return Analytics.GetPendingEventCount() == 0
end
function Analytics.Init(): ()
	if scope then
		return
	end
	local active = Lifecycle.new()
	scope = active
	closing = false
	if
		Config.GameAnalyticsEnabled
		and not RunService:IsStudio()
		and ServerConfig.GoogleAnalyticsGameKey ~= ""
		and ServerConfig.GoogleAnalyticsSecretKey ~= ""
	then
		GameAnalytics:configureBuild(Config.GameVersion)
		GameAnalytics:initServer(ServerConfig.GoogleAnalyticsGameKey, ServerConfig.GoogleAnalyticsSecretKey)
		GameAnalytics:setEnabledReportErrors(false)
		gaReady = true
	end
	if Enabled() then
		nextFlush = os.clock() + Config.AnalyticsFlushInterval
		active:Connect(RunService.Heartbeat:Connect(function(): ()
			if closing or os.clock() < nextFlush then
				return
			end
			nextFlush = os.clock() + Config.AnalyticsFlushInterval
			Analytics.Flush()
		end))
	end
end
function Analytics.AddEvent(player: Player, eventName: string, parameters: { [string]: string }?): ()
	if not scope or closing or not Enabled() then
		return
	end
	local info = Info.GetPlayerInfo(player)
	if not info then
		return
	end
	local batch = batches[player]
	if not batch then
		batch = {
			proj_id = Config.AnalyticsProjectId,
			user_id = tostring(player.UserId),
			first_time = info.firstEnterTime,
			version = info.firstEnterVersion,
			country = info.countryRegion,
			events = {},
			removed = false,
			inFlight = false,
			retryAt = 0,
		}
		batches[player] = batch
	end
	local params: { EventParam } = {}
	local values: { [string]: string } = parameters or {}
	for key, value in values do
		table.insert(params, { filed = key, value = value })
	end
	table.insert(batch.events, { event_name = eventName, event_time = os.time(), total_time = math.floor(info.gameTime), event_params = params })
end
function Analytics.AddPlayer(player: Player): ()
	Analytics.AddEvent(player, "PlayerAdded")
end
function Analytics.RemovePlayer(player: Player): ()
	local info = Info.GetPlayerInfo(player)
	if info then
		Analytics.AddEvent(player, "PlayerRemoving", { start_time = tostring(info.timeOfThisLogin), game_time = tostring(os.time() - info.timeOfThisLogin) })
	end
	local batch = batches[player]
	if batch then
		batch.removed = true
	end
end
Analytics.AddPlayerEnterGameEvent = Analytics.AddPlayer
Analytics.AddPlayerLeaveGameEvent = Analytics.RemovePlayer
function Analytics.AddProductPurchaseEvent(player: Player, receipt: Config.ReceiptInfo): ()
	Analytics.AddEvent(
		player,
		"GamePurchase",
		{ purchase_id = receipt.PurchaseId, player_id = tostring(receipt.PlayerId), product_id = tostring(receipt.ProductId), spent = tostring(
			receipt.CurrencySpent
		) }
	)
	if gaReady then
		GameAnalytics:ProcessReceiptCallback(receipt)
	end
end
function Analytics.AddPassPurchaseEvent(player: Player, id: number, price: number?): ()
	Analytics.AddEvent(
		player,
		"GamePurchase",
		{ purchase_id = HttpService:GenerateGUID(false), player_id = tostring(player.UserId), product_id = tostring(id), spent = tostring(price or 0) }
	)
end
function Analytics.AddTeleportData(players: { Instance }, teleportData: { [string]: unknown }): ()
	if not gaReady then
		return
	end
	local ids: { number } = {}
	for _, player in players do
		if player:IsA("Player") then
			table.insert(ids, player.UserId)
		end
	end
	GameAnalytics:addGameAnalyticsTeleportData(ids, teleportData)
end
function Analytics.Close(deadline: number): boolean
	local active = scope
	if not active then
		return true
	end
	closing = true
	while Analytics.GetPendingEventCount() > 0 and os.clock() < deadline do
		Analytics.Flush()
		if Analytics.GetPendingEventCount() == 0 then
			break
		end
		task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
	end
	local pending = Analytics.GetPendingEventCount()
	if pending > 0 then
		warn("[Analytics] Shutdown deadline reached; pending events", pending)
	end
	active:Destroy()
	scope = nil
	gaReady = false
	table.clear(batches)
	return pending == 0
end
function Analytics.Destroy(): ()
	Analytics.Close(os.clock() + Config.FoundationShutdownSeconds)
end
return Analytics
