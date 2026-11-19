-- 正式客户端方法回归：退出端点、输入冻结、帧内顺序及重生清理。
local R=require('@lune/roblox')
local Client=require('./PaintClientLifecycle')
local Upload=require('./VisualUpload')
local Net=require('./VisualNet')
local B=require('./PaintClientBoundary')
local count=0
local function check(v,m) assert(v,m);count+=1 end
local function client()
 local log={}
 local view={curved=nil,budgetReached=false}
 function view:Update() table.insert(log,'raster') end
 function view:Drain() return {} end
 function view:IsReady() return true end
 local c=setmetatable({
  paintId='body',session='session',visualClosing=false,visualUpload=Upload.new(),
  drawing=false,finishPaint=false,pointer=R.Vector2.new(800,900),visualPointer=nil,lastPointer=nil,
  rotationInput=R.Vector2.one,angularVelocity=R.Vector2.one,
  yaw=.2,pitch=.3,sentYaw=0,sentPitch=0,touch=nil,
  bodies={GetPaintModel=function() return nil end},view=view,items={},synced=true,lastFrame=B.time,lastHint=B.time,messageEnds=100,
  presentation={CapturePose=function() return nil end},
  paintCamera={ready=true,Exit=function() table.insert(log,'camera-exit') end},
  Text=function() end,
  ui={SetPainting=function() end,UpdatePointer=function() end,SetProgress=function() end},
 },Client)
 c.visualUpload:Begin('session')
 function c:Paint() table.insert(log,'sample');self.finishPaint=false end
 return c,log
end
table.clear(Net.requests)
local c,log=client()
c:RequestPaintEnd()
check(c.visualClosing and not c.finishPaint,'exit without a gesture creates no final stroke')
check(#Net.requests==0 and #log==0,'exit request preserves camera and awaits synchronization')
c:RequestPaintEnd()
check(not c.finishPaint,'repeated exit request remains idempotent')
local active,activeLog=client()
active.drawing=true;active.visualPointer=R.Vector2.new(100,200);active.lastPointer=R.Vector2.new(80,190)
active.touch={}
active:RequestPaintEnd()
check(active.finishPaint and not active.drawing and active.touch==nil,'active exit closes the existing gesture')
check(active.pointer==R.Vector2.new(100,200),'exit button coordinates cannot become the final paint endpoint')
check(active.rotationInput==R.Vector2.zero and active.angularVelocity==R.Vector2.zero,'closing clears pending rotation')
local pointer=active.pointer
active:OnMove({UserInputType=R.Enum.UserInputType.MouseMovement,Position=R.Vector3.new(900,950,0)})
active:OnRelease({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(901,951,0)})
active:OnInput({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(902,952,0)},false)
active:ResetPaintView()
check(active.pointer==pointer and active.finishPaint and not active.drawing,'move, release and begin cannot change a closing gesture')
check(active.yaw==.2 and active.pitch==.3 and #Net.requests==0,'reset cannot alter closing pose or emit a new request')
local released=client()
released.drawing=true
released:OnRelease({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(101,201,0)})
check(released.finishPaint and not released.drawing and released.pointer==R.Vector2.new(101,201),'normal release captures one final endpoint')
released.visualPointer=R.Vector2.new(99,199)
released:RequestPaintEnd()
check(released.finishPaint and released.pointer==released.visualPointer,'release followed by exit retains an existing gesture without using the button endpoint')
-- 调用正式 Update，日志证明采样与栅格化顺序，且等待本地完成后才发结束。
table.clear(Net.requests)
active.yaw,active.pitch=0,0
active:Update()
check(activeLog[1]=='sample' and activeLog[2]=='raster' and #activeLog==2,'current-frame sample precedes exactly one raster update')
check(Net.requests[1].action=='EndPaint','ready local raster allows synchronized exit')
active:ExitView()
check(active.paintId==nil and active.session==nil and not active.drawing and not active.finishPaint,'confirmed exit clears paint input state')
check(activeLog[3]=='camera-exit' and active.visualUpload.session==nil,'camera exits only on confirmation and upload owner clears')
local cameraCalls=#activeLog
active:ExitView()
check(#activeLog==cameraCalls,'duplicate exit confirmation cannot restore camera twice')
local waiting=client()
waiting.yaw,waiting.pitch=0,0
waiting.view.IsReady=function() return false end
waiting:RequestPaintEnd();table.clear(Net.requests);waiting:Update()
check(#Net.requests==0 and waiting.paintId=='body','client remains in view until local raster is complete')
waiting.view.IsReady=function() return true end
B.time+=.1;waiting:Update()
check(Net.requests[1].action=='EndPaint','client automatically finishes after raster catches up')
local respawn=client()
respawn.drawing=true;respawn.finishPaint=true;respawn.touch={}
respawn:ExitView()
check(respawn.touch==nil and respawn.visualPointer==nil and respawn.lastPointer==nil and respawn.angularVelocity==R.Vector2.zero,'respawn exit releases all gesture ownership')
-- 原会话清理后，新会话仍可正常接受输入。
respawn.paintId='next-body';respawn.session='next-session';respawn.visualGesture=0
respawn:OnInput({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(20,30,0)},false)
check(respawn.drawing and respawn.visualGesture==1 and respawn.pointer==R.Vector2.new(20,30),'reentry starts a fresh gesture')
print('PASS: '..count..' production paint client lifecycle assertions')
