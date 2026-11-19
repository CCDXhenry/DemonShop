-- UI 模板管理器回归：单例、动作重绑、端显隐、翻译释放、标牌及参考层生命周期
local U=require('./FoundationUIBoundary')
local UI=require('./UIManager')
local R=require('@lune/roblox')
local checks=0
local function check(value,message) assert(value,message);checks+=1 end
local screen=UI.GetGameScreenGuiManager()
local gui=UI.CreateGameScreenGui()
local root=gui:WaitForChild('CenterFrame')
check(UI.CreateGameScreenGui()==gui and screen.gui==gui,'one main GUI belongs to its dedicated manager')
local calls=0
local function onAction() calls+=1 end
local actions={attack=onAction,exitPaint=onAction,resetView=onAction}
screen:BindActions(actions);screen:BindActions(actions)
local button=root:WaitForChild('ExitPaintButton')
button.Activated:Fire()
check(calls==1 and button.Activated:Count()==1,'rebinding actions disconnects previous handlers')
local attack=screen.attackButton
attack.InputBegan:Fire({UserInputType=R.Enum.UserInputType.MouseButton1})
check(calls==2 and attack.InputBegan:Count()==1,'touch attack presses once')
screen:Refresh({painting=false,hasTarget=true})
check(not screen.touchAttack.Visible,'desktop keeps the touch attack button hidden')
U.UserInputService.TouchEnabled=true
U.UserInputService.PreferredInput=R.Enum.PreferredInput.Touch
local jump=U.Node('JumpButton','ImageButton')
jump.AbsoluteSize=R.Vector2.new(100,100)
jump.AbsolutePosition=R.Vector2.new(220,400)
jump.Visible=true
jump.Parent=U.playerGui
check(screen.touchAttack.Visible and screen.touchAttack.Size==R.UDim2.fromOffset(90,90),'touch attack matches the jump button size')
check(screen.touchAttack.Position==R.UDim2.fromOffset(122,302),'touch attack keeps a gap above the jump button')
screen:Refresh({painting=false,hasTarget=false,windowOpen=true})
check(not screen.touchAttack.Visible,'an open window hides the touch attack button')
local camera=U.workspace.CurrentCamera
screen:SetPainting(true)
check(screen.paintFrame.Visible and screen.touchFrames.TouchPaintFrame.Visible and not screen.buttons.ExitPaintButton.Visible and not screen.touchAttack.Visible,'touch paint controls replace the attack button')
screen:SetProgress(.375)
check(screen.labels.ProgressText.Text=='37%' and screen.fill.Size==R.UDim2.fromScale(.375,1),'paint progress updates number and fill')
local brush=root:WaitForChild('PaintBrushCursorImage')
screen:UpdatePointer(nil,camera,R.Vector2.zero,false)
check(U.pointerRoot==root,'pointer uses the manager-owned root')
check(not brush.Visible,'touch paint hides the brush until the finger is down')
screen:UpdatePointer(nil,camera,R.Vector2.zero,true,true)
check(brush.Visible,'touch drawing shows the brush tip')
screen:Refresh({painting=true,hasTarget=false})
check(brush.Visible,'touch paint refresh keeps the brush while drawing')
screen:UpdatePointer(nil,camera,R.Vector2.zero,false)
check(not brush.Visible,'lifting the finger hides the touch brush')
U.UserInputService.TouchEnabled=false
U.UserInputService.MouseIconEnabled=true
U.GuiService.MenuIsOpen=false
screen:SetPainting(true)
check(not U.UserInputService.MouseIconEnabled,'desktop paint hides the system cursor')
U.GuiService.MenuIsOpen=true
screen:Refresh({painting=true,hasTarget=false})
check(U.UserInputService.MouseIconEnabled,'the Roblox menu restores the system cursor')
U.GuiService.MenuIsOpen=false
screen:SetPainting(false)
check(U.UserInputService.MouseIconEnabled,'leaving paint keeps the system cursor')
U.UserInputService.TouchEnabled=true
screen:ShowNotice({kind='Message',textId='PaintSegmentLimit'})
local notice=screen.labels.NoticeText
check(notice.translationKey~=nil,'notices use translation controller')
local target=UI.GetTargetGuiManager()
local part=U.Node('Head','Part')
target:Refresh({adornee=part,visible=true,hits=1,touch=false})
local targetGui=target.gui
check(targetGui.Parent==U.playerGui and targetGui.Enabled and targetGui.Adornee==part,'target remains private in PlayerGui and shows the health bar')
local fill=targetGui:FindFirstChild('FillImage',true)
check(fill and fill.Size==R.UDim2.fromScale(2/3,1),'one hit leaves two thirds of the health bar')
target:Refresh({adornee=part,visible=true,hits=999,touch=false})
check(not targetGui.Enabled,'target hides prompt when stunned')
target:Refresh({visible=false,hits=0,touch=true})
check(not targetGui.Enabled and targetGui.Adornee==nil,'lost target clears adornment and hides prompt')
target:Destroy();target:Destroy()
check(targetGui.destroyed and target.gui==nil,'target teardown is idempotent')
target:Init()
check(target.gui~=targetGui,'target can initialize after teardown')
local guide=UI.GetScreenLayoutGuideFrameManager()
check(next(guide.frames)==nil,'normal startup creates no design guide')
local reference=guide:Create(root)
check(reference.Parent==root and guide.frames[reference]~=nil,'explicit design guide has a registered owner')
reference:Destroy()
check(next(guide.frames)==nil,'external guide destruction unregisters ownership')
guide:Create(root);guide:Destroy();guide:Destroy()
check(next(guide.frames)==nil,'guide bulk teardown is idempotent')
local textSignal=notice:GetPropertyChangedSignal('Text')
screen:UnbindActions();button.Activated:Fire();attack.InputBegan:Fire({UserInputType=R.Enum.UserInputType.MouseButton1})
check(calls==2 and button.Activated:Count()==0 and attack.InputBegan:Count()==0,'stopped gameplay cannot receive UI actions')
UI.Destroy();UI.Destroy()
check(gui.destroyed and textSignal:Count()==0 and notice.translationKey==nil,'main teardown releases GUI, text listeners and translation registration')
U.workspace.CurrentCamera=camera
U.UserInputService.TouchEnabled=false
local replacement=UI.CreateGameScreenGui()
check(replacement~=gui and replacement.Parent==U.playerGui,'whole UI can initialize again after repeated destruction')
UI.Destroy()
print('PASS: '..checks..' dedicated UI template manager assertions (production modules; engine signals and translation service mocked)')
