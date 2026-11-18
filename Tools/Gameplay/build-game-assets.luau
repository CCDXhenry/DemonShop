-- Edit 资源构建器：幂等创建白膜 R15、道具、网络事件与唯一 UI 模板
assert(not game:GetService("RunService"):IsRunning(), "Edit mode required")
local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local function folder(parent,name)
 local v=parent:FindFirstChild(name);if not v then v=Instance.new("Folder");v.Name=name;v.Parent=parent end;return v
end
-- 提前检查，缺少官方模板时停止，避免半途修改其他资源。
local models=folder(RS,"Models")
-- 官方武器模板从本地 RBXM 恢复，不再生成会覆盖美术资源的方棍。
local sword=models:FindFirstChild("Club")
assert(sword and sword:IsA("Tool") and sword:GetAttribute("SourceAssetId"),
 "Import Assets/Models/ClassicSword.rbxm into ReplicatedStorage.Models before building (replace old Club)")
local district=workspace:WaitForChild("NeonContractDistrict")
if not district:FindFirstChild("SummoningSubmitAnchor") then
 local sigil=district.summoning.Generated.SummoningCircle["Flat Purple Summoning Sigil"]
 local anchor=Instance.new("Part");anchor.Name="SummoningSubmitAnchor";anchor.Size=Vector3.new(.1,.1,.1);anchor.Position=sigil:GetPivot().Position+Vector3.new(0,1,5)
 anchor.Anchored=true;anchor.Transparency=1;anchor.CanCollide=false;anchor.CanQuery=false;anchor.CanTouch=false;anchor.Parent=district
end
for _,name in {"SoulHoldingPool","RuneBodyTable","SoulConversionAltar","SoulCrystalDisplay"} do district[name].ModelStreamingMode=Enum.ModelStreamingMode.Persistent end
assert(models:FindFirstChild("WhiteR15") and models.WhiteR15:GetAttribute("SurfaceVersion")==1,
 "Import Assets/Models/GameModels.rbxm containing the curved WhiteR15 template before building")
-- 曲面 UV、面积与可绘制区域由离线数据提供，不再生成六平面遮罩。
local function part(parent,name,size,color,cf)
 local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=color;p.CFrame=cf or CFrame.identity
 p.CanCollide=false;p.CanTouch=false;p.Massless=true;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent;return p
end
local function tool(name,size,color)
 local old=models:FindFirstChild(name);if old then return old end
 local t=Instance.new("Tool");t.Name=name;t.CanBeDropped=false;t.RequiresHandle=true
 part(t,"Handle",size,color);t.Parent=models;return t
end
tool("RuneBrush",Vector3.new(.12,1.8,.12),Color3.fromRGB(188,128,255))
if not models:FindFirstChild("Potion") then
 local m=Instance.new("Tool");m.Name="Potion";m.CanBeDropped=false;m.RequiresHandle=true;m.ManualActivationOnly=true
 m.Grip=CFrame.new(0,0,0.5)*CFrame.Angles(math.rad(-90),0,0)
 local body=part(m,"Handle",Vector3.new(.9,1.25,.9),Color3.fromRGB(166,63,255));body.Shape=Enum.PartType.Ball;body.Material=Enum.Material.Neon
 local neck=part(m,"Stopper",Vector3.new(.35,.45,.35),Color3.fromRGB(235,188,102),CFrame.new(0,.7,0))
 local w=Instance.new("WeldConstraint");w.Part0=body;w.Part1=neck;w.Parent=body
 m.PrimaryPart=body;m.Parent=models
end
local events=folder(RS,"RemoteEvents")
for _,name in {"GameRequest","GameNotify"} do if not events:FindFirstChild(name) then local r=Instance.new("RemoteEvent");r.Name=name;r.Parent=events end end
local ui=folder(RS,"UI")
local existing=ui:FindFirstChild("GameScreenGui");if existing then existing:Destroy() end
local gui=Instance.new("ScreenGui");gui.Name="GameScreenGui";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=10
local root=Instance.new("Frame");root.Name="CenterFrame";root.BackgroundTransparency=1;root.Size=UDim2.fromOffset(1920,1080);root.AnchorPoint=Vector2.new(.5,.5);root.Position=UDim2.fromScale(.5,.5);root.Parent=gui
local scale=Instance.new("UIScale");scale.Parent=root
local function label(parent,name,text,x,y,w,h,font)
 local l=Instance.new("TextLabel");l.Name=name;l.Text=text;l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h)
 l.BackgroundTransparency=1;l.TextColor3=Color3.fromRGB(245,238,255);l.Font=Enum.Font.GothamBold;l.TextSize=font;l.TextScaled=false;l.TextWrapped=false;l.AutoLocalize=false;l:SetAttribute("DesignTextSize",font);l.Parent=parent
 local stroke=Instance.new("UIStroke");stroke.StrokeSizingMode=Enum.StrokeSizingMode.ScaledSize;stroke.Thickness=.05;stroke.Color=Color3.fromRGB(25,13,39);stroke.Parent=l
 return l
end
local function panel(name,x,y,w,h)
 local f=Instance.new("Frame");f.Name=name;f.Position=UDim2.fromOffset(x,y);f.Size=UDim2.fromOffset(w,h);f.BackgroundColor3=Color3.fromRGB(23,16,36);f.BackgroundTransparency=.12;f.BorderSizePixel=0;f.Parent=root
 local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,16);c.Parent=f
 local s=Instance.new("UIStroke");s.StrokeSizingMode=Enum.StrokeSizingMode.ScaledSize;s.Thickness=.012;s.Color=Color3.fromRGB(138,80,190);s.Parent=f;return f
end
local hud=panel("StatusFrame",1390,60,460,240)
label(hud,"TitleText","SOUL WORKSHOP",16,8,428,52,36)
label(hud,"CoinsText","COINS  0",16,65,428,48,32)
label(hud,"CarryText","HANDS EMPTY",16,120,428,44,26)
label(hud,"StockText","POOL 0/8  |  POTIONS 0/8",16,172,428,40,24)
label(root,"HintText","",400,900,1120,56,32)
label(root,"NoticeText","",400,840,1120,48,28)
local paint=panel("PaintFrame",550,90,820,170);paint.Visible=false
label(paint,"TitleText","DRAW THE RUNE",20,8,780,44,32)
label(paint,"ProgressText","0%",20,55,780,42,28)
local bar=Instance.new("Frame");bar.Name="ProgressBarFrame";bar.Position=UDim2.fromOffset(40,115);bar.Size=UDim2.fromOffset(740,22);bar.BorderSizePixel=0;bar.BackgroundColor3=Color3.fromRGB(59,37,78);bar.Parent=paint
local fill=Instance.new("Frame");fill.Name="FillFrame";fill.Size=UDim2.fromScale(0,1);fill.BorderSizePixel=0;fill.BackgroundColor3=Color3.fromRGB(180,85,255);fill.Parent=bar
local function button(name,text,x,y,w)
 local b=Instance.new("ImageButton");b.Name=name;b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,72);b.Image="";b.BackgroundColor3=Color3.fromRGB(89,44,133);b.BorderSizePixel=0;b.AutoButtonColor=true;b.Parent=root
 local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,14);c.Parent=b
 label(b,"LabelText",text,8,8,w-16,56,28);return b
end
button("DropButton","Q  DROP",1420,820,360)
button("AttackButton","ATTACK",1420,910,360)
local exit=button("ExitPaintButton","EXIT",560,950,350);exit.Visible=false
local reset=button("ResetViewButton","RESET VIEW",1010,950,350);reset.Visible=false
-- 独立触屏操作模板使用物理尺寸，普通 HUD 仍只由 Center 画布整体缩放。
local function touchControls(name,portrait,painting)
 local f=Instance.new("Frame");f.Name=name;f.BackgroundTransparency=1;f.Visible=false;f.Parent=gui
 if painting then f.Size=UDim2.fromOffset(300,50);f.AnchorPoint=Vector2.new(.5,1);f.Position=UDim2.new(.5,0,1,-24)
 else f.Size=UDim2.fromOffset(140,170);f.AnchorPoint=if portrait then Vector2.new(1,.5) else Vector2.new(1,1);f.Position=if portrait then UDim2.new(1,-24,.5,0) else UDim2.new(1,-140,1,-24) end
 local names=if painting then {"ExitPaintButton","ResetViewButton"} else {"DropButton","AttackButton"}
 local texts=if painting then {"EXIT","RESET"} else {"DROP","HIT"}
 for index,buttonName in names do
  local b=Instance.new("ImageButton");b.Name=buttonName;b.Image="";b.Size=UDim2.fromOffset(140,50);b.Position=if painting then UDim2.fromOffset((index-1)*160,0) else UDim2.fromOffset(0,index*60)
  b.BackgroundColor3=Color3.fromRGB(89,44,133);b.BorderSizePixel=0;b.Parent=f
  local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,12);c.Parent=b
  label(b,"LabelText",texts[index],8,2,124,46,24)
 end
end
touchControls("TouchLandscapeFrame",false,false)
touchControls("TouchPortraitFrame",true,false)
touchControls("TouchPaintFrame",false,true)
gui.Parent=ui
for _,name in {"PaintFaceGui","PaintCellFrame"} do local v=ui:FindFirstChild(name);if v then v:Destroy() end end
local surface=Instance.new("SurfaceGui");surface.Name="PaintFaceGui";surface.CanvasSize=Vector2.new(256,256);surface.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;surface.AlwaysOnTop=false;surface.LightInfluence=0;surface.Brightness=2;surface.ZOffset=.015;surface.Parent=ui
local cell=Instance.new("Frame");cell.Name="PaintCellFrame";cell.AnchorPoint=Vector2.new(.5,.5);cell.Size=UDim2.fromScale(.15,.15);cell.BackgroundColor3=Color3.fromRGB(176,63,255);cell.BorderSizePixel=0
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=cell;cell.Parent=ui
-- 清理已替换的旧业务资源；共享 Core、第三方与现有地图几何保持原样。
local legacy={
 [RS.UI]={"GameFrame","GameScreenGui","FarmToolShopFrame","FarmWeaponEnhanceFrame","FarmCollectorShopFrame","FarmBasketShopFrame","FarmRestaurantFrame","FarmSpeciesFrame","FarmEquipmentFrame","FarmWeaponShopFrame","FarmHatchFrame","FarmConfirmationFrame","RoastChickenHUDFrame","FarmInteractionFrame","AnimalHealthGui","NestSignGui","RestaurantSignGui","WorkerSignGui","EggSignGui","FarmOwnerSignGui","CookedFoodSignGui","DamagePopGui","FarmTouchUseFrame","PackingDeliverySignGui","PackingEntranceSignGui","OriginalFoodDeliverySignGui","OriginalKitchenEntranceSignGui","OriginalFoodDirectionSignGui"},
 [RS.RemoteEvents]={"NotifyPlayerInfoInit","NotifyPlayersOtherPlayerInfoInit","NotifyPlayerAcquiredGamePass","RequestSetBGMVolume","RequestSetSoundEffectVolume","RequestSetVibrationsOnOffState","RoastChickenAction"},
 [RS.Models]={"Weapons","Baskets","Collectors","CollectorTools"},
 [SS.Models]={"PersonalFarmTemplate","FarmWorkerTemplate","FarmUIArtwork","FarmPackerTemplate","FarmCustomerTemplate","FarmPackageTemplate","FarmRestaurantOriginalLayout"},
 [RS.Sounds]={"Upgrade","Zap_T1","Zap_T2","Zap_T3","Zap_T4","Zap_T5","AnimalHit","UIClick","FoodDrop","EggHatch","Warning","Coin","UIOpen","AnimalCooked","Delivery","PackageDone","UIClose","AnimalScared","EggSpeedup","EggLand","Pickup","EggSpawn"},
 [RS.VFX]={"ZapMuzzle_T1","ZapMuzzle_T2","ZapMuzzle_T3","ZapMuzzle_T4","ZapMuzzle_T5","ZapArcBeam","HitImpact","RoastFlight","FloatAnchor"},
 [RS.BindableEvents]={"CloseWindow","LocalPlayerInfoInit","OtherPlayerInfoInit","LocalPlayerAcquiredGamePass","OpenWindow","FarmInfoChanged"},
 [SS.BindableEvents]={"PlayerInfoInit","FarmInfoChanged"},
 [SS]={"FarmVillageArchive"},
}
for parent,names in legacy do for _,name in names do local old=parent:FindFirstChild(name);if old and old~=gui then old:Destroy() end end end
local house=district:FindFirstChild("StairEntranceHouse")
if house then for _,name in {"AutomaticDoor","DoorController"} do local old=house:FindFirstChild(name);if old and old:IsA("LuaSourceContainer") then old:Destroy() end end end
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
for _, node in gui:GetDescendants() do
	if node.Name == "InteractButton" or node.Name == "HintKeyText" then node:Destroy() end
end
local dropKey = SplitKey(root.DropButton.LabelText, "KeyText", "Q", 48)
dropKey.Visible = true
root.DropButton.LabelText.Text = ""
root.DropButton.LabelText.AutoLocalize = false
local target = ui:FindFirstChild("TargetGui")
if target then
	local count = target.ContentFrame.CountText
	count.AutoLocalize, count.Text = false, ""
	local key = count.Parent:FindFirstChild("KeyText"); if key then key:Destroy() end
end

local prompt = ui:FindFirstChild("WorldInteractionPrompt") :: ProximityPrompt?
if not prompt then prompt = Instance.new("ProximityPrompt"); prompt.Name = "WorldInteractionPrompt"; prompt.Parent = ui end
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

return {rigParts=#models.WhiteR15:GetChildren(),ui=gui:GetFullName(),models=models:GetFullName()}

