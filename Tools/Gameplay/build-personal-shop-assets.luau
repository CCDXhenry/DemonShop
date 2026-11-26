-- 在 Studio Edit 构建 恶魔商店、触控冲刺与耐力 HUD 模板
--!strict
local RunService = game:GetService("RunService")
local storage = game:GetService("ReplicatedStorage")
local ui = storage:WaitForChild("UI")
local shopAssetJson, _, hitMaskJson = ...
local hitMasks = game:GetService("HttpService"):JSONDecode(hitMaskJson)
local assets: {[string]: string} = game:GetService("HttpService"):JSONDecode(assert(shopAssetJson, "Pass evil_shop_assets.json to the builder"))
local sprintImage = "rbxassetid://114836508163438"
assert(not RunService:IsRunning(), "Build personal shop in Edit mode")

local function BuildTemplates(parent: Instance): ()
	local rgb = Color3.fromRGB
	local ink = rgb(21, 17, 30)
	local white = rgb(255, 255, 255)
	local blue = rgb(54, 155, 237)
	local gold = rgb(253, 215, 5)

	local function place(gui: GuiObject, name: string, x: number, y: number, w: number, h: number, color: Color3?, layer: number?): ()
		gui.Name = name
		gui.Position = UDim2.fromOffset(x, y)
		gui.Size = UDim2.fromOffset(w, h)
		gui.BorderSizePixel = 0
		gui.BackgroundTransparency = if color then 0 else 1
		if color then gui.BackgroundColor3 = color end
		gui.ZIndex = layer or 2
	end
	local function frame(root: Instance?, name: string, x: number, y: number, w: number, h: number, color: Color3?, layer: number?): Frame
		local obj = Instance.new("Frame")
		place(obj, name, x, y, w, h, color, layer)
		obj.Parent = root
		return obj
	end
	local function outline(obj: GuiObject, radius: number, thickness: number, color: Color3?): ()
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radius)
		corner.Parent = obj
		if thickness > 0 then
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
			stroke.Thickness = thickness
			stroke.Color = color or ink
			stroke.Parent = obj
		end
	end
	local function label(root: Instance, name: string, x: number, y: number, w: number, h: number, size: number, value: string, color: Color3?, layer: number?): TextLabel
		local obj = Instance.new("TextLabel")
		place(obj, name, x, y, w, h, nil, layer or 6)
		obj.AutoLocalize = false
		obj.Font = Enum.Font.BuilderSansExtraBold
		obj.Text = value
		obj.TextScaled = false
		obj.TextWrapped = false
		obj.TextSize = size
		obj.TextColor3 = color or white
		obj:SetAttribute("DesignTextSize", size)
		if not color then
			local stroke = Instance.new("UIStroke")
			stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
			stroke.Thickness = 0.065
			stroke.Color = ink
			stroke.Parent = obj
		end
		obj.Parent = root
		return obj
	end
	local function canvas(name: string): Frame
		local root = frame(nil, name, 0, 0, 1920, 1080, nil, 1)
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		return root
	end
	local function mount(obj: Instance): ()
		local old = parent:FindFirstChild(obj.Name)
		if old then old:Destroy() end
		obj.Parent = parent
	end

	local function asset(key: string): string
		return assert(assets[key], "Missing shop image: " .. key)
	end

	local function image(root: Instance, name: string, x: number, y: number, w: number, h: number, key: string, layer: number, mode: Enum.ScaleType?, slice: Rect?): ImageLabel
		local obj = Instance.new("ImageLabel")
		place(obj, name, x, y, w, h, nil, layer)
		obj.Image = asset(key)
		obj.ScaleType = mode or Enum.ScaleType.Stretch
		if slice then obj.SliceCenter = slice end
		obj.Parent = root
		return obj
	end

	local function imageButton(root: Instance, name: string, x: number, y: number, w: number, h: number, key: string, layer: number): ImageButton
		local obj = Instance.new("ImageButton")
		place(obj, name, x + w / 2, y + h / 2, w, h, nil, layer)
		obj.AnchorPoint = Vector2.new(0.5, 0.5)
		obj.Image = asset(key)
		obj.ScaleType = Enum.ScaleType.Stretch
		obj.AutoButtonColor = false
		obj:SetAttribute("HasClickSound", true)
		obj:SetAttribute("HasInteractionEffect", true)
		Instance.new("UIScale", obj)
		obj.Parent = root
		return obj
	end

	local function AddShadow(main: TextLabel, parent: Instance): ()
		local shadow = main:Clone()
		shadow:ClearAllChildren()
		shadow.Name = "ShadowText"
		shadow:SetAttribute("DesignTextSize", nil)
		shadow.ZIndex = main.ZIndex - 1
		shadow.TextColor3 = Color3.new(0, 0, 0)
		if parent == main then
			shadow.AutomaticSize = Enum.AutomaticSize.None
			shadow.Position = UDim2.fromOffset(0, 3)
			shadow.Size = UDim2.fromScale(1, 1)
		else
			shadow.Position += UDim2.fromOffset(0, 4)
		end
		shadow.Parent = parent
	end

	local shop = canvas("PersonalShopFrame")
	local panel = image(shop, "PanelFrame", 266, 120, 1389, 943, "frame_evilshop_1", 2)
	local header = image(panel, "HeaderFrame", 262, -120, 865, 322, "frame_evilshop_title", 3)
	local function SetHitMask(region: GuiObject, key: string): ()
		local mask = assert(hitMasks[key], "Missing hit mask: " .. key)
		region:SetAttribute("ModalAlphaWidth", mask.width)
		region:SetAttribute("ModalAlphaRows", mask.rows)
	end
	SetHitMask(panel, "frame_evilshop_1")
	SetHitMask(header, "frame_evilshop_title")
	local title = label(header, "TitleText", 202, 46, 461, 120, 88, "SHOP", nil, 6)
	AddShadow(title, header)
	local close = imageButton(panel, "CloseButton", 1261, -14, 94, 94, "btn_close", 8)
	SetHitMask(close, "btn_close")

	local abilities = imageButton(panel, "AbilitiesButton", 351, 90, 336, 98, "btn_green_1_336", 7)
	local tools = imageButton(panel, "ToolsButton", 701, 90, 336, 98, "btn_graypurple_1_336", 7)
	label(abilities, "TitleText", 7, 0, 322, 98, 56, "ABILITY UPGRADES", nil, 8)
	label(tools, "TitleText", 7, 0, 322, 98, 56, "TOOL EVOLUTION", nil, 8)
	for _, tab in { abilities, tools } do
		image(tab, "AlertFrame", 279, -7, 41, 44, "btn_tip", 9, Enum.ScaleType.Fit).Visible = false
	end
	panel:SetAttribute("ActiveTabImage", asset("btn_green_1_336"))
	panel:SetAttribute("InactiveTabImage", asset("btn_graypurple_1_336"))

	local abilitiesFrame = frame(panel, "AbilitiesFrame", 109, 205, 1170, 498, nil, 3)
	local toolsFrame = frame(panel, "ToolsFrame", 141, 205, 1106, 498, nil, 3)
	toolsFrame.Visible = false

	local compareSlice = Rect.new(24, 24, 64, 64)
	local function card(root: Frame, key: string, x: number, name: string, iconKey: string, isTool: boolean): ()
		local width = if isTool then 538 else 378
		local tile = image(root, key, x, 0, width, 498, if isTool then "frame_evilshop_2" else "frame_evilshop_4", 4)
		label(tile, "TitleText", 12, 14, width - 24, 78, 56, name)
		local iconWidth, iconHeight = if isTool then 230 else 220, if isTool then 190 else 182
		image(tile, "IconImage", (width - iconWidth) / 2, if isTool then 82 else 90, iconWidth, iconHeight, iconKey, 5, Enum.ScaleType.Fit)
		if isTool then
			local equipped = image(tile, "EquippedFrame", width - 136, 72, 136, 55, "icon_frame_evilshop", 7)
			label(equipped, "TitleText", 6, 0, 125, 55, 28, "EQUIPPED", Color3.new(0, 0, 0), 8)
		end

		local compareWidth, compareHeight = if isTool then 490 else 330, if isTool then 96 else 84
		local compare = image(tile, "CompareFrame", (width - compareWidth) / 2, 273, compareWidth, compareHeight, "frame_evilshop_3", 5, Enum.ScaleType.Slice, compareSlice)
		if isTool then
			local primary = label(compare, "PrimaryText", 0, 0, compareWidth, 48, 32, "")
			primary.Position = UDim2.fromOffset(8, 0)
			primary.Size = UDim2.fromOffset(compareWidth - 16, 48)
			local nextText = label(compare, "SecondaryText", 8, 42, compareWidth - 16, 48, 36, "")
			nextText.TextColor3 = gold
		else
			label(compare, "PrimaryText", 8, 0, compareWidth - 16, 84, 44, "")
		end

		local buyWidth = if isTool then 310 else 330
		local lockedArt = "btn_graypurple_2_" .. buyWidth
		local buy = imageButton(tile, "BuyButton", (width - buyWidth) / 2, 390, buyWidth, 80, lockedArt, 7)
		buy:SetAttribute("AvailableImage", asset("btn_bule_2_" .. buyWidth))
		buy:SetAttribute("LockedImage", asset(lockedArt))
		buy:SetAttribute("MaxImage", asset(lockedArt))
		local content = frame(buy, "ContentFrame", 0, 0, buyWidth, 80, nil, 8)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 10)
		layout.Parent = content
		local money = image(content, "MoneyIcon", 0, 0, 54, 45, "icon_money_s", 9, Enum.ScaleType.Fit)
		money.LayoutOrder = 1
		local price = label(content, "TitleText", 0, 0, 0, 72, 56, "", nil, 10)
		price.LayoutOrder = 2
		price.AutomaticSize = Enum.AutomaticSize.X
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(buyWidth - 84, 72)
		limit.Parent = price
		AddShadow(price, price)
	end

	card(abilitiesFrame, "moveSpeed", 0, "MOVE SPEED", "icon_sneakers", false)
	card(abilitiesFrame, "runeBatch", 396, "RUNE BATCH", "icon_paint", false)
	card(abilitiesFrame, "sellBonus", 792, "SALE BONUS", "icon_money_1", false)
	card(toolsFrame, "weapon", 0, "RUSTY PAN", "icon_pan", true)
	card(toolsFrame, "carryTool", 568, "BARE SHOULDER", "icon_power", true)

	local hud = canvas("PersonalHudFrame")
	local stamina = frame(hud, "StaminaFrame", 1642, 392, 208, 37, ink, 3)
	outline(stamina, 12, 0.025)
	local track = frame(stamina, "TrackFrame", 5, 5, 198, 27, rgb(55, 52, 72), 4)
	outline(track, 8, 0)
	local fill = frame(track, "FillFrame", 0, 0, 198, 27, blue, 5)
	fill.Size = UDim2.fromScale(1, 1)
	outline(fill, 8, 0)
	label(stamina, "TitleText", 0, 0, 208, 37, 26, "STAMINA")
	stamina.Visible = false
	local oldRootSprint = parent:FindFirstChild("TouchSprintFrame")
	if oldRootSprint then oldRootSprint:Destroy() end
	local gameScreenGui = parent:FindFirstChild("GameScreenGui")
	local center = if gameScreenGui then gameScreenGui:FindFirstChild("CenterFrame") else nil
	local touchControls = if center then center:FindFirstChild("TouchControlsFrame") else nil
	local touch = if touchControls then touchControls:FindFirstChild("TouchSprintFrame") else nil
	assert(touch and touch:IsA("Frame"), "Build GameScreenGui.CenterFrame.TouchControlsFrame.TouchSprintFrame before personal shop assets")
	local sprint = touch:FindFirstChild("SprintButton") :: ImageButton
	assert(sprint and sprint:IsA("ImageButton"), "Missing TouchSprintFrame.SprintButton")
	sprint.ImageContent = Content.fromUri(sprintImage)
	sprint.ImageRectSize = Vector2.zero
	sprint.ImageRectOffset = Vector2.zero
	sprint:SetAttribute("AttackImage", nil)
	sprint:SetAttribute("AttackRectOffset", nil)
	sprint:SetAttribute("HasClickSound", false)
	sprint:SetAttribute("HasInteractionEffect", true)
	sprint:SetAttribute("ScaleWhilePressed", true)
	sprint:SetAttribute("PressedScale", 0.86)
	sprint:SetAttribute("PressTweenSeconds", 0.1)
	sprint:SetAttribute("IdleColor", white)
	sprint:SetAttribute("ActiveColor", rgb(255, 222, 148))
	local action = sprint:FindFirstChild("ActionText") :: TextLabel
	if action then
		action.Text = "SPRINT"
	end
	mount(shop)
	mount(hud)
end

BuildTemplates(ui)
