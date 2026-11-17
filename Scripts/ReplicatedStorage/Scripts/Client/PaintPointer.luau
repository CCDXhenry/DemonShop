-- 画符笔尖反馈：从 Edit 模板驱动屏幕接触圈，显示真实覆盖半径与落点
--!strict
local Config = require(game:GetService("ReplicatedStorage").Scripts.Shared.GameConfig)
local Surface = require(game:GetService("ReplicatedStorage").Scripts.Shared.PaintSurface)
local Pointer = {}
function Pointer.Update(root: Frame, model: Model?, camera: Camera, pointer: Vector2, enabled: boolean): ()
	local cursor = root:FindFirstChild("PaintCursorFrame") :: Frame
	cursor.Visible = false
	if not enabled or not model then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 100, params)
	if not hit or not hit.Instance:IsA("BasePart") or not Surface.IsBody(hit.Instance) then return end
	local sample = Surface.Project(hit.Instance, hit.Position, hit.Normal)
	if not Surface.Allowed(hit.Instance, sample.face) then return end
	local screen = camera:WorldToScreenPoint(hit.Position)
	local edge = camera:WorldToScreenPoint(hit.Position + camera.CFrame.RightVector * Config.BrushRadius)
	local scale = (root:FindFirstChild("UIScale") :: UIScale).Scale
	local position = (Vector2.new(screen.X, screen.Y) - root.AbsolutePosition) / scale
	local diameter = math.abs(edge.X - screen.X) * 2 / scale
	cursor.Position = UDim2.fromOffset(position.X, position.Y)
	cursor.Size = UDim2.fromOffset(diameter, diameter)
	cursor.Visible = true
end
return Pointer
