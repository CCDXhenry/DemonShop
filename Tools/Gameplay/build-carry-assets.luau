-- M7 搬运背饰模板，由 Studio Edit 安装，供角色和商店共用。
--!strict
assert(not game:GetService("RunService"):IsRunning(), "DemonShop Edit mode required")
local models = game:GetService("ReplicatedStorage"):FindFirstChild("Models")
assert(models and models:IsA("Folder"), "ReplicatedStorage.Models is required")
local rgb = Color3.fromRGB
local iron, dark, violet = rgb(151, 160, 175), rgb(48, 39, 66), rgb(173, 80, 255)
local brass, leather, red = rgb(226, 164, 70), rgb(128, 72, 51), rgb(230, 38, 74)
local function model(id: string): Model
	local result = Instance.new("Model")
	result.Name = "CarryRig_" .. id
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
local sack = model("T1")
part(sack, "Sack", v(2.11, 2.55, 1.76), v(0, -0.3, 0), leather, ball)
part(sack, "Tie", v(0.3, 0.81, 0.7), v(0, 0.95, 0), brass, cylinder, v(0, 0, 90))
part(sack, "Knot", v(0.8, 0.57, 0.7), v(0, 1.28, 0), leather, ball)
local seal = part(sack, "Seal", v(0.55, 0.55, 0.18), v(0, -0.34, 0.87), violet, nil, v(0, 0, 45))
local barrow = model("T2")
part(barrow, "Bed", v(2.37, 0.25, 2.4), v(0, 0, 0), iron, nil, v(9, 0, 0))
part(barrow, "Wheel", v(0.44, 1.23, 1.23), v(0, -0.72, -1.02), dark, cylinder)
part(barrow, "Hub", v(0.49, 0.57, 0.57), v(0, -0.72, -1.02), brass, cylinder)
for index, side in {-1, 1} do
	part(barrow, "Side" .. index, v(0.25, 0.71, 2.39), v(side * 1.11, 0.45, 0), iron, nil, v(9, 0, side * -16))
	part(barrow, "Handle" .. index, v(0.2, 0.2, 2.55), v(side * 0.73, -0.17, 0.95), brass, nil, v(9, 0, 0))
end
local tether = model("T3")
for i = 1, 12 do
	local theta = i * math.pi / 6
	part(tether, "Link" .. i, v(0.93, 0.4, 0.34), v(1.38 * math.cos(theta), 1.38 * math.sin(theta), 0), if i % 2 == 0 then red else dark, nil, v(i % 2 * 68, 0, math.deg(theta) + 90))
end
part(tether, "Clasp", v(0.68, 0.78, 0.65), v(0, -1.41, 0), iron)
local pack = model("T4")
part(pack, "Chassis", v(1.67, 2.77, 1.29), v(0, 0, 0), dark)
local core = part(pack, "Core", v(0.87, 1.31, 1.31), v(0, 0.22, 0.6), violet, cylinder, v(0, 90, 0))
for index, side in {-1, 1} do
	part(pack, "Cylinder" .. index, v(2.18, 0.72, 0.72), v(side * 1.03, -0.08, 0.02), iron, cylinder, v(0, 0, 90))
	part(pack, "Cap" .. index, v(0.32, 0.83, 0.83), v(side * 1.03, 1.07, 0.02), brass, cylinder, v(0, 0, 90))
end

seal.Color = rgb(99, 49, 155)
for _, link in tether:GetChildren() do
	if link:IsA("BasePart") and link.Color == red then link.Material = Enum.Material.Neon end
end
core.Material = Enum.Material.Neon

local offsets = {
	[sack] = CFrame.new(0, -0.12, 1.32),
	[barrow] = CFrame.new(0, 0, 1.35) * CFrame.Angles(math.rad(-85), 0, 0),
	[tether] = CFrame.new(0, 0.03, 0.95),
	[pack] = CFrame.new(0, -0.12, 1.22),
}
local carryRigs = models:FindFirstChild("CarryRigs")
if not carryRigs then
	local created = Instance.new("Folder")
	created.Name = "CarryRigs"
	created.Parent = models
	carryRigs = created
end
for rig, offset in offsets do
	local root = part(rig, "RootPart", v(0.2, 0.2, 0.2), Vector3.zero, iron)
	root.Transparency, root.CastShadow, root.Massless = 1, false, true
	rig.PrimaryPart = root
	rig:SetAttribute("MountOffset", offset)
	for _, child in rig:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			child.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Name, weld.Part0, weld.Part1 = "Weld_" .. child.Name, root, child
			weld.Parent = root
		end
	end
	local oldRoot = models:FindFirstChild(rig.Name)
	if oldRoot then oldRoot:Destroy() end
	local previous = (carryRigs :: Folder):FindFirstChild(rig.Name)
	if previous then previous:Destroy() end
	rig.Parent = carryRigs
end
for _, folderName in {"Previews", "PersonalShopPreviews"} do
	local previews = models:FindFirstChild(folderName)
	if previews then
		for _, id in {"T1", "T2", "T3", "T4"} do
			local old = previews:FindFirstChild(id)
			if old then old:Destroy() end
		end
	end
end
return "Installed Models.CarryRigs.CarryRig_T1 through CarryRig_T4"
