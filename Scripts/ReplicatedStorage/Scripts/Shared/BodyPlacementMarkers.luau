-- 手动画符台 Edit 白膜放置位置标记读取、运行期隐藏、缩放动作同步与离台恢复
--!strict
local PaintRotation = require(script.Parent.PaintRotation)
local PaintBodyPose = require(script.Parent.PaintBodyPose)
local Types = require(script.Parent.GameTypes)

local BodyPlacementMarkers = {}

BodyPlacementMarkers.FolderName = "BodyPlacementMarkers"
BodyPlacementMarkers.SlotAttribute = "PlacementSlot"
BodyPlacementMarkers.MarkerAttribute = "BodyPlacementMarker"
BodyPlacementMarkers.MaxSlots = 5

local OriginalSizeAttr = "TableOriginalSize"
local OriginalRestPoseAttr = "TableOriginalRestPose"

export type SlotSpec = {
	pose: CFrame,
	torsoOffset: CFrame?,
	bodyPose: Types.BodyPose?,
	partSizes: { [string]: Vector3 }?,
}

local function IsFiniteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	local frame = value :: CFrame
	for _, n in { frame:GetComponents() } do
		if n ~= n or math.abs(n) == math.huge then
			return false
		end
	end
	return true
end

local function ParseSlotIndex(instance: Instance): number?
	local attr = instance:GetAttribute(BodyPlacementMarkers.SlotAttribute)
	if typeof(attr) == "number" and attr >= 1 and attr <= BodyPlacementMarkers.MaxSlots and attr % 1 == 0 then
		return attr
	end
	local matched = string.match(instance.Name, "^Slot(%d+)$")
	if matched then
		local num = tonumber(matched)
		if num and num >= 1 and num <= BodyPlacementMarkers.MaxSlots and num % 1 == 0 then
			return num
		end
	end
	return nil
end

local function HideVisual(instance: Instance): ()
	if instance:IsA("BasePart") then
		instance.Transparency = 1
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
	elseif instance:IsA("Decal") then
		instance.Transparency = 1
	elseif instance:IsA("Texture") then
		instance.Transparency = 1
	elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") or instance:IsA("Highlight") or instance:IsA("SelectionBox") then
		(instance :: any).Enabled = false
	end
end

local function ReadModelPose(model: Model): CFrame?
	local ok, pivot = pcall(function(): CFrame
		return model:GetPivot()
	end)
	if ok and typeof(pivot) == "CFrame" then
		return pivot
	end
	local primary = model.PrimaryPart
	if primary then
		return primary.CFrame
	end
	local worldPivot = (model :: any).WorldPivot
	return if typeof(worldPivot) == "CFrame" then worldPivot else nil
end

local function SetModelPivot(model: Model, pose: CFrame): ()
	local ok = pcall(function(): ()
		model:PivotTo(pose)
	end)
	if not ok then
		(model :: any).WorldPivot = pose
	end
end

local function ReadModelSpec(model: Model): SlotSpec?
	local pose = ReadModelPose(model)
	if not pose or not IsFiniteCFrame(pose) then
		return nil
	end
	local partSizes: { [string]: Vector3 } = {}
	local hasSize = false
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			partSizes[child.Name] = child.Size
			hasSize = true
		end
	end
	local torsoOffset: CFrame? = nil
	local bodyPose: Types.BodyPose? = nil
	local torso = model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		local rel = pose:ToObjectSpace(torso.CFrame)
		if IsFiniteCFrame(rel) then
			torsoOffset = rel
		end
		local captured = PaintBodyPose.Capture(model)
		if next(captured) ~= nil then
			bodyPose = captured
		end
	end
	return {
		pose = pose,
		torsoOffset = torsoOffset,
		bodyPose = bodyPose,
		partSizes = if hasSize then partSizes else nil,
	}
end

function BodyPlacementMarkers.ReadSlotSpecs(tableModel: Instance?, fallbackAnchor: BasePart): { [number]: SlotSpec }
	local specs: { [number]: SlotSpec } = {}
	local folder = if tableModel then tableModel:FindFirstChild(BodyPlacementMarkers.FolderName) else nil
	if folder and folder:IsA("Folder") then
		for _, child in folder:GetChildren() do
			local slot = ParseSlotIndex(child)
			if slot and not specs[slot] then
				if child:IsA("Model") then
					local spec = ReadModelSpec(child)
					if spec then
						specs[slot] = spec
					end
				elseif child:IsA("BasePart") and IsFiniteCFrame(child.CFrame) then
					specs[slot] = { pose = child.CFrame }
				end
			end
		end
	end
	if not specs[1] then
		specs[1] = { pose = PaintRotation.TablePose(fallbackAnchor.CFrame.Position) }
	end
	for slot = 2, BodyPlacementMarkers.MaxSlots do
		if not specs[slot] then
			local offset = PaintRotation.BatchOffset(slot) or Vector3.zero
			specs[slot] = {
				pose = specs[1].pose + offset,
				torsoOffset = specs[1].torsoOffset,
				bodyPose = specs[1].bodyPose,
				partSizes = specs[1].partSizes,
			}
		end
	end
	return specs
end

function BodyPlacementMarkers.ReadSlotPoses(tableModel: Instance?, fallbackAnchor: BasePart): { [number]: CFrame }
	local specs = BodyPlacementMarkers.ReadSlotSpecs(tableModel, fallbackAnchor)
	local poses: { [number]: CFrame } = {}
	for slot, spec in specs do
		poses[slot] = spec.pose
	end
	return poses
end

function BodyPlacementMarkers.ApplyToModel(
	model: Model,
	spec: SlotSpec,
	orientation: CFrame?,
	geometry: PaintRotation.Geometry?,
	lift: number?
): ()
	if spec.partSizes then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				local size = spec.partSizes[child.Name]
				if size and child.Size ~= size then
					if child:GetAttribute(OriginalSizeAttr) == nil then
						child:SetAttribute(OriginalSizeAttr, child.Size)
					end
					child.Size = size
				end
			end
		end
	end
	if spec.torsoOffset then
		local torso = model:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			if torso:GetAttribute(OriginalRestPoseAttr) == nil then
				local currentRest = torso:GetAttribute("RestPose")
				torso:SetAttribute(OriginalRestPoseAttr, if typeof(currentRest) == "CFrame" then currentRest else false)
			end
			torso:SetAttribute("RestPose", spec.torsoOffset)
		end
	end
	local base = if lift and lift ~= 0 then spec.pose + Vector3.yAxis * lift else spec.pose
	if orientation then
		base = PaintRotation.Pose(base, geometry, orientation)
	end
	if spec.bodyPose then
		PaintBodyPose.Apply(model, base, spec.bodyPose)
	else
		SetModelPivot(model, base)
	end
end

function BodyPlacementMarkers.RestoreModel(model: Model): ()
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			local origSize = child:GetAttribute(OriginalSizeAttr)
			if typeof(origSize) == "Vector3" then
				child.Size = origSize
				child:SetAttribute(OriginalSizeAttr, nil)
			end
		end
	end
	local torso = model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		local origRest = torso:GetAttribute(OriginalRestPoseAttr)
		if origRest ~= nil then
			torso:SetAttribute("RestPose", if typeof(origRest) == "CFrame" then origRest else nil)
			torso:SetAttribute(OriginalRestPoseAttr, nil)
		end
	end
end

function BodyPlacementMarkers.HideAll(tableModel: Instance?): number
	local folder = if tableModel then tableModel:FindFirstChild(BodyPlacementMarkers.FolderName) else nil
	if not folder or not folder:IsA("Folder") then
		return 0
	end
	local hiddenCount = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			hiddenCount += 1
		end
		HideVisual(child)
		for _, desc in child:GetDescendants() do
			HideVisual(desc)
		end
	end
	return hiddenCount
end

function BodyPlacementMarkers.TransformBatchPart(partCFrame: CFrame, primaryBase: CFrame, slotBase: CFrame): CFrame
	return slotBase * primaryBase:ToObjectSpace(partCFrame)
end

return BodyPlacementMarkers
