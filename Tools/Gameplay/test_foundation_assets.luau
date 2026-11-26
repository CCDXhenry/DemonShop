-- 恢复资产契约：离线重新反序列化正式导出，核验模板和基础事件可恢复
local fs=require('@lune/fs')
local R=require('@lune/roblox')
local count=0
local function check(value,label)assert(value,label);count+=1 end
local function load(path)
 local map={}
 for _,node in R.deserializeModel(fs.readFile(path)) do check(map[node.Name]==nil,'no duplicate exported root');map[node.Name]=node end
 return map
end
local ui=load('Assets/UI/ProjectTemplates.rbxm')
check(ui.GameScreenGui and ui.PaintFaceGui and ui.PaintCellFrame and ui.TargetGui,'all gameplay UI roots restored')
check(ui.GameScreenGui.ScreenInsets==R.Enum.ScreenInsets.None,'GameScreenGui spans full physical viewport')
check(ui.GameScreenGui:FindFirstChild('TouchPaintFrame')==nil,'legacy TouchPaintFrame removed')
check(ui.TouchAttackFrame==nil and ui.ThrowStick==nil and ui.TouchSprintFrame==nil,'top-level touch templates consolidated into CenterFrame')
local brute = ui.BruteNameGui
check(brute and brute:IsA('BillboardGui') and brute.MaxDistance==45 and brute.AlwaysOnTop and brute.LightInfluence==0,'brute nameplate restored as a world billboard')
local title=brute.ContentFrame.NameText
check(title.TextScaled and not title.AutoLocalize and title.UIStroke.StrokeSizingMode==R.Enum.StrokeSizingMode.ScaledSize,'brute title scales and accepts the existing localized names')
for _,name in {'CenterFrame','WindowCanvas','OverlayCanvas'} do
 local frame=ui.GameScreenGui:FindFirstChild(name)
 check(frame and frame.Size==R.UDim2.fromOffset(1920,1080) and frame.AnchorPoint==R.Vector2.new(.5,.5),'fixed root canvas restored')
 check(frame:FindFirstChildOfClass('UIScale')~=nil,'canvas scale template restored')
end
check(ui.GameScreenGui.ModalButton:IsA('ImageButton') and not ui.GameScreenGui.ModalButton.Visible,'global backdrop restored')
local center=ui.GameScreenGui.CenterFrame
local overlay=ui.GameScreenGui:FindFirstChild('OverlayCanvas')
local coins=overlay.CoinsFrame
check(overlay.ZIndex==900 and coins.ZIndex>=overlay.ZIndex and coins.CoinsText.ZIndex>coins.ZIndex,'coins render above the modal')
check(coins:IsA('ImageLabel') and coins.ScaleType==R.Enum.ScaleType.Slice and coins.SliceCenter==R.Rect.new(32,16,178,49),'coins capsule uses its nine-slice artwork')
check(coins.MoneyIcon.ScaleType==R.Enum.ScaleType.Fit and coins.CoinsText:GetAttribute('DesignTextSize')==56 and coins.CoinsText.Size==R.UDim2.fromOffset(140,75) and coins.CoinsText.UIStroke.StrokeSizingMode==R.Enum.StrokeSizingMode.ScaledSize,'coins icon and amount use fitted artwork and text')
local coinLabels=0
for _, node in ui.GameScreenGui:GetDescendants() do
 if node.Name=='CoinsText' then coinLabels+=1 end
end
check(coinLabels==1 and not center:FindFirstChild('StatusFrame'),'only the overlay coin label remains')
local slot=center.BottomButtonsFrame.ToolButton
check(slot.IconImage:IsA('ImageLabel') and slot.IconImage.ScaleType==R.Enum.ScaleType.Fit and not slot:FindFirstChild('ToolViewport'),'toolbar uses a fitted 2D image')
check(center.ExitPaintButton.Size==R.UDim2.fromOffset(350,84) and center.ResetViewButton.Size==R.UDim2.fromOffset(350,84),'shared paint buttons resized to 84px height')
local tc=center:FindFirstChild('TouchControlsFrame')
check(tc and tc:IsA('Frame') and tc.Size==R.UDim2.fromOffset(1920,1080) and tc.AnchorPoint==R.Vector2.new(.5,.5) and not tc.Visible,'TouchControlsFrame restored inside CenterFrame')
local jumpSlot,attackSlot,stickSlot,sprintSlot=tc.TouchJumpFrame,tc.TouchAttackFrame,tc.ThrowStick,tc.TouchSprintFrame
check(jumpSlot.Position==R.UDim2.fromOffset(1765,915) and jumpSlot.Size==R.UDim2.fromOffset(190,190) and jumpSlot.AnchorPoint==R.Vector2.new(.5,.5),'TouchJumpFrame layout restored')
check(attackSlot.Position==R.UDim2.fromOffset(1545,845) and attackSlot.Size==R.UDim2.fromOffset(190,190) and attackSlot.AnchorPoint==R.Vector2.new(.5,.5),'TouchAttackFrame layout restored')
check(stickSlot.Position==R.UDim2.fromOffset(1545,845) and stickSlot.Size==R.UDim2.fromOffset(190,190) and stickSlot.AnchorPoint==R.Vector2.new(.5,.5) and not stickSlot.Visible,'ThrowStick layout restored')
check(sprintSlot.Position==R.UDim2.fromOffset(1765,695) and sprintSlot.Size==R.UDim2.fromOffset(156,156) and sprintSlot.AnchorPoint==R.Vector2.new(.5,.5),'TouchSprintFrame layout restored')
for _,slot in {jumpSlot,attackSlot,stickSlot,sprintSlot} do
 check(slot:GetAttribute('MinimumTouchSize')==nil and slot:GetAttribute('JumpGap')==nil and slot:GetAttribute('JumpSizeRatio')==nil,'legacy dynamic layout attributes removed: '..slot.Name)
end
check(tostring(jumpSlot.JumpButton.ImageContent)==tostring(R.Content.fromUri('rbxassetid://138878448546121')),'jump button artwork restored')
check(tostring(attackSlot.AttackButton.ImageContent)==tostring(R.Content.fromUri('rbxassetid://110366066946567')),'attack button artwork restored')
check(tostring(sprintSlot.SprintButton.ImageContent)==tostring(R.Content.fromUri('rbxassetid://114836508163438'))
 and sprintSlot.SprintButton.ScaleType==attackSlot.AttackButton.ScaleType
 and sprintSlot.SprintButton.ImageRectSize==R.Vector2.zero and sprintSlot.SprintButton.ImageRectOffset==R.Vector2.zero,
 'sprint shows its complete approved image in the fixed touch controls layout')

local personal = load('Assets/UI/PersonalShopTemplates.rbxm')
local shop, hud = personal.PersonalShopFrame, personal.PersonalHudFrame
check(personal.TouchSprintFrame==nil,'TouchSprintFrame removed from PersonalShopTemplates root')
for _, canvas in {shop,hud} do
 check(canvas.Size == R.UDim2.fromOffset(1920,1080) and canvas.AnchorPoint == R.Vector2.new(.5,.5), 'M5 canvas matches parent scaling contract')
 check(canvas:FindFirstChildOfClass('UIScale') == nil, 'M5 canvas inherits scale once')
end
local panel = shop.PanelFrame
local hitTest = require('../../Scripts/ReplicatedStorage/Scripts/Client/UIManager/ModalImageHitTest')
local function mockRegion(image, x, y, w, h)
 return {
  Visible = true,
  AbsolutePosition = R.Vector2.new(x, y),
  AbsoluteSize = R.Vector2.new(w, h),
  GetAttribute = function(_, key) return image:GetAttribute(key) end,
 }
end
local panelHit = mockRegion(panel, 266, 120, 1389 / 2, 943 / 2)
check(panel:GetAttribute('ModalContentHeight')==nil and panel:GetAttribute('ModalAlphaRows')~=nil,'shop restores an alpha mask instead of the fixed height cutoff')
check(hitTest.ContainsImage(panelHit, R.Vector2.new(266 + 350, 120 + 425)),'scaled skull near the bottom remains clickable')
check(not hitTest.ContainsImage(panelHit, R.Vector2.new(269, 123)),'scaled transparent corner is backdrop')
check(not hitTest.ContainsImage(panelHit, R.Vector2.new(600, 580)),'scaled transparent bottom margin is backdrop')
local coinHit = mockRegion(coins, 100, 100, 210, 65)
check(hitTest.ContainsImage(coinHit, R.Vector2.new(200, 130)),'foreground coin capsule has a visible hit region')
check(coins.CoinsText.FontFace.Weight==R.Enum.FontWeight.ExtraBold and panel.HeaderFrame.TitleText.FontFace.Weight==R.Enum.FontWeight.ExtraBold,'shop typography uses the prototype weight fallback')
check(panel.AbilitiesButton.ScaleType==R.Enum.ScaleType.Stretch and panel.ToolsButton.ScaleType==R.Enum.ScaleType.Stretch,'tabs use full authored artwork')
check(panel.HeaderFrame.TitleText:GetAttribute('DesignTextSize')==88 and panel.AbilitiesButton.TitleText:GetAttribute('DesignTextSize')==56,'shop heading and tabs restore with larger type')
check(panel.AbilitiesFrame.moveSpeed.TitleText:GetAttribute('DesignTextSize')==56 and panel.AbilitiesFrame.moveSpeed.CompareFrame.PrimaryText:GetAttribute('DesignTextSize')==44,'shop ability headings and figures restore with larger type')
check(panel.ToolsFrame.weapon.CompareFrame.PrimaryText:GetAttribute('DesignTextSize')==32 and panel.ToolsFrame.weapon.CompareFrame.SecondaryText:GetAttribute('DesignTextSize')==36,'tool comparisons preserve distinct larger type roles')
check(panel.ToolsFrame.weapon.BuyButton.ContentFrame.TitleText:GetAttribute('DesignTextSize')==56,'shop prices use larger type')
check(panel:IsA('ImageLabel') and panel.Size==R.UDim2.fromOffset(1389,943),'shop uses the full-size panel artwork')
for _, name in {'ActiveTabImage','InactiveTabImage'} do
 check(type(panel:GetAttribute(name))=='string','shop declares tab artwork: '..name)
end
check(#panel.AbilitiesFrame:GetChildren() == 3 and #panel.ToolsFrame:GetChildren() == 2, 'shop contains all five purchase cards')
check(not panel.AbilitiesButton.AlertFrame.Visible and not panel.ToolsButton.AlertFrame.Visible and not hud:FindFirstChild('ShopButton') and hud:FindFirstChild('StaminaFrame'),'purchase badges default hidden and only the stamina HUD is retained')
for _, page in {panel.AbilitiesFrame,panel.ToolsFrame} do
 for _, card in page:GetChildren() do
  check(card.IconImage:IsA('ImageLabel') and card.IconImage.ImageContent.Uri~=nil and card.IconImage.ScaleType==R.Enum.ScaleType.Fit and not card:FindFirstChild('ProgressFrame') and not card:FindFirstChildOfClass('ViewportFrame'),'shop card uses a 2D icon without legacy progress markers')
  check(card.CompareFrame.ScaleType==R.Enum.ScaleType.Slice and card.CompareFrame.SliceCenter==R.Rect.new(24,24,64,64),'comparison uses nine-slice artwork')
  local secondary=card.CompareFrame:FindFirstChild('SecondaryText')
  check((secondary~=nil)==(page==panel.ToolsFrame),'tools alone show a second comparison line')
  if secondary then
   check(secondary.TextColor3==R.Color3.fromRGB(253,215,5) and secondary.UIStroke.StrokeSizingMode==R.Enum.StrokeSizingMode.ScaledSize,'next tool uses outlined gold text')
  end
  local buy=card.BuyButton
  check(buy.ScaleType==R.Enum.ScaleType.Stretch and buy.ContentFrame.MoneyIcon:IsA('ImageLabel'),'purchase button uses artwork and a separate money icon')
  for _, name in {'AvailableImage','LockedImage','MaxImage'} do
   check(type(buy:GetAttribute(name))=='string','purchase button declares state artwork: '..name)
  end
 end
end
local models = load('Assets/Models/GameModels.rbxm').Models
local expectedCategories = {
	Characters = true,
	Weapons = true,
	CarryRigs = true,
	Items = true,
	Effects = true,
	Previews = true,
}
local categoryCount = 0
for _, child in models:GetChildren() do
	check(child:IsA('Folder') and expectedCategories[child.Name] == true, 'Models root only contains semantic category folders: ' .. child.Name)
	categoryCount += 1
end
check(categoryCount == 6, 'Models contains all 6 semantic category folders')
check(models:FindFirstChild('NeonContractDistrict') == nil and models:FindFirstChild('UnlockPad') == nil and models:FindFirstChild('Club') == nil and models:FindFirstChild('PersonalShopPreviews') == nil, 'Models excludes static district, edit-only UnlockPad, retired Club and legacy preview folder')

local characters = models.Characters
for _, name in {'WhiteR15', 'HellBrute_1', 'HellBrute_2', 'AutoClerk'} do
	local rig = characters:FindFirstChild(name)
	check(rig and rig:IsA('Model'), 'character template restores under Characters: ' .. name)
end

local weapons = models.Weapons
for _, name in {'W01_RustyPan', 'W02_IronCrowbar', 'W03_DemonScimitar', 'W04_ReaperScythe', 'W05_VoidCannon', 'W06_AbyssalHammer'} do
	local tool = weapons:FindFirstChild(name)
	check(tool and tool:IsA('Tool') and tool.Visual:IsA('Model') and tool.Handle:IsA('BasePart'), 'single restored tool template under Weapons: ' .. name)
	for _, part in tool.Visual:GetChildren() do
		local weld = tool.Handle:FindFirstChild("Weld_" .. part.Name)
		check(weld and weld.Part0 == tool.Handle and weld.Part1 == part and not part.Anchored, 'equippable welded piece ' .. part.Name)
	end
end

local carryRigs = models.CarryRigs
local previews = models.Previews
for tier = 1, 4 do
 local id = 'T' .. tier
 local rig = carryRigs:FindFirstChild('CarryRig_' .. id)
 check(rig and rig:IsA('Model') and rig.PrimaryPart == rig.RootPart, 'carry rig restores under CarryRigs with a primary part: ' .. id)
 check(typeof(rig:GetAttribute('MountOffset')) == 'CFrame' and not previews:FindFirstChild(id), 'carry rig has exactly one source: ' .. id)
 for _, part in rig:GetChildren() do
  check(part:IsA('BasePart') and part.Massless and part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch, 'carry rig restores passive parts: ' .. id)
  if part ~= rig.PrimaryPart then
   local weld = rig.RootPart:FindFirstChild('Weld_' .. part.Name)
   check(weld and weld.Part0 == rig.RootPart and weld.Part1 == part, 'visible part weld restores: ' .. part.Name)
  end
 end
end

local items = models.Items
check(items:FindFirstChild('Potion') and items.Potion:IsA('Tool'), 'Potion tool template restores under Items')
local effects = models.Effects
check(effects:FindFirstChild('ThrowAim') and effects.ThrowAim:IsA('Model'), 'ThrowAim effect template restores under Effects')
check(previews:FindFirstChild('T0') and previews.T0:IsA('Model'), 'T0 unarmed preview restores under Previews')
check(previews.ViewportWorld:IsA('WorldModel') and #previews.ViewportWorld:GetChildren()==0, 'viewport containers clone the empty Previews.ViewportWorld template')
for _, templates in {ui, personal} do
 for _, template in templates do
  for _, node in template:GetDescendants() do
   check(not node:IsA('Model') and not node:IsA('WorldModel'), 'UI recovery packages contain no models or viewport containers')
  end
 end
end
for _, template in {ui.GameScreenGui, shop, hud} do
 for _, node in template:GetDescendants() do
  if node:IsA('GuiButton') and node.Name ~= 'ModalButton' then
   check(node.AnchorPoint == R.Vector2.new(0.5,0.5) and node:FindFirstChildOfClass('UIScale') ~= nil
    and node:GetAttribute('HasInteractionEffect') == true,'button tween is centered: '..node.Name)
   local shouldHold = node == jumpSlot.JumpButton or node == attackSlot.AttackButton or node == sprintSlot.SprintButton
   check((node:GetAttribute('ScaleWhilePressed') == true) == shouldHold, 'button hold mode matches template: '..node.Name)
   if shouldHold then
    check(node:GetAttribute('PressedScale') == 0.86 and node:GetAttribute('PressTweenSeconds') == 0.1, 'hold tween settings restored: '..node.Name)
   end
  end
 end
end
for _, template in {shop,hud} do
 for _, instance in template:GetDescendants() do
  if instance:IsA('UIStroke') then check(instance.StrokeSizingMode==R.Enum.StrokeSizingMode.ScaledSize,'shop uses scaled outlines') end
  if instance:IsA('TextLabel') and instance.Name~='ShadowText' then check(not instance.TextWrapped and not instance.TextScaled and type(instance:GetAttribute('DesignTextSize'))=='number','shop single-line labels have a design font size') end
 end
end
local rs=load('Assets/Foundation/ReplicatedStorage.rbxm')
for _,name in {'NotifyPlayerInfoInit','NotifyPlayersOtherPlayerInfoInit','NotifyPlayerAcquiredGamePass','NotifyPlayerLeft','RequestSetBGMVolume','RequestSetSoundEffectVolume','RequestSetVibrationsOnOffState','FoundationRequest','GameRequest','GameNotify'} do
 check(rs.RemoteEvents:FindFirstChild(name) and rs.RemoteEvents[name]:IsA('RemoteEvent'),'remote restored: '..name)
end
check(rs.RemoteEvents:FindFirstChild('FoundationNotify')==nil,'retired remote excluded from recovery')
for _,name in {'CloseWindow','OpenWindow','LocalPlayerInfoInit','OtherPlayerInfoInit','LocalPlayerAcquiredGamePass'} do
 check(rs.BindableEvents:FindFirstChild(name)~=nil,'client message restored: '..name)
end
local ss=load('Assets/Foundation/ServerStorage.rbxm')
check(ss.BindableEvents.PlayerInfoInit:IsA('BindableEvent'),'server message restored')
local sounds=load('Assets/Foundation/SoundService.rbxm')
check(sounds.SoundGroups.BGM:IsA('SoundGroup') and sounds.SoundGroups.SoundEffects:IsA('SoundGroup'),'sound groups restored')
for _,roots in {ui,rs,ss,sounds} do
 for _,root in roots do for _,node in root:GetDescendants() do check(not node:IsA('LuaSourceContainer'),'recovery resources contain no script source') end end
end
print(string.format('PASS: %d restored asset assertions (actual RBXM deserialize)',count))
