-- 根据商店贴图的透明度判断橱窗和前景金币是否占用点击位置
--!strict
local HitTest = {}
local rowsByMask: {[string]: {string}} = {}

function HitTest.ContainsImage(region: GuiObject, point: Vector2): boolean
	local position, size = region.AbsolutePosition, region.AbsoluteSize
	local x, y = point.X - position.X, point.Y - position.Y
	if not region.Visible or x < 0 or y < 0 or x >= size.X or y >= size.Y then
		return false
	end
	local mask = region:GetAttribute("ModalAlphaRows") :: string?
	local width = region:GetAttribute("ModalAlphaWidth") :: number?
	if not mask or not width then return true end
	local rows = rowsByMask[mask]
	if not rows then
		rows = string.split(mask, ";")
		rowsByMask[mask] = rows
	end
	local column = math.floor(x / size.X * width)
	local row = rows[math.floor(y / size.Y * #rows) + 1]
	for first, pastLast in string.gmatch(row, "(%d+):(%d+)") do
		if column >= (tonumber(first) :: number) and column < (tonumber(pastLast) :: number) then
			return true
		end
	end
	return false
end

local function ContainsNamed(parent: Instance, name: string, point: Vector2): boolean
	local region = parent:FindFirstChild(name)
	return region ~= nil and region:IsA("GuiObject") and HitTest.ContainsImage(region, point)
end

function HitTest.ContainsShop(window: Frame, gui: ScreenGui, point: Vector2): boolean
	local panel = window:FindFirstChild("PanelFrame") :: ImageLabel
	local overlay = gui:FindFirstChild("OverlayCanvas") :: Frame
	local coins = overlay:FindFirstChild("CoinsFrame") :: ImageLabel
	return (panel.Visible and (
		HitTest.ContainsImage(panel, point)
		or ContainsNamed(panel, "HeaderFrame", point)
		or ContainsNamed(panel, "CloseButton", point)
	))
		or (overlay.Visible and coins.Visible and (
			HitTest.ContainsImage(coins, point) or ContainsNamed(coins, "MoneyIcon", point)
		))
end

return HitTest
