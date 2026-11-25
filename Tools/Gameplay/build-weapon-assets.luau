-- 在 Studio Edit 构建六阶武器，工具栏、随身商店和发放共用这些模板
--!strict
local storage = game:GetService("ReplicatedStorage")
local models = storage:WaitForChild("Models")
assert(models:IsA("Folder") and not game:GetService("RunService"):IsRunning(), "Build weapons under Models in Edit mode")

local names = {
	W01 = "W01_RustyPan",
	W02 = "W02_IronCrowbar",
	W03 = "W03_DemonScimitar",
	W04 = "W04_ReaperScythe",
	W05 = "W05_VoidCannon",
	W06 = "W06_AbyssalHammer",
}
local drafts: {[string]: Tool} = {}
local rgb = Color3.fromRGB
local iron, dark, violet = rgb(151, 160, 175), rgb(48, 39, 66), rgb(173, 80, 255)
local brass, leather, red = rgb(226, 164, 70), rgb(149, 88, 47), rgb(243, 61, 68)
local function model(id: string): Model
	local tool = Instance.new("Tool")
	tool.Name = names[id]
	tool.CanBeDropped = false
	local visual = Instance.new("Model")
	visual.Name = "Visual"
	visual.Parent = tool
	drafts[id] = tool
	return visual
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
local v, cylinder = Vector3.new, Enum.PartType.Cylinder
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
	part(hammer, if side < 0 then "AnvilLeft" else "AnvilRight", v(0.64, 1.69, 1.51), v(0.23 + side * 1.32, 1.2 - side * 0.31, 0), brass, nil, v(0, 0, -14))
end
part(hammer, "Core", v(0.88, 0.79, 1.41), v(0.23, 1.2, 0), violet, nil, v(0, 0, -14))
local handleFrames = {
	W01 = CFrame.new(0, 0.3, 1.6) * CFrame.Angles(math.pi / 2, 0, 0),
	W02 = CFrame.new(-0.38, -1.03, 0),
	W03 = CFrame.new(-0.46, -1.05, 0),
	W04 = CFrame.new(-0.68, -0.57, 0),
	W05 = CFrame.new(0, -0.55, 0.53),
	W06 = CFrame.new(-0.43, -1, 0),
}
-- 用可见握柄的局部坐标定位掌心，俯仰角以装备后的右手握持关节为参考。
local handGrips = {
	W01 = {piece = "Grip", offset = v(0, 0, 0.34), pitch = 20},
	W02 = {piece = "Shaft", offset = v(0, -0.98, 0), pitch = -18},
	W03 = {piece = "Grip", offset = v(0, -0.07, 0), pitch = -22},
	W04 = {piece = "Haft", offset = v(0, -0.55, 0), pitch = -25},
	W05 = {piece = "Grip", offset = v(0, -0.12, 0), pitch = 0},
	W06 = {piece = "Haft", offset = v(0, -0.65, 0), pitch = -22},
}
for id, tool in drafts do
	local visual = tool:FindFirstChild("Visual") :: Model
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.2
	handle.Transparency = 1
	handle.CastShadow = false
	handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
	handle.CFrame = handleFrames[id]
	handle.Parent = tool
	local handGrip = handGrips[id]
	local gripPiece = visual:FindFirstChild(handGrip.piece) :: BasePart
	local palm = gripPiece.CFrame:PointToWorldSpace(handGrip.offset)
	tool.Grip = handle.CFrame:ToObjectSpace(CFrame.new(palm) * CFrame.Angles(math.rad(-handGrip.pitch), 0, 0))
	for _, piece in visual:GetChildren() do
		if not piece:IsA("BasePart") then continue end
		piece.Anchored, piece.Massless = false, true
		if piece.Name == "Core" or piece.Name == "GravityCore" or (id == "W03" and string.sub(piece.Name, 1, 4) == "Edge") then
			piece.Material = Enum.Material.Neon
		else
			piece.Material = if piece.Color == leather then Enum.Material.Leather else Enum.Material.Metal
		end
		local weld = Instance.new("WeldConstraint")
		weld.Name = "Weld_" .. piece.Name
		weld.Part0, weld.Part1 = handle, piece
		weld.Parent = handle
	end
end

local weapons = models:FindFirstChild("Weapons")
if not weapons then
	local created = Instance.new("Folder")
	created.Name = "Weapons"
	created.Parent = models
	weapons = created
end
local previews = models:FindFirstChild("Previews")
local legacyPreviews = models:FindFirstChild("PersonalShopPreviews")
for id, tool in drafts do
	local oldRoot = models:FindFirstChild(tool.Name)
	if oldRoot then oldRoot:Destroy() end
	local old = (weapons :: Folder):FindFirstChild(tool.Name)
	if old then old:Destroy() end
	tool.Parent = weapons
	for _, folder in {previews, legacyPreviews} do
		local duplicate = folder and folder:FindFirstChild(id)
		if duplicate then duplicate:Destroy() end
	end
end
