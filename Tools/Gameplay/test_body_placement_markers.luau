-- 手动画符台白膜放置标记模块 BodyPlacementMarkers 离线单元测试
local R = require('@lune/roblox')
local Instance = R.Instance
local CFrame = R.CFrame
local Vector3 = R.Vector3

local BodyPlacementMarkers = require('./BodyPlacementMarkers')
local PaintRotation = require('./PaintRotation')

local checks = 0
local function check(cond: boolean, msg: string)
	assert(cond, msg)
	checks += 1
end

local function nearVec(a: Vector3, b: Vector3, eps: number?): boolean
	return (a - b).Magnitude <= (eps or 1e-4)
end

local function nearCF(a: CFrame, b: CFrame, eps: number?): boolean
	local tol = eps or 1e-4
	return (a.Position - b.Position).Magnitude <= tol
		and (a.LookVector - b.LookVector).Magnitude <= tol
		and (a.UpVector - b.UpVector).Magnitude <= tol
end

local function MakeSlotModel(name: string, slot: number?, pose: CFrame): Instance
	local model = Instance.new('Model')
	model.Name = name
	if slot ~= nil then
		model:SetAttribute('PlacementSlot', slot)
	end
	local root = Instance.new('Part')
	root.Name = 'HumanoidRootPart'
	root.Anchored = true
	root.CanCollide = true
	root.CanTouch = true
	root.CanQuery = true
	root.CastShadow = true
	root.Transparency = 1
	root.CFrame = pose
	root.Parent = model

	local torso = Instance.new('Part')
	torso.Name = 'UpperTorso'
	torso.Anchored = true
	torso.CanCollide = false
	torso.CanTouch = false
	torso.CanQuery = true
	torso.CastShadow = true
	torso.Transparency = 0.45
	torso.CFrame = pose * CFrame.new(0, 0.3, 0)
	torso.Parent = model

	local billboard = Instance.new('BillboardGui')
	billboard.Name = 'SlotLabel'
	billboard.Enabled = true
	billboard.Parent = torso

	model.PrimaryPart = root
	model.WorldPivot = pose
	return model
end

-- 1. 全量 1~5 号 Model 读取（含自定义位置和旋转）
do
	local tableModel = Instance.new('Model')
	tableModel.Name = 'RuneBodyTable'
	local anchor = Instance.new('Part')
	anchor.Name = 'BodyPlacementAnchor'
	anchor.CFrame = CFrame.new(-16, 4.5, 15)
	anchor.Parent = tableModel

	local folder = Instance.new('Folder')
	folder.Name = 'BodyPlacementMarkers'
	folder.Parent = tableModel

	local expected = {}
	for slot = 1, 5 do
		local pose = CFrame.new(-16 + (slot - 1) * 4.2, 4.8 + slot * 0.1, 15 - slot)
			* CFrame.Angles(0.1 * slot, 0.25 * slot, -0.05 * slot)
		expected[slot] = pose
		local m = MakeSlotModel('Slot' .. tostring(slot), slot, pose)
		m.Parent = folder
	end

	local poses = BodyPlacementMarkers.ReadSlotPoses(tableModel, anchor)
	for slot = 1, 5 do
		check(poses[slot] ~= nil and nearCF(poses[slot], expected[slot]), 'ReadSlotPoses reads full CFrame for slot ' .. tostring(slot))
	end
end

-- 2. 空文件夹 / 缺失部分槽位时的回退逻辑
do
	local tableModel = Instance.new('Model')
	local anchor = Instance.new('Part')
	anchor.Name = 'BodyPlacementAnchor'
	anchor.CFrame = CFrame.new(-10, 5, 20)
	anchor.Parent = tableModel

	local emptyFolder = Instance.new('Folder')
	emptyFolder.Name = 'BodyPlacementMarkers'
	emptyFolder.Parent = tableModel

	local fallbackPoses = BodyPlacementMarkers.ReadSlotPoses(tableModel, anchor)
	local default1 = PaintRotation.TablePose(anchor.CFrame.Position)
	check(nearCF(fallbackPoses[1], default1), 'Empty folder falls back slot 1 to PaintRotation.TablePose')
	for slot = 2, 5 do
		check(nearCF(fallbackPoses[slot], default1 + PaintRotation.BatchOffset(slot)), 'Empty folder falls back slot ' .. tostring(slot) .. ' via BatchOffset')
	end

	local customPose1 = CFrame.new(-12, 6, 22) * CFrame.Angles(0, 0.4, 0)
	local customPose3 = CFrame.new(0, 6.5, 22) * CFrame.Angles(0, -0.3, 0)
	MakeSlotModel('CustomPrimary', 1, customPose1).Parent = emptyFolder
	MakeSlotModel('Slot3', nil, customPose3).Parent = emptyFolder

	local partialPoses = BodyPlacementMarkers.ReadSlotPoses(tableModel, anchor)
	check(nearCF(partialPoses[1], customPose1), 'Partial markers read PlacementSlot attribute even with custom name')
	check(nearCF(partialPoses[2], customPose1 + PaintRotation.BatchOffset(2)), 'Missing slot 2 falls back relative to custom slot 1')
	check(nearCF(partialPoses[3], customPose3), 'Partial markers read Slot3 by name without attribute')
	check(nearCF(partialPoses[4], customPose1 + PaintRotation.BatchOffset(4)), 'Missing slot 4 falls back relative to custom slot 1')
	check(nearCF(partialPoses[5], customPose1 + PaintRotation.BatchOffset(5)), 'Missing slot 5 falls back relative to custom slot 1')
end

-- 3. HideAll 隐藏视觉表现但不销毁节点
do
	local tableModel = Instance.new('Model')
	local folder = Instance.new('Folder')
	folder.Name = 'BodyPlacementMarkers'
	folder.Parent = tableModel

	local m1 = MakeSlotModel('Slot1', 1, CFrame.new(0, 4, 0))
	m1.Parent = folder
	local m2 = MakeSlotModel('Slot2', 2, CFrame.new(-5, 4, 0))
	m2.Parent = folder

	local hiddenCount = BodyPlacementMarkers.HideAll(tableModel)
	check(hiddenCount == 2, 'HideAll returns hidden marker count')
	check(m1.Parent == folder and m2.Parent == folder, 'HideAll preserves marker instances instead of destroying them')

	local torso = m1:FindFirstChild('UpperTorso') :: BasePart
	local billboard = torso:FindFirstChild('SlotLabel') :: BillboardGui
	check(torso.Transparency == 1 and not torso.CanCollide and not torso.CanTouch and not torso.CanQuery and not torso.CastShadow,
		'HideAll hides BasePart and disables collision/query/shadow')
	check(billboard.Enabled == false, 'HideAll disables BillboardGui')
end

-- 4. TransformBatchPart 在纯平移与带旋转场景下的准确性
do
	local primaryBase = PaintRotation.TablePose(Vector3.new(-16, 4.5, 15))
	local slotBaseShift = primaryBase + Vector3.new(-5.55, 0, 0)
	local sourcePart = primaryBase * CFrame.new(0.5, 1.2, -0.3) * CFrame.Angles(0.2, 0.4, -0.1)

	local shifted = BodyPlacementMarkers.TransformBatchPart(sourcePart, primaryBase, slotBaseShift)
	check(nearCF(shifted, sourcePart + Vector3.new(-5.55, 0, 0)), 'TransformBatchPart matches pure translation when slot rotation matches primary')

	local rotatedSlotBase = CFrame.new(10, 6, -4) * CFrame.Angles(0.3, -0.7, 0.15)
	local localOffset = primaryBase:ToObjectSpace(sourcePart)
	local transformed = BodyPlacementMarkers.TransformBatchPart(sourcePart, primaryBase, rotatedSlotBase)
	check(nearCF(transformed, rotatedSlotBase * localOffset), 'TransformBatchPart preserves local pose relative to rotated slotBase')
end

-- 5. ReadSlotSpecs / ApplyToModel / RestoreModel：完整同步尺寸与肢体动作并支持离台恢复
do
	local function MakeRig(pose: CFrame, torsoScale: number, armPoseOffset: CFrame, restAttr: CFrame?): Instance
		local rig = Instance.new('Model')
		local root = Instance.new('Part')
		root.Name = 'HumanoidRootPart'
		root.Size = Vector3.new(2, 2, 1) * torsoScale
		root.CFrame = pose
		root.Parent = rig

		local torso = Instance.new('Part')
		torso.Name = 'UpperTorso'
		torso.Size = Vector3.new(2, 1.6, 1) * torsoScale
		torso:SetAttribute('Paintable', true)
		if restAttr ~= nil then
			torso:SetAttribute('RestPose', restAttr)
		end
		torso.CFrame = pose * CFrame.new(0, 0.35 * torsoScale, 0)
		torso.Parent = rig

		local arm = Instance.new('Part')
		arm.Name = 'LeftUpperArm'
		arm.Size = Vector3.new(1, 1.4, 1) * torsoScale
		arm:SetAttribute('Paintable', true)
		arm.CFrame = torso.CFrame * armPoseOffset
		arm.Parent = rig

		rig.PrimaryPart = root
		rig.WorldPivot = pose
		return rig
	end

	local tableModel = Instance.new('Model')
	local anchor = Instance.new('Part')
	anchor.Name = 'BodyPlacementAnchor'
	anchor.CFrame = CFrame.new(-16, 4.5, 15)
	anchor.Parent = tableModel

	local folder = Instance.new('Folder')
	folder.Name = 'BodyPlacementMarkers'
	folder.Parent = tableModel

	local marker1Pose = CFrame.new(-16, 5.2, 14) * CFrame.Angles(0.15, 0.4, -0.1)
	local marker1ArmOffset = CFrame.new(-1.8, 0.4, -0.3) * CFrame.Angles(0.6, -0.2, 0.5)
	local marker1 = MakeRig(marker1Pose, 1.5, marker1ArmOffset, nil)
	marker1.Name = 'Slot1'
	marker1:SetAttribute('PlacementSlot', 1)
	marker1.Parent = folder

	local marker2Pose = CFrame.new(-22, 5.6, 13) * CFrame.Angles(-0.1, -0.35, 0.2)
	local marker2ArmOffset = CFrame.new(-2.1, -0.2, 0.4) * CFrame.Angles(-0.5, 0.3, -0.4)
	local marker2 = MakeRig(marker2Pose, 0.75, marker2ArmOffset, nil)
	marker2.Name = 'Slot2'
	marker2:SetAttribute('PlacementSlot', 2)
	marker2.Parent = folder

	local specs = BodyPlacementMarkers.ReadSlotSpecs(tableModel, anchor)
	check(specs[1] ~= nil and specs[1].partSizes ~= nil and specs[1].bodyPose ~= nil and specs[1].torsoOffset ~= nil,
		'ReadSlotSpecs captures partSizes, bodyPose, and torsoOffset from Slot1 model')
	check(nearVec((specs[1].partSizes :: { [string]: Vector3 }).UpperTorso, Vector3.new(3, 2.4, 1.5)),
		'ReadSlotSpecs captures scaled UpperTorso size from Slot1')
	check(nearVec((specs[2].partSizes :: { [string]: Vector3 }).UpperTorso, Vector3.new(1.5, 1.2, 0.75)),
		'ReadSlotSpecs captures independent scaled UpperTorso size from Slot2')
	check(specs[3].partSizes ~= nil and nearVec((specs[3].partSizes :: { [string]: Vector3 }).UpperTorso, Vector3.new(3, 2.4, 1.5)),
		'Missing Slot3 falls back to Slot1 size and pose spec')

	-- 情况 A：原始白膜带有 RestPose 属性
	local origRest = CFrame.new(0, 0.2, 0)
	local runtimeWithRest = MakeRig(CFrame.identity, 1.0, CFrame.new(-1.5, 0, 0), origRest)
	BodyPlacementMarkers.ApplyToModel(runtimeWithRest :: any, specs[1])
	local torsoA = runtimeWithRest:FindFirstChild('UpperTorso') :: BasePart
	local armA = runtimeWithRest:FindFirstChild('LeftUpperArm') :: BasePart
	check(nearVec(torsoA.Size, Vector3.new(3, 2.4, 1.5)), 'ApplyToModel scales UpperTorso to match Slot1 marker')
	check(nearVec(armA.Size, Vector3.new(1.5, 2.1, 1.5)), 'ApplyToModel scales LeftUpperArm to match Slot1 marker')
	check(nearCF(torsoA.CFrame, (marker1:FindFirstChild('UpperTorso') :: BasePart).CFrame),
		'ApplyToModel aligns UpperTorso CFrame 1:1 with Slot1 marker')
	check(nearCF(armA.CFrame, (marker1:FindFirstChild('LeftUpperArm') :: BasePart).CFrame),
		'ApplyToModel aligns LeftUpperArm pose 1:1 with Slot1 marker')

	-- 叠加翻面与抬升高度
	local lift = 1.25
	BodyPlacementMarkers.ApplyToModel(runtimeWithRest :: any, specs[2], PaintRotation.FlipOrientation, nil, lift)
	local expectedFlipped2 = (specs[2].pose + Vector3.yAxis * lift) * PaintRotation.FlipOrientation * (specs[2].torsoOffset :: CFrame) * (specs[2].bodyPose :: any).LeftUpperArm
	check(nearVec(torsoA.Size, Vector3.new(1.5, 1.2, 0.75)), 'ApplyToModel updates size to Slot2')
	check(nearCF(armA.CFrame, expectedFlipped2), 'ApplyToModel overlays orientation flip and lift onto Slot2 pose')

	BodyPlacementMarkers.RestoreModel(runtimeWithRest :: any)
	check(nearVec(torsoA.Size, Vector3.new(2, 1.6, 1)) and nearVec(armA.Size, Vector3.new(1, 1.4, 1)),
		'RestoreModel restores original part sizes')
	check(nearCF(torsoA:GetAttribute('RestPose') :: CFrame, origRest), 'RestoreModel restores original RestPose CFrame')
	check(torsoA:GetAttribute('TableOriginalSize') == nil and torsoA:GetAttribute('TableOriginalRestPose') == nil,
		'RestoreModel clears temporary backup attributes')

	-- 情况 B：原始白膜最初没有 RestPose 属性
	local runtimeNoRest = MakeRig(CFrame.identity, 1.0, CFrame.new(-1.5, 0, 0), nil)
	local torsoB = runtimeNoRest:FindFirstChild('UpperTorso') :: BasePart
	BodyPlacementMarkers.ApplyToModel(runtimeNoRest :: any, specs[1])
	check(torsoB:GetAttribute('TableOriginalRestPose') == false, 'ApplyToModel stores false sentinel when RestPose was absent')
	BodyPlacementMarkers.RestoreModel(runtimeNoRest :: any)
	check(torsoB:GetAttribute('RestPose') == nil and torsoB:GetAttribute('TableOriginalRestPose') == nil,
		'RestoreModel removes RestPose when it was originally absent')
end

print(string.format('PASS: BodyPlacementMarkers (%d checks)', checks))
