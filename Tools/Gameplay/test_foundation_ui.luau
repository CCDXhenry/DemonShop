-- 正式 UI 管理器回归：模态层级、幂等初始化、关闭栈、文本接口与事件释放
local U=require('./FoundationUIBoundary')
local UI=require('./UIManager')
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
check(UI.FitTextLabel({})==22 and UI.FitTextWithShadow({},nil)==22,'text fitting interfaces retained')
local button=U.Node('Button','ImageButton');button:SetAttribute('HasInteractionEffect',true)
local scale=U.Node('UIScale','UIScale');scale.Scale=1;scale.Parent=button;button.Parent=U.gui
button.Activated:Fire();check(U.sounds==1,'button effect plays once')
button:Destroy();check(button.Activated:Count()==0,'button destroy releases hooks')
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
