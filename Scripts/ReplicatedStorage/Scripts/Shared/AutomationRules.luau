-- 自动化公共解锁规则：前置校验、三态 UI 状态计算及 UnlockPad 外观同步
--!strict
local NumberExtension = require(game:GetService("ReplicatedStorage").Core.Scripts.Shared.NumberExtension)
local GameData = require(script.Parent.GameData)
local Texts = require(script.Parent.GameTexts)
export type PadState = string -- "Unlocked" | "Locked" | "Insufficient" | "Ready"
export type SyncOptions = {
	skipText: boolean?,
}
type AutomationRulesApi = {
	GetFacility: (facilityId: number) -> GameData.AutomationFacilityConfig?,
	ArePrerequisitesMet: (facilityId: number, unlocked: { [number]: boolean }?) -> boolean,
	ComputePadState: (facilityId: number, unlocked: { [number]: boolean }?, coins: number) -> PadState,
	FormatCost: (cost: number) -> string,
	DescribeTitle: (facilityId: number) -> string?,
	DescribeDesc: (facilityId: number) -> string?,
	DescribePrereq: (facilityId: number, state: PadState) -> Texts.Description,
	DescribePrice: (facilityId: number) -> Texts.Description?,
	FormatPrereqLabel: (facilityId: number, state: PadState, defaultLabel: string?) -> string,
	ApplyPadVisual: (pad: Model, state: PadState, prereqLabel: string?, options: SyncOptions?) -> (),
	SyncPad: (pad: Model, unlocked: { [number]: boolean }?, coins: number, options: SyncOptions?) -> PadState,
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

local function GetFacility(facilityId: number): GameData.AutomationFacilityConfig?
	return GameData.GetFacility(facilityId)
end

local function ArePrerequisitesMet(facilityId: number, unlocked: { [number]: boolean }?): boolean
	local def = GameData.GetFacility(facilityId)
	if not def then
		return false
	end
	if not def.prerequisite then
		return true
	end
	return unlocked ~= nil and unlocked[def.prerequisite] == true
end

local function ComputePadState(facilityId: number, unlocked: { [number]: boolean }?, coins: number): PadState
	local result: PadState
	local def = GameData.GetFacility(facilityId)
	if unlocked and unlocked[facilityId] == true then
		result = "Unlocked"
	elseif not def then
		result = "Locked"
	elseif not ArePrerequisitesMet(facilityId, unlocked) then
		result = "Locked"
	elseif coins ~= coins or coins < def.cost then
		result = "Insufficient"
	else
		result = "Ready"
	end
	return result
end

local function FormatCost(cost: number): string
	return NumberExtension.FormatBigNumberAA(cost)
end

local function DescribeTitle(facilityId: number): string?
	local def = GameData.GetFacility(facilityId)
	if not def then
		return nil
	end
	return def.name_t
end

local function DescribeDesc(facilityId: number): string?
	local def = GameData.GetFacility(facilityId)
	if not def then
		return nil
	end
	return def.desc_t
end

local function DescribePrereq(facilityId: number, state: PadState): Texts.Description
	local def = GameData.GetFacility(facilityId)
	if not def or not def.prerequisite then
		return { textId = "PadPrereqNone" }
	end
	if state == "Locked" then
		local prereq = GameData.GetFacility(def.prerequisite)
		local targetName = if prereq then prereq.name_t else tostring(def.prerequisite)
		local argSources = if prereq then { [1] = prereq.name_t } else nil
		return { textId = "PadPrereqRequires", args = { targetName }, argSources = argSources }
	end
	return { textId = "PadPrereqUnlocked" }
end

local function DescribePrice(facilityId: number): Texts.Description?
	local def = GameData.GetFacility(facilityId)
	if not def then
		return nil
	end
	return { textId = "PadPrice", args = { FormatCost(def.cost) } }
end

local function FormatPrereqLabel(facilityId: number, state: PadState, defaultLabel: string?): string
	local def = GameData.GetFacility(facilityId)
	if not def or not def.prerequisite then
		return defaultLabel or Texts.Automation.PadPrereqNone.source
	end
	if state == "Locked" then
		if defaultLabel and defaultLabel ~= "" then
			return defaultLabel
		end
		local prereq = GameData.GetFacility(def.prerequisite)
		local name = if prereq then prereq.name_t else tostring(def.prerequisite)
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
				if typeof(facilityId) == "number" and facilityId >= 1 and facilityId % 1 == 0 then
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

local function SyncPad(pad: Model, unlocked: { [number]: boolean }?, coins: number, options: SyncOptions?): PadState
	local facilityId = pad:GetAttribute("FacilityId")
	if typeof(facilityId) ~= "number" or facilityId < 1 or facilityId % 1 ~= 0 then
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
