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
screen:SetPainting(true)
check(screen.paintFrame.Visible and screen.touchFrames.TouchPaintFrame.Visible and not screen.buttons.ExitPaintButton.Visible and not screen.touchAttack.Visible,'touch paint controls replace the attack button')
screen:SetProgress(.375)
check(screen.labels.ProgressText.Text=='37%' and screen.fill.Size==R.UDim2.fromScale(.375,1),'paint progress updates number and fill')
local brush=root:WaitForChild('PaintBrushCursorImage')
screen:UpdatePointer(nil,false)
check(U.pointerRoot==root,'pointer uses the manager-owned root')
check(not brush.Visible,'the brush requires a valid surface contact')
screen:UpdatePointer(R.Vector2.zero,true)
check(brush.Visible,'touch drawing shows the brush tip')
screen:Refresh({painting=true,hasTarget=false})
check(brush.Visible,'touch paint refresh keeps the brush while drawing')
screen:UpdatePointer(R.Vector2.zero,false)
check(brush.Visible,'lifting the finger leaves the brush attached')
screen:SetPainting(false)
U.UserInputService.TouchEnabled=false
U.UserInputService.MouseIconEnabled=true
U.GuiService.MenuIsOpen=false
screen:SetPainting(true)
screen:UpdatePointer(R.Vector2.zero,false)
check(not U.UserInputService.MouseIconEnabled,'desktop paint hides the system cursor')
check(screen.buttons.ResetViewButton.Visible,'desktop painting exposes the reset control')
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
local anotherHead=U.Node('Head','Part')
local visibleHeads={first=part,second=anotherHead}
local function resolveHead(id) return visibleHeads[id] end
target:ShowHit('first',2,1,10,part)
target:ShowHit('second',4,1,10,anotherHead)
target:ShowHit('first',3,2,10.65,part)
target:ShowHit('first',2,1,10.75,part)
target:RefreshHits(11.6,resolveHead)
target:Refresh({id='first',adornee=part,visible=true,hits=1,touch=false})
check(not targetGui.Enabled and target.hitBars.first.fill.Size==R.UDim2.fromScale(1/3,1),'confirmed hit takes precedence over focus and older hits')
check(target.hitBars.second==nil,'different targets expire independently')
visibleHeads.first=anotherHead
target:RefreshHits(11.7,resolveHead)
check(target.hitBars.first.gui.Adornee==anotherHead,'hit bar follows visual head replacement')
target:ShowHit('first',4,3,11.8,anotherHead)
check(target.hitBars.first==nil,'final hit removes the hit bar')
target:Refresh({id='first',adornee=anotherHead,visible=true,hits=2,touch=false})
target:ShowHit('first',3,2,11.7,anotherHead)
check(not targetGui.Enabled and target.hitBars.first==nil,'final hit blocks stale focus and delayed hit packets')
target:ShowHit('second',5,2,11.8,anotherHead)
visibleHeads.second=nil
target:RefreshHits(11.9,resolveHead)
check(target.hitBars.second==nil,'streaming out removes the hit bar')
target:ShowHit('second',6,1,12,nil)
target:RefreshHits(12.1,resolveHead)
check(not target.hitBars.second.gui.Enabled,'a head that has not streamed in keeps its hit bar hidden')
visibleHeads.second=anotherHead
target:RefreshHits(12.2,resolveHead)
check(target.hitBars.second.gui.Enabled and target.hitBars.second.gui.Adornee==anotherHead,'a late head binds within the hit window')
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
