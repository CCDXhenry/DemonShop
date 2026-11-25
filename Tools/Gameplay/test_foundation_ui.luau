-- 正式 UI 管理器回归：模态层级、幂等初始化、关闭栈、文本接口与事件释放
local U=require('./FoundationUIBoundary')
local UI=require('./UIManager')
local R=require('@lune/roblox')
local checks=0
local function check(v,label)assert(v,label);checks+=1 end
local created,closed=0,0
local function factory(frame,id,actions)
 created+=1
 return {frame=frame,OnInit=function()end,OnClose=function()closed+=1;frame:Destroy()end}
end
for _,id in {'A','B','C'} do UI.RegisterWindow(id,{frameName='TestWindow',isModal=true,newWindow=factory}) end
UI.Init(U.gui);UI.Init(U.gui)
check(U.gui.DescendantAdded:Count()==1 and U.modal.Activated:Count()==1 and U.cameraSignal:Count()==2,'UI initialization registers once')
local B=require('./FoundationBoundary')
local originalCamera=U.workspace.CurrentCamera
local replacementSignal=B.Signal()
U.workspace.CurrentCamera={ViewportSize={X=960,Y=540},GetPropertyChangedSignal=function()return replacementSignal end}
U.cameraChanged:Fire()
check(U.cameraSignal:Count()==0 and replacementSignal:Count()==2,'camera replacement transfers each canvas listener once')
check(U.scale.Scale==.5 and U.gui:FindFirstChild('CenterFrame'):FindFirstChildOfClass('UIScale').Scale==.5,'HUD and window root share fixed-canvas scaling rule')
local nested=U.Node('Nested','Frame');nested.Parent=U.canvas
local nestedScale=U.Node('UIScale','UIScale');nestedScale.Scale=1;nestedScale.Parent=nested
local Wrapper=require('./GameFrameWrapper')
local wrapper=Wrapper.new(nested,UI.GetUIActions());wrapper:Init()
check(replacementSignal:Count()==2 and nestedScale.Scale==1,'nested wrappers do not double-scale parent canvas')
wrapper:OnDestroy();nested:Destroy()
U.workspace.CurrentCamera=originalCamera;U.cameraChanged:Fire()
check(replacementSignal:Count()==0 and U.scale.Scale==1,'camera teardown releases replacement listeners')
UI.OpenWindow('A');UI.OpenWindow('A');check(created==1 and UI.IsWindowShowing('A'),'window singleton')
local a=U.canvas.children[2]
check(a.Parent==U.canvas and U.modal.Visible and U.modal.ZIndex==a.ZIndex-1,'window uses fixed canvas and backdrop')
UI.OpenWindow('B');UI.OpenWindow('C')
local c=U.canvas.children[4]
check(c.Label==nil and c:GetChildren()[1].ZIndex>=c.ZIndex,'child content stays above modal')
UI.CloseWindow('B');UI.OpenWindow('B')
local b=U.canvas.children[4]
check(b.ZIndex>c.ZIndex and U.modal.ZIndex==b.ZIndex-1,'closing middle window cannot create layer collision')
U.modal.Activated:Fire();check(not UI.IsWindowShowing('B') and UI.IsWindowShowing('C'),'backdrop closes top modal only')
UI.CloseWindow('A');UI.CloseWindow('A');check(closed==3,'close idempotent')
UI.CloseAllWindow();check(not U.modal.Visible and not UI.HasShowingWindow() and closed==4,'close all releases stack')
local panel=U.Node('PanelFrame','Frame')
panel.AbsolutePosition=R.Vector2.new(150,150);panel.AbsoluteSize=R.Vector2.new(500,300);panel.Parent=U.template
local header=U.Node('HeaderFrame','Frame')
header.AbsolutePosition=R.Vector2.new(300,100);header.AbsoluteSize=R.Vector2.new(200,80);header.Parent=panel
UI.RegisterWindow('Shop',{frameName='TestWindow',isModal=true,modalContentRegions={'PanelFrame','HeaderFrame'},newWindow=factory})
UI.OpenWindow('Shop')
local function tap(x,y)
 U.modal.Activated:Fire({UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(x,y,0)})
end
tap(180,320);check(UI.IsWindowShowing('Shop'),'a backdrop event inside the blank panel keeps the shop open')
local previousMouseLocation=U.UserInputService.GetMouseLocation
U.UserInputService.GetMouseLocation=function() return R.Vector2.new(180,320) end
U.modal.Activated:Fire({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.zero})
U.UserInputService.GetMouseLocation=previousMouseLocation
check(UI.IsWindowShowing('Shop'),'mouse backdrop events use the release location instead of the stale input position')
tap(350,110);check(UI.IsWindowShowing('Shop'),'a backdrop event on the protruding title keeps the shop open')
U.gui.IgnoreGuiInset=false
tap(350,146);check(UI.IsWindowShowing('Shop'),'backdrop hit test converts touch coordinates for a screen with an inset')
U.gui.IgnoreGuiInset=true
tap(80,400);check(not UI.IsWindowShowing('Shop'),'tap outside the panel closes the shop')
check(UI.FitTextLabel({})==22 and UI.FitTextWithShadow({},nil)==22,'text fitting interfaces retained')
local function newEffectButton(name, baseline, ratio)
 local node=U.Node(name,'ImageButton')
 node:SetAttribute('HasInteractionEffect',true)
 node:SetAttribute('PressedScale',ratio)
 local buttonScale=U.Node('UIScale','UIScale')
 buttonScale.Scale=baseline;buttonScale.Parent=node;node.Parent=U.gui
 U.manualTweens[buttonScale]=true
 return node,buttonScale
end
local function newInput(kind, key)
 local input=U.Node('Input','InputObject')
 input.UserInputType=kind
 input.KeyCode=key
 input.UserInputState=R.Enum.UserInputState.Begin
 return input
end
local function finishInput(input,state)
 input.UserInputState=state
 input:GetPropertyChangedSignal('UserInputState'):Fire()
end
local function assertScale(scale, expected, label)
 check(math.abs(scale.Scale-expected)<1e-6,label)
end
local function expectScaleTween(scale,goal,time,label)
 local tween=U.manualTweens[scale]
 check(type(tween)=='table' and math.abs(tween.Goals.Scale-goal)<1e-6
  and tween.Info.Time==time and tween.PlaybackState==R.Enum.PlaybackState.Playing,label)
 return tween
end
local button,scale=newEffectButton('Button',0.75)
button.MouseEnter:Fire()
local hover=U.manualTweens[scale]
check(hover.Goals.Scale==0.75*1.10 and hover.Info.Time==0.1,'hover uses normal easing and ratio')
local mouse=newInput(R.Enum.UserInputType.MouseButton1)
button.InputBegan:Fire(mouse)
local press=expectScaleTween(scale,0.75*0.80,0.07,'mouse down immediately starts a short shrink tween')
check(press.Info.EasingStyle==R.Enum.EasingStyle.Quad and press.Info.EasingDirection==R.Enum.EasingDirection.Out,'shrink eases toward its target')
press:Finish()
check(hover.PlaybackState==R.Enum.PlaybackState.Cancelled,'mouse down interrupts an in-flight hover tween')
button.MouseLeave:Fire();button.MouseEnter:Fire()
assertScale(scale,0.75*0.80,'pointer leaving and reentering preserves held scale')
check(U.manualTweens[scale]==press,'pointer movement does not schedule a tween while held')
finishInput(mouse,R.Enum.UserInputState.End)
local release=expectScaleTween(scale,0.75,0.10,'mouse up starts smooth return to the authored scale')
assertScale(scale,0.75*0.80,'beginning release keeps the current size')
release:Finish()
button.Activated:Fire(mouse)
assertScale(scale,0.75,'activation does not restart scale animation')
check(U.sounds==1,'activation plays one click sound')

U.UserInputService.PreferredInput=R.Enum.PreferredInput.Touch
U.manualTweens[scale]=true
button.MouseEnter:Fire();button.MouseLeave:Fire()
check(U.manualTweens[scale]==true,'touch skips hover')
local touch=newInput(R.Enum.UserInputType.Touch)
local otherTouch=newInput(R.Enum.UserInputType.Touch)
button.InputBegan:Fire(touch);button.InputBegan:Fire(otherTouch)
local touchPress=expectScaleTween(scale,0.75*0.80,0.07,'touch starts the same short shrink')
touchPress:Finish()
finishInput(otherTouch,R.Enum.UserInputState.End)
assertScale(scale,0.75*0.80,'a second finger cannot release the first press')
finishInput(touch,R.Enum.UserInputState.Cancel)
expectScaleTween(scale,0.75,0.10,'touch cancellation releases the held scale'):Finish()

local quickTap=newInput(R.Enum.UserInputType.Touch)
button.InputBegan:Fire(quickTap)
local interrupted=expectScaleTween(scale,0.75*0.80,0.07,'quick tap starts a shrink')
scale.Scale=0.70 -- 模拟引擎刚播放一部分补间。
finishInput(quickTap,R.Enum.UserInputState.End)
local reversed=expectScaleTween(scale,0.75,0.10,'quick tap reverses before shrink finishes')
check(interrupted.PlaybackState==R.Enum.PlaybackState.Cancelled and reversed.StartScale==0.70,'release starts from the current intermediate size')
reversed:Finish()

local gamepad=newInput(R.Enum.UserInputType.Gamepad1,R.Enum.KeyCode.ButtonA)
U.UserInputService.InputBegan:Fire(gamepad)
assertScale(scale,0.75,'gamepad press ignores buttons without GUI selection')
U.GuiService.SelectedObject=button
U.UserInputService.InputBegan:Fire(gamepad)
expectScaleTween(scale,0.75*0.80,0.07,'selected button shrinks on gamepad press'):Finish()
finishInput(gamepad,R.Enum.UserInputState.End)
expectScaleTween(scale,0.75,0.10,'gamepad release restores selected button'):Finish()
U.GuiService.SelectedObject=nil
local pending=newInput(R.Enum.UserInputType.Touch)
button.InputBegan:Fire(pending)
U.UserInputService.WindowFocusReleased:Fire()
assertScale(scale,0.75,'window blur releases held buttons')
button:Destroy()
check(button.Activated:Count()==0 and pending:GetPropertyChangedSignal('UserInputState'):Count()==0,'button destruction releases input and activation listeners')

for _, buttonName in {'AttackButton','SprintButton'} do
 local heldButton,heldScale=newEffectButton(buttonName,1,0.86)
 heldButton:SetAttribute('HasClickSound',false)
 local input=newInput(R.Enum.UserInputType.Touch)
 heldButton.InputBegan:Fire(input)
 expectScaleTween(heldScale,0.86,0.07,buttonName..' uses its authored press ratio'):Finish()
 finishInput(input,R.Enum.UserInputState.End)
 heldButton.Activated:Fire(input)
 expectScaleTween(heldScale,1,0.10,buttonName..' restores on release'):Finish()
 check(U.sounds==1,buttonName..' keeps the click sound disabled')
 heldButton:Destroy()
end
U.UserInputService.PreferredInput=R.Enum.PreferredInput.KeyboardAndMouse
UI.Destroy();check(U.cameraSignal:Count()==0 and U.gui.DescendantAdded:Count()==0 and U.modal.Activated:Count()==0,'UI destroy releases viewport and input')
UI.Init(U.gui);UI.OpenWindow('A');check(UI.IsWindowShowing('A') and U.modal.Activated:Count()==1,'UI can initialize after destroy')
UI.Destroy()
local owned=UI.CreateGameScreenGui()
check(owned.Parent==U.playerGui and UI.CreateGameScreenGui()==owned,'foundation owns one GUI independently of gameplay')
check(owned:FindFirstChild('WindowCanvas') and owned:FindFirstChild('ModalButton'),'GUI clones all required edit templates')
UI.Destroy()
check(owned.destroyed and U.playerGui:FindFirstChild('GameScreenGui')==nil,'UI teardown destroys owned GUI')
local duplicate=U.gui:Clone();duplicate.Parent=U.playerGui
check(not pcall(UI.CreateGameScreenGui),'external duplicate GUI rejected')
duplicate:Destroy()
print(string.format('PASS: %d UI framework assertions (production manager; GUI/Tween services mocked)',checks))
