-- 基础统计封装：玩家生命周期与通用事件，未配置项目时不启用外部上报
--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Config = require(Shared.GameConfig)
local Lifecycle = require(Shared.LifecycleTool)
local scope: Lifecycle.Lifecycle? = nil
local Info = require(script.Parent.ServerGameInfo)
local GameAnalytics = require(game:GetService("ReplicatedStorage").GameAnalytics)
local ServerConfig = require(script.Parent.ServerConfig)
local gaReady = false
local Analytics = {}
function Analytics.Init(): ()
	if scope then
		return
	end
	scope = Lifecycle.new()
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
end
function Analytics.AddEvent(player: Player, eventName: string, parameters: { [string]: string }?): ()
	local active = scope
	if not active or not Config.AnalyticsEnabled or RunService:IsStudio() or Config.AnalyticsEndpoint == "" or Config.AnalyticsProjectId == "" then
		return
	end
	local record = Info.GetPlayerInfo(player)
	if not record then
		return
	end
	local eventParams: { { filed: string, value: string } } = {}
	local params: { [string]: string } = parameters or {}
	for key, value in params do
		table.insert(eventParams, { filed = key, value = value })
	end
	local body = HttpService:JSONEncode({
		first_time = record.firstEnterTime,
		country = record.countryRegion,
		proj_id = Config.AnalyticsProjectId,
		user_id = tostring(player.UserId),
		version = record.firstEnterVersion,
		events = { { event_name = eventName, event_time = os.time(), total_time = math.floor(record.gameTime), event_params = eventParams } },
	})
	active:Spawn(function(): ()
		local ok, result = pcall(function(): boolean
			local response =
				HttpService:RequestAsync({ Url = Config.AnalyticsEndpoint, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
			if not response.Success then
				warn("[Analytics] HTTP", response.StatusCode)
			end
			return response.Success
		end)
		if not ok then
			warn("[Analytics] Request failed", result)
		end
	end)
end
function Analytics.AddPlayer(player: Player): ()
	Analytics.AddEvent(player, "PlayerAdded")
end
function Analytics.RemovePlayer(player: Player): ()
	local info = Info.GetPlayerInfo(player)
	if info then
		Analytics.AddEvent(player, "PlayerRemoving", { start_time = tostring(info.timeOfThisLogin), game_time = tostring(os.time() - info.timeOfThisLogin) })
	end
end
Analytics.AddPlayerEnterGameEvent = Analytics.AddPlayer
Analytics.AddPlayerLeaveGameEvent = Analytics.RemovePlayer
function Analytics.AddProductPurchaseEvent(player: Player, receipt: Config.ReceiptInfo): ()
	Analytics.AddEvent(
		player,
		"GamePurchase",
		{
			purchase_id = receipt.PurchaseId,
			player_id = tostring(receipt.PlayerId),
			product_id = tostring(receipt.ProductId),
			spent = tostring(receipt.CurrencySpent),
		}
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
function Analytics.Destroy(): ()
	gaReady = false
	if scope then
		scope:Destroy()
		scope = nil
	end
end
return Analytics
