-- 在撞击点生成短暂的墙面能量光效
--!strict
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Physics = require(game:GetService("ReplicatedStorage").Scripts.Shared.PhysicsConfig)
local View = {}
local ImpactDiameter = 2.6
local FaceOffset = 0.035
local CageColor = Color3.fromRGB(141, 115, 255)
local BaffleColor = Color3.fromRGB(112, 224, 255)

function View.PlayAt(position: Vector3, normal: Vector3, isBaffle: boolean?, parent: Instance?): ()
	if normal.Magnitude < 1e-4 then return end
	local n = normal.Unit
	local reference = if math.abs(n:Dot(Vector3.yAxis)) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local zVector = n:Cross(reference).Unit
	local yVector = zVector:Cross(n).Unit
	local flash = Instance.new("Part")
	flash.Name = "CageImpact"
	flash.Shape = Enum.PartType.Cylinder
	flash.CFrame = CFrame.fromMatrix(position + n * FaceOffset, n, yVector, zVector)
	flash.Size = Vector3.new(0.04, ImpactDiameter, ImpactDiameter)
	flash.Color = if isBaffle then BaffleColor else CageColor
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.18
	flash.Anchored, flash.CastShadow = true, false
	flash.CanCollide, flash.CanTouch, flash.CanQuery = false, false, false
	flash.Parent = if parent and parent:IsDescendantOf(workspace) then parent else workspace
	local duration = Physics.Cage.ImpactDuration
	TweenService:Create(flash, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.04, ImpactDiameter * 1.5, ImpactDiameter * 1.5),
	}):Play()
	Debris:AddItem(flash, duration)
end

function View.Play(wall: BasePart, position: Vector3): ()
	if not wall:IsDescendantOf(workspace) then return end
	local point = wall.CFrame:PointToObjectSpace(position)
	local xFace = wall.Size.X < wall.Size.Z
	local axis = if xFace then Vector3.xAxis else Vector3.zAxis
	local sign = if (if xFace then point.X else point.Z) >= 0 then 1 else -1
	local normal = wall.CFrame:VectorToWorldSpace(axis * sign)
	View.PlayAt(position, normal, wall.CollisionGroup == Physics.ChuteBaffleGroup, wall)
end

return View
