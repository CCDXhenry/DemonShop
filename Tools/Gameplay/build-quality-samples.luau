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
local target=rs.UI:FindFirstChild("TargetGui")
if not target then
 target=Instance.new("BillboardGui");target.Name="TargetGui";target.Size=UDim2.fromOffset(170,44);target.StudsOffsetWorldSpace=Vector3.new(0,1,0);target.AlwaysOnTop=true;target.LightInfluence=0;target.Enabled=false;target.MaxDistance=45
 local frame=Instance.new("Frame");frame.Name="ContentFrame";frame.AnchorPoint=Vector2.new(.5,1);frame.Position=UDim2.fromScale(.5,1);frame.Size=UDim2.fromScale(1,1);frame.BackgroundColor3=Color3.fromRGB(23,16,36);frame.BackgroundTransparency=.1;frame.BorderSizePixel=0;frame.Parent=target
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,8);corner.Parent=frame
 local text=Instance.new("TextLabel");text.Name="CountText";text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.TextColor3=Color3.fromRGB(240,219,255);text.Font=Enum.Font.GothamBold;text.TextScaled=true;text.AutoLocalize=false;text.Text="HIT 0 / 3";text.Parent=frame
 local stroke=Instance.new("UIStroke");stroke.StrokeSizingMode=Enum.StrokeSizingMode.ScaledSize;stroke.Thickness=.05;stroke.Parent=text
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
local root = gui.CenterFrame
local function SplitKey(label: TextLabel, name: string, key: string, width: number): TextLabel
	local parent = label.Parent :: Instance
	local existing = parent:FindFirstChild(name) :: TextLabel?
	if existing then return existing end
	local keyLabel = label:Clone()
	keyLabel.Name, keyLabel.Text, keyLabel.AutoLocalize = name, key, false
	keyLabel.Size = UDim2.new(0, width, label.Size.Y.Scale, label.Size.Y.Offset)
	keyLabel.Visible = false
	keyLabel.Parent = parent
	label.Position += UDim2.fromOffset(width, 0)
	label.Size -= UDim2.fromOffset(width, 0)
	return keyLabel
end
for _, value in gui:GetDescendants() do
	if value:IsA("TextLabel") then
		local dynamic = value.Name == "CoinsText" or value.Name == "CarryText" or value.Name == "StockText"
			or value.Name == "HintText" or value.Name == "NoticeText" or value.Name == "ProgressText"
			or (value.Name == "LabelText" and value.Parent and value.Parent.Name == "DropButton")
		value.AutoLocalize = not dynamic and not string.find(value.Name, "KeyText")
		if dynamic and value.Name ~= "ProgressText" then value.Text = "" end
	end
end
SplitKey(root.HintText, "HintKeyText", "E", 48)
local interactKey = SplitKey(root.InteractButton.LabelText, "KeyText", "E", 48)
interactKey.Visible = true
root.InteractButton.LabelText.Text = "INTERACT"
root.InteractButton.LabelText.AutoLocalize = true
local dropKey = SplitKey(root.DropButton.LabelText, "KeyText", "Q", 48)
dropKey.Visible = true
root.DropButton.LabelText.Text = ""
root.DropButton.LabelText.AutoLocalize = false
local target = ui:FindFirstChild("TargetGui")
if target then
	local count = target.ContentFrame.CountText
	count.AutoLocalize, count.Text = false, ""
	SplitKey(count, "KeyText", "E", 32)
end

end

return {cursor=cursor:GetFullName(),potionParts=#potion:GetChildren(),white=tostring(white)}
