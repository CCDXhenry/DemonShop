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
for _,name in {'CenterFrame','WindowCanvas'} do
 local frame=ui.GameScreenGui:FindFirstChild(name)
 check(frame and frame.Size==R.UDim2.fromOffset(1920,1080) and frame.AnchorPoint==R.Vector2.new(.5,.5),'fixed root canvas restored')
 check(frame:FindFirstChildOfClass('UIScale')~=nil,'canvas scale template restored')
end
check(ui.GameScreenGui.ModalButton:IsA('ImageButton') and not ui.GameScreenGui.ModalButton.Visible,'global backdrop restored')
local center=ui.GameScreenGui.CenterFrame
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
check(#panel.AbilitiesFrame:GetChildren() == 3 and #panel.ToolsFrame:GetChildren() == 2, 'shop contains all five purchase cards')
check(not panel.AbilitiesButton.AlertFrame.Visible and not panel.ToolsButton.AlertFrame.Visible and not hud.ShopButton.AlertFrame.Visible,'purchase badges default hidden')
check(#shop.Previews:GetChildren() == 11 and shop.Previews.W06:IsA('Model') and shop.Previews.T4:IsA('Model'), 'all eleven tier previews are recoverable')
check(panel.ToolsFrame.weapon.ToolViewport.WorldModel:IsA('WorldModel') and panel.ToolsFrame.carryTool.ToolViewport.WorldModel:IsA('WorldModel'), 'tool cards have independent 3D viewports')
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
  if instance:IsA('TextLabel') then check(not instance.TextWrapped and not instance.TextScaled and type(instance:GetAttribute('DesignTextSize'))=='number','shop single-line labels have a design font size') end
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
