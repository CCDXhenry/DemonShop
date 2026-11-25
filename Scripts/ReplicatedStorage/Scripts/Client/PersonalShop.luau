-- 随身商店窗口、个人升级状态与跨页可购提示
--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local GameTexts = require(Shared.GameTexts)
local Types = require(Shared.GameTypes)
local Net = require(Shared.ProcessingNet)
local Lifecycle = require(Shared.LifecycleTool)
local Rules = require(Shared.PersonalUpgradeRules)
local UIManager = require(script.Parent.UIManager)
local WindowBase = require(script.Parent.UIManager.WindowBase)
local UIActions = require(script.Parent.UIManager.UIActions)
local Text = require(script.Parent.ProcessingTextTool)
local Sprint = require(script.Parent.SprintController)

local Shop = {}
local player = Players.LocalPlayer
local WindowId = "PersonalShop"
local AbilityCategories = {"moveSpeed", "runeBatch", "sellBonus"}
local ToolCategories = {"weapon", "carryTool"}
local Titles: {[string]: GameTexts.TextId} = {
	moveSpeed = "ShopMove", runeBatch = "ShopRunes", sellBonus = "ShopSales",
	weapon = "ShopWeapon", carryTool = "ShopCarry",
}
local TierNames: {[string]: GameTexts.TextId} = {
	W01 = "ShopW01", W02 = "ShopW02", W03 = "ShopW03", W04 = "ShopW04", W05 = "ShopW05", W06 = "ShopW06",
	T0 = "ShopT0", T1 = "ShopT1", T2 = "ShopT2", T3 = "ShopT3", T4 = "ShopT4",
}
local CompletedColor = Color3.fromRGB(255, 223, 81)
local CurrentColor = Color3.fromRGB(222, 153, 56)
local LockedColor = Color3.fromRGB(58, 52, 74)

local function Bind(text: Text.Controller, parent: Instance, name: string, id: GameTexts.TextId, ...: number): ()
	local label = parent:FindFirstChild(name) :: TextLabel
	local args: {string} = {}
	for i, value in {...} do args[i] = tostring(value) end
	text:Bind(label, {textId = id, args = args})
end

local function RenderPreview(card: Frame, previews: Folder, id: string): ()
	if card:GetAttribute("PreviewId") == id then return end
	local viewport = card:FindFirstChild("ToolViewport") :: ViewportFrame
	local world = viewport:FindFirstChildOfClass("WorldModel") :: WorldModel
	local source = previews:FindFirstChild(id) :: Model
	world:ClearAllChildren()
	local clone = source:Clone()
	clone.Parent = world
	local camera: Camera = viewport:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.Parent = viewport
	local bounds, size = clone:GetBoundingBox()
	local center = bounds.Position
	camera.FieldOfView = 33
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0.5, 0.29, 1).Unit * size.Magnitude * 1.75, center)
	viewport.CurrentCamera = camera
	card:SetAttribute("PreviewId", id)
end

local function RefreshComparison(text: Text.Controller, card: Frame, previews: Folder, category: string, current: number, nextLevel: number?): ()
	local compare = card:FindFirstChild("CompareFrame") :: Frame
	if category == "moveSpeed" then
		local now = Rules.GetMoveTier(current)
		if nextLevel then
			local next = Rules.GetMoveTier(nextLevel)
			Bind(text, compare, "PrimaryText", "ShopWalkCompare", now.walk, next.walk)
			Bind(text, compare, "SecondaryText", if next.unlimited then "ShopSprintUnlimitedCompare" else "ShopSprintCompare", now.sprint, next.sprint)
		else
			Bind(text, compare, "PrimaryText", "ShopWalkValue", now.walk)
			Bind(text, compare, "SecondaryText", "ShopUnlimitedSprint", now.sprint)
		end
	elseif category == "runeBatch" then
		local now = Rules.GetRuneBatch(current)
		if nextLevel then
			Bind(text, compare, "PrimaryText", "ShopRuneCompare", now, Rules.GetRuneBatch(nextLevel))
		else
			Bind(text, compare, "PrimaryText", "ShopRuneValue", now)
		end
		Bind(text, compare, "SecondaryText", "ShopPendingAbility")
	elseif category == "sellBonus" then
		local now = math.round(Rules.GetSellBonus(current) * 100)
		if nextLevel then
			Bind(text, compare, "PrimaryText", "ShopSellCompare", now, math.round(Rules.GetSellBonus(nextLevel) * 100))
		else
			Bind(text, compare, "PrimaryText", "ShopSellValue", now)
		end
		Bind(text, compare, "SecondaryText", "ShopPrice", Rules.ComputePlayerPayout(Config.PotionReward, current))
	elseif category == "weapon" then
		local now = Rules.GetWeaponTier(current)
		RenderPreview(card, previews, now.id)
		Bind(text, card, "TierText", TierNames[now.id])
		if nextLevel then
			local next = Rules.GetWeaponTier(nextLevel)
			Bind(text, compare, "PrimaryText", "ShopWeaponCompare", now.damage, next.damage, now.targets, next.targets)
		else
			Bind(text, compare, "PrimaryText", "ShopWeaponValue", now.damage, now.targets)
		end
		Bind(text, compare, "SecondaryText", "ShopPendingWeapon")
	else
		local now = Rules.GetCarryTier(current)
		RenderPreview(card, previews, now.id)
		Bind(text, card, "TierText", TierNames[now.id])
		if nextLevel then
			Bind(text, compare, "PrimaryText", "ShopCarryCompare", now.capacity, Rules.GetCarryTier(nextLevel).capacity)
		else
			Bind(text, compare, "PrimaryText", "ShopCarryValue", now.capacity)
		end
		Bind(text, compare, "SecondaryText", "ShopPendingCarry")
	end
end

local function Coins(): number
	return player:GetAttribute("Coins") :: number? or 0
end

local function CanBuyAny(levels: Rules.Levels, categories: {string}, coins: number): boolean
	for _, category in categories do
		if Rules.IsAffordable(levels, category, coins) then return true end
	end
	return false
end

function Shop.Init(gui: ScreenGui, sprintButton: ImageButton, scope: Lifecycle.Lifecycle): () -> ()
	local hud = UIManager.CreateFrame("PersonalHudFrame", gui:FindFirstChild("CenterFrame") :: Frame)
	scope:Own(hud)
	local text = Text.new()
	local shortcut = hud:FindFirstChild("ShopButton") :: ImageButton
	local shortcutAlert = shortcut:FindFirstChild("AlertFrame") :: Frame
	local modal = gui:FindFirstChild("ModalButton") :: GuiButton?
	Bind(text, shortcut, "TitleText", "ShopTitle")
	Bind(text, sprintButton, "ActionText", "ShopSprint")
	Bind(text, hud:FindFirstChild("StaminaFrame") :: Frame, "TitleText", "ShopStamina")
	local stopSprint = Sprint.Init(hud, sprintButton, modal, scope)
	local levels = Rules.New()
	local ready = false
	local refreshWindow: (() -> ())? = nil

	local function Refresh(): ()
		local allowed = ready and player:GetAttribute("Painting") ~= true
		if not allowed then UIManager.CloseWindow(WindowId) end
		shortcut.Visible = allowed
		local coins = Coins()
		shortcutAlert.Visible = allowed and CanBuyAny(levels, Config.PersonalUpgradeOrder, coins)
		if refreshWindow then refreshWindow() end
	end

	local function NewWindow(frame: Frame, id: string, actions: UIActions.UIActions): WindowBase.WindowBase
		local window = WindowBase.new(frame, id, actions)
		local panel = frame:FindFirstChild("PanelFrame") :: Frame
		local previews = frame:FindFirstChild("Previews") :: Folder
		local windowText = Text.new()
		local abilityPage = panel:FindFirstChild("AbilitiesFrame") :: Frame
		local toolPage = panel:FindFirstChild("ToolsFrame") :: Frame
		local abilityTab = panel:FindFirstChild("AbilitiesButton") :: ImageButton
		local toolTab = panel:FindFirstChild("ToolsButton") :: ImageButton
		local abilityAlert = abilityTab:FindFirstChild("AlertFrame") :: Frame
		local toolAlert = toolTab:FindFirstChild("AlertFrame") :: Frame
		local close = panel:FindFirstChild("CloseButton") :: ImageButton
		local activeColor = panel:GetAttribute("ActiveTabColor") :: Color3
		local inactiveColor = panel:GetAttribute("InactiveTabColor") :: Color3

		local currentTab = abilityPage
		local cards: {[string]: Frame} = {}
		Bind(windowText, panel:FindFirstChild("HeaderFrame") :: Frame, "TitleText", "ShopTitle")
		Bind(windowText, abilityTab, "TitleText", "ShopAbilities")
		Bind(windowText, toolTab, "TitleText", "ShopTools")
		for _, category in Config.PersonalUpgradeOrder do
			local page = if category == "weapon" or category == "carryTool" then toolPage else abilityPage
			local card = page:FindFirstChild(category) :: Frame
			cards[category] = card
			Bind(windowText, card, "TitleText", Titles[category])
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
			abilityTab.BackgroundColor3 = if abilityPage.Visible then activeColor else inactiveColor
			toolTab.BackgroundColor3 = if toolPage.Visible then activeColor else inactiveColor
			abilityAlert.Visible = not abilityPage.Visible and CanBuyAny(levels, AbilityCategories, coins)
			toolAlert.Visible = not toolPage.Visible and CanBuyAny(levels, ToolCategories, coins)
			for category, card in cards do
				local level = levels[category]
				local costs = Config.PersonalUpgradeCosts[category]
				local cost = Rules.GetPurchaseCost(levels, category, level + 1)
				local affordable = Rules.IsAffordable(levels, category, coins)
				local buy = card:FindFirstChild("BuyButton") :: ImageButton
				buy.Active = affordable
				buy.Selectable = affordable
				local colorAttribute = if not cost then "MaxColor" elseif affordable then "AvailableColor" else "LockedColor"
				buy.BackgroundColor3 = buy:GetAttribute(colorAttribute) :: Color3
				if cost then
					Bind(windowText, buy, "TitleText", "ShopPrice", cost)
				else
					Bind(windowText, buy, "TitleText", "ShopMax")
				end
				local route = card:FindFirstChild("ProgressFrame") :: Frame
				for i = 1, #costs do
					local step = route:FindFirstChild("Step" .. i) :: Frame
					local evolution = card.Parent == toolPage
					step.BackgroundColor3 = if i > level then LockedColor elseif evolution and i ~= level then CurrentColor else CompletedColor
				end
				RefreshComparison(windowText, card, previews, category, level, if cost then level + 1 else nil)
			end
		end

		window.scope:Connect(abilityTab.Activated:Connect(function(): () currentTab = abilityPage; RefreshWindow() end))
		window.scope:Connect(toolTab.Activated:Connect(function(): () currentTab = toolPage; RefreshWindow() end))
		window.scope:Connect(close.Activated:Connect(function(): () window:Close() end))
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
		modalContentRegions = {"PanelFrame", "HeaderFrame"},
		newWindow = NewWindow,
	})
	local function Toggle(): ()
		if ready and player:GetAttribute("Painting") ~= true and not GuiService.MenuIsOpen then
			UIManager.SwitchWindowShowing(WindowId)
		end
	end
	local function OnInput(input: InputObject, processed: boolean): ()
		if input.KeyCode == Enum.KeyCode.B and not processed and not UserInputService:GetFocusedTextBox() then Toggle() end
	end
	local function OnNotice(notice: Types.Notice): ()
		if notice.kind == "PersonalUpgrades" and notice.personalLevels then
			levels = notice.personalLevels
			ready = true
			Refresh()
		end
	end

	scope:Connect(shortcut.Activated:Connect(Toggle))
	scope:Connect(UserInputService.InputBegan:Connect(OnInput))
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
