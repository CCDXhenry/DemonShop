-- 在 Studio Edit 构建 M5 商店、触控冲刺与耐力 HUD 模板
--!strict
local RunService = game:GetService("RunService")
local storage = game:GetService("ReplicatedStorage")
local ui = storage:WaitForChild("UI")
local models = storage:WaitForChild("Models")
local sprintImage = "rbxassetid://114836508163438"
assert(not RunService:IsRunning(), "Build personal shop in Edit mode")

local function BuildTemplates(parent: Instance): ()
	local rgb = Color3.fromRGB
	local ink = rgb(21, 17, 30)
	local white = rgb(255, 255, 255)
	local blue = rgb(54, 155, 237)
	local orange = rgb(243, 136, 40)
	local green = rgb(83, 227, 109)
	local gold = rgb(255, 215, 67)
	local gray = rgb(172, 176, 187)
	local red = rgb(243, 61, 68)

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
		obj.Font = Enum.Font.GothamBlack
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
	local function shade(root: GuiObject): ()
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(white, rgb(206, 206, 206))
		gradient.Parent = root
	end
	local function button(root: Instance, name: string, x: number, y: number, w: number, h: number, size: number, value: string, color: Color3, layer: number?): ImageButton
		local obj = Instance.new("ImageButton")
		place(obj, name, x, y, w, h, color, layer or 5)
		obj.AutoButtonColor = false
		obj.AnchorPoint = Vector2.new(0.5, 0.5)
		obj.Position = UDim2.fromOffset(x + w / 2, y + h / 2)
		obj:SetAttribute("HasClickSound", true)
		obj:SetAttribute("HasInteractionEffect", true)
		local scale = Instance.new("UIScale")
		scale.Parent = obj
		outline(obj, 15, 0.025)
		shade(obj)
		label(obj, "TitleText", 8, 0, w - 16, h, size, value, nil, (layer or 5) + 2)
		obj.Parent = root
		return obj
	end
	local function checker(root: Frame, cell: number, tint: Color3): ()
		local w, h = root.Size.X.Offset - 14, root.Size.Y.Offset - 14
		local grid = frame(root, "CheckerFrame", 7, 7, w, h, nil, root.ZIndex + 1)
		for y = 0, math.ceil(h / cell) - 1 do
			for x = 0, math.ceil(w / cell) - 1 do
				if (x + y) % 2 == 0 then
					frame(grid, "Tile", x * cell, y * cell, math.min(cell, w - x * cell), math.min(cell, h - y * cell), tint, grid.ZIndex)
				end
			end
		end
	end
	local function badge(root: GuiObject, layer: number): ()
		local dot = frame(root, "AlertFrame", root.Size.X.Offset - 19, -10, 34, 34, red, layer)
		outline(dot, 18, 0.07)
		label(dot, "AlertText", 0, 0, 34, 34, 22, "!", nil, layer + 1)
		dot.Visible = false
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

	local shop = canvas("PersonalShopFrame")
	local panel = frame(shop, "PanelFrame", 364, 228, 1188, 586, rgb(245, 244, 247))
	outline(panel, 26, 0.014)
	checker(panel, 44, rgb(225, 224, 232))

	local header = frame(panel, "HeaderFrame", 379, -47, 430, 78, orange, 5)
	outline(header, 23, 0.025)
	checker(header, 34, rgb(252, 164, 62))
	label(header, "TitleText", 12, 0, 406, 78, 56, "SHOP", nil, 8)
	button(panel, "CloseButton", 1120, -21, 64, 64, 32, "×", red, 9)
	local abilities = button(panel, "AbilitiesButton", 230, 62, 348, 64, 28, "ABILITY UPGRADES", orange)
	local tools = button(panel, "ToolsButton", 596, 62, 348, 64, 28, "TOOL EVOLUTION", gray)
	badge(abilities, 9)
	badge(tools, 9)
	panel:SetAttribute("ActiveTabColor", orange)
	panel:SetAttribute("InactiveTabColor", gray)

	local abilitiesFrame = frame(panel, "AbilitiesFrame", 24, 150, 1140, 410, nil)
	local toolsFrame = frame(panel, "ToolsFrame", 24, 150, 1140, 410, nil)
	toolsFrame.Visible = false

	local function card(root: Frame, key: string, index: number, width: number, name: string, a: Color3, b: Color3, symbol: string?, tiers: {string}?): ()
		local tile = frame(root, key, (index - 1) * (width + 18), 0, width, 410, a, 3)
		outline(tile, 22, 0.017)
		checker(tile, 36, b)
		label(tile, "TitleText", 12, 10, width - 24, 44, 32, name)
		if tiers then
			local viewport = Instance.new("ViewportFrame")
			place(viewport, "ToolViewport", 12, 47, width - 24, 140, nil, 5)
			viewport.Ambient = rgb(171, 161, 190)
			viewport.LightColor = white
			viewport.LightDirection = Vector3.new(-1, -1, -1)
			viewport.Parent = tile
			local ribbon = frame(tile, "EquippedFrame", 17, 68, 154, 33, green, 7)
			ribbon.Rotation = -9
			outline(ribbon, 9, 0.05)
			label(ribbon, "TitleText", 4, 0, 146, 33, 20, "EQUIPPED", nil, 8)
			label(tile, "TierText", 12, 179, width - 24, 35, 26, "")
			local route = frame(tile, "ProgressFrame", 14, 218, width - 28, 38, ink, 5)
			route.BackgroundTransparency = 0.3
			outline(route, 9, 0)
			local step = (width - 40) / #tiers
			for i, id in tiers do
				local node = frame(route, "Step" .. i, 6 + (i - 1) * step, 4, step - 5, 30, ink, 6)
				outline(node, 6, 0)
				label(node, "TitleText", 0, 0, step - 5, 30, 20, id, nil, 7)
			end
		else
			if symbol then
				label(tile, "SymbolText", 0, 69, width, 102, 72, symbol)
			else
				local rune = frame(tile, "RuneMarkFrame", (width - 49) / 2, 96, 49, 49, gold, 6)
				rune.Rotation = 45
				outline(rune, 8, 0.06)
				local core = frame(rune, "CoreFrame", 14, 14, 21, 21, white, 7)
				outline(core, 3, 0.06)
			end
			local route = frame(tile, "ProgressFrame", math.floor((width - 182) / 2), 189, 182, 32, nil, 5)
			for i = 1, 5 do
				local dot = frame(route, "Step" .. i, (i - 1) * 38, 3, 28, 28, ink, 6)
				outline(dot, 16, 0.07)
			end
		end
		local compare = frame(tile, "CompareFrame", 14, 266, width - 28, 62, ink, 5)
		compare.BackgroundTransparency = 0.24
		outline(compare, 10, 0)
		label(compare, "PrimaryText", 8, 0, width - 44, 31, 22, "")
		label(compare, "SecondaryText", 8, 31, width - 44, 31, 20, "")
		local buy = button(tile, "BuyButton", 14, 341, width - 28, 54, 28, "", green)
		buy:SetAttribute("AvailableColor", green)
		buy:SetAttribute("LockedColor", gray)
		buy:SetAttribute("MaxColor", gold)
	end

	card(abilitiesFrame, "moveSpeed", 1, 368, "MOVE SPEED", blue, rgb(71, 174, 248), "⚡")
	card(abilitiesFrame, "runeBatch", 2, 368, "RUNE BATCH", orange, rgb(254, 159, 60))
	card(abilitiesFrame, "sellBonus", 3, 368, "SALE BONUS", rgb(51, 188, 78), rgb(67, 210, 89), "$")
	card(toolsFrame, "weapon", 1, 561, "WEAPON EVOLUTION", rgb(143, 100, 223), rgb(160, 119, 236), nil, {"W01", "W02", "W03", "W04", "W05", "W06"})
	card(toolsFrame, "carryTool", 2, 561, "CARRY EVOLUTION", rgb(38, 173, 157), rgb(52, 194, 176), nil, {"T0", "T1", "T2", "T3", "T4"})

	-- 徒手搬运的商店展示模型与 3D 视口空容器统一放入 Models.Previews，武器展示复用 Models.Weapons。
	local previews = models:FindFirstChild("Previews")
	if not previews or not previews:IsA("Folder") then
		local created = Instance.new("Folder")
		created.Name = "Previews"
		created.Parent = models
		previews = created
	end
	local iron = rgb(151, 160, 175)
	local function model(id: string): Model
		local old = (previews :: Folder):FindFirstChild(id)
		if old then old:Destroy() end
		local result = Instance.new("Model")
		result.Name = id
		result.Parent = previews
		return result
	end
	local function part(root: Model, name: string, size: Vector3, at: Vector3, color: Color3, shape: Enum.PartType?, angle: Vector3?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		local r = angle or Vector3.zero
		p.CFrame = CFrame.new(at) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		p.Color = color
		p.Shape = shape or Enum.PartType.Block
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Parent = root
		return p
	end
	local v, ball = Vector3.new, Enum.PartType.Ball
	local shoulder = model("T0")
	part(shoulder, "Torso", v(1.7, 2.08, 1.01), v(0, -0.52, 0), iron)
	part(shoulder, "Head", v(0.86, 0.86, 0.86), v(0, 0.98, 0), white, ball)
	for _, side in {-1, 1} do
		part(shoulder, "Shoulder", v(0.8, 1.39, 0.91), v(side * 1.05, -0.06, 0), iron, nil, v(0, 0, side * 12))
	end

	local hud = canvas("PersonalHudFrame")
	local open = button(hud, "ShopButton", 1642, 317, 208, 62, 28, "SHOP", orange)
	badge(open, 9)
	local stamina = frame(hud, "StaminaFrame", 1642, 392, 208, 37, ink, 3)
	outline(stamina, 12, 0.025)
	local track = frame(stamina, "TrackFrame", 5, 5, 198, 27, rgb(55, 52, 72), 4)
	outline(track, 8, 0)
	local fill = frame(track, "FillFrame", 0, 0, 198, 27, blue, 5)
	fill.Size = UDim2.fromScale(1, 1)
	outline(fill, 8, 0)
	label(stamina, "TitleText", 0, 0, 208, 37, 20, "STAMINA")
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
	local legacyPreviews = models:FindFirstChild("PersonalShopPreviews")
	if legacyPreviews then legacyPreviews:Destroy() end
	local legacyWorld = models:FindFirstChild("ViewportWorld")
	if legacyWorld then legacyWorld:Destroy() end
	if not (previews :: Folder):FindFirstChild("ViewportWorld") then
		local world = Instance.new("WorldModel")
		world.Name = "ViewportWorld"
		world.Parent = previews
	end
	mount(shop)
	mount(hud)
end

BuildTemplates(ui)
