-- 二次重构 Edit 样板：白膜曝光、笔尖反馈、克制 HUD 与分层药水；不创建或覆写脚本
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "Place1 Edit required")
local rs = game:GetService("ReplicatedStorage")
local rig = rs.Models.WhiteR15
local white = if rig:GetAttribute("SurfaceVersion")==1 then Color3.fromRGB(220,220,231) else Color3.fromRGB(205,204,216)
for _, part in rig:GetChildren() do if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then part.Color = white end end
local colors = rig:FindFirstChildOfClass("BodyColors")
if colors then for _, name in {"HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3"} do colors[name] = white end end
local surface = rs.UI.PaintFaceGui
surface.Brightness = 1.2
local root = rs.UI.GameScreenGui.CenterFrame
root.HintText.Position = UDim2.fromOffset(320, 900)
root.HintText.Size = UDim2.fromOffset(1000, 56)
if root:FindFirstChild("HintKeyText") then
 root.HintKeyText.Position = root.HintText.Position
 root.HintText.Position += UDim2.fromOffset(48,0)
 root.HintText.Size -= UDim2.fromOffset(48,0)
end
root.NoticeText.Position = UDim2.fromOffset(320, 840)
root.NoticeText.Size = UDim2.fromOffset(1000, 48)
local cursor = root:FindFirstChild("PaintCursorFrame")
if not cursor then
 cursor = Instance.new("Frame")
 cursor.Name = "PaintCursorFrame"
 cursor.AnchorPoint = Vector2.new(.5, .5)
 cursor.Size = UDim2.fromOffset(48,48)
 cursor.BackgroundTransparency, cursor.BorderSizePixel, cursor.Active, cursor.Visible, cursor.ZIndex = 1,0,false,false,20
 local corner = Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=cursor
 local stroke = Instance.new("UIStroke");stroke.StrokeSizingMode=Enum.StrokeSizingMode.ScaledSize;stroke.Thickness=.025;stroke.Color=Color3.fromRGB(213,166,255);stroke.Parent=cursor
 local dot=Instance.new("Frame");dot.Name="TipFrame";dot.AnchorPoint=Vector2.new(.5,.5);dot.Position=UDim2.fromScale(.5,.5);dot.Size=UDim2.fromOffset(6,6);dot.BorderSizePixel=0;dot.BackgroundColor3=Color3.fromRGB(246,227,255);dot.Parent=cursor
 local dotCorner=Instance.new("UICorner");dotCorner.CornerRadius=UDim.new(1,0);dotCorner.Parent=dot
 cursor.Parent=root
end
-- 画笔光标按裁切后的原图比例摆放，锚点落在笔尖，避免 Fit 留白把落点挪偏。
local brushCursor = root:FindFirstChild("PaintBrushCursorImage")
if not brushCursor then
 brushCursor = Instance.new("ImageLabel")
 brushCursor.Name = "PaintBrushCursorImage"
 brushCursor.Parent = root
end
brushCursor.AnchorPoint = Vector2.new(0.41, 0)
brushCursor.Rotation = -38
brushCursor.Size = UDim2.fromOffset(28, 194)
brushCursor.BackgroundTransparency = 1
brushCursor.BorderSizePixel = 0
brushCursor.ScaleType = Enum.ScaleType.Fit
brushCursor.Active = false
brushCursor.Interactable = false
brushCursor.Visible = false
brushCursor.ZIndex = 30
brushCursor.Image = "rbxassetid://135479236200618"
local target=rs.UI:FindFirstChild("TargetGui")
if not target then
 target=Instance.new("BillboardGui");target.Name="TargetGui";target.Size=UDim2.fromScale(3.6,3.6*199/1163);target.StudsOffsetWorldSpace=Vector3.new(0,1,0);target.AlwaysOnTop=true;target.LightInfluence=0;target.Enabled=false;target.MaxDistance=45
 local frame=Instance.new("Frame");frame.Name="ContentFrame";frame.AnchorPoint=Vector2.new(.5,1);frame.Position=UDim2.fromScale(.5,1);frame.Size=UDim2.fromScale(1,1);frame.BackgroundTransparency=1;frame.BorderSizePixel=0;frame.Parent=target
 local uiScale=Instance.new("UIScale");uiScale.Scale=1;uiScale.Parent=frame
 local art=Instance.new("ImageLabel");art.Name="FrameImage";art.BackgroundTransparency=1;art.BorderSizePixel=0;art.Size=UDim2.fromScale(1,1);art.ScaleType=Enum.ScaleType.Stretch;art.Image="rbxassetid://70702135277728";art.ZIndex=2;art.Active=false;art.Parent=frame
 local clip=Instance.new("Frame");clip.Name="ClipFrame";clip.BackgroundTransparency=1;clip.BorderSizePixel=0;clip.Position=UDim2.fromScale(130/1163,58/199);clip.Size=UDim2.fromScale(900/1163,84/199);clip.ClipsDescendants=true;clip.ZIndex=1;clip.Parent=frame
 local fill=Instance.new("ImageLabel");fill.Name="FillImage";fill.BackgroundTransparency=1;fill.BorderSizePixel=0;fill.Size=UDim2.fromScale(1,1);fill.ScaleType=Enum.ScaleType.Stretch;fill.Image="rbxassetid://88599892799863";fill.Active=false;fill.Parent=clip
 target.Parent=rs.UI
end
local status=root.StatusFrame
status.BackgroundTransparency=.05
local paint=root.PaintFrame
paint.BackgroundTransparency=.04
-- 复用既有药水模板，只扩充层次，保留 Bottle 主部件与承载契约。
local potion=rs.Models.Potion
local bottle=potion.Bottle
bottle.Color=Color3.fromRGB(157,141,181);bottle.Material=Enum.Material.Glass;bottle.Transparency=.35;bottle.Size=Vector3.new(.9,1.1,.9)
local stopper=potion.Stopper
stopper.Color=Color3.fromRGB(222,180,107);stopper.Size=Vector3.new(.32,.28,.32);stopper.CFrame=bottle.CFrame*CFrame.new(0,.8,0)
local function extra(name, size, offset, color, material, shape)
 local part=potion:FindFirstChild(name)
 if not part then part=Instance.new("Part");part.Name=name;part.Parent=potion end
 part.Size=size;part.CFrame=bottle.CFrame*CFrame.new(offset);part.Color=color;part.Material=material;part.Shape=shape
 part.CanCollide=false;part.CanTouch=false;part.Massless=true
 local weld=part:FindFirstChild("BottleWeld")
 if not weld then weld=Instance.new("WeldConstraint");weld.Name="BottleWeld";weld.Parent=part end
 weld.Part0,weld.Part1=bottle,part
 return part
end
local core=extra("SoulCore",Vector3.new(.61,.74,.61),Vector3.new(0,-.1,0),Color3.fromRGB(154,55,222),Enum.Material.Neon,Enum.PartType.Ball)
extra("Neck",Vector3.new(.29,.34,.29),Vector3.new(0,.56,0),Color3.fromRGB(157,141,181),Enum.Material.Glass,Enum.PartType.Block)
extra("SealBand",Vector3.new(.4,.11,.4),Vector3.new(0,.65,0),Color3.fromRGB(222,180,107),Enum.Material.Metal,Enum.PartType.Block)
local light=core:FindFirstChildOfClass("PointLight")
if not light then light=Instance.new("PointLight");light.Parent=core end
light.Color=Color3.fromRGB(176,83,255);light.Brightness=.5;light.Range=4
-- 出生方向与最初验收的通道对齐；不改变街道和楼梯几何。
local spawn=workspace.NeonContractDistrict.StreetSpawn
spawn.CFrame=CFrame.new(55,spawn.Position.Y,29)
-- 文案迁移与 update-processing-localization.luau 保持一致（离线测试校验）。
do
-- 加工文案 Edit 模板迁移：仅增量配置文字及独立键位，不重建 HUD
--!strict
assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), "DemonShop Edit required")
local ui = game:GetService("ReplicatedStorage").UI
local gui = ui.GameScreenGui
for _, value in gui:GetDescendants() do
	if value:IsA("TextLabel") then
		local dynamic = value.Name == "CoinsText" or value.Name == "CarryText" or value.Name == "StockText"
			or value.Name == "HintText" or value.Name == "NoticeText" or value.Name == "ProgressText"
		value.AutoLocalize = not dynamic and not string.find(value.Name, "KeyText")
		if dynamic and value.Name ~= "ProgressText" then value.Text = "" end
	end
end
for _, node in gui:GetDescendants() do
	if node.Name == "InteractButton" or node.Name == "HintKeyText" or node.Name == "DropButton" or node.Name == "AttackButton" then node:Destroy() end
end
local target = ui:FindFirstChild("TargetGui")
if target then
	local content = target:FindFirstChild("ContentFrame")
	if content then
		local count = content:FindFirstChild("CountText")
		if count then count:Destroy() end
		local key = content:FindFirstChild("KeyText")
		if key then key:Destroy() end
	end
end

local existingPrompt = ui:FindFirstChild("WorldInteractionPrompt")
local prompt: ProximityPrompt
if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
	prompt = existingPrompt
else
	local created = Instance.new("ProximityPrompt")
	created.Name = "WorldInteractionPrompt"
	created.Parent = ui
	prompt = created
end
prompt.Style = Enum.ProximityPromptStyle.Default
prompt.HoldDuration = 0.5
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.ClickablePrompt = true
prompt.RequiresLineOfSight = true
prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
prompt.MaxActivationDistance = 8
prompt.Enabled = false
prompt.AutoLocalize = false


end

return {cursor=cursor:GetFullName(),potionParts=#potion:GetChildren(),white=tostring(white)}
