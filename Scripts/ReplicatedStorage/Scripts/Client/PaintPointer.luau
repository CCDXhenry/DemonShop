-- 画符笔尖：笔尖钉在落笔点，左手斜握，按下时再倾斜
--!strict
local TweenService = game:GetService("TweenService")
local Pointer = {}
local RestRotation = -38
local PressedRotation = -56
local TiltInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local tiltTween: Tween? = nil
local tilted: boolean? = nil
-- 界面旋转绕控件中心，不绕锚点。把笔尖相对中心的位移转回去，锚点才会留在落笔点上。
local function TipOnPoint(brush: ImageLabel, point: Vector2, scale: number): Vector2
	local width = brush.AbsoluteSize.X / scale
	local height = brush.AbsoluteSize.Y / scale
	if width < 1 or height < 1 then
		width = brush.Size.X.Offset
		height = brush.Size.Y.Offset
	end
	local anchor = brush.AnchorPoint
	local fromCenter = Vector2.new((anchor.X - 0.5) * width, (anchor.Y - 0.5) * height)
	local theta = math.rad(brush.Rotation)
	local cosine, sine = math.cos(theta), math.sin(theta)
	local rotated = Vector2.new(fromCenter.X * cosine - fromCenter.Y * sine, fromCenter.X * sine + fromCenter.Y * cosine)
	return point + fromCenter - rotated
end
local function SetTilt(brush: ImageLabel, pressed: boolean): ()
	if tilted == pressed then
		return
	end
	local previous = tilted
	tilted = pressed
	local goal = if pressed then PressedRotation else RestRotation
	if previous == nil then
		brush.Rotation = goal
		return
	end
	if tiltTween then
		tiltTween:Cancel()
		tiltTween:Destroy()
		tiltTween = nil
	end
	local created = TweenService:Create(brush, TiltInfo, { Rotation = goal })
	tiltTween = created
	created:Play()
end
function Pointer.PlaceBrush(root: Frame, screen: Vector2, visible: boolean, pressed: boolean): ()
	local brush = root:FindFirstChild("PaintBrushCursorImage")
	if not brush or not brush:IsA("ImageLabel") then
		return
	end
	brush.Visible = visible
	if not visible then
		if tiltTween then
			tiltTween:Cancel()
			tiltTween:Destroy()
			tiltTween = nil
		end
		tilted = nil
		brush.Rotation = RestRotation
		return
	end
	local scaleNode = root:FindFirstChild("UIScale")
	local scale = if scaleNode and scaleNode:IsA("UIScale") and scaleNode.Scale > 1e-4 then scaleNode.Scale else 1
	local point = (screen - root.AbsolutePosition) / scale
	SetTilt(brush, pressed)
	local position = TipOnPoint(brush, point, scale)
	brush.Position = UDim2.fromOffset(position.X, position.Y)
end
function Pointer.Update(root: Frame, _model: Model?, _camera: Camera, _pointer: Vector2, _enabled: boolean): ()
	local cursor = root:FindFirstChild("PaintCursorFrame")
	if cursor and cursor:IsA("GuiObject") then
		cursor.Visible = false
	end
end
return Pointer
