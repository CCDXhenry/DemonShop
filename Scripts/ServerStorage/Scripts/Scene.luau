-- 场景契约：静态锚点、街道路面采样、工位放置、存放池边界与安全地面回收
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Physics = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local CageGeometry = require(ReplicatedStorage.Scripts.Shared.CageGeometry)
local ThrowArc = require(ReplicatedStorage.Scripts.Shared.ThrowArc)
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local PaintRotation = require(ReplicatedStorage.Scripts.Shared.PaintRotation)
local FixedCamera = require(ReplicatedStorage.Scripts.Shared.FixedCamera)
local StreetZones = require(script.Parent.StreetWalkZones)
local Scene = {}
local district = workspace:WaitForChild("NeonContractDistrict")
local pool = district:WaitForChild("SoulHoldingPool")
local StreetFloorProbeSpacing = 2.5
local PointRowBand = 0.5 -- 同一排点位的高度差上限，studs
local ChuteFallbackLanding = Vector3.new(-58.8, 1.15, -28.5)
local ChuteSpawnSpread = 1.8
local ChuteEdgeClearance = 2.5
local ChuteFallTolerance = 4
local ShelfPivotOffset = -0.35 -- 相对符文托位下调瓶身枢轴，studs
local ShelfSlotOffsets = {
	Vector3.new(0, ShelfPivotOffset, 0.85),
	Vector3.new(-1.20, ShelfPivotOffset, 0.85),
	Vector3.new(1.20, ShelfPivotOffset, 0.85),
	Vector3.new(0.45, ShelfPivotOffset, -0.35),
	Vector3.new(-0.75, ShelfPivotOffset, -0.35),
	Vector3.new(1.65, ShelfPivotOffset, -0.35),
}
local function Part(root: Instance, name: string): BasePart
	local p = root:WaitForChild(name)
	assert(p:IsA("BasePart"))
	return p
end
local function TopThenLeft(a: BasePart, b: BasePart): boolean
	if math.abs(a.Position.Y - b.Position.Y) > PointRowBand then
		return a.Position.Y > b.Position.Y
	end
	return a.Position.X < b.Position.X
end
Scene.District = district
Scene.Deck = Part(district:WaitForChild("deck"):WaitForChild("Generated"):WaitForChild("Street"):WaitForChild("Raised Street Deck With Stair Void"), "Box_005")
local function ReadStreetWalkZones(): { StreetZones.Zone }
	local zones: { StreetZones.Zone } = {}
	local folder = district:FindFirstChild("StreetWalkZones")
	if folder and folder:IsA("Folder") then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part.CFrame.UpVector.Y > 0.9999 then
				table.insert(zones, StreetZones.New(part.CFrame, part.Size))
				part.Transparency = 1
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
	end
	if #zones == 0 then
		local deck = Scene.Deck
		local surface = deck.CFrame * CFrame.new(0, deck.Size.Y / 2, 0)
		local usable = Vector3.new(math.max(0.1, deck.Size.X - 8), deck.Size.Y, math.max(0.1, deck.Size.Z - 8))
		table.insert(zones, StreetZones.New(surface, usable))
	end
	return zones
end
local streetZones = ReadStreetWalkZones()

-- 只用静态街区找路，玩家和其他假人经过时不反复改变巡游方向。
local function CreateStreetCastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { district }
	params.RespectCanCollide = true
	return params
end

local streetCastParams = CreateStreetCastParams()

function Scene.StreetFloor(point: Vector3): Vector3?
	local hit = workspace:Raycast(point + Vector3.new(0, 5, 0), Vector3.new(0, -7, 0), streetCastParams)
	if hit and hit.Normal.Y > 0.6 and math.abs(hit.Position.Y - point.Y) <= 1.25 then return hit.Position end
	return nil
end

function Scene.StreetPoint(random: Random): Vector3
	local point = assert(StreetZones.Sample(streetZones, random))
	for _ = 1, 8 do
		local floor = Scene.StreetFloor(point)
		if floor then return floor end
		point = assert(StreetZones.Sample(streetZones, random))
	end
	-- 刷出和移动的调用方会拒绝没有可站立地面的目标。
	return point
end

function Scene.IsInStreetWalkZones(position: Vector3, margin: number?): boolean
	return StreetZones.Contains(streetZones, position, margin)
end

function Scene.ClampToStreetWalkZones(position: Vector3): Vector3?
	local nearest = StreetZones.Closest(streetZones, position, 1.25)
	local floor = nearest and Scene.StreetFloor(nearest)
	if floor then return floor end
	local best: Vector3? = nil
	local distance = math.huge
	for _, zone in streetZones do
		for _, point in { StreetZones.Clamp(zone, position, 1.25), zone.frame.Position } do
			local candidate = Scene.StreetFloor(point)
			if candidate and (candidate - position).Magnitude < distance then
				best, distance = candidate, (candidate - position).Magnitude
			end
		end
	end
	return best
end

function Scene.StreetRoute(from: Vector3, target: Vector3, recovering: boolean?): Vector3?
	local floor = Scene.StreetFloor(target)
	if not floor or not Scene.IsInStreetWalkZones(floor) then return nil end
	if not recovering and not StreetZones.CoversSegment(streetZones, from, floor) then return nil end
	local horizontal = Vector3.new(floor.X - from.X, 0, floor.Z - from.Z)
	local distance = horizontal.Magnitude
	if distance > 0.01 then
		local frame = CFrame.lookAlong(from + Vector3.new(0, 0.15, 0), horizontal)
		if workspace:Blockcast(frame, Vector3.new(2.5, 4.1, 1.2), horizontal, streetCastParams) then return nil end
		local steps = math.ceil(distance / StreetFloorProbeSpacing)
		local startFloor = Vector3.new(from.X, floor.Y, from.Z)
		for step = 1, steps - 1 do
			local support = Scene.StreetFloor(startFloor:Lerp(floor, step / steps))
			if not support or (not recovering and not Scene.IsInStreetWalkZones(support)) then return nil end
		end
	end
	return floor
end

export type InterestPoint = StreetZones.InterestPoint

function Scene.StreetBoundaryPush(position: Vector3, margin: number?): Vector3
	return StreetZones.BoundaryPush(streetZones, position, margin or 1.4)
end

Scene.PoolDrop = Part(pool, "DropPointAnchor")
Scene.PoolPickup = Part(pool, "PickupPointAnchor")
Scene.PoolFloor = Part(pool, "PoolFloor")
Scene.PoolAirWalls = pool:FindFirstChild("AirWalls")
local tableModel = district:WaitForChild("RuneBodyTable")
Scene.TableModel = tableModel
Scene.Table = Part(tableModel, "BodyPlacementAnchor")
Scene.TableInteract = Part(tableModel, "TransferStartAnchor")
FixedCamera.HideAll(district)
Scene.Altar = Part(district:WaitForChild("SoulConversionAltar"), "BodyArrivalAnchor")
local altarRest = Part(district:WaitForChild("SoulConversionAltar"), "BodyRest")
Scene.AltarMouth = altarRest:WaitForChild("FurnaceMouth") :: Attachment
local display = district:WaitForChild("SoulCrystalDisplay")
Scene.Shelf = Part(display, "StockPickupAnchor")
local potionPointFolder = display:WaitForChild("PotionPoints")
local potionPoints: { BasePart } = {}
for _, child in potionPointFolder:GetChildren() do
	if child:IsA("BasePart") then
		table.insert(potionPoints, child)
	end
end
table.sort(potionPoints, TopThenLeft)
assert(#potionPoints > 0, "SoulCrystalDisplay.PotionPoints is empty")
Scene.Spawn = Part(district, "StreetSpawn")
local sigil = Part(district, "SummoningSubmitAnchor")
Scene.SigilPosition = sigil.Position
local function PromptRange(anchor: BasePart): number
	local prompt = anchor:FindFirstChild("WorldInteractionPrompt")
	if prompt and prompt:IsA("ProximityPrompt") and prompt.MaxActivationDistance > 0 then
		return prompt.MaxActivationDistance
	end
	return Config.InteractionRange
end
local function OptionalPart(root: Instance?, ...: string): BasePart?
	local current: Instance? = root
	for i = 1, select("#", ...) do
		if not current then
			return nil
		end
		local name = select(i, ...)
		current = current:FindFirstChild(name)
	end
	return if current and current:IsA("BasePart") then current else nil
end
local function OptionalModel(root: Instance?, ...: string): Model?
	local current: Instance? = root
	for i = 1, select("#", ...) do
		if not current then
			return nil
		end
		local name = select(i, ...)
		current = current:FindFirstChild(name)
	end
	return if current and current:IsA("Model") then current else nil
end
local autoLine = district:FindFirstChild("AutomationLine")
Scene.AutomationLine = autoLine
Scene.FastChuteCover = OptionalModel(autoLine, "FastChuteCover")
Scene.FastChuteOpening = OptionalPart(autoLine, "FastChuteOpening")
Scene.ChuteBaffles = if autoLine then autoLine:FindFirstChild("ChuteThrowBaffles") else nil
Scene.ChuteTopDrop = OptionalPart(autoLine, "ChuteTopDropAnchor")
Scene.ChutePrompt = OptionalPart(autoLine, "ChutePromptAnchor")
Scene.FastChuteLanding = OptionalModel(autoLine, "FastChuteLanding")
Scene.ChuteAirWalls = if Scene.FastChuteLanding then Scene.FastChuteLanding:FindFirstChild("AirWalls") else nil
Scene.ChuteDropZone = OptionalPart(autoLine, "FastChuteLanding", "DropZone")
Scene.ChuteLanding = OptionalPart(autoLine, "FastChuteLanding", "LandingAnchor")
Scene.ChutePickup = OptionalPart(autoLine, "FastChuteLanding", "ChutePickupAnchor")
Scene.AutoRuneMachine = OptionalModel(autoLine, "AutoRuneMachine")
Scene.AutoRuneWorkBed = OptionalPart(autoLine, "AutoRuneMachine", "WorkBedAnchor")
Scene.AutoRuneOutputPad = OptionalPart(autoLine, "AutoRuneMachine", "OutputPadAnchor")
Scene.AutoRuneOutputPrompt = OptionalPart(autoLine, "AutoRuneMachine", "OutputPromptAnchor")
Scene.AutoSmelterMachine = OptionalModel(autoLine, "AutoSmelterMachine")
Scene.AutoTransferRamp = OptionalPart(autoLine, "AutoRuneMachine", "TransferRampAnchor")
Scene.AutoTransferRampTop = OptionalPart(autoLine, "AutoRuneMachine", "TransferRampTopAnchor")
Scene.AutoTransferPass = OptionalPart(autoLine, "AutoRuneMachine", "TransferPassAnchor")
Scene.AutoSmelterInlet = OptionalPart(autoLine, "AutoSmelterMachine", "FurnaceInletAnchor")
Scene.AutoPotionRack = OptionalModel(Scene.AutoSmelterMachine, "AutoPotionRack")
Scene.AutoSmelterCenter = OptionalPart(autoLine, "AutoSmelterMachine", "MachineCenterAnchor")
Scene.AutoShelfPickup = OptionalPart(Scene.AutoPotionRack, "AutoShelfPickupAnchor")
Scene.BrutePost = OptionalModel(autoLine, "BrutePost")
Scene.Brute1Spawn = OptionalPart(autoLine, "BrutePost", "Brute1SpawnAnchor")
Scene.Brute2Spawn = OptionalPart(autoLine, "BrutePost", "Brute2SpawnAnchor")
Scene.AutoClerkStation = OptionalModel(autoLine, "AutoClerkStation")
Scene.ClerkSpawn = OptionalPart(autoLine, "AutoClerkStation", "ClerkSpawnAnchor")
Scene.Noodles = OptionalModel(district, "UpperStreetCompletion", "NewShop_Noodles")
local autoPotionPoints: { BasePart } = {}
local autoPotionFolder = if Scene.AutoPotionRack then Scene.AutoPotionRack:FindFirstChild("PotionPoints") else nil
if autoPotionFolder then
	for _, child in autoPotionFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(autoPotionPoints, child)
		end
	end
	table.sort(autoPotionPoints, TopThenLeft)
end
local unlockPads: { [number]: Model } = {}
local padsFolder = if autoLine then autoLine:FindFirstChild("UnlockPads") else nil
if padsFolder then
	for _, child in padsFolder:GetChildren() do
		if child:IsA("Model") then
			local fid = child:GetAttribute("FacilityId")
			if typeof(fid) == "number" and fid >= 1 and fid % 1 == 0 then
				unlockPads[fid] = child
			end
		end
	end
end
Scene.UnlockPads = unlockPads
local stationRanges: { [string]: number } = {
	Pool = PromptRange(Scene.PoolPickup),
	Table = PromptRange(Scene.TableInteract),
	Altar = PromptRange(Scene.Altar),
	Shelf = PromptRange(Scene.Shelf),
	Sigil = PromptRange(sigil),
	Chute = if Scene.ChutePrompt then PromptRange(Scene.ChutePrompt) else Config.InteractionRange,
	ChutePickup = if Scene.ChutePickup then PromptRange(Scene.ChutePickup) else Config.InteractionRange,
	AutoOutput = if Scene.AutoRuneOutputPrompt then PromptRange(Scene.AutoRuneOutputPrompt) else Config.InteractionRange,
	AutoShelf = if Scene.AutoShelfPickup then PromptRange(Scene.AutoShelfPickup) else Config.InteractionRange,
}
Scene.StationRanges = stationRanges
function Scene.StationRange(target: string): number
	local range = Scene.StationRanges[target]
	if typeof(range) == "number" and range > 0 then
		return range
	end
	return Config.InteractionRange
end
function Scene.TablePose(): CFrame
	return PaintRotation.TablePose(Scene.Table.Position)
end
function Scene.CameraPose(_count: number?): CFrame
	local markerPose = FixedCamera.GetCFrame(Scene.TableModel)
	if markerPose then
		return markerPose
	end
	return PaintRotation.CameraPose(Scene.Table.Position, 1)
end
function Scene.PoolPose(slot: number): CFrame
	return CFrame.new(Scene.PoolPickup.Position + Vector3.new(((slot - 1) % 4 - 1.5) * 4, 1.7, -5 - math.floor((slot - 1) / 4) * 4))
		* CFrame.Angles(math.pi / 2, 0, 0)
end
function Scene.PoolDropTarget(random: Random): CFrame
	local floor = Scene.PoolFloor
	local inset = math.min(Physics.PoolInset, floor.Size.X * 0.5, floor.Size.Z * 0.5)
	local x = random:NextNumber(-floor.Size.X * 0.5 + inset, floor.Size.X * 0.5 - inset)
	local z = random:NextNumber(-floor.Size.Z * 0.5 + inset, floor.Size.Z * 0.5 - inset)
	local yaw = random:NextNumber(-math.pi, math.pi)
	return floor.CFrame
		* CFrame.new(x, floor.Size.Y * 0.5 + Physics.PoolTossClearance, z)
		* CFrame.Angles(random:NextNumber(-0.4, 0.4), yaw, random:NextNumber(-0.4, 0.4))
end
function Scene.CageInset(cage: string): number
	return if cage == "Pool" then Physics.Cage.PoolWallInset else Physics.Cage.ChuteWallInset
end

function Scene.CageFloor(cage: string): BasePart?
	return if cage == "Pool" then Scene.PoolFloor else Scene.ChuteDropZone
end

function Scene.IsSoftCageEnabled(cage: string): boolean
	if cage == "Pool" then
		return Scene.PoolAirWalls ~= nil and Scene.PoolAirWalls:GetAttribute("SoftCageEnabled") ~= false
	end
	return Scene.ChuteAirWalls ~= nil and Scene.ChuteAirWalls:GetAttribute("SoftCageEnabled") == true
end

function Scene.CageAt(position: Vector3, allowChute: boolean): string?
	local floor, chute = Scene.PoolFloor, Scene.ChuteDropZone
	if Scene.IsSoftCageEnabled("Pool") and CageGeometry.Contains(floor.CFrame, floor.Size, position, Physics.Cage.PoolWallInset) then return "Pool" end
	if allowChute and Scene.IsSoftCageEnabled("Chute") and chute and CageGeometry.Contains(chute.CFrame, chute.Size, position, Physics.Cage.ChuteWallInset) then return "Chute" end
	return nil
end

function Scene.CageRetains(cage: string, position: Vector3): boolean
	local floor = Scene.CageFloor(cage)
	return floor ~= nil and CageGeometry.Retains(floor.CFrame, floor.Size, position, Scene.CageInset(cage))
end

function Scene.ClampToCage(cage: string, position: Vector3): Vector3?
	local floor = Scene.CageFloor(cage)
	if not floor then return nil end
	return CageGeometry.ClampInside(floor.CFrame, floor.Size, Scene.CageInset(cage), position)
end

function Scene.SetChuteBarriersEnabled(enabled: boolean): ()
	local airWalls, baffles = Scene.ChuteAirWalls, Scene.ChuteBaffles
	if airWalls then
		airWalls:SetAttribute("SoftCageEnabled", enabled)
		for _, wall in airWalls:GetChildren() do
			if wall:IsA("BasePart") then
				wall.CanCollide = false
				wall.CanQuery = false
				wall.CanTouch = false
			end
		end
	end
	if baffles then
		for _, wall in baffles:GetChildren() do
			if wall:IsA("BasePart") then wall.CanCollide, wall.CanQuery, wall.CanTouch = enabled, enabled, enabled end
		end
	end
end

function Scene.PoolContainsStrict(position: Vector3): boolean
	local floor = Scene.PoolFloor
	return ThrowArc.InsidePoolStrict(floor.CFrame, floor.Size, position, Physics.PoolStackHeight)
end
function Scene.PoolContains(position: Vector3): boolean
	local floor = Scene.PoolFloor
	local localPosition = floor.CFrame:PointToObjectSpace(position)
	local half = floor.Size * 0.5
	local pad = 1.5
	return math.abs(localPosition.X) <= half.X + pad
		and math.abs(localPosition.Z) <= half.Z + pad
		and localPosition.Y >= -2
		and localPosition.Y <= half.Y + Physics.PoolStackHeight + 2
end
function Scene.PoolBasinContains(position: Vector3): boolean
	if not Scene.PoolContainsStrict(position) then
		return false
	end
	local floor = Scene.PoolFloor
	local manual = Physics.ManualThrow
	local localPos = floor.CFrame:PointToObjectSpace(position)
	local half = floor.Size * 0.5
	local inset = math.min(manual.PoolCaptureInset, half.X * 0.5, half.Z * 0.5)
	return math.abs(localPos.X) <= half.X - inset
		and math.abs(localPos.Z) <= half.Z - inset
		and localPos.Y >= -half.Y
		and localPos.Y <= half.Y + Physics.PoolStackHeight
end
function Scene.ShelfPose(quality: number, slot: number): CFrame
	local point = potionPoints[math.clamp(quality, 1, #potionPoints)]
	local offset = ShelfSlotOffsets[math.clamp(slot, 1, #ShelfSlotOffsets)]
	return point.CFrame * CFrame.new(offset)
end
function Scene.ChuteContains(position: Vector3): boolean
	if not Scene.FastChuteOpening or not Scene.ChuteDropZone then
		return false
	end
	return ThrowArc.InsideChute(
		Scene.FastChuteOpening.CFrame,
		Scene.FastChuteOpening.Size,
		Scene.ChuteDropZone.CFrame,
		Scene.ChuteDropZone.Size,
		position,
		Physics.ChuteStackHeight
	)
end
function Scene.ChuteLandingContains(position: Vector3): boolean
	if not Scene.ChuteDropZone then
		return false
	end
	return ThrowArc.InsideChuteLanding(
		Scene.ChuteDropZone.CFrame,
		Scene.ChuteDropZone.Size,
		position,
		Physics.ChuteStackHeight
	)
end
function Scene.ChuteDropPose(random: Random, landing: CFrame?): CFrame
	local base = if Scene.ChuteLanding then Scene.ChuteLanding.Position else ChuteFallbackLanding
	local zone = Scene.ChuteDropZone
	local position = base + Vector3.new(random:NextNumber(-ChuteSpawnSpread, ChuteSpawnSpread), 0, random:NextNumber(-ChuteSpawnSpread, ChuteSpawnSpread))
	local yaw = random:NextNumber(0, 2 * math.pi)
	if landing then
		position = landing.Position
		local direction = landing.LookVector
		if Vector3.new(direction.X, 0, direction.Z).Magnitude < 0.1 then direction = landing.UpVector end
		yaw = math.atan2(-direction.X, -direction.Z)
	end
	if zone then
		local offset = zone.CFrame:PointToObjectSpace(position)
		local halfX = math.max(0, zone.Size.X * 0.5 - ChuteEdgeClearance)
		local halfZ = math.max(0, zone.Size.Z * 0.5 - ChuteEdgeClearance)
		position = zone.CFrame:PointToWorldSpace(Vector3.new(math.clamp(offset.X, -halfX, halfX), 0, math.clamp(offset.Z, -halfZ, halfZ)))
	end
	return CFrame.new(position.X, base.Y, position.Z)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(math.pi / 2 + random:NextNumber(-0.12, 0.12), 0, random:NextNumber(-0.18, 0.18))
end
function Scene.ChutePileContains(position: Vector3): boolean
	local zone = Scene.ChuteDropZone
	if not zone then
		return position.Y >= ChuteFallbackLanding.Y - ChuteFallTolerance
			and position.Y <= ChuteFallbackLanding.Y + Physics.ChuteStackHeight
	end
	local offset = zone.CFrame:PointToObjectSpace(position)
	return math.abs(offset.X) <= zone.Size.X * 0.5 + 0.45
		and math.abs(offset.Z) <= zone.Size.Z * 0.5 + 0.45
		and offset.Y >= -ChuteFallTolerance
		and offset.Y <= zone.Size.Y * 0.5 + Physics.ChuteStackHeight
end
function Scene.AutoOutputPose(slot: number): CFrame
	local index = math.max(0, slot - 1)
	local col = (index % 3) - 1
	local layer = math.floor(index / 3) % 2
	local base = if Scene.AutoRuneOutputPad then Scene.AutoRuneOutputPad.Position else Vector3.new(-14.8, 4.05, -27.5)
	return CFrame.new(base + Vector3.new(col * 2.95, 0.76 + layer * 1.36, 0)) * CFrame.Angles(math.pi / 2, 0, 0)
end
function Scene.AutoRunePose(): CFrame
	local base = if Scene.AutoRuneWorkBed then Scene.AutoRuneWorkBed.Position else Vector3.new(-19.0, 4.4, -27.0)
	return PaintRotation.TablePose(base + Vector3.new(0, 0.25, 0))
end
function Scene.AutoSmelterPose(): CFrame
	local base = if Scene.AutoSmelterCenter then Scene.AutoSmelterCenter.Position else Vector3.new(-1.0, 4.5, -27.0)
	return PaintRotation.TablePose(base)
end
function Scene.AutoTransferPoses(): (CFrame, CFrame, CFrame, CFrame)
	local ramp = if Scene.AutoTransferRamp then Scene.AutoTransferRamp.Position else Vector3.new(-18, 2.5, -27)
	local rampTop = if Scene.AutoTransferRampTop then Scene.AutoTransferRampTop.Position else Vector3.new(-14, 4.5, -27)
	local pass = if Scene.AutoTransferPass then Scene.AutoTransferPass.Position else Vector3.new(-12, 4.5, -27)
	local inlet = if Scene.AutoSmelterInlet then Scene.AutoSmelterInlet.Position else Vector3.new(-5, 4.5, -27)
	return PaintRotation.TablePose(ramp), PaintRotation.TablePose(rampTop), PaintRotation.TablePose(pass), PaintRotation.TablePose(inlet)
end
local transferPassLight = if Scene.AutoTransferPass then Scene.AutoTransferPass:FindFirstChild("TransferPassLight") else nil
local transferPassStrip = if Scene.AutoRuneMachine then Scene.AutoRuneMachine:FindFirstChild("TransferPassStrip", true) else nil
function Scene.SetAutoTransferLight(enabled: boolean): ()
	if transferPassLight and transferPassLight:IsA("Light") and transferPassLight.Enabled ~= enabled then
		transferPassLight.Enabled = enabled
		if transferPassStrip and transferPassStrip:IsA("BasePart") then
			transferPassStrip.Material = if enabled then Enum.Material.Neon else Enum.Material.SmoothPlastic
			transferPassStrip.Transparency = if enabled then 0 else 0.75
		end
	end
end
function Scene.AutoShelfPose(slot: number): CFrame
	if #autoPotionPoints == 0 then
		return CFrame.new(10.0, 5.245, -31.0)
	end
	local point = autoPotionPoints[math.clamp(slot, 1, #autoPotionPoints)]
	return point.CFrame * CFrame.new(0, 0.345, 0)
end
function Scene.SafePose(position: Vector3, fallback: Vector3, ignored: { Instance }): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	local result = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -25, 0), params)
	if result and result.Normal.Y > 0.6 then
		return CFrame.new(result.Position + Vector3.new(0, 3, 0))
	end
	return CFrame.new(fallback + Vector3.new(0, 3, 0))
end
local function ReadStreetInterestPoints(): { InterestPoint }
	local points: { InterestPoint } = {}
	local folder = district:FindFirstChild("StreetInterestPoints")
	if folder and folder:IsA("Folder") then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				local look = part.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				local lookDir = if flatLook.Magnitude > 1e-4 then flatLook.Unit else -Vector3.zAxis
				local pos = Scene.StreetFloor(part.Position) or part.Position
				if Scene.IsInStreetWalkZones(pos) then
					table.insert(points, {
						id = part.Name,
						position = pos,
						lookDirection = lookDir,
					})
				end
			end
		end
	end
	if #points == 0 then
		local fallback = StreetZones.FallbackInterestPoints(streetZones)
		for _, entry in fallback do
			local pos = Scene.StreetFloor(entry.position) or entry.position
			table.insert(points, {
				id = entry.id,
				position = pos,
				lookDirection = entry.lookDirection,
			})
		end
	end
	return points
end

local streetInterestPoints = ReadStreetInterestPoints()

function Scene.GetStreetInterestPoints(): { InterestPoint }
	return streetInterestPoints
end

function Scene.Visible(character: Model, position: Vector3, target: Model?, ignored: Instance?): boolean
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ignored then { character, ignored } else { character }
	params.RespectCanCollide = true
	local direction = position - head.Position
	if direction.Magnitude < 0.01 then
		return true
	end
	local hit = workspace:Raycast(head.Position, direction, params)
	return not hit or (target ~= nil and hit.Instance:IsDescendantOf(target)) or (hit.Position - position).Magnitude < 1
end
return Scene
