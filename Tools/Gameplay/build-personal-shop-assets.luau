-- 在 Studio Edit 构建 M5 商店、触控冲刺与耐力 HUD 模板
--!strict
local RunService = game:GetService("RunService")
local ui = game:GetService("ReplicatedStorage"):WaitForChild("UI")
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
			local world = Instance.new("WorldModel")
			world.Parent = viewport
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

	-- 展示用几何仅存在于商店资源内，独立于角色装备和战斗碰撞体。
	local previews = Instance.new("Folder")
	previews.Name = "Previews"
	previews.Parent = shop
	local iron, dark, violet = rgb(151, 160, 175), rgb(48, 39, 66), rgb(173, 80, 255)
	local brass, leather = rgb(226, 164, 70), rgb(149, 88, 47)
	local function model(id: string): Model
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
	local v, cylinder, ball = Vector3.new, Enum.PartType.Cylinder, Enum.PartType.Ball
	local pan = model("W01")
	part(pan, "Pan", v(0.28, 2.1, 2.1), v(0, 0.52, 0), dark, cylinder, v(0, 0, 75))
	part(pan, "CookingSurface", v(0.1, 1.79, 1.79), v(0.04, 0.67, 0), iron, cylinder, v(0, 0, 75))
	part(pan, "Grip", v(0.28, 0.25, 1.75), v(0, 0.3, 1.43), leather)
	local bar = model("W02")
	part(bar, "Shaft", v(0.29, 3.7, 0.29), v(0, -0.13, 0), red, nil, v(0, 0, -23))
	part(bar, "Hook", v(0.28, 0.31, 0.92), v(0.67, 1.54, 0.25), iron, nil, v(16, 22, -23))
	part(bar, "Claw", v(0.33, 0.67, 0.34), v(0.81, 1.32, 0.62), iron, nil, v(-28, 0, -23))
	local blade = model("W03")
	part(blade, "Grip", v(0.35, 1.15, 0.34), v(-0.46, -1.05, 0), dark, nil, v(0, 0, -28))
	part(blade, "Guard", v(1.28, 0.24, 0.38), v(-0.14, -0.56, 0), brass, nil, v(0, 0, -18))
	for i = 1, 5 do
		part(blade, "Edge" .. i, v(0.63 - i * 0.073, 0.72, 0.18), v(i * i * 0.05 - 0.13, i * 0.42 - 0.52, 0), if i % 2 == 0 then red else rgb(202, 46, 86), nil, v(0, 0, -i * 9))
	end
	local scythe = model("W04")
	part(scythe, "Haft", v(0.31, 4.15, 0.31), v(-0.58, -0.05, 0), dark, nil, v(0, 0, -9))
	part(scythe, "Socket", v(0.45, 0.47, 0.44), v(-0.27, 1.99, 0), violet)
	for i = 1, 6 do
		part(scythe, "Crescent" .. i, v(0.65, 0.65 - i * 0.07, 0.22), v(i * 0.35 - 0.43, 2.07 - i * i * 0.037, 0), if i % 2 == 0 then violet else iron, nil, v(0, 0, -i * 10))
	end
	local cannon = model("W05")
	part(cannon, "Receiver", v(1.4, 1.45, 1.9), v(0, 0.4, 0.37), dark)
	part(cannon, "Barrel", v(2.35, 1.15, 1.15), v(0, 0.46, -0.63), iron, cylinder, v(0, 90, 0))
	part(cannon, "Muzzle", v(0.52, 1.72, 1.72), v(0, 0.46, -1.78), dark, cylinder, v(0, 90, 0))
	part(cannon, "GravityCore", v(0.31, 0.99, 0.99), v(0, 0.46, -2.05), violet, cylinder, v(0, 90, 0))
	part(cannon, "Grip", v(0.5, 1.35, 0.54), v(0, -0.55, 0.53), dark, nil, v(-18, 0, 0))
	local hammer = model("W06")
	part(hammer, "Haft", v(0.34, 3.35, 0.34), v(-0.31, -0.48, 0), dark, nil, v(0, 0, -14))
	part(hammer, "Head", v(2.87, 1.2, 1.32), v(0.23, 1.2, 0), dark, nil, v(0, 0, -14))
	for _, side in {-1, 1} do
		part(hammer, "Anvil", v(0.64, 1.69, 1.51), v(0.23 + side * 1.32, 1.2 - side * 0.31, 0), brass, nil, v(0, 0, -14))
	end
	part(hammer, "Core", v(0.88, 0.79, 1.41), v(0.23, 1.2, 0), violet, nil, v(0, 0, -14))
	local shoulder = model("T0")
	part(shoulder, "Torso", v(1.7, 2.08, 1.01), v(0, -0.52, 0), iron)
	part(shoulder, "Head", v(0.86, 0.86, 0.86), v(0, 0.98, 0), white, ball)
	for _, side in {-1, 1} do
		part(shoulder, "Shoulder", v(0.8, 1.39, 0.91), v(side * 1.05, -0.06, 0), iron, nil, v(0, 0, side * 12))
	end
	local sack = model("T1")
	part(sack, "Sack", v(2.11, 2.55, 1.76), v(0, -0.3, 0), leather, ball)
	part(sack, "Tie", v(0.3, 0.81, 0.7), v(0, 0.95, 0), brass, cylinder, v(0, 0, 90))
	part(sack, "Knot", v(0.8, 0.57, 0.7), v(0, 1.28, 0), leather, ball)
	part(sack, "Seal", v(0.55, 0.55, 0.18), v(0, -0.34, 0.87), violet, nil, v(0, 0, 45))
	local barrow = model("T2")
	part(barrow, "Bed", v(2.37, 0.25, 2.4), v(0, 0, 0), iron, nil, v(9, 0, 0))
	part(barrow, "Wheel", v(0.44, 1.23, 1.23), v(0, -0.72, -1.02), dark, cylinder)
	part(barrow, "Hub", v(0.49, 0.57, 0.57), v(0, -0.72, -1.02), brass, cylinder)
	for _, side in {-1, 1} do
		part(barrow, "Side", v(0.25, 0.71, 2.39), v(side * 1.11, 0.45, 0), iron, nil, v(9, 0, side * -16))
		part(barrow, "Handle", v(0.2, 0.2, 2.55), v(side * 0.73, -0.17, 0.95), brass, nil, v(9, 0, 0))
	end
	local tether = model("T3")
	for i = 1, 12 do
		local theta = i * math.pi / 6
		part(tether, "Link" .. i, v(0.93, 0.4, 0.34), v(1.38 * math.cos(theta), 1.38 * math.sin(theta), 0), if i % 2 == 0 then red else dark, nil, v(i % 2 * 68, 0, math.deg(theta) + 90))
	end
	part(tether, "Clasp", v(0.68, 0.78, 0.65), v(0, -1.41, 0), iron)
	local pack = model("T4")
	part(pack, "Chassis", v(1.67, 2.77, 1.29), v(0, 0, 0), dark)
	part(pack, "Core", v(0.87, 1.31, 1.31), v(0, 0.22, 0.6), violet, cylinder, v(0, 90, 0))
	for _, side in {-1, 1} do
		part(pack, "Cylinder", v(2.18, 0.72, 0.72), v(side * 1.03, -0.08, 0.02), iron, cylinder, v(0, 0, 90))
		part(pack, "Cap", v(0.32, 0.83, 0.83), v(side * 1.03, 1.07, 0.02), brass, cylinder, v(0, 0, 90))
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
	mount(shop)
	mount(hud)
end

BuildTemplates(ui)
