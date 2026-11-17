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
local actions={interact=onAction,drop=onAction,attack=onAction,exitPaint=onAction,resetView=onAction}
screen:BindActions(actions);screen:BindActions(actions)
local button=root:WaitForChild('InteractButton')
button.Activated:Fire()
check(calls==1 and button.Activated:Count()==1,'rebinding actions disconnects previous handlers')
screen:Refresh({painting=false,hasTarget=true,dropDescription={textId='Drop'}})
check(button.Visible and screen.labels.HintKeyText.Visible and not screen.touchFrames.TouchLandscapeFrame.Visible,'desktop HUD shows keyboard controls')
for _,label in screen.dropLabels do check(label.translationKey~=nil,'all drop variants receive translated description') end
U.UserInputService.TouchEnabled=true
screen:Refresh({painting=false,hasTarget=true})
check(not button.Visible and not screen.labels.HintKeyText.Visible and screen.touchFrames.TouchLandscapeFrame.Visible and not screen.touchFrames.TouchPortraitFrame.Visible,'touch landscape selects only its controls')
local camera=U.workspace.CurrentCamera
U.workspace.CurrentCamera={ViewportSize={X=540,Y=960}}
screen:Refresh({painting=false,hasTarget=false})
check(screen.touchFrames.TouchPortraitFrame.Visible and not screen.touchFrames.TouchLandscapeFrame.Visible,'portrait switches control variant')
screen:SetPainting(true)
check(screen.paintFrame.Visible and screen.touchFrames.TouchPaintFrame.Visible and not screen.buttons.ExitPaintButton.Visible,'touch paint controls replace normal controls')
screen:SetProgress(.375)
check(screen.labels.ProgressText.Text=='37%' and screen.fill.Size==R.UDim2.fromScale(.375,1),'paint progress updates number and fill')
screen:UpdatePointer(nil,camera,R.Vector2.zero,false)
check(U.pointerRoot==root,'pointer uses the manager-owned root')
screen:ShowNotice({kind='Message',textId='PaintSegmentLimit'})
local notice=screen.labels.NoticeText
check(notice.translationKey~=nil,'notices use translation controller')
local target=UI.GetTargetGuiManager()
local part=U.Node('Head','Part')
target:Refresh({adornee=part,visible=true,hits=999,touch=false})
local targetGui=target.gui
check(targetGui.Parent==U.playerGui and targetGui.Enabled and targetGui.Adornee==part and target.key.Visible,'target remains private in PlayerGui and shows stunned prompt')
target:Refresh({visible=false,hits=0,touch=true})
check(not targetGui.Enabled and targetGui.Adornee==nil and not target.key.Visible,'lost target clears adornment and hides prompt')
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
screen:UnbindActions();button.Activated:Fire()
check(calls==1 and button.Activated:Count()==0,'stopped gameplay cannot receive UI actions')
UI.Destroy();UI.Destroy()
check(gui.destroyed and textSignal:Count()==0 and notice.translationKey==nil,'main teardown releases GUI, text listeners and translation registration')
U.workspace.CurrentCamera=camera
U.UserInputService.TouchEnabled=false
local replacement=UI.CreateGameScreenGui()
check(replacement~=gui and replacement.Parent==U.playerGui,'whole UI can initialize again after repeated destruction')
UI.Destroy()
print('PASS: '..checks..' dedicated UI template manager assertions (production modules; engine signals and translation service mocked)')
