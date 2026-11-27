-- 随身商店窗口、个人升级状态与跨页可购提示
--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberExtension = require(ReplicatedStorage.Core.Scripts.Shared.NumberExtension)
local Shared = ReplicatedStorage.Scripts.Shared
local GameData = require(Shared.GameData)
local GameTexts = require(Shared.GameTexts)
local Types = require(Shared.GameTypes)
local Net = require(Shared.ProcessingNet)
local Lifecycle = require(Shared.LifecycleTool)
local Rules = require(Shared.PersonalUpgradeRules)
local UIManager = require(script.Parent.UIManager)
local ModalImageHitTest = require(script.Parent.UIManager.ModalImageHitTest)
local WindowBase = require(script.Parent.UIManager.WindowBase)
local UIActions = require(script.Parent.UIManager.UIActions)
local Text = require(script.Parent.ProcessingTextTool)
local Sprint = require(script.Parent.SprintController)
local ClientPreloadManager = require(script.Parent.ClientPreloadManager)

local Shop = {}
local player = Players.LocalPlayer
local WindowId = "PersonalShop"
local AbilityCategories: {GameData.UpgradeCategory} = {"moveSpeed", "runeBatch", "sellBonus"}
local ToolCategories: {GameData.UpgradeCategory} = {"weapon", "carryTool"}
local Titles: {[string]: GameTexts.TextId} = {
	moveSpeed = "ShopMove", runeBatch = "ShopRunes", sellBonus = "ShopSales",
}
local WeaponShapes: {[string]: GameTexts.TextId} = {
	Single = "ShopWeaponSingle", Cone = "ShopWeaponCone", Spin = "ShopWeaponSpin",
	Line = "ShopWeaponLine", Slam = "ShopWeaponSlam",
}
local function Bind(text: Text.Controller, parent: Instance, name: string, id: GameTexts.TextId, ...: number): ()
	local label = parent:FindFirstChild(name) :: TextLabel
	local args: {string} = {}
	for i, value in {...} do args[i] = NumberExtension.FormatBigNumberAA(value) end
	text:Bind(label, {textId = id, args = args})
end

local function RefreshComparison(text: Text.Controller, card: ImageLabel, category: string, current: number, nextLevel: number?): ()
	local compare = card:FindFirstChild("CompareFrame") :: ImageLabel
	if category == "moveSpeed" then
		local now = Rules.GetMoveTier(current)
		if nextLevel then
			local next = Rules.GetMoveTier(nextLevel)
			Bind(text, compare, "PrimaryText", if next.unlimited then "ShopMoveUnlimitedCompare" else "ShopMoveCompare", now.walk, next.walk)
		else
			Bind(text, compare, "PrimaryText", "ShopMoveUnlimitedValue", now.walk)
		end
	elseif category == "runeBatch" then
		local now = Rules.GetRuneBatch(current)
		if nextLevel then
			Bind(text, compare, "PrimaryText", "ShopRuneCompare", now, Rules.GetRuneBatch(nextLevel))
		else
			Bind(text, compare, "PrimaryText", "ShopRuneValue", now)
		end
	elseif category == "sellBonus" then
		local now = math.round(Rules.GetSellBonus(current) * 100)
		if nextLevel then
			Bind(text, compare, "PrimaryText", "ShopSellCompare", now, math.round(Rules.GetSellBonus(nextLevel) * 100))
		else
			Bind(text, compare, "PrimaryText", "ShopSellValue", now)
		end
	else
		local icon = card:FindFirstChild("IconImage") :: ImageLabel
		local title = card:FindFirstChild("TitleText") :: TextLabel
		local primary = compare:FindFirstChild("PrimaryText") :: TextLabel
		local secondary = compare:FindFirstChild("SecondaryText") :: TextLabel
		secondary.Visible = nextLevel ~= nil
		primary.Position = UDim2.new(0, 8, if nextLevel then 0 else 0.25, 0)
		if category == "weapon" then
			local now = Rules.GetWeaponTier(current)
			icon.Image = now.icon
			text:BindSource(title, now.name_t)
			text:Bind(primary, {
				textId = "ShopCurrentWeapon",
				args = { "", NumberExtension.FormatBigNumberAA(now.targets), NumberExtension.FormatBigNumberAA(now.damage) },
				argTextIds = { WeaponShapes[now.shape] },
			})
			if nextLevel then
				local next = Rules.GetWeaponTier(nextLevel)
				text:Bind(secondary, {
					textId = "ShopNextWeapon",
					args = { next.name_t, "", NumberExtension.FormatBigNumberAA(next.targets), NumberExtension.FormatBigNumberAA(next.damage) },
					argSources = { next.name_t },
					argTextIds = { [2] = WeaponShapes[next.shape] },
				})
			end
		else
			local now = Rules.GetCarryTier(current)
			icon.Image = now.icon
			text:BindSource(title, now.name_t)
			Bind(text, compare, "PrimaryText", "ShopCurrentCarry", now.capacity)
			if nextLevel then
				local next = Rules.GetCarryTier(nextLevel)
				text:Bind(secondary, {
					textId = "ShopNextCarry",
					args = { next.name_t, NumberExtension.FormatBigNumberAA(next.capacity) },
					argSources = { next.name_t },
				})
			end
		end
	end
end

local function Coins(): number
	return player:GetAttribute("Coins") :: number? or 0
end

local function CanBuyAny(levels: Rules.Levels, categories: {GameData.UpgradeCategory}, coins: number): boolean
	for _, category in categories do
		if Rules.IsAffordable(levels, category, coins) then return true end
	end
	return false
end

function Shop.Init(gui: ScreenGui, sprintButton: ImageButton, scope: Lifecycle.Lifecycle): () -> ()
	local hud = UIManager.CreateFrame("PersonalHudFrame", gui:FindFirstChild("CenterFrame") :: Frame)
	scope:Own(hud)
	local text = Text.new()
	local modal = gui:FindFirstChild("ModalButton") :: GuiButton?
	Bind(text, sprintButton, "ActionText", "ShopSprint")
	Bind(text, hud:FindFirstChild("StaminaFrame") :: Frame, "TitleText", "ShopStamina")
	local stopSprint = Sprint.Init(hud, sprintButton, modal, scope)
	local levels = Rules.New()
	local ready = false
	local refreshWindow: (() -> ())? = nil

	local function Refresh(): ()
		local allowed = ready and player:GetAttribute("Painting") ~= true
		if not allowed then UIManager.CloseWindow(WindowId) end
		if refreshWindow then refreshWindow() end
	end

	local function NewWindow(frame: Frame, id: string, actions: UIActions.UIActions): WindowBase.WindowBase
		ClientPreloadManager.Promote("Shop")
		local window = WindowBase.new(frame, id, actions)
		local panel = frame:FindFirstChild("PanelFrame") :: ImageLabel
		local windowText = Text.new()
		local abilityPage = panel:FindFirstChild("AbilitiesFrame") :: Frame
		local toolPage = panel:FindFirstChild("ToolsFrame") :: Frame
		local abilityTab = panel:FindFirstChild("AbilitiesButton") :: ImageButton
		local toolTab = panel:FindFirstChild("ToolsButton") :: ImageButton
		local abilityAlert = abilityTab:FindFirstChild("AlertFrame") :: ImageLabel
		local toolAlert = toolTab:FindFirstChild("AlertFrame") :: ImageLabel
		local close = panel:FindFirstChild("CloseButton") :: ImageButton
		local activeImage = panel:GetAttribute("ActiveTabImage") :: string
		local inactiveImage = panel:GetAttribute("InactiveTabImage") :: string

		local currentTab = abilityPage
		local cards: {[string]: ImageLabel} = {}
		Bind(windowText, panel:FindFirstChild("HeaderFrame") :: ImageLabel, "TitleText", "ShopTitle")
		Bind(windowText, abilityTab, "TitleText", "ShopAbilities")
		Bind(windowText, toolTab, "TitleText", "ShopTools")
		for _, category in GameData.GetPersonalUpgradeOrder() do
			local page = if category == "weapon" or category == "carryTool" then toolPage else abilityPage
			local card = page:FindFirstChild(category) :: ImageLabel
			cards[category] = card
			local titleId = Titles[category]
			if titleId then Bind(windowText, card, "TitleText", titleId :: GameTexts.TextId) end
			local ribbon = card:FindFirstChild("EquippedFrame")
			if ribbon then Bind(windowText, ribbon, "TitleText", "ShopEquipped") end
			local buy = card:FindFirstChild("BuyButton") :: ImageButton
			window.scope:Connect(buy.Activated:Connect(function(): ()
				if player:GetAttribute("Painting") ~= true and Rules.IsAffordable(levels, category, Coins()) then
					Net.RequestPersonalUpgrade(category, levels[category] + 1)
				end
			end))
		end

		local function RefreshWindow(): ()
			local coins = Coins()
			abilityPage.Visible = currentTab == abilityPage
			toolPage.Visible = currentTab == toolPage
			abilityTab.Image = if abilityPage.Visible then activeImage else inactiveImage
			toolTab.Image = if toolPage.Visible then activeImage else inactiveImage
			abilityAlert.Visible = not abilityPage.Visible and CanBuyAny(levels, AbilityCategories, coins)
			toolAlert.Visible = not toolPage.Visible and CanBuyAny(levels, ToolCategories, coins)
			for category, card in cards do
				local level = levels[category]
				local cost = Rules.GetPurchaseCost(levels, category, level + 1)
				local affordable = Rules.IsAffordable(levels, category, coins)
				local buy = card:FindFirstChild("BuyButton") :: ImageButton
				buy.Active = affordable
				buy.Selectable = affordable
				local imageAttribute = if not cost then "MaxImage" elseif affordable then "AvailableImage" else "LockedImage"
				buy.Image = buy:GetAttribute(imageAttribute) :: string
				local content = buy:FindFirstChild("ContentFrame") :: Frame
				local moneyIcon = content:FindFirstChild("MoneyIcon") :: ImageLabel
				moneyIcon.Visible = cost ~= nil
				if cost then
					Bind(windowText, content, "TitleText", "ShopPrice", cost)
				else
					Bind(windowText, content, "TitleText", "ShopMax")
				end
				RefreshComparison(windowText, card, category, level, if cost then level + 1 else nil)
			end
		end

		window.scope:Connect(abilityTab.Activated:Connect(function(): () currentTab = abilityPage; RefreshWindow() end))
		window.scope:Connect(toolTab.Activated:Connect(function(): () currentTab = toolPage; RefreshWindow() end))
		window.scope:Connect(close.Activated:Connect(function(input: InputObject): ()
			local point = UIManager.GetModalPointerPosition(input)
			if not point or ModalImageHitTest.ContainsImage(close, point) or not ModalImageHitTest.ContainsShop(frame, gui, point) then
				window:Close()
			end
		end))
		window.onClosed = function(): ()
			refreshWindow = nil
			windowText:Destroy()
		end
		refreshWindow = RefreshWindow
		RefreshWindow()
		return window
	end

	UIManager.RegisterWindow(WindowId, {
		frameName = "PersonalShopFrame",
		isModal = true,
		containsModalPoint = ModalImageHitTest.ContainsShop,
		newWindow = NewWindow,
	})
	local function OnShopPrompt(prompt: ProximityPrompt, triggeringPlayer: Player): ()
		if triggeringPlayer ~= player or not ready or player:GetAttribute("Painting") == true or GuiService.MenuIsOpen then
			return
		end
		local district = workspace:FindFirstChild("NeonContractDistrict")
		local shop = if district then district:FindFirstChild("PersonalShop") else nil
		local anchor = if shop then shop:FindFirstChild("InteractionAnchor") else nil
		if anchor and prompt == anchor:FindFirstChild("ShopPrompt") then
			UIManager.OpenWindow(WindowId)
		end
	end
	local function OnNotice(notice: Types.Notice): ()
		if notice.kind == "PersonalUpgrades" and notice.personalLevels then
			levels = notice.personalLevels
			ready = true
			Refresh()
		end
	end

	scope:Connect(ProximityPromptService.PromptTriggered:Connect(OnShopPrompt))
	scope:Connect(player:GetAttributeChangedSignal("Coins"):Connect(Refresh))
	scope:Connect(player:GetAttributeChangedSignal("Painting"):Connect(Refresh))
	scope:Connect(Net.ConnectNotify(OnNotice))
	Refresh()

	return function(): ()
		UIManager.CloseWindow(WindowId)
		stopSprint()
		text:Destroy()
	end
end

return Shop
