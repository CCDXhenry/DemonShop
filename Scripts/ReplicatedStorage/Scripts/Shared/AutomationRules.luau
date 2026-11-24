-- 自动化公共解锁规则：前置校验、三态 UI 状态计算及 UnlockPad 外观同步
--!strict
local Config = require(script.Parent.GameConfig)
local Texts = require(script.Parent.GameTexts)
export type PadState = string -- "Unlocked" | "Locked" | "Insufficient" | "Ready"
export type SyncOptions = {
	skipText: boolean?,
}
type AutomationRulesApi = {
	GetFacility: (facilityId: string) -> Config.AutomationFacilityConfig?,
	ArePrerequisitesMet: (facilityId: string, unlocked: { [string]: boolean }?) -> boolean,
	ComputePadState: (facilityId: string, unlocked: { [string]: boolean }?, coins: number) -> PadState,
	FormatCost: (cost: number) -> string,
	DescribeTitle: (facilityId: string) -> Texts.Description?,
	DescribeDesc: (facilityId: string) -> Texts.Description?,
	DescribePrereq: (facilityId: string, state: PadState) -> Texts.Description,
	DescribePrice: (facilityId: string) -> Texts.Description?,
	FormatPrereqLabel: (facilityId: string, state: PadState, defaultLabel: string?) -> string,
	ApplyPadVisual: (pad: Model, state: PadState, prereqLabel: string?, options: SyncOptions?) -> (),
	SyncPad: (pad: Model, unlocked: { [string]: boolean }?, coins: number, options: SyncOptions?) -> PadState,
}

local DefaultLockedColor = Color3.fromRGB(130, 136, 150)
local DefaultInsufficientColor = Color3.fromRGB(228, 68, 82)
local DefaultReadyColor = Color3.fromRGB(46, 229, 145)
local VisibleParts: { [string]: boolean } = {
	OuterRim = true,
	GlowRing = true,
	InnerDisc = true,
	CenterGlyph = true,
}

local function GetFacility(facilityId: string): Config.AutomationFacilityConfig?
	return Config.AutomationFacilities[facilityId]
end

local function ArePrerequisitesMet(facilityId: string, unlocked: { [string]: boolean }?): boolean
	local def = Config.AutomationFacilities[facilityId]
	if not def then
		return false
	end
	if not def.prerequisite or def.prerequisite == "" then
		return true
	end
	return unlocked ~= nil and unlocked[def.prerequisite] == true
end

local function ComputePadState(facilityId: string, unlocked: { [string]: boolean }?, coins: number): PadState
	local result: PadState
	if unlocked and unlocked[facilityId] == true then
		result = "Unlocked"
	elseif not Config.AutomationFacilities[facilityId] then
		result = "Locked"
	elseif not ArePrerequisitesMet(facilityId, unlocked) then
		result = "Locked"
	elseif coins ~= coins or coins < Config.AutomationFacilities[facilityId].cost then
		result = "Insufficient"
	else
		result = "Ready"
	end
	return result
end

local function FormatCost(cost: number): string
	local rounded = tostring(math.max(0, math.floor(cost + 0.5)))
	while true do
		local nextStr, count = string.gsub(rounded, "^(-?%d+)(%d%d%d)", "%1,%2")
		rounded = nextStr
		if count == 0 then
			break
		end
	end
	return rounded
end

local function DescribeTitle(facilityId: string): Texts.Description?
	local def = Config.AutomationFacilities[facilityId]
	if not def then
		return nil
	end
	return { textId = def.nameTextId :: Texts.TextId }
end

local function DescribeDesc(facilityId: string): Texts.Description?
	local def = Config.AutomationFacilities[facilityId]
	if not def then
		return nil
	end
	return { textId = def.descTextId :: Texts.TextId }
end

local function DescribePrereq(facilityId: string, state: PadState): Texts.Description
	local def = Config.AutomationFacilities[facilityId]
	if not def or not def.prerequisite or def.prerequisite == "" then
		return { textId = "PadPrereqNone" }
	end
	if state == "Locked" then
		local prereq = Config.AutomationFacilities[def.prerequisite]
		local targetName = if prereq then prereq.name else def.prerequisite
		local argTextIds = if prereq then { [1] = prereq.nameTextId :: Texts.TextId } else nil
		return { textId = "PadPrereqRequires", args = { targetName }, argTextIds = argTextIds }
	end
	return { textId = "PadPrereqUnlocked" }
end

local function DescribePrice(facilityId: string): Texts.Description?
	local def = Config.AutomationFacilities[facilityId]
	if not def then
		return nil
	end
	return { textId = "PadPrice", args = { FormatCost(def.cost) } }
end

local function FormatPrereqLabel(facilityId: string, state: PadState, defaultLabel: string?): string
	local def = Config.AutomationFacilities[facilityId]
	if not def or not def.prerequisite or def.prerequisite == "" then
		return defaultLabel or Texts.Automation.PadPrereqNone.source
	end
	if state == "Locked" then
		if defaultLabel and defaultLabel ~= "" then
			return defaultLabel
		end
		local prereq = Config.AutomationFacilities[def.prerequisite]
		local name = if prereq then prereq.name else def.prerequisite
		return (string.gsub(Texts.Automation.PadPrereqRequires.source, "{1}", name))
	end
	return Texts.Automation.PadPrereqUnlocked.source
end

local function ReadPadColor(pad: Model, attrName: string, fallback: Color3): Color3
	local value = pad:GetAttribute(attrName)
	return if typeof(value) == "Color3" then value else fallback
end

local function ApplyPadVisual(pad: Model, state: PadState, prereqLabel: string?, options: SyncOptions?): ()
	local hidden = state == "Unlocked"
	pad:SetAttribute("PadState", state)
	pad:SetAttribute("Unlocked", hidden)
	for _, descendant in pad:GetDescendants() do
		if descendant:IsA("BasePart") then
			if VisibleParts[descendant.Name] then
				descendant.LocalTransparencyModifier = if hidden then 1 else 0
			end
			if descendant.Name == "TriggerZone" then
				descendant.CanTouch = not hidden
			end
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = not hidden
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = not hidden
		end
	end
	if hidden then
		return
	end
	local stateColor = if state == "Locked"
		then ReadPadColor(pad, "LockedColor", DefaultLockedColor)
		elseif state == "Insufficient" then ReadPadColor(pad, "InsufficientColor", DefaultInsufficientColor)
		else ReadPadColor(pad, "ReadyColor", DefaultReadyColor)
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
		local borderStroke = card:FindFirstChild("BorderStroke")
		if borderStroke and borderStroke:IsA("UIStroke") then
			borderStroke.Color = stateColor
		end
		local accentBar = card:FindFirstChild("AccentBarFrame")
		if accentBar and accentBar:IsA("Frame") then
			accentBar.BackgroundColor3 = stateColor
		end
		local pLabel = card:FindFirstChild("PrereqText")
		if pLabel and pLabel:IsA("TextLabel") then
			if not (options and options.skipText) then
				local facilityId = pad:GetAttribute("FacilityId")
				if typeof(facilityId) == "string" then
					pLabel.Text = FormatPrereqLabel(facilityId, state, prereqLabel)
				elseif prereqLabel then
					pLabel.Text = prereqLabel
				end
			end
			pLabel.TextColor3 = if state == "Locked"
				then Color3.fromRGB(190, 196, 210)
				elseif state == "Insufficient" then Color3.fromRGB(255, 165, 172)
				else Color3.fromRGB(166, 240, 204)
		end
		local priceFrame = card:FindFirstChild("PriceFrame")
		if priceFrame then
			local priceStroke = priceFrame:FindFirstChild("PriceStroke")
			if priceStroke and priceStroke:IsA("UIStroke") then
				priceStroke.Color = stateColor
			end
		end
	end
end

local function SyncPad(pad: Model, unlocked: { [string]: boolean }?, coins: number, options: SyncOptions?): PadState
	local facilityId = pad:GetAttribute("FacilityId")
	if typeof(facilityId) ~= "string" or facilityId == "" then
		return "Locked"
	end
	local state = ComputePadState(facilityId, unlocked, coins)
	local prereqLabel = pad:GetAttribute("PrerequisiteLabel")
	ApplyPadVisual(
		pad,
		state,
		if typeof(prereqLabel) == "string" then prereqLabel else nil,
		options
	)
	return state
end

local Rules: AutomationRulesApi = {
	GetFacility = GetFacility,
	ArePrerequisitesMet = ArePrerequisitesMet,
	ComputePadState = ComputePadState,
	FormatCost = FormatCost,
	DescribeTitle = DescribeTitle,
	DescribeDesc = DescribeDesc,
	DescribePrereq = DescribePrereq,
	DescribePrice = DescribePrice,
	FormatPrereqLabel = FormatPrereqLabel,
	ApplyPadVisual = ApplyPadVisual,
	SyncPad = SyncPad,
}

return Rules
