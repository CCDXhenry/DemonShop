-- 阶段 M2 Edit 资源构建器：打通面馆空洞通道、替换自动化正式模型与构建 UnlockPad 模板；仅 Edit 模式运行
--!strict
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "DemonShop Edit required")

local chuteOnly = ... == "ChuteOnly"
local RS = game:GetService("ReplicatedStorage")
local CageGeometry = require(RS.Scripts.Shared.CageGeometry)
local Physics = require(RS.Scripts.Shared.PhysicsConfig)
local district = workspace:WaitForChild("NeonContractDistrict")
local streetUpgrade = district:WaitForChild("StreetUpgrade")
local upperCompletion = district:WaitForChild("UpperStreetCompletion")
local noodles = upperCompletion:WaitForChild("NewShop_Noodles")
assert(not noodles:FindFirstChild("ChuteMouthVisual"), "This graybox builder is for a scene without the installed chute model")
local bar5 = streetUpgrade:WaitForChild("BAR_5")
local raisedDeck = district:WaitForChild("deck"):WaitForChild("Generated"):WaitForChild("Street"):WaitForChild("Raised Street Deck With Stair Void")

local COLORS = {
	SlateDark = Color3.fromRGB(35, 29, 47),
	SlateMid = Color3.fromRGB(62, 49, 77),
	MetalDark = Color3.fromRGB(32, 34, 46),
	MetalTrim = Color3.fromRGB(78, 86, 104),
	NeonPurple = Color3.fromRGB(165, 65, 250),
	NeonCyan = Color3.fromRGB(48, 220, 255),
	NeonAmber = Color3.fromRGB(255, 168, 64),
	NeonGreen = Color3.fromRGB(46, 229, 145),
	NeonRed = Color3.fromRGB(228, 68, 82),
	PadGray = Color3.fromRGB(130, 136, 150),
	ShopWall = Color3.fromRGB(129, 76, 61),
	ShopFloor = Color3.fromRGB(66, 73, 87),
	ShopRoof = Color3.fromRGB(69, 47, 48),
	ShopNeon = Color3.fromRGB(255, 121, 84),
	ShopGold = Color3.fromRGB(255, 226, 145),
	Bar5Wall = Color3.fromRGB(81, 69, 117),
	Foundation = Color3.fromRGB(91, 99, 112),
}

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	collide: boolean?,
	transparency: number?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = if collide == nil then true else collide
	p.CanTouch = false
	p.CanQuery = p.CanCollide
	p.Transparency = transparency or 0
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function makeBox(
	parent: Instance,
	name: string,
	minV: Vector3,
	maxV: Vector3,
	color: Color3,
	material: Enum.Material,
	collide: boolean?,
	transparency: number?
): Part
	local size = maxV - minV
	local center = (minV + maxV) * 0.5
	return makePart(parent, name, size, CFrame.new(center), color, material, collide, transparency, Enum.PartType.Block)
end

local function makeCylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	centerPos: Vector3,
	color: Color3,
	material: Enum.Material,
	collide: boolean?,
	transparency: number?
): Part
	local cf = CFrame.new(centerPos) * CFrame.Angles(0, 0, math.rad(90))
	return makePart(parent, name, Vector3.new(height, diameter, diameter), cf, color, material, collide, transparency, Enum.PartType.Cylinder)
end

local function makeAnchor(parent: Instance, partName: string, attachName: string, pos: Vector3, addPrompt: boolean?): Part
	local p = makePart(parent, partName, Vector3.new(0.1, 0.1, 0.1), CFrame.new(pos), COLORS.SlateDark, Enum.Material.Plastic, false, 1)
	p.CastShadow = false
	p.CanQuery = false
	local att = Instance.new("Attachment")
	att.Name = attachName
	att.Parent = p
	if addPrompt then
		local ui = RS:FindFirstChild("UI")
		local tmpl = if ui then ui:FindFirstChild("WorldInteractionPrompt") else nil
		local prompt: ProximityPrompt
		if tmpl and tmpl:IsA("ProximityPrompt") then
			prompt = tmpl:Clone()
		else
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = "WorldInteractionPrompt"
			prompt.Style = Enum.ProximityPromptStyle.Default
			prompt.HoldDuration = 0.5
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.ClickablePrompt = true
			prompt.RequiresLineOfSight = true
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			prompt.MaxActivationDistance = 8
			prompt.AutoLocalize = false
		end
		prompt.Enabled = false
		prompt.Parent = p
	end
	return p
end

local function makePlaque(parent: Instance, name: string, size: Vector3, cf: CFrame, text: string, face: Enum.NormalId, textColor: Color3?): Part
	local plaque = makePart(parent, name, size, cf, COLORS.SlateDark, Enum.Material.Slate, true, 0)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SurfaceGui"
	sg.Face = face
	sg.CanvasSize = Vector2.new(800, 120)
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.Parent = plaque

	local lbl = Instance.new("TextLabel")
	lbl.Name = "TextLabel"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextScaled = true
	lbl.TextColor3 = textColor or COLORS.NeonCyan
	lbl.AutoLocalize = false
	lbl.Parent = sg

	local stroke = Instance.new("UIStroke")
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 0.05
	stroke.Color = Color3.fromRGB(16, 12, 26)
	stroke.Parent = lbl
	return plaque
end

local function makeWorkLight(parent: Instance, pos: Vector3, color: Color3, brightness: number, range: number): Part
	local holder = makePart(parent, "WorkAreaLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), Color3.fromRGB(163, 162, 165), Enum.Material.Plastic, false, 1)
	holder.CastShadow = false
	holder.CanQuery = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = holder
	return holder
end

local function makeRootedModel(parent: Instance, name: string, rootPos: Vector3): (Model, Part)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local root = makePart(model, "RootPart", Vector3.new(0.2, 0.2, 0.2), CFrame.new(rootPos), COLORS.SlateDark, Enum.Material.Plastic, false, 1)
	root.CastShadow = false
	root.CanQuery = false
	root.Massless = true
	model.PrimaryPart = root
	model.Parent = parent
	return model, root
end

local function weldAllToRoot(model: Model, root: BasePart): ()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Name = "Weld_" .. d.Name
			w.Part0 = root
			w.Part1 = d
			w.Parent = root
		end
	end
end

-- ============================================================================
-- 1. 构造内存态解锁底盘圈样板（仅 Edit 期克隆至 Workspace 静态场景，不留驻 ReplicatedStorage.Models）
-- ============================================================================
local modelsFolder = RS:FindFirstChild("Models")
if modelsFolder then
	local legacyPad = modelsFolder:FindFirstChild("UnlockPad")
	if legacyPad then
		legacyPad:Destroy()
	end
end
local function buildUnlockPadTemplate(): Model
	local pad = Instance.new("Model")
	pad.Name = "UnlockPad"
	pad:SetAttribute("FacilityId", 1)
	pad:SetAttribute("FacilityName", "FAST DROP CHUTE")
	pad:SetAttribute("FacilityDesc", "OPENS AN IN-SHOP CHUTE TO THE BASEMENT")
	pad:SetAttribute("PrerequisiteId", 0)
	pad:SetAttribute("PrerequisiteLabel", "PRE-REQ: NONE")
	pad:SetAttribute("Cost", 250)
	pad:SetAttribute("PadState", "Ready")
	pad:SetAttribute("LockedColor", COLORS.PadGray)
	pad:SetAttribute("InsufficientColor", COLORS.NeonRed)
	pad:SetAttribute("ReadyColor", COLORS.NeonGreen)

	local root = makePart(pad, "RootPart", Vector3.new(0.2, 0.2, 0.2), CFrame.identity, COLORS.SlateDark, Enum.Material.Plastic, false, 1)
	root.CastShadow = false
	root.CanQuery = false
	root.Massless = true
	pad.PrimaryPart = root

	local outer = makeCylinder(pad, "OuterRim", 3.4, 0.12, Vector3.new(0, 0.06, 0), COLORS.MetalDark, Enum.Material.Metal, false, 0)
	outer.CastShadow = false
	outer.Massless = true

	local glow = makeCylinder(pad, "GlowRing", 3.12, 0.15, Vector3.new(0, 0.075, 0), COLORS.NeonGreen, Enum.Material.Neon, false, 0)
	glow.CastShadow = false
	glow.Massless = true

	local inner = makeCylinder(pad, "InnerDisc", 2.66, 0.17, Vector3.new(0, 0.085, 0), Color3.fromRGB(22, 18, 34), Enum.Material.SmoothPlastic, false, 0)
	inner.CastShadow = false
	inner.Massless = true

	local core = makeCylinder(pad, "CenterGlyph", 1.15, 0.185, Vector3.new(0, 0.0925, 0), COLORS.NeonGreen, Enum.Material.Neon, false, 0.35)
	core.CastShadow = false
	core.Massless = true

	local padLight = Instance.new("PointLight")
	padLight.Name = "StateLight"
	padLight.Color = COLORS.NeonGreen
	padLight.Brightness = 0.7
	padLight.Range = 7
	padLight.Parent = core

	local trigger = makePart(pad, "TriggerZone", Vector3.new(3.4, 3.0, 3.4), CFrame.new(0, 1.5, 0), COLORS.NeonGreen, Enum.Material.Plastic, false, 1)
	trigger.CanTouch = true
	trigger.CanQuery = false
	trigger.CastShadow = false
	trigger.Massless = true

	local guiAnchor = makePart(pad, "GuiAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 2.55, 0), COLORS.SlateDark, Enum.Material.Plastic, false, 1)
	guiAnchor.CanQuery = false
	guiAnchor.CastShadow = false
	guiAnchor.Massless = true

	local bb = Instance.new("BillboardGui")
	bb.Name = "PadGui"
	bb.Adornee = guiAnchor
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 55
	bb.ResetOnSpawn = false
	bb.AutoLocalize = false
	bb.Size = UDim2.fromScale(6.2, 3.0)
	bb.StudsOffset = Vector3.zero
	bb.Parent = guiAnchor

	local card = Instance.new("Frame")
	card.Name = "CardFrame"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.fromScale(0.5, 1)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(23, 18, 36)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Parent = bb

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = card

	local borderStroke = Instance.new("UIStroke")
	borderStroke.Name = "BorderStroke"
	borderStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	borderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borderStroke.Thickness = 0.025
	borderStroke.Color = COLORS.NeonGreen
	borderStroke.Parent = card

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBarFrame"
	accentBar.Position = UDim2.fromScale(0.04, 0.05)
	accentBar.Size = UDim2.fromScale(0.92, 0.06)
	accentBar.BackgroundColor3 = COLORS.NeonGreen
	accentBar.BorderSizePixel = 0
	accentBar.Parent = card
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = accentBar

	local function makeGuiLabel(labelName: string, pos: UDim2, size: UDim2, text: string, color: Color3): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.Name = labelName
		lbl.Position = pos
		lbl.Size = size
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = text
		lbl.TextColor3 = color
		lbl.TextWrapped = true
		lbl.TextScaled = true
		lbl.AutoLocalize = false
		lbl.Parent = card

		local st = Instance.new("UIStroke")
		st.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		st.Thickness = 0.05
		st.Color = Color3.fromRGB(16, 12, 26)
		st.Parent = lbl
		return lbl
	end

	makeGuiLabel("TitleText", UDim2.fromScale(0.06, 0.13), UDim2.fromScale(0.88, 0.24), "FAST DROP CHUTE", Color3.fromRGB(246, 241, 255))
	makeGuiLabel("DescText", UDim2.fromScale(0.06, 0.37), UDim2.fromScale(0.88, 0.18), "OPENS AN IN-SHOP CHUTE TO THE BASEMENT", Color3.fromRGB(205, 198, 226))
	makeGuiLabel("PrereqText", UDim2.fromScale(0.06, 0.56), UDim2.fromScale(0.88, 0.15), "PRE-REQ: NONE", Color3.fromRGB(166, 232, 200))

	local pricePill = Instance.new("Frame")
	pricePill.Name = "PriceFrame"
	pricePill.Position = UDim2.fromScale(0.14, 0.74)
	pricePill.Size = UDim2.fromScale(0.72, 0.20)
	pricePill.BackgroundColor3 = Color3.fromRGB(36, 30, 54)
	pricePill.BorderSizePixel = 0
	pricePill.Parent = card

	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(1, 0)
	pillCorner.Parent = pricePill

	local pillStroke = Instance.new("UIStroke")
	pillStroke.Name = "PriceStroke"
	pillStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pillStroke.Thickness = 0.025
	pillStroke.Color = COLORS.NeonGreen
	pillStroke.Parent = pricePill

	local priceLbl = Instance.new("TextLabel")
	priceLbl.Name = "PriceText"
	priceLbl.Position = UDim2.fromScale(0.06, 0.08)
	priceLbl.Size = UDim2.fromScale(0.88, 0.84)
	priceLbl.BackgroundTransparency = 1
	priceLbl.Font = Enum.Font.GothamBold
	priceLbl.Text = "250 COINS"
	priceLbl.TextColor3 = Color3.fromRGB(255, 220, 88)
	priceLbl.TextWrapped = true
	priceLbl.TextScaled = true
	priceLbl.AutoLocalize = false
	priceLbl.Parent = pricePill

	local priceTextStroke = Instance.new("UIStroke")
	priceTextStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	priceTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	priceTextStroke.Thickness = 0.05
	priceTextStroke.Color = Color3.fromRGB(16, 12, 26)
	priceTextStroke.Parent = priceLbl

	weldAllToRoot(pad, root)
	return pad
end

local unlockPadTemplate = buildUnlockPadTemplate()

local function applyPadState(pad: Model, state: string, prereqLabel: string, costText: string): ()
	local stateColor = if state == "Locked"
		then COLORS.PadGray
		elseif state == "Insufficient" then COLORS.NeonRed
		else COLORS.NeonGreen
	pad:SetAttribute("PadState", state)
	local glow = pad:FindFirstChild("GlowRing")
	if glow and glow:IsA("BasePart") then
		glow.Color = stateColor
	end
	local core = pad:FindFirstChild("CenterGlyph")
	if core and core:IsA("BasePart") then
		core.Color = stateColor
		local light = core:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = stateColor
		end
	end
	local guiAnchor = pad:FindFirstChild("GuiAnchor")
	local bb = if guiAnchor then guiAnchor:FindFirstChild("PadGui") else nil
	local card = if bb then bb:FindFirstChild("CardFrame") else nil
	if card and card:IsA("Frame") then
		local bs = card:FindFirstChild("BorderStroke")
		if bs and bs:IsA("UIStroke") then
			bs.Color = stateColor
		end
		local ab = card:FindFirstChild("AccentBarFrame")
		if ab and ab:IsA("Frame") then
			ab.BackgroundColor3 = stateColor
		end
		local pLabel = card:FindFirstChild("PrereqText")
		if pLabel and pLabel:IsA("TextLabel") then
			pLabel.Text = prereqLabel
			pLabel.TextColor3 = if state == "Locked"
				then Color3.fromRGB(190, 196, 210)
				elseif state == "Insufficient" then Color3.fromRGB(255, 165, 172)
				else Color3.fromRGB(166, 240, 204)
		end
		local priceFrame = card:FindFirstChild("PriceFrame")
		if priceFrame then
			local ps = priceFrame:FindFirstChild("PriceStroke")
			if ps and ps:IsA("UIStroke") then
				ps.Color = stateColor
			end
			local pt = priceFrame:FindFirstChild("PriceText")
			if pt and pt:IsA("TextLabel") then
				pt.Text = costText
			end
		end
	end
end

local function spawnUnlockPad(
	parent: Instance,
	nodeName: string,
	pos: Vector3,
	facilityId: number,
	title: string,
	desc: string,
	prereqId: number,
	prereqLabel: string,
	cost: number,
	costText: string,
	initialState: string
): Model
	local pad = unlockPadTemplate:Clone()
	pad.Name = nodeName
	pad:SetAttribute("FacilityId", facilityId)
	pad:SetAttribute("FacilityName", title)
	pad:SetAttribute("FacilityDesc", desc)
	pad:SetAttribute("PrerequisiteId", prereqId)
	pad:SetAttribute("PrerequisiteLabel", prereqLabel)
	pad:SetAttribute("Cost", cost)
	pad:PivotTo(CFrame.new(pos))
	local guiAnchor = pad:FindFirstChild("GuiAnchor")
	local bb = if guiAnchor then guiAnchor:FindFirstChild("PadGui") else nil
	if bb and bb:IsA("BillboardGui") and guiAnchor and guiAnchor:IsA("BasePart") then
		bb.Adornee = guiAnchor
		local card = bb:FindFirstChild("CardFrame")
		if card then
			local t = card:FindFirstChild("TitleText")
			if t and t:IsA("TextLabel") then
				t.Text = title
			end
			local d = card:FindFirstChild("DescText")
			if d and d:IsA("TextLabel") then
				d.Text = desc
			end
		end
	end
	applyPadState(pad, initialState, prereqLabel, costText)
	pad.Parent = parent
	return pad
end

-- ============================================================================
-- 2. 恢复 SouthFoundation_Side (Y=19.0) 与 PerimeterJumpBarrier，并拆分 Box_001 开洞
-- ============================================================================
-- 精确原始边界（与 Studio 一致）：SouthFoundation X in [-69.615, 90.385], Y in [18, 20], Z in [-18.4, 61.6]
local sfMinX, sfMaxX = -69.61499881744385, 90.38500118255615
local sfMinY, sfMaxY = 18.0, 20.0
local sfMinZ, sfMaxZ = -18.399999618530272, 61.60000038146973
local chuteCenterX, chuteCenterZ = -58.8, -28.75
local holeMinX, holeMaxX = chuteCenterX - 9, chuteCenterX + 9
local holeMinZ, holeMaxZ = chuteCenterZ - 6.75, chuteCenterZ + 6.75
local standCenterZ = (-39 + holeMinZ) / 2
local linerReveal = 0.05 -- 护壁内面略微凸出，避免与楼板断面共面闪烁。

for _, c in streetUpgrade:GetChildren() do
	if (c.Name == "SouthFoundation_Side" and c:IsA("BasePart") and c.Size.X > 100)
		or c.Name == "SouthFoundation_West"
		or c.Name == "SouthFoundation_East"
		or c.Name == "SouthFoundation_NorthStrip"
		or c.Name == "SouthFoundation_SouthStrip"
	then
		c:Destroy()
	end
end

makeBox(streetUpgrade, "SouthFoundation_Side", Vector3.new(sfMinX, sfMinY, sfMinZ), Vector3.new(sfMaxX, sfMaxY, sfMaxZ), COLORS.Foundation, Enum.Material.Concrete, true, 0)

for _, c in upperCompletion:GetChildren() do
	if (c.Name == "PerimeterJumpBarrier" and c:IsA("BasePart") and c.Position.Z > -30)
		or c.Name == "PerimeterJumpBarrier_ChuteWest"
		or c.Name == "PerimeterJumpBarrier_ChuteEast"
		or c.Name == "PerimeterJumpBarrier_DetourWest"
		or c.Name == "PerimeterJumpBarrier_DetourSouth"
		or c.Name == "PerimeterJumpBarrier_DetourEast"
	then
		c:Destroy()
	end
end

local barrierColor = Color3.fromRGB(43, 43, 51)
makeBox(upperCompletion, "PerimeterJumpBarrier", Vector3.new(-68.0, 20.0, -17.5), Vector3.new(90.0, 120.0, -16.5), barrierColor, Enum.Material.Concrete, true, 1)

for _, c in raisedDeck:GetChildren() do
	if c.Name == "Box_001"
		or c.Name == "Box_001_West"
		or c.Name == "Box_001_East"
		or c.Name == "Box_001_NorthStrip"
		or c.Name == "Box_001_SouthStrip"
	then
		c:Destroy()
	end
end
local function makeDeckSlice(name: string, pMin: Vector3, pMax: Vector3): Part
	local p = makeBox(raisedDeck, name, pMin, pMax, COLORS.Foundation, Enum.Material.Concrete, true, 0)
	p:SetAttribute("ZFScope", "m1")
	return p
end
makeDeckSlice("Box_001_West", Vector3.new(-70.0, sfMinY, -128.0), Vector3.new(holeMinX - linerReveal, sfMaxY, -18.0))
makeDeckSlice("Box_001_East", Vector3.new(holeMaxX + linerReveal, sfMinY, -128.0), Vector3.new(90.0, sfMaxY, -18.0))
makeDeckSlice("Box_001_NorthStrip", Vector3.new(holeMinX - linerReveal, sfMinY, -128.0), Vector3.new(holeMaxX + linerReveal, sfMaxY, holeMinZ - linerReveal))
makeDeckSlice("Box_001_SouthStrip", Vector3.new(holeMinX - linerReveal, sfMinY, holeMaxZ + linerReveal), Vector3.new(holeMaxX + linerReveal, sfMaxY, -18.0))

-- 地下原有横梁与吊件擦过新井口前缘，将它们收至井筒东侧。
local cellar = district:FindFirstChild("Industrial Cellar Shell", true)
local beam = if cellar then cellar:FindFirstChild("Segment_001") else nil
if beam and beam:IsA("BasePart") and beam.Position.X - beam.Size.X * 0.5 < holeMaxX then
	local endX = beam.Position.X + beam.Size.X * 0.5
	beam.Size = Vector3.new(endX - holeMaxX, beam.Size.Y, beam.Size.Z)
	beam.Position = Vector3.new((endX + holeMaxX) * 0.5, beam.Position.Y, beam.Position.Z)
end
local hanger = if cellar then cellar:FindFirstChild("Box_006") else nil
if hanger and hanger:IsA("BasePart") and hanger.Position.X > holeMinX and hanger.Position.X < holeMaxX then
	hanger.Position = Vector3.new(holeMaxX + hanger.Size.X * 0.5, hanger.Position.Y, hanger.Position.Z)
end

-- ============================================================================
-- 3. 保留面馆正面，在门内站立带后开井，并恢复 BAR_5 西侧
-- ============================================================================
local noodlesFloorYMin, noodlesFloorYMax = 21.044943, 21.396761
local noodlesWallYMax = 35.997215
local roomMinX, roomMaxX, roomMinZ, roomMaxZ = -68.70, -49.35, -39.0, -21.409092

for _, c in noodles:GetChildren() do
	if c.Name == "InteriorCounter"
		or c.Name == "BackWall"
		or c.Name == "BackWall_West"
		or c.Name == "BackWall_PortalHeader"
		or c.Name == "Floor"
		or string.sub(c.Name, 1, 11) == "Floor_Chute"
		or (c.Name == "SideWall" and c:IsA("BasePart") and c.Position.X > -55)
		or string.sub(c.Name, 1, 13) == "SideWall_East"
		or c.Name == "FastChuteRoom"
	then
		c:Destroy()
	end
end

makeBox(noodles, "BackWall", Vector3.new(roomMinX, noodlesFloorYMin, -21.7609), Vector3.new(roomMaxX, noodlesWallYMax, -21.0573), COLORS.ShopWall, Enum.Material.Metal, true, 0)
makeBox(noodles, "SideWall_East", Vector3.new(holeMaxX, noodlesFloorYMin, roomMinZ), Vector3.new(roomMaxX, noodlesWallYMax, roomMaxZ), COLORS.ShopWall, Enum.Material.Metal, true, 0)
makeBox(noodles, "Floor", Vector3.new(roomMinX, noodlesFloorYMin, roomMinZ), Vector3.new(roomMaxX, noodlesFloorYMax, holeMinZ - linerReveal), COLORS.ShopFloor, Enum.Material.Marble, true, 0)
makeBox(noodles, "Floor_ChuteSouth", Vector3.new(roomMinX, noodlesFloorYMin, holeMaxZ + linerReveal), Vector3.new(roomMaxX, noodlesFloorYMax, roomMaxZ), COLORS.ShopFloor, Enum.Material.Marble, true, 0)
makeBox(noodles, "Floor_ChuteWest", Vector3.new(roomMinX, noodlesFloorYMin, holeMinZ - linerReveal), Vector3.new(holeMinX - linerReveal, noodlesFloorYMax, holeMaxZ + linerReveal), COLORS.ShopFloor, Enum.Material.Marble, true, 0)
makeBox(noodles, "Floor_ChuteEast", Vector3.new(holeMaxX + linerReveal, noodlesFloorYMin, holeMinZ - linerReveal), Vector3.new(roomMaxX, noodlesFloorYMax, holeMaxZ + linerReveal), COLORS.ShopFloor, Enum.Material.Marble, true, 0)

for _, c in bar5:GetChildren() do
	if c.Name == "Floor"
		or string.sub(c.Name, 1, 11) == "Floor_Chute"
		or (c.Name == "SideWall" and c:IsA("BasePart") and c.Position.X < -40)
		or string.sub(c.Name, 1, 13) == "SideWall_West"
	then
		c:Destroy()
	end
end
makeBox(bar5, "Floor", Vector3.new(-48.965, 20.0, -39.0), Vector3.new(-22.965, 20.4, -19.0), COLORS.ShopFloor, Enum.Material.Marble, true, 0)
makeBox(bar5, "SideWall_West", Vector3.new(-48.965, 20.0, -39.0), Vector3.new(-48.365, 44.0, -19.0), COLORS.Bar5Wall, Enum.Material.Metal, true, 0)

local room = Instance.new("Model")
room.Name = "FastChuteRoom"
room.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
room.Parent = noodles

-- 门槛、井口描边和井筒护壁均沿原建筑的轴线布置。
local entryStep = makeBox(room, "EntryStep", Vector3.new(-62.10, 20.345, -39.75), Vector3.new(-55.95, 20.90, -39.0), COLORS.ShopFloor, Enum.Material.Marble, true, 0)
entryStep.CastShadow = false

local rimWidth = 0.22
local linerWidth = 0.4
local function FrameOpening(prefix: string, width: number, minY: number, maxY: number, color: Color3, material: Enum.Material, collide: boolean): ()
	makeBox(room, prefix .. "_West", Vector3.new(holeMinX - width, minY, holeMinZ - width), Vector3.new(holeMinX, maxY, holeMaxZ + width), color, material, collide, 0)
	makeBox(room, prefix .. "_East", Vector3.new(holeMaxX, minY, holeMinZ - width), Vector3.new(holeMaxX + width, maxY, holeMaxZ + width), color, material, collide, 0)
	makeBox(room, prefix .. "_North", Vector3.new(holeMinX, minY, holeMinZ - width), Vector3.new(holeMaxX, maxY, holeMinZ), color, material, collide, 0)
	makeBox(room, prefix .. "_South", Vector3.new(holeMinX, minY, holeMaxZ), Vector3.new(holeMaxX, maxY, holeMaxZ + width), color, material, collide, 0)
end
FrameOpening("ShaftLiner", linerWidth, sfMinY, noodlesFloorYMax - 0.01, COLORS.MetalDark, Enum.Material.Metal, true)
FrameOpening("ChuteRim", rimWidth, noodlesFloorYMax, noodlesFloorYMax + 0.04, COLORS.NeonAmber, Enum.Material.Neon, false)
makeWorkLight(room, Vector3.new(chuteCenterX, 32, chuteCenterZ), Color3.fromRGB(255, 200, 145), 1.35, 28)
makePlaque(room, "RoomGuidePlaque", Vector3.new(8.2, 1.2, 0.22), CFrame.lookAt(
	Vector3.new(chuteCenterX, 26.5, -21.9), Vector3.new(chuteCenterX, 26.5, -22.9)
), "FAST CHUTE  ▼", Enum.NormalId.Front, COLORS.NeonAmber)

-- ============================================================================
-- 4. 清理临时灰盒 AutoHole / AutoPaint / AutoCook，构建 NeonContractDistrict.AutomationLine
-- ============================================================================
local autoLine = ensureFolder(district, "AutomationLine")
if chuteOnly then
	for _, name in { "FastChuteOpening", "ChuteThrowBaffles", "ChuteTopDropAnchor", "ChutePromptAnchor" } do
		local old = autoLine:FindFirstChild(name)
		if old then old:Destroy() end
	end
else
	for _, oldName in { "AutoHole", "AutoPaint", "AutoCook" } do
		local old = workspace:FindFirstChild(oldName)
		if old then old:Destroy() end
	end
	for _, child in autoLine:GetChildren() do child:Destroy() end
end

-- 4.1 井口封盖板 FastChuteCover（未解锁 A00 时闭合井口并与地板齐平）
local coverModel, coverRoot = makeRootedModel(autoLine, "FastChuteCover", Vector3.new(chuteCenterX, noodlesFloorYMin, chuteCenterZ))
local coverPlate = makeBox(coverModel, "CoverPlate", Vector3.new(holeMinX, noodlesFloorYMin, holeMinZ), Vector3.new(holeMaxX, noodlesFloorYMax, holeMaxZ), Color3.fromRGB(52, 56, 68), Enum.Material.DiamondPlate, true, 0)
coverPlate.CastShadow = false
makeBox(coverModel, "HatchSeamX", Vector3.new(holeMinX + 0.3, noodlesFloorYMax - 0.01, chuteCenterZ - 0.08), Vector3.new(holeMaxX - 0.3, noodlesFloorYMax + 0.015, chuteCenterZ + 0.08), COLORS.MetalDark, Enum.Material.Metal, false, 0)
makeBox(coverModel, "HatchSeamZ", Vector3.new(chuteCenterX - 0.08, noodlesFloorYMax - 0.01, holeMinZ + 0.3), Vector3.new(chuteCenterX + 0.08, noodlesFloorYMax + 0.015, holeMaxZ - 0.3), COLORS.MetalDark, Enum.Material.Metal, false, 0)
weldAllToRoot(coverModel, coverRoot)

-- 井口逻辑体积、站立带交互点，以及解锁后用于白膜物理导流的三面挡板。
local chuteOpening = makePart(autoLine, "FastChuteOpening", Vector3.new(holeMaxX - holeMinX, 1, holeMaxZ - holeMinZ), CFrame.new(chuteCenterX, noodlesFloorYMax, chuteCenterZ), COLORS.NeonAmber, Enum.Material.Plastic, false, 1)
chuteOpening.CastShadow = false
makeAnchor(autoLine, "ChuteTopDropAnchor", "ChuteTopDrop", Vector3.new(chuteCenterX, noodlesFloorYMax + 0.4, standCenterZ), false)
makeAnchor(autoLine, "ChutePromptAnchor", "ChutePrompt", Vector3.new(-53.6, noodlesFloorYMax + 1, standCenterZ), true)

CageGeometry.Build(autoLine, "ChuteThrowBaffles", CageGeometry.Baffles(chuteOpening.CFrame, chuteOpening.Size, noodlesWallYMax - 0.3))
local baffles = autoLine:WaitForChild("ChuteThrowBaffles")

-- 4.2 FastChuteLanding，24×16，南侧留取料通道。
local landingCenterZ = -28.5
local landMinX, landMaxX = chuteCenterX - 12, chuteCenterX + 12
local landMinZ, landMaxZ = landingCenterZ - 8, landingCenterZ + 8
local landingModel, landingRoot = makeRootedModel(autoLine, "FastChuteLanding", Vector3.new(chuteCenterX, 0, landingCenterZ))
makeBox(landingModel, "BaseSlab", Vector3.new(landMinX, 0, landMinZ), Vector3.new(landMaxX, 0.75, landMaxZ), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(landingModel, "CushionPad", Vector3.new(landMinX + 0.6, 0.75, landMinZ + 0.6), Vector3.new(landMaxX - 0.6, 1, landMaxZ - 0.6), COLORS.SlateMid, Enum.Material.SmoothPlastic, true, 0)
makeBox(landingModel, "CurbNorth", Vector3.new(landMinX, 0.75, landMinZ), Vector3.new(landMaxX, 1.45, landMinZ + 0.6), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(landingModel, "CurbWest", Vector3.new(landMinX, 0.75, landMinZ + 0.6), Vector3.new(landMinX + 0.6, 1.45, landMaxZ - 0.6), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(landingModel, "CurbEast", Vector3.new(landMaxX - 0.6, 0.75, landMinZ + 0.6), Vector3.new(landMaxX, 1.45, landMaxZ - 0.6), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(landingModel, "CurbSouthLeft", Vector3.new(landMinX, 0.75, landMaxZ - 0.6), Vector3.new(chuteCenterX - 3, 1.35, landMaxZ), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(landingModel, "CurbSouthRight", Vector3.new(chuteCenterX + 3, 0.75, landMaxZ - 0.6), Vector3.new(landMaxX, 1.35, landMaxZ), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeCylinder(landingModel, "TargetRingOuter", 6.2, 0.06, Vector3.new(chuteCenterX, 1.02, landingCenterZ), COLORS.NeonPurple, Enum.Material.Neon, false, 0)
makeCylinder(landingModel, "TargetRingInnerMask", 5.6, 0.07, Vector3.new(chuteCenterX, 1.025, landingCenterZ), COLORS.SlateMid, Enum.Material.SmoothPlastic, false, 0)
makeCylinder(landingModel, "TargetRingCore", 2.8, 0.08, Vector3.new(chuteCenterX, 1.03, landingCenterZ), COLORS.NeonCyan, Enum.Material.Neon, false, 0)
makeCylinder(landingModel, "TargetCoreMask", 2.2, 0.09, Vector3.new(chuteCenterX, 1.035, landingCenterZ), COLORS.SlateDark, Enum.Material.Slate, false, 0)
makePlaque(landingModel, "StationPlaque", Vector3.new(6, 1.1, 0.24), CFrame.new(chuteCenterX + 7, 1.1, landMaxZ + 0.15), "FAST CHUTE LANDING", Enum.NormalId.Back, COLORS.NeonAmber)
makeWorkLight(landingModel, Vector3.new(chuteCenterX, 9, landingCenterZ), Color3.fromRGB(220, 165, 255), 1.15, 28)
local dropZone = makePart(landingModel, "DropZone", Vector3.new(24, 1.4, 16), CFrame.new(chuteCenterX, 1, landingCenterZ), COLORS.NeonPurple, Enum.Material.Plastic, false, 1)
dropZone.CastShadow = false
makeAnchor(landingModel, "LandingAnchor", "LandingPoint", Vector3.new(chuteCenterX, 1.15, landingCenterZ), false)
makeAnchor(landingModel, "ChutePickupAnchor", "ChutePickup", Vector3.new(chuteCenterX, 1.8, landMaxZ + 0.4), true)
weldAllToRoot(landingModel, landingRoot)
CageGeometry.Build(landingModel, "AirWalls", CageGeometry.Walls(dropZone.CFrame, dropZone.Size, Physics.Cage.ChuteWallInset))

local padsFolder = ensureFolder(autoLine, "UnlockPads")
local a00Position = Vector3.new(-65.8, noodlesFloorYMax, standCenterZ)
local a00 = padsFolder:FindFirstChild("A00_FastChute")
if a00 and a00:IsA("Model") then
	a00:PivotTo(CFrame.new(a00Position))
else
	spawnUnlockPad(padsFolder, "A00_FastChute", a00Position, 1, "FAST DROP CHUTE", "OPENS AN IN-SHOP CHUTE TO THE BASEMENT", 0, "PRE-REQ: NONE", 250, "250 COINS", "Insufficient")
end
local function BuildSummary()
	return {
		opening = tostring(chuteOpening.Size),
		landing = tostring(dropZone.Size),
		baffles = #baffles:GetChildren(),
		unlockPad = unlockPadTemplate:GetFullName(),
		pads = #padsFolder:GetChildren(),
		automationChildren = #autoLine:GetChildren(),
	}
end
if chuteOnly then return BuildSummary() end

-- 4.3 BrutePost（NewShop_Noodles 店门侧方打手召唤底座）
local streetTopY = 20.345
local brutePostModel, brutePostRoot = makeRootedModel(autoLine, "BrutePost", Vector3.new(-52.1, streetTopY, -41.0))
makeBox(brutePostModel, "PostDeck", Vector3.new(-55.6, streetTopY, -42.1), Vector3.new(-48.6, streetTopY + 0.45, -39.9), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(brutePostModel, "PostTrimFront", Vector3.new(-55.6, streetTopY + 0.45, -42.15), Vector3.new(-48.6, streetTopY + 0.54, -41.98), COLORS.NeonPurple, Enum.Material.Neon, false, 0)
for idx, bayX in { -54.0, -50.2 } do
	makeCylinder(brutePostModel, "SummonRing_" .. tostring(idx), 2.3, 0.08, Vector3.new(bayX, streetTopY + 0.47, -41.0), COLORS.NeonRed, Enum.Material.Neon, false, 0)
	makeCylinder(brutePostModel, "SummonMask_" .. tostring(idx), 1.85, 0.09, Vector3.new(bayX, streetTopY + 0.475, -41.0), COLORS.MetalDark, Enum.Material.Metal, false, 0)
	makeBox(brutePostModel, "TotemPylon_" .. tostring(idx), Vector3.new(bayX - 0.32, streetTopY + 0.45, -40.35), Vector3.new(bayX + 0.32, streetTopY + 4.1, -39.85), COLORS.MetalDark, Enum.Material.Metal, true, 0)
	makeBox(brutePostModel, "TotemCore_" .. tostring(idx), Vector3.new(bayX - 0.16, streetTopY + 1.0, -40.42), Vector3.new(bayX + 0.16, streetTopY + 3.6, -40.32), COLORS.NeonPurple, Enum.Material.Neon, false, 0)
	makeAnchor(brutePostModel, "Brute" .. tostring(idx) .. "SpawnAnchor", "Brute" .. tostring(idx) .. "Spawn", Vector3.new(bayX, streetTopY + 0.55, -41.0), false)
end
makePlaque(brutePostModel, "StationPlaque", Vector3.new(5.6, 0.95, 0.22), CFrame.new(-52.1, streetTopY + 4.45, -40.1), "BRUTE SUMMON POST", Enum.NormalId.Front, COLORS.NeonAmber)
makeWorkLight(brutePostModel, Vector3.new(-52.1, streetTopY + 4.8, -42.5), Color3.fromRGB(255, 140, 120), 0.9, 14)
weldAllToRoot(brutePostModel, brutePostRoot)

-- 4.4 AutoRuneMachine (-19.0, 4.5, -27.0)，出料排队点设在中间过渡位置
local runeModel, runeRoot = makeRootedModel(autoLine, "AutoRuneMachine", Vector3.new(-19.0, 4.5, -27.0))
makeBox(runeModel, "MachineBase", Vector3.new(-24.0, 0.0, -31.5), Vector3.new(-14.0, 1.2, -22.5), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(runeModel, "PedestalCore", Vector3.new(-23.2, 1.2, -30.8), Vector3.new(-14.8, 3.3, -23.2), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(runeModel, "WorkBed", Vector3.new(-23.8, 3.3, -31.2), Vector3.new(-14.2, 3.9, -22.8), COLORS.SlateMid, Enum.Material.Slate, true, 0)
makeBox(runeModel, "WorkBedGlow", Vector3.new(-22.8, 3.9, -30.0), Vector3.new(-15.2, 3.96, -24.0), COLORS.NeonPurple, Enum.Material.Neon, false, 0.25)
makeBox(runeModel, "GantryBackColumn", Vector3.new(-23.4, 3.9, -31.2), Vector3.new(-14.6, 9.2, -30.1), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(runeModel, "GantryTopHood", Vector3.new(-23.6, 8.2, -30.6), Vector3.new(-14.4, 9.4, -25.2), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(runeModel, "GantrySideFinL", Vector3.new(-23.7, 4.0, -30.6), Vector3.new(-23.0, 8.6, -25.4), COLORS.SlateMid, Enum.Material.Metal, true, 0)
makeBox(runeModel, "GantrySideFinR", Vector3.new(-15.0, 4.0, -30.6), Vector3.new(-14.3, 8.6, -25.4), COLORS.SlateMid, Enum.Material.Metal, true, 0)
makeBox(runeModel, "RuneLaserBar", Vector3.new(-22.2, 7.85, -27.3), Vector3.new(-15.8, 8.2, -26.7), COLORS.MetalTrim, Enum.Material.Metal, false, 0)
for idx, emitterX in { -21.2, -19.0, -16.8 } do
	makeCylinder(runeModel, "EngraverHead_" .. tostring(idx), 0.75, 1.1, Vector3.new(emitterX, 7.35, -27.0), COLORS.MetalDark, Enum.Material.Metal, false, 0)
	makeCylinder(runeModel, "EngraverEmitter_" .. tostring(idx), 0.38, 0.45, Vector3.new(emitterX, 6.65, -27.0), COLORS.NeonCyan, Enum.Material.Neon, false, 0)
end
makePlaque(runeModel, "StationPlaque", Vector3.new(8.2, 1.2, 0.22), CFrame.new(-19.0, 2.0, -22.38), "AUTO RUNE  /  2.0s", Enum.NormalId.Back, COLORS.NeonCyan)
makeWorkLight(runeModel, Vector3.new(-19.0, 9.8, -22.0), Color3.fromRGB(165, 190, 255), 1.25, 22)

makeAnchor(runeModel, "MachineCenterAnchor", "MachineCenter", Vector3.new(-19.0, 4.5, -27.0), false)
makeAnchor(runeModel, "WorkBedAnchor", "WorkBed", Vector3.new(-19.0, 4.4, -27.0), false)
makeAnchor(runeModel, "OutputPadAnchor", "OutputPad", Vector3.new(-12, 4.15, -27.0), false)
makeAnchor(runeModel, "OutputPromptAnchor", "OutputPrompt", Vector3.new(-12, 3.0, -22.2), true)
makeAnchor(runeModel, "UnlockPadAnchor", "UnlockPad", Vector3.new(-19.0, 0.0, -19.0), false)
weldAllToRoot(runeModel, runeRoot)

-- 4.5 AutoSmelterMachine (-1.0, 4.5, -27.0) + 进料导轨 (-10.0, 3.9, -27.0) + 右侧自动药水暂存架 (10.0, 0.5~7.9, -31.0)
local smelterModel, smelterRoot = makeRootedModel(autoLine, "AutoSmelterMachine", Vector3.new(-1.0, 4.5, -27.0))
makeBox(smelterModel, "FeedRailDeck", Vector3.new(-14.3, 3.55, -29.6), Vector3.new(-5.7, 4.15, -24.4), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(smelterModel, "FeedRailGuardN", Vector3.new(-14.3, 4.15, -29.85), Vector3.new(-5.7, 4.85, -29.55), COLORS.SlateMid, Enum.Material.Metal, true, 0)
makeBox(smelterModel, "FeedRailGuardS", Vector3.new(-14.3, 4.15, -24.45), Vector3.new(-5.7, 4.85, -24.15), COLORS.SlateMid, Enum.Material.Metal, true, 0)
makeBox(smelterModel, "FeedRailLegW", Vector3.new(-13.6, 0.0, -29.2), Vector3.new(-12.6, 3.55, -24.8), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(smelterModel, "FeedRailLegE", Vector3.new(-7.4, 0.0, -29.2), Vector3.new(-6.4, 3.55, -24.8), COLORS.SlateDark, Enum.Material.Slate, true, 0)
for idx, rollerX in { -13.2, -11.6, -10.0, -8.4, -6.8 } do
	makeBox(smelterModel, "FeedRoller_" .. tostring(idx), Vector3.new(rollerX - 0.18, 4.15, -29.2), Vector3.new(rollerX + 0.18, 4.24, -24.8), COLORS.NeonCyan, Enum.Material.Neon, false, 0)
end
makeAnchor(runeModel, "TransferRampAnchor", "TransferRamp", Vector3.new(-16, 2.5, -27), false)
makeAnchor(runeModel, "TransferRampTopAnchor", "TransferRampTop", Vector3.new(-14, 4.5, -27), false)
local transferPass = makeAnchor(runeModel, "TransferPassAnchor", "TransferPass", Vector3.new(-12, 4.5, -27), false)
local passLight = Instance.new("PointLight")
passLight.Name, passLight.Enabled, passLight.Parent = "TransferPassLight", false, transferPass
makeAnchor(smelterModel, "FurnaceInletAnchor", "FurnaceInlet", Vector3.new(-5, 4.5, -27), false)

makeBox(smelterModel, "SmelterBase", Vector3.new(-6.0, 0.0, -31.5), Vector3.new(4.0, 1.3, -22.5), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(smelterModel, "FurnaceBody", Vector3.new(-5.4, 1.3, -31.0), Vector3.new(3.4, 7.6, -23.2), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(smelterModel, "FurnaceTopCap", Vector3.new(-5.8, 7.6, -31.4), Vector3.new(3.8, 8.4, -22.8), COLORS.SlateMid, Enum.Material.Slate, true, 0)
makeBox(smelterModel, "ReactorCore", Vector3.new(-3.8, 2.5, -29.6), Vector3.new(1.8, 6.2, -23.45), COLORS.NeonPurple, Enum.Material.Neon, false, 0)
local viewGlass = makeBox(smelterModel, "ReactorViewport", Vector3.new(-4.0, 2.4, -23.22), Vector3.new(2.0, 6.3, -23.05), Color3.fromRGB(165, 120, 220), Enum.Material.Glass, true, 0.45)
viewGlass.CastShadow = false
makeBox(smelterModel, "ViewportFrameTop", Vector3.new(-4.25, 6.25, -23.26), Vector3.new(2.25, 6.55, -22.96), COLORS.MetalTrim, Enum.Material.Metal, false, 0)
makeBox(smelterModel, "ViewportFrameBottom", Vector3.new(-4.25, 2.2, -23.26), Vector3.new(2.25, 2.5, -22.96), COLORS.MetalTrim, Enum.Material.Metal, false, 0)
makeBox(smelterModel, "ViewportFrameLeft", Vector3.new(-4.25, 2.5, -23.26), Vector3.new(-3.95, 6.25, -22.96), COLORS.MetalTrim, Enum.Material.Metal, false, 0)
makeBox(smelterModel, "ViewportFrameRight", Vector3.new(1.95, 2.5, -23.26), Vector3.new(2.25, 6.25, -22.96), COLORS.MetalTrim, Enum.Material.Metal, false, 0)
for idx, ribX in { -2.5, -1.0, 0.5 } do
	makeBox(smelterModel, "ViewportGrate_" .. tostring(idx), Vector3.new(ribX - 0.12, 2.5, -23.12), Vector3.new(ribX + 0.12, 6.25, -22.94), COLORS.MetalDark, Enum.Material.Metal, false, 0)
end
for idx, stackX in { -3.8, 1.8 } do
	makeCylinder(smelterModel, "ExhaustStack_" .. tostring(idx), 1.5, 2.4, Vector3.new(stackX, 9.5, -28.6), COLORS.MetalDark, Enum.Material.Metal, true, 0)
	makeCylinder(smelterModel, "ExhaustGlowRing_" .. tostring(idx), 1.7, 0.25, Vector3.new(stackX, 10.3, -28.6), COLORS.NeonCyan, Enum.Material.Neon, false, 0)
end
makeBox(smelterModel, "OutputConduitPipe", Vector3.new(3.4, 4.6, -31.3), Vector3.new(5.4, 5.2, -30.7), COLORS.MetalTrim, Enum.Material.Metal, false, 0)
makeBox(smelterModel, "OutputConduitGlow", Vector3.new(3.5, 4.82, -30.72), Vector3.new(5.3, 4.98, -30.62), COLORS.NeonPurple, Enum.Material.Neon, false, 0)

local rackFolder = Instance.new("Model")
rackFolder.Name = "AutoPotionRack"
rackFolder.Parent = smelterModel
makeBox(rackFolder, "RackPillarWest", Vector3.new(5.0, 0.0, -33.3), Vector3.new(5.7, 9.1, -28.7), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(rackFolder, "RackPillarEast", Vector3.new(14.3, 0.0, -33.3), Vector3.new(15.0, 9.1, -28.7), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(rackFolder, "RackBackPanel", Vector3.new(5.7, 0.0, -33.45), Vector3.new(14.3, 9.0, -33.0), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makeBox(rackFolder, "RackTierLower", Vector3.new(5.5, 0.0, -33.2), Vector3.new(14.5, 1.0, -28.8), COLORS.SlateMid, Enum.Material.Slate, true, 0)
makeBox(rackFolder, "RackTierMiddle", Vector3.new(5.5, 3.45, -33.2), Vector3.new(14.5, 4.45, -28.8), COLORS.SlateMid, Enum.Material.Slate, true, 0)
makeBox(rackFolder, "RackTierUpper", Vector3.new(5.5, 7.45, -33.2), Vector3.new(14.5, 8.45, -28.8), COLORS.SlateMid, Enum.Material.Slate, true, 0)
for idx, tierY in { 1.0, 4.45, 8.45 } do
	makeBox(rackFolder, "RackTierGlow_" .. tostring(idx), Vector3.new(5.7, tierY - 0.14, -28.82), Vector3.new(14.3, tierY - 0.02, -28.72), COLORS.NeonCyan, Enum.Material.Neon, false, 0)
end
makePlaque(rackFolder, "RackPlaque", Vector3.new(8.2, 1.05, 0.22), CFrame.new(10.0, 8.95, -28.7), "AUTO POTIONS", Enum.NormalId.Back, COLORS.NeonPurple)
local rackPoints = ensureFolder(rackFolder, "PotionPoints")
local slotCoords = {
	Vector3.new(7.4, 4.9, -31.0),
	Vector3.new(10.0, 4.9, -31.0),
	Vector3.new(12.6, 4.9, -31.0),
	Vector3.new(7.4, 1.45, -31.0),
	Vector3.new(10.0, 1.45, -31.0),
	Vector3.new(12.6, 1.45, -31.0),
}
for i, pt in slotCoords do
	makeAnchor(rackPoints, "PotionPoint" .. tostring(i), "PotionPoint", pt, false)
end
makeAnchor(rackFolder, "AutoShelfPickupAnchor", "StockPickup", Vector3.new(10.0, 2.0, -27.2), true)

makePlaque(smelterModel, "StationPlaque", Vector3.new(8.4, 1.2, 0.22), CFrame.new(-1.0, 0.95, -22.38), "AUTO SMELTER  /  2.5s", Enum.NormalId.Back, COLORS.NeonCyan)
makeWorkLight(smelterModel, Vector3.new(3.0, 9.8, -24.5), Color3.fromRGB(179, 155, 225), 1.3, 24)
makeAnchor(smelterModel, "MachineCenterAnchor", "MachineCenter", Vector3.new(-1.0, 4.5, -27.0), false)
makeAnchor(smelterModel, "UnlockPadAnchor", "UnlockPad", Vector3.new(-1.0, 0.0, -19.0), false)
weldAllToRoot(smelterModel, smelterRoot)

-- 4.6 AutoClerkStation (22.0, 1.0, -27.25)
local clerkModel, clerkRoot = makeRootedModel(autoLine, "AutoClerkStation", Vector3.new(22.0, 1.0, -27.25))
makeBox(clerkModel, "StationBase", Vector3.new(18.0, 0.0, -31.25), Vector3.new(26.0, 0.75, -23.25), COLORS.SlateDark, Enum.Material.Slate, true, 0)
makeBox(clerkModel, "DispatchDeck", Vector3.new(18.5, 0.75, -30.75), Vector3.new(25.5, 1.0, -23.75), COLORS.SlateMid, Enum.Material.SmoothPlastic, true, 0)
makeCylinder(clerkModel, "DispatchCircleOuter", 4.8, 0.06, Vector3.new(22.0, 1.02, -27.25), COLORS.NeonGreen, Enum.Material.Neon, false, 0)
makeCylinder(clerkModel, "DispatchCircleMask", 4.2, 0.07, Vector3.new(22.0, 1.025, -27.25), COLORS.SlateMid, Enum.Material.SmoothPlastic, false, 0)
makeCylinder(clerkModel, "DispatchCircleCore", 1.8, 0.08, Vector3.new(22.0, 1.03, -27.25), COLORS.NeonCyan, Enum.Material.Neon, false, 0.25)
makeBox(clerkModel, "ConsoleDesk", Vector3.new(19.2, 1.0, -30.85), Vector3.new(24.8, 3.6, -29.65), COLORS.MetalDark, Enum.Material.Metal, true, 0)
makePlaque(clerkModel, "ConsoleScreen", Vector3.new(5.2, 1.8, 0.2), CFrame.new(22.0, 4.6, -30.15), "  AUTO CLERK DISPATCH  ", Enum.NormalId.Back, COLORS.NeonGreen)
for idx, sideX in { 18.7, 25.3 } do
	makeBox(clerkModel, "BeaconPillar_" .. tostring(idx), Vector3.new(sideX - 0.45, 1.0, -30.55), Vector3.new(sideX + 0.45, 5.2, -29.65), COLORS.SlateDark, Enum.Material.Slate, true, 0)
	local crystal = makePart(clerkModel, "BeaconCrystal_" .. tostring(idx), Vector3.new(0.65, 0.65, 0.65), CFrame.new(sideX, 5.75, -30.1) * CFrame.Angles(math.rad(45), math.rad(45), 0), COLORS.NeonGreen, Enum.Material.Neon, false, 0)
	crystal.CastShadow = false
end
makePlaque(clerkModel, "StationPlaque", Vector3.new(6.8, 1.1, 0.22), CFrame.new(22.0, 0.55, -23.13), "AUTO CLERK", Enum.NormalId.Back, COLORS.NeonGreen)
makeWorkLight(clerkModel, Vector3.new(22.0, 8.8, -24.75), Color3.fromRGB(140, 240, 200), 1.2, 22)
makeAnchor(clerkModel, "ClerkSpawnAnchor", "ClerkSpawn", Vector3.new(22.0, 1.15, -27.25), false)
makeAnchor(clerkModel, "UnlockPadAnchor", "UnlockPad", Vector3.new(22.0, 0.0, -19.25), false)
weldAllToRoot(clerkModel, clerkRoot)

-- ============================================================================
-- 5. 放置 6 处解锁底盘圈（A00 ~ A05，使用英文基准词条 + PadGui.AutoLocalize=false）
-- ============================================================================
spawnUnlockPad(padsFolder, "A01_Brute1", Vector3.new(-54.0, streetTopY, -44.2), 2, "HELL BRUTE #1", "AUTO-STUNS CITIZENS AND DROPS INTO CHUTE", 1, "REQUIRES: FAST DROP CHUTE", 1000, "1K COINS", "Locked")
spawnUnlockPad(padsFolder, "A02_Brute2", Vector3.new(-50.2, streetTopY, -44.2), 3, "HELL BRUTE #2", "ADDS A SECOND BRUTE TO DOUBLE SUPPLY", 2, "REQUIRES: HELL BRUTE #1", 2500, "2.5K COINS", "Locked")
spawnUnlockPad(padsFolder, "A03_AutoRune", Vector3.new(-19.0, 0.0, -19.25), 4, "AUTO RUNE TABLE", "AUTO-PULLS BODIES AND ENGRAVES RUNES", 1, "REQUIRES: FAST DROP CHUTE", 2000, "2K COINS", "Locked")
spawnUnlockPad(padsFolder, "A04_AutoSmelter", Vector3.new(-1.0, 0.0, -17.25), 5, "AUTO SMELTER", "AUTO-SMELTS RUNE BODIES INTO POTIONS", 4, "REQUIRES: AUTO RUNE TABLE", 4500, "4.5K COINS", "Locked")
spawnUnlockPad(padsFolder, "A05_AutoClerk", Vector3.new(22.0, 0.0, -19.25), 6, "AUTO CLERK", "AUTO-DELIVERS POTIONS FOR COINS", 0, "PRE-REQ: NONE", 9000, "9K COINS", "Insufficient")

unlockPadTemplate:Destroy()
return BuildSummary()
