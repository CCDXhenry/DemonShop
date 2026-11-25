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
for _, bruteName in {"HellBrute_1", "HellBrute_2", "AutoClerk"} do
 local brute = models:FindFirstChild(bruteName)
 assert(brute and brute:IsA("Model") and brute:FindFirstChild("HumanoidRootPart") and brute:FindFirstChildOfClass("Humanoid"),
  "Import Assets/Models/GameModels.rbxm containing " .. bruteName .. " before building")
end
-- 自动化底盘圈模板从 GameModels.rbxm 恢复；场景空洞与 AutomationLine 设施由 build-automation-assets.luau 构建。
assert(models:FindFirstChild("UnlockPad") and models.UnlockPad:FindFirstChild("GuiAnchor"),
 "Import Assets/Models/GameModels.rbxm containing UnlockPad or run Tools/Gameplay/build-automation-assets.luau")
-- 曲面 UV、面积与可绘制区域由离线数据提供，不再生成六平面遮罩。
local function part(parent,name,size,color,cf)
 local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=color;p.CFrame=cf or CFrame.identity
 p.CanCollide=false;p.CanTouch=false;p.Massless=true;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent;return p
end
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
-- 增量补齐唯一 UI 模板，严禁销毁既有 GameScreenGui、WindowCanvas、ModalButton 或定制模板。
local existing=ui:FindFirstChild("GameScreenGui")
local gui: ScreenGui
if existing and existing:IsA("ScreenGui") then
 gui=existing
else
 local created=Instance.new("ScreenGui");created.Name="GameScreenGui";created.ResetOnSpawn=false;created.IgnoreGuiInset=true;created.DisplayOrder=10;created.Parent=ui
 gui=created
end
gui.IgnoreGuiInset=true
gui.ScreenInsets=Enum.ScreenInsets.None
local function label(parent,name,text,x,y,w,h,font)
 local l=Instance.new("TextLabel");l.Name=name;l.Text=text;l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h)
 l.BackgroundTransparency=1;l.TextColor3=Color3.fromRGB(245,238,255);l.Font=Enum.Font.GothamBold;l.TextSize=font;l.TextScaled=false;l.TextWrapped=false;l.AutoLocalize=false;l:SetAttribute("DesignTextSize",font);l.Parent=parent
 local stroke=Instance.new("UIStroke");stroke.StrokeSizingMode=Enum.StrokeSizingMode.ScaledSize;stroke.Thickness=.05;stroke.Color=Color3.fromRGB(25,13,39);stroke.Parent=l
 return l
end
local existingRoot=gui:FindFirstChild("CenterFrame")
local root: Frame
if existingRoot and existingRoot:IsA("Frame") then
 root=existingRoot
else
 local created=Instance.new("Frame");created.Name="CenterFrame";created.BackgroundTransparency=1;created.Size=UDim2.fromOffset(1920,1080);created.AnchorPoint=Vector2.new(.5,.5);created.Position=UDim2.fromScale(.5,.5);created.Parent=gui
 root=created
 local scale=Instance.new("UIScale");scale.Parent=root
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
 local function button(name,text,cx,cy,w,h)
  local b=Instance.new("ImageButton");b.Name=name;b.AnchorPoint=Vector2.new(.5,.5);b.Position=UDim2.fromOffset(cx,cy);b.Size=UDim2.fromOffset(w,h);b.Image="";b.BackgroundColor3=Color3.fromRGB(89,44,133);b.BorderSizePixel=0;b.AutoButtonColor=true;b.Parent=root
  local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,14);c.Parent=b
  label(b,"LabelText",text,8,8,w-16,h-16,28);return b
 end
 local exit=button("ExitPaintButton","EXIT",735,982,350,84);exit.Visible=false
 local reset=button("ResetViewButton","RESET VIEW",1185,982,350,84);reset.Visible=false
end
if not root:FindFirstChildOfClass("UIScale") then
 local scale=Instance.new("UIScale");scale.Parent=root
end
for _, info in { { name = "ExitPaintButton", cx = 735, cy = 982 }, { name = "ResetViewButton", cx = 1185, cy = 982 } } do
 local b = root:FindFirstChild(info.name)
 if b and b:IsA("GuiButton") then
  b.AnchorPoint = Vector2.new(0.5, 0.5)
  b.Size = UDim2.fromOffset(350, 84)
  b.Position = UDim2.fromOffset(info.cx, info.cy)
  local lbl = b:FindFirstChild("LabelText")
  if lbl and lbl:IsA("TextLabel") then
   lbl.Position = UDim2.fromOffset(8, 8)
   lbl.Size = UDim2.fromOffset(334, 68)
   lbl:SetAttribute("DesignTextSize", 28)
  end
 end
end
local windowCanvas=gui:FindFirstChild("WindowCanvas")
if not windowCanvas then
 local canvas=Instance.new("Frame");canvas.Name="WindowCanvas";canvas.Size=UDim2.fromOffset(1920,1080);canvas.AnchorPoint=Vector2.new(.5,.5);canvas.Position=UDim2.fromScale(.5,.5);canvas.BackgroundTransparency=1;canvas.Active=false;canvas.Parent=gui
 windowCanvas=canvas
end
if not windowCanvas:FindFirstChildOfClass("UIScale") then
 local s=Instance.new("UIScale");s.Parent=windowCanvas
end
if not gui:FindFirstChild("ModalButton") then
 local modal=Instance.new("ImageButton");modal.Name="ModalButton";modal.Size=UDim2.fromScale(1,1);modal.BackgroundColor3=Color3.new(0,0,0);modal.BackgroundTransparency=.4;modal.Image="";modal.Modal=true;modal.AutoButtonColor=false;modal.Visible=false;modal.ZIndex=101;modal.Parent=gui
end
-- 清理已合并/废弃的独立触控模板（画符双端共用 CenterFrame 按钮；触控操作键固定于 CenterFrame.TouchControlsFrame）。
for _, old in { gui:FindFirstChild("TouchPaintFrame"), ui:FindFirstChild("TouchAttackFrame"), ui:FindFirstChild("TouchSprintFrame"), ui:FindFirstChild("ThrowStick") } do
 if old then old:Destroy() end
end
local function touchControls()
 local controls = root:FindFirstChild("TouchControlsFrame")
 if not (controls and controls:IsA("Frame")) then
  if controls then controls:Destroy() end
  local f = Instance.new("Frame")
  f.Name = "TouchControlsFrame"
  f.Parent = root
  controls = f
 end
 local tc = controls :: Frame
 tc.Size = UDim2.fromOffset(1920, 1080)
 tc.AnchorPoint = Vector2.new(0.5, 0.5)
 tc.Position = UDim2.fromScale(0.5, 0.5)
 tc.BackgroundTransparency = 1
 tc.BorderSizePixel = 0
 tc.Active = false
 tc.Selectable = false
 tc.ZIndex = 10
 tc.Visible = false

 local function ensureSlot(name: string, cx: number, cy: number, sizePx: number, visible: boolean): Frame
  local slot = tc:FindFirstChild(name)
  if not (slot and slot:IsA("Frame")) then
   if slot then slot:Destroy() end
   local created = Instance.new("Frame")
   created.Name = name
   created.Parent = tc
   slot = created
  end
  local frame = slot :: Frame
  frame.BackgroundTransparency = 1
  frame.BorderSizePixel = 0
  frame.AnchorPoint = Vector2.new(0.5, 0.5)
  frame.Position = UDim2.fromOffset(cx, cy)
  frame.Size = UDim2.fromOffset(sizePx, sizePx)
  frame.Active = false
  frame.Selectable = false
  frame.ZIndex = 10
  frame.Visible = visible
  frame:SetAttribute("MinimumTouchSize", nil)
  frame:SetAttribute("JumpGap", nil)
  frame:SetAttribute("JumpSizeRatio", nil)
  return frame
 end

 local function ensureActionButton(slot: Frame, btnName: string, imageUri: string, textValue: string, fontSize: number): ImageButton
  local existingBtn = slot:FindFirstChild(btnName)
  if not (existingBtn and existingBtn:IsA("ImageButton")) then
   if existingBtn then existingBtn:Destroy() end
   local created = Instance.new("ImageButton")
   created.Name = btnName
   created.Parent = slot
   existingBtn = created
  end
  local btn = existingBtn :: ImageButton
  btn.AnchorPoint = Vector2.new(0.5, 0.5)
  btn.Position = UDim2.fromScale(0.5, 0.5)
  btn.Size = UDim2.fromScale(1, 1)
  btn.BackgroundTransparency = 1
  btn.BorderSizePixel = 0
  btn.ImageContent = Content.fromUri(imageUri)
  btn.ImageRectSize = Vector2.zero
  btn.ImageRectOffset = Vector2.zero
  btn.ScaleType = Enum.ScaleType.Fit
  btn.ZIndex = 10
  btn.AutoButtonColor = true
  btn.Active = true
  btn.Selectable = true
  btn.InputSink = Enum.InputSink.Activate
  btn:SetAttribute("HasInteractionEffect", true)
  btn:SetAttribute("HasClickSound", false)
  btn:SetAttribute("ScaleWhilePressed", true)
  btn:SetAttribute("PressedScale", 0.86)
  btn:SetAttribute("PressTweenSeconds", 0.1)
  local uiScale = btn:FindFirstChildOfClass("UIScale")
  if not uiScale then
   local s = Instance.new("UIScale")
   s.Parent = btn
   uiScale = s
  end
  uiScale.Scale = 1
  local textNode = btn:FindFirstChild("ActionText")
  if not (textNode and textNode:IsA("TextLabel")) then
   if textNode then textNode:Destroy() end
   local t = Instance.new("TextLabel")
   t.Name = "ActionText"
   t.Parent = btn
   textNode = t
  end
  local text = textNode :: TextLabel
  text.BackgroundTransparency = 1
  text.BorderSizePixel = 0
  text.Position = UDim2.fromScale(0, 0.65)
  text.Size = UDim2.fromScale(1, 0.25)
  text.Font = Enum.Font.GothamBold
  text.Text = textValue
  text.TextColor3 = Color3.new(1, 1, 1)
  text.TextSize = fontSize
  text.TextScaled = false
  text.TextWrapped = false
  text.TextXAlignment = Enum.TextXAlignment.Center
  text.TextYAlignment = Enum.TextYAlignment.Center
  text.ZIndex = 11
  text.AutoLocalize = true
  text:SetAttribute("DesignTextSize", fontSize)
  local stroke = text:FindFirstChildOfClass("UIStroke")
  if not stroke then
   local s = Instance.new("UIStroke")
   s.Parent = text
   stroke = s
  end
  stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
  stroke.Thickness = 0.05
  stroke.Color = Color3.fromRGB(25, 37, 43)
  return btn
 end

 local jumpSlot = ensureSlot("TouchJumpFrame", 1765, 915, 190, true)
 ensureActionButton(jumpSlot, "JumpButton", "rbxassetid://138878448546121", "JUMP", 26)

 local attackSlot = ensureSlot("TouchAttackFrame", 1545, 845, 190, true)
 local attackBtn = ensureActionButton(attackSlot, "AttackButton", "rbxassetid://110366066946567", "ATTACK", 26)
 attackBtn:SetAttribute("AttackImage", "rbxassetid://110366066946567")
 attackBtn:SetAttribute("AttackRectOffset", Vector2.zero)

 local stickSlot = ensureSlot("ThrowStick", 1545, 845, 190, false)
 local stickNode = stickSlot:FindFirstChild("StickButton")
 if not (stickNode and stickNode:IsA("ImageButton")) then
  if stickNode then stickNode:Destroy() end
  local created = Instance.new("ImageButton")
  created.Name = "StickButton"
  created.Parent = stickSlot
  stickNode = created
 end
 local stick = stickNode :: ImageButton
 stick.AnchorPoint = Vector2.new(0.5, 0.5)
 stick.Position = UDim2.fromScale(0.5, 0.5)
 stick.Size = UDim2.fromScale(1, 1)
 stick.BackgroundColor3 = Color3.fromRGB(23, 16, 36)
 stick.BackgroundTransparency = 0.25
 stick.Image = ""
 stick.BorderSizePixel = 0
 stick.AutoButtonColor = false
 stick.Active = true
 stick.Selectable = true
 stick.ZIndex = 10
 stick:SetAttribute("HasInteractionEffect", true)
 stick:SetAttribute("HasClickSound", false)
 stick:SetAttribute("ScaleWhilePressed", nil)
 if not stick:FindFirstChildOfClass("UICorner") then
  local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = stick
 end
 local stickStroke = stick:FindFirstChildOfClass("UIStroke")
 if not stickStroke then
  local s = Instance.new("UIStroke"); s.Parent = stick; stickStroke = s
 end
 stickStroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
 stickStroke.Thickness = 0.02
 stickStroke.Color = Color3.fromRGB(180, 85, 255)
 local stickScale = stick:FindFirstChildOfClass("UIScale")
 if not stickScale then
  local s = Instance.new("UIScale"); s.Parent = stick; stickScale = s
 end
 stickScale.Scale = 1
 local knobNode = stick:FindFirstChild("KnobImage")
 if not (knobNode and knobNode:IsA("ImageLabel")) then
  if knobNode then knobNode:Destroy() end
  local created = Instance.new("ImageLabel")
  created.Name = "KnobImage"
  created.Parent = stick
  knobNode = created
 end
 local knob = knobNode :: ImageLabel
 knob.AnchorPoint = Vector2.new(0.5, 0.5)
 knob.Position = UDim2.fromScale(0.5, 0.5)
 knob.Size = UDim2.fromScale(0.42, 0.42)
 knob.BackgroundColor3 = Color3.fromRGB(245, 238, 255)
 knob.BackgroundTransparency = 0.05
 knob.Image = ""
 knob.BorderSizePixel = 0
 knob.ZIndex = 11
 if not knob:FindFirstChildOfClass("UICorner") then
  local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = knob
 end

 local sprintSlot = ensureSlot("TouchSprintFrame", 1765, 695, 156, true)
 local sprintBtn = ensureActionButton(sprintSlot, "SprintButton", "rbxassetid://114836508163438", "SPRINT", 24)
 sprintBtn:SetAttribute("IdleColor", Color3.fromRGB(255, 255, 255))
 sprintBtn:SetAttribute("ActiveColor", Color3.fromRGB(255, 222, 148))
end
touchControls()
local function throwAim()
 if models:FindFirstChild("ThrowAim") then return end
 local root=Instance.new("Model");root.Name="ThrowAim"
 local arc=Instance.new("Model");arc.Name="AimArc";arc.Parent=root
 local host=Instance.new("Part");host.Name="ArcHost";host.Anchored=true;host.CanCollide=false;host.CanQuery=false;host.CanTouch=false
 host.Transparency=1;host.CastShadow=false;host.Size=Vector3.new(.2,.2,.2);host.Parent=arc;arc.PrimaryPart=host
 local function beam(name)
  local start=Instance.new("Attachment");start.Name=name.."Start";start.Parent=host
  local finish=Instance.new("Attachment");finish.Name=name.."Finish";finish.Parent=host
  local node=Instance.new("Beam");node.Name=name;node.Attachment0=start;node.Attachment1=finish
  node.FaceCamera=true;node.LightEmission=.4;node.Width0=.12;node.Width1=.12;node.Segments=16;node.Enabled=false;node.Parent=host
 end
 beam("BeamA");beam("BeamB")
 local ring=Instance.new("Model");ring.Name="Ring";ring.Parent=root
 local disc=Instance.new("Part");disc.Name="RingPart";disc.Shape=Enum.PartType.Cylinder
 disc.Size=Vector3.new(.15,3.2,3.2);disc.Color=Color3.fromRGB(255,196,64);disc.Material=Enum.Material.Neon
 disc.Anchored=true;disc.CanCollide=false;disc.CanQuery=false;disc.CanTouch=false;disc.CastShadow=false
 disc.CFrame=CFrame.Angles(0,0,math.rad(90));disc.Parent=ring;ring.PrimaryPart=disc
 root.PrimaryPart=host;root.Parent=models
end
throwAim()
gui.Parent=ui
if not ui:FindFirstChild("PaintFaceGui") then
 local surface=Instance.new("SurfaceGui");surface.Name="PaintFaceGui";surface.CanvasSize=Vector2.new(256,256);surface.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;surface.AlwaysOnTop=false;surface.LightInfluence=0;surface.Brightness=2;surface.ZOffset=.015;surface.Parent=ui
end
if not ui:FindFirstChild("PaintCellFrame") then
 local cell=Instance.new("Frame");cell.Name="PaintCellFrame";cell.AnchorPoint=Vector2.new(.5,.5);cell.Size=UDim2.fromScale(.15,.15);cell.BackgroundColor3=Color3.fromRGB(176,63,255);cell.BorderSizePixel=0
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=cell;cell.Parent=ui
end
if not ui:FindFirstChild("PaintRuneImage") then
 local rune=Instance.new("ImageLabel");rune.Name="PaintRuneImage";rune.AnchorPoint=Vector2.new(.5,.5);rune.Size=UDim2.fromOffset(36,36);rune.BackgroundTransparency=1;rune.BorderSizePixel=0;rune.ImageColor3=Color3.fromRGB(176,63,255);rune.ImageTransparency=0;rune.ScaleType=Enum.ScaleType.Stretch;rune.Parent=ui
end
-- 清理已替换的旧业务资源；基础框架事件、共享音效（UIClick/UIOpen/UIClose）与现有 UI 骨架严禁销毁。
local legacy={
 {parent=ui,names={"FarmToolShopFrame","FarmWeaponEnhanceFrame","FarmCollectorShopFrame","FarmBasketShopFrame","FarmRestaurantFrame","FarmSpeciesFrame","FarmEquipmentFrame","FarmWeaponShopFrame","FarmHatchFrame","FarmConfirmationFrame","RoastChickenHUDFrame","FarmInteractionFrame","AnimalHealthGui","NestSignGui","RestaurantSignGui","WorkerSignGui","EggSignGui","FarmOwnerSignGui","CookedFoodSignGui","DamagePopGui","FarmTouchUseFrame","PackingDeliverySignGui","PackingEntranceSignGui","OriginalFoodDeliverySignGui","OriginalKitchenEntranceSignGui","OriginalFoodDirectionSignGui"}},
 {parent=events,names={"RoastChickenAction"}},
 {parent=models,names={"Weapons","Baskets","Collectors","CollectorTools"}},
 {parent=SS:FindFirstChild("Models"),names={"PersonalFarmTemplate","FarmWorkerTemplate","FarmUIArtwork","FarmPackerTemplate","FarmCustomerTemplate","FarmPackageTemplate","FarmRestaurantOriginalLayout"}},
 {parent=RS:FindFirstChild("Sounds"),names={"Upgrade","Zap_T1","Zap_T2","Zap_T3","Zap_T4","Zap_T5","AnimalHit","FoodDrop","EggHatch","Warning","Coin","AnimalCooked","Delivery","PackageDone","AnimalScared","EggSpeedup","EggLand","Pickup","EggSpawn"}},
 {parent=RS:FindFirstChild("VFX"),names={"ZapMuzzle_T1","ZapMuzzle_T2","ZapMuzzle_T3","ZapMuzzle_T4","ZapMuzzle_T5","ZapArcBeam","HitImpact","RoastFlight","FloatAnchor"}},
 {parent=RS:FindFirstChild("BindableEvents"),names={"FarmInfoChanged"}},
 {parent=SS:FindFirstChild("BindableEvents"),names={"FarmInfoChanged"}},
 {parent=SS,names={"FarmVillageArchive"}},
}
for _,entry in legacy do if entry.parent then for _,name in entry.names do local old=entry.parent:FindFirstChild(name);if old and old~=gui then old:Destroy() end end end end
local house=district:FindFirstChild("StairEntranceHouse")
if house then for _,name in {"AutomaticDoor","DoorController"} do local old=house:FindFirstChild(name);if old and old:IsA("LuaSourceContainer") then old:Destroy() end end end
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
	if node.Name == "InteractButton" or node.Name == "HintKeyText" or node.Name == "DropButton" or (node.Name == "AttackButton" and not node:FindFirstAncestor("TouchControlsFrame")) then node:Destroy() end
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

local function setupStationPrompt(parent: Instance): ProximityPrompt
	local existingPrompt = parent:FindFirstChild("WorldInteractionPrompt")
	local prompt: ProximityPrompt
	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		prompt = existingPrompt
	else
		local created = Instance.new("ProximityPrompt")
		created.Name = "WorldInteractionPrompt"
		created.Parent = parent
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
	return prompt
end

-- Workspace 工位锚点预置 WorldInteractionPrompt 作为唯一来源
setupStationPrompt(district:WaitForChild("SoulHoldingPool"):WaitForChild("PickupPointAnchor"))
setupStationPrompt(district:WaitForChild("RuneBodyTable"):WaitForChild("TransferStartAnchor"))
setupStationPrompt(district:WaitForChild("SoulConversionAltar"):WaitForChild("BodyArrivalAnchor"))
setupStationPrompt(district:WaitForChild("SoulCrystalDisplay"):WaitForChild("StockPickupAnchor"))
setupStationPrompt(district:WaitForChild("SummoningSubmitAnchor"))

-- ReplicatedStorage.UI 保持备份模板
setupStationPrompt(ui)


end

-- 在 Edit 补齐可见按钮的中心缩放，保留每个按钮在 1× 时的设计位置。
for _, node in ui:GetDescendants() do
	if node:IsA("GuiButton") and node.Name ~= "ModalButton" then
		local delta = Vector2.new(0.5, 0.5) - node.AnchorPoint
		if delta ~= Vector2.zero then
			local p, s = node.Position, node.Size
			node.Position = UDim2.new(p.X.Scale + s.X.Scale * delta.X, p.X.Offset + s.X.Offset * delta.X,
				p.Y.Scale + s.Y.Scale * delta.Y, p.Y.Offset + s.Y.Offset * delta.Y)
			node.AnchorPoint = Vector2.new(0.5, 0.5)
		end
		if not node:FindFirstChildOfClass("UIScale") then
			local scale = Instance.new("UIScale")
			scale.Parent = node
		end
		node:SetAttribute("HasInteractionEffect", true)
		if node.Name == "JumpButton" or node.Name == "AttackButton" or node.Name == "SprintButton" then
			node:SetAttribute("HasClickSound", false)
			node:SetAttribute("ScaleWhilePressed", true)
			node:SetAttribute("PressedScale", 0.86)
			node:SetAttribute("PressTweenSeconds", 0.1)
		elseif node.Name == "StickButton" then
			node:SetAttribute("HasClickSound", false)
			node:SetAttribute("ScaleWhilePressed", nil)
		end
	end
end

return {rigParts=#models.WhiteR15:GetChildren(),ui=gui:GetFullName(),models=models:GetFullName()}
