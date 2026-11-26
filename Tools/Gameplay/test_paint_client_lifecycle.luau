-- 正式客户端方法回归：退出端点、输入冻结、帧内顺序、外层浇灌及重生清理。
local R=require('@lune/roblox')
local C=R.CFrame
local Rotation=require('./PaintRotation')
local Client=require('./PaintClientLifecycle')
local Upload=require('./VisualUpload')
local Net=require('./VisualNet')
local B=require('./PaintClientBoundary')
local Config=require('./GameConfig')
local count=0
local function check(v,m) assert(v,m);count+=1 end
local function client()
 local log={}
 local textLog={}
 local sacrificed={}
 local view={curved=nil,budgetReached=false,sacrifices=sacrificed}
 function view:Update() table.insert(log,'raster') end
 function view:Drain() return {} end
 function view:IsReady() return true end
 function view:DrawLocal() end
 function view:SetSacrifice(id,brightness,fade) sacrificed[id]={brightness=brightness,fade=fade} end
 function view:ClearSacrifice(id) sacrificed[id]=nil; table.insert(log,'clear-sacrifice:'..tostring(id)) end
 local c=setmetatable({
  paintId='body',session='session',visualClosing=false,visualUpload=Upload.new(),
  drawing=false,finishPaint=false,pointer=R.Vector2.new(800,900),paintSamples={},
  angularSpeed=1,lastPaint=B.time,paintSequence=0,lastPaintSound=0,visualGesture=0,
  orientation=C.Angles(.3,.2,0),sentOrientation=C.identity,touch=nil,
  bodies={
   GetPaintModel=function() return nil end,
   GetVisualPart=function() return nil end,
   GetAltarModel=function() return nil end,
   IsAltarTossing=function() return false end,
   Fly=function() end,
  },
  view=view,items={},synced=true,lastFrame=B.time,lastSync=B.time,lastHint=B.time,messageEnds=100,
  localProgress=0,localArea=0,localTotalArea=0,localFrontArea=0,localBackArea=0,localFrontTotalArea=0,localBackTotalArea=0,paintFlipped=false,flipFlash=nil,
  hiddenPlayerParts={},altarViews={},altarView={Clear=function() end},
  presentation={
   flipped=false,flipping=false,
   CapturePose=function() return nil end,
   IsFlipping=function(p) return p.flipping==true end,
   SetFlipped=function(p,f,anim) p.flipped=f; p.flipping=(f and anim==true); if not p.flipping then p.targetOrientation=Rotation.FlatOrientation(f) end end,
  },
  paintCamera={
   ready=true,follow=nil,
   Exit=function(cam) cam.follow=nil; table.insert(log,'camera-exit') end,
   FollowToss=function(cam,ends,target) cam.follow={ends=ends,target=target}; table.insert(log,'camera-follow') end,
  },
  textLog=textLog,
  Text=function(_,name,desc) textLog[name]=desc end,
  ui={SetPainting=function() end,UpdatePointer=function() end,SetProgress=function() end,Refresh=function() end},
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
active.drawing=true
active.touch={}
active.rotationAnchor=R.Vector2.new(1,1)
active:RequestPaintEnd()
check(active.finishPaint and not active.drawing and active.touch==nil,'active exit closes the existing gesture')
check(active.pointer==R.Vector2.new(800,900),'exit button coordinates cannot become the final paint endpoint')
check(active.angularSpeed==0 and active.rotationAnchor==nil,'closing clears pending rotation')
local pointer=active.pointer
active:OnMove({UserInputType=R.Enum.UserInputType.MouseMovement,Position=R.Vector3.new(900,950,0)})
active:OnRelease({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(901,951,0)})
active:OnInput({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(902,952,0)},false)
active:ResetPaintView()
check(active.pointer==pointer and active.finishPaint and not active.drawing,'move, release and begin cannot change a closing gesture')
check(active.orientation==C.Angles(.3,.2,0) and #Net.requests==0,'reset cannot alter closing pose or emit a new request')
local released=client()
released.drawing=true
released:OnRelease({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(101,201,0)})
check(released.finishPaint and not released.drawing and released.pointer==R.Vector2.new(101,201),'normal release saves the idle pointer and closes the held stroke')
released:RequestPaintEnd()
check(released.finishPaint and released.pointer==R.Vector2.new(101,201),'release followed by exit retains the pointer without sampling the button')
-- 调用正式 Update，日志证明采样与栅格化顺序，且等待本地完成后才发结束。
table.clear(Net.requests)
active.orientation=C.identity
active:Update(1/60)
check(activeLog[1]=='sample' and activeLog[2]=='raster' and #activeLog==2,'current-frame sample precedes exactly one raster update')
check(Net.requests[1].action=='EndPaint','ready local raster allows synchronized exit')
active:ExitView()
check(active.paintId==nil and active.session==nil and not active.drawing and not active.finishPaint,'confirmed exit clears paint input state')
check(activeLog[3]=='camera-exit' and active.visualUpload.session==nil,'camera exits only on confirmation and upload owner clears')
local cameraCalls=#activeLog
active:ExitView()
check(#activeLog==cameraCalls,'duplicate exit confirmation cannot restore camera twice')
local waiting=client()
waiting.orientation=C.identity
waiting.view.IsReady=function() return false end
waiting:RequestPaintEnd();table.clear(Net.requests);waiting:Update(1/60)
check(#Net.requests==0 and waiting.paintId=='body','client remains in view until local raster is complete')
waiting.view.IsReady=function() return true end
B.time+=.1;waiting:Update(1/60)
check(Net.requests[1].action=='EndPaint','client automatically finishes after raster catches up')
local respawn=client()
respawn.drawing=true;respawn.finishPaint=true;respawn.touch={}
respawn.rotationAnchor=R.Vector2.new(1,1)
respawn:ExitView()
check(respawn.touch==nil and respawn.brushFrame==nil and respawn.rotationAnchor==nil and #respawn.paintSamples==0 and respawn.angularSpeed==0,'respawn exit releases all gesture ownership')
-- 原会话清理后，新会话仍可正常接受输入。
respawn.paintId='next-body';respawn.session='next-session';respawn.visualGesture=0
respawn:OnInput({UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(20,30,0)},false)
check(respawn.drawing and respawn.visualGesture==1 and respawn.pointer==R.Vector2.new(20,30),'reentry starts a fresh gesture')

table.clear(Net.requests)
local painter=client()
painter.Paint=nil
painter.orientation=C.identity
painter.angularSpeed=0
local model={}
painter.bodies.GetPaintModel=function() return model end
painter.presentation.center,painter.presentation.model=R.Vector3.zero,model
painter.presentation.geometry,painter.presentation.orientation={radius=3,halfExtents=R.Vector3.new(1.5,1,0.8)},C.identity
-- 模拟 3D 椭圆体投影限制区域：X 半轴 150px，Y 半轴 100px
local ellipsoidRx, ellipsoidRy = 150, 100
B.workspace.CurrentCamera={
	CFrame=C.identity,
	WorldToScreenPoint=function(_,p) return R.Vector3.new(p.X*100,p.Y*100,10) end,
	ViewportSize=R.Vector2.new(1920,1080),
}
B.resolve={
	ellipsoidPoint=function(_orientation,point)
		local nx, ny = point.X / ellipsoidRx, point.Y / ellipsoidRy
		local r = math.sqrt(nx * nx + ny * ny)
		if r <= 1 then
			return point, R.Vector3.new(point.X / 100, point.Y / 100, 0), false
		end
		local clampedTip = R.Vector2.new(point.X / r, point.Y / r)
		return clampedTip, R.Vector3.new(clampedTip.X / 100, clampedTip.Y / 100, 0), true
	end,
	cast=function(orientation,point)
		local axis,angle=orientation:ToAxisAngle()
		local x=point.X-axis.X*angle*30
		if x<-100 or x>200 or math.abs(point.Y)>80 then return nil end
		return {point=point,localPoint=R.Vector3.new(x/300,point.Y/300,0),sample={part='UpperTorso',face=1,u=(x+100)/300,v=.5}}
	end,
}
local drawn={}
painter.view.DrawLocal=function(_,_,_,_,samples) table.insert(drawn,samples) end
-- 默认 PaintRotationEnabled=false 时按下并拖动只落笔手绘，不产生旋转锚点与旋转角速度。
check(Config.PaintRotationEnabled == false, 'PaintRotationEnabled defaults to false')
local noRotTouch={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(10,0,0)}
painter:OnInput(noRotTouch,false)
check(painter.rotationAnchor == nil, 'disabled PaintRotationEnabled creates no rotation anchor')
noRotTouch.Position=R.Vector3.new(80,0,0)
painter:OnMove(noRotTouch)
painter:StepPaintRotation(.03)
painter:Paint(B.time)
check(painter.orientation == C.identity and painter.angularSpeed == 0 and #drawn > 0,
	'disabled PaintRotationEnabled keeps body flat without rotating while still hand-drawing')
painter:OnRelease(noRotTouch)
table.clear(drawn)
table.clear(painter.paintSamples)
table.clear(Net.requests)
painter.pendingCoverage = nil

Config.PaintRotationEnabled = true
local touch={UserInputType=R.Enum.UserInputType.Touch,Position=R.Vector3.new(100,0,0)}
painter:OnInput(touch,false)
painter:OnMove({UserInputType=R.Enum.UserInputType.MouseMovement,Position=R.Vector3.new(900,950,0)})
check(painter.pointer.X==100,'unrelated mouse motion cannot take ownership of a touch gesture')
painter:Paint(B.time)
-- 拖到椭圆体外侧加速旋转：白膜立即旋转，画笔平滑贴合椭圆体投影边缘。
touch.Position=R.Vector3.new(400,0,0)
painter:OnMove(touch)
painter:StepPaintRotation(.03)
painter.presentation.orientation=painter.orientation
local tip=painter:Paint(B.time+.03)
local endpoint=drawn[#drawn][#drawn[#drawn]]
check(painter.orientation~=C.identity and math.abs(tip.X-ellipsoidRx)<1e-4 and math.abs(tip.Y)<1e-4 and endpoint.orientation==painter.orientation,
	'dragging outside ellipsoid clamps brush onto ellipsoid boundary while spinning immediately')
painter:StepPaintRotation(.03)
painter.presentation.orientation=painter.orientation
local tip2=painter:Paint(B.time+.06)
check(tip2==tip and drawn[#drawn][#drawn[#drawn]].u<endpoint.u,'stationary clamped brush paints continuously as body rotates')
local orientation=painter.orientation
local beforeRelease=#drawn
painter:OnRelease(touch)
painter:StepPaintRotation(.03)
check(painter.orientation==orientation and painter.touch==nil and painter.finishPaint,'touch release stops rotation immediately')
local restTip=painter:Paint(B.time+Config.PaintBatchInterval+.01)
local uploaded={}
local index=1
while painter.pendingCoverage or #painter.paintSamples>0 do
	local sent=Net.requests[index]
	check(sent and sent.action=='Paint' and #sent.samples<=Config.PaintCoverageBatchSize,'bounded coverage packet')
	for _,sample in sent.samples do table.insert(uploaded,sample) end
	painter:OnNotice({kind='PaintPose',id='body',session='session',sequence=sent.sequence,progress=.1})
	B.time+=.2
	painter:Paint(B.time)
	index+=1
end
local expected={}
for _,batch in drawn do for _,sample in batch do table.insert(expected,sample) end end
check(#uploaded==#expected,'coverage retains every displayed sample')
for i,sample in uploaded do check(sample==expected[i],'packet boundaries preserve paint order') end
check(restTip==nil and #drawn==beforeRelease and not painter.finishPaint,'release waits for all samples to be acknowledged')
painter:ResetPaintView()
check(painter.orientation==C.identity and painter.brushFrame==nil and Net.requests[#Net.requests].action=='ResetView','reset restores neutral and breaks the current stroke')
painter.presentation.orientation=C.identity
local mouse={UserInputType=R.Enum.UserInputType.MouseButton1,Position=R.Vector3.new(230,0,0)}
local move={UserInputType=R.Enum.UserInputType.MouseMovement,Position=mouse.Position}
painter:OnMove(move)
check(painter:Paint(B.time)==R.Vector2.new(230,0),'idle pen follows the raw pointer outside the white body')
local beforeTap=#painter.paintSamples
painter:OnInput(mouse,false)
local clampedFrame=painter.brushFrame
check(clampedFrame~=nil and clampedFrame.clamped and clampedFrame.contact~=nil and #painter.paintSamples==beforeTap+1 and math.abs(clampedFrame.tip.X-ellipsoidRx)<1e-4,
	'pressing outside ellipsoid clamps brush onto ellipsoid boundary and stamps body')
check(painter:Paint(B.time)==clampedFrame.tip,'while drawing, brush cursor displays at the ellipsoid-clamped position')
painter:OnRelease(mouse)
local rested=painter:Paint(B.time)
check(math.abs(rested.X-ellipsoidRx)<1e-4 and math.abs(rested.Y)<1e-4,'released mouse pen stays on the clamped ellipsoid tip')
move.Position=R.Vector3.new(240,0,0)
painter:OnMove(move)
local shifted=painter:Paint(B.time)
check(math.abs(shifted.X-(ellipsoidRx+10))<1e-4 and math.abs(shifted.Y)<1e-4,'mouse motion after release continues from the ellipsoid tip')
mouse.Position=R.Vector3.new(240,0,0)
painter:OnInput(mouse,false)
check(painter.rotationAnchor~=nil and math.abs(painter.rotationAnchor.X-(ellipsoidRx+10))<1e-4 and math.abs(painter.rotationAnchor.Y)<1e-4,'the next press anchors at the rebased tip')
painter:OnRelease(mouse)
painter.pointerOrigin,painter.hardwareOrigin=nil,nil

-- 客户端本地覆盖去重：对真实曲面模型重复发送已涂过的采样点时，不反复堆积 paintSamples 队列。
local Curve=require('./CurvedSurface')
local Data=require('./BodySurfaceData')
local realModel=R.Instance.new('Model')
local realTorso=R.Instance.new('Part')
realTorso.Name,realTorso.Size='UpperTorso',Data.Parts.UpperTorso.size
realTorso:SetAttribute('Paintable',true)
realTorso:SetAttribute('SurfaceVersion',Curve.Version)
realTorso.CFrame=C.identity
realTorso.Parent=realModel
local hitSample=Curve.Intersect(realTorso,R.Vector3.new(0,0,-4),R.Vector3.zAxis,10)
assert(hitSample,'real curved hit fixture')
painter.bodies.GetPaintModel=function() return realModel end
painter.presentation.model=realModel
painter.localCovered={}
painter.localProgress,painter.localArea,painter.localTotalArea=0,0,0
painter.lastSync=B.time
painter.lastHint=B.time
painter.items.body={id='body',model=realModel,progress=0}
local reportedProgress=0
painter.ui.SetProgress=function(_,value) reportedProgress=value end
table.clear(painter.paintSamples)
B.resolve={
	ellipsoidPoint=function(_ori,pt) return pt,R.Vector3.new(0,0,-0.5),false end,
	cast=function(_ori,pt)
		return {point=pt,localPoint=Curve.Point(realTorso,hitSample),sample=table.clone(hitSample)}
	end,
}
painter.orientation,painter.presentation.orientation=C.identity,C.identity
mouse.Position=R.Vector3.new(10,10,0)
painter:OnInput(mouse,false)
local firstQueued=#painter.paintSamples
check(firstQueued==1,'first hit on uncovered cell queues into paintSamples')
check(painter.localProgress>0 and painter.localProgress<=0.99,'client predicts coverage progress immediately on local stroke before server reply')
painter:Update(1/60)
check(reportedProgress==painter.localProgress and painter.items.body.progress==0,'UI displays immediate local progress while server item.progress is still 0')
painter:OnNotice({kind='PaintPose',id='body',session='session',orientation=C.identity,progress=math.min(0.95,painter.localProgress+0.2)})
check(painter.localProgress>=painter.items.body.progress,'server PaintPose monotonically raises local progress without rollback')
painter:OnRelease(mouse)
-- 再次在同一已涂过的位置反复点击 10 次，本地去重直接过滤，不再膨胀上传队列。
for k=1,10 do
	mouse.Position=R.Vector3.new(10+k*0.001,10,0)
	painter:OnInput(mouse,false)
	painter:OnRelease(mouse)
end
check(#painter.paintSamples==firstQueued,'local coverage deduplication prevents duplicate samples from clogging upload queue')
-- 背面旋转切片点不会被客户端提前写入 localCovered，翻到正面后仍可正常上报服务端。
do
	local backHit = Curve.Intersect(realTorso, R.Vector3.new(0, 0, 4), -R.Vector3.zAxis, 10)
	assert(backHit, 'back curved hit fixture')
	local sliceBack = table.clone(backHit)
	sliceBack.slice = true
	sliceBack.orientation = C.identity
	local beforeBackCount = #painter.paintSamples
	B.workspace.CurrentCamera.CFrame = C.lookAt(R.Vector3.new(0, 0, -12), R.Vector3.zero)
	painter.presentation.geometry = { center = R.Vector3.zero, rest = C.identity, radius = 2, halfExtents = R.Vector3.new(1, 1, 1) }
	B.resolve = {
		ellipsoidPoint = function(_ori, pt) return pt, R.Vector3.new(0, 0, -0.5), false end,
		cast = function(_ori, pt)
			return { point = pt, localPoint = Curve.Point(realTorso, sliceBack), sample = table.clone(sliceBack) }
		end,
	}
	mouse.Position = R.Vector3.new(15, 15, 0)
	painter:OnInput(mouse, false)
	painter:OnRelease(mouse)
	check(#painter.paintSamples == beforeBackCount, 'back-hemisphere slice sample is not queued or poisoned into localCovered')
	-- 旋转 180° 将该背面转至面向镜头后，客户端应正常记录并上报。
	local flipped = C.Angles(0, math.pi, 0)
	local frontSlice = table.clone(backHit)
	frontSlice.slice = true
	frontSlice.orientation = flipped
	painter.orientation = flipped
	painter.presentation.orientation = flipped
	realTorso.CFrame = flipped
	B.resolve = {
		ellipsoidPoint = function(_ori, pt) return pt, R.Vector3.new(0, 0, -0.5), false end,
		cast = function(_ori, pt)
			return { point = pt, localPoint = Curve.Point(realTorso, frontSlice), sample = table.clone(frontSlice) }
		end,
	}
	mouse.Position = R.Vector3.new(16, 16, 0)
	painter:OnInput(mouse, false)
	painter:OnRelease(mouse)
	check(#painter.paintSamples == beforeBackCount + 1, 'previously rejected back-hemisphere cell queues normally once rotated to camera side')
	painter.orientation, painter.presentation.orientation = C.identity, C.identity
	B.workspace.CurrentCamera.CFrame = C.identity
end
realModel:Destroy()
painter.bodies.GetPaintModel=function() return model end
painter.presentation.model=model
B.resolve={
	ellipsoidPoint=function(_orientation,point)
		local nx, ny = point.X / ellipsoidRx, point.Y / ellipsoidRy
		local r = math.sqrt(nx * nx + ny * ny)
		if r <= 1 then
			return point, R.Vector3.new(point.X / 100, point.Y / 100, 0), false
		end
		local clampedTip = R.Vector2.new(point.X / r, point.Y / r)
		return clampedTip, R.Vector3.new(clampedTip.X / 100, clampedTip.Y / 100, 0), true
	end,
	cast=function(orientation,point)
		local axis,angle=orientation:ToAxisAngle()
		local x=point.X-axis.X*angle*30
		if x<-100 or x>200 or math.abs(point.Y)>80 then return nil end
		return {point=point,localPoint=R.Vector3.new(x/300,point.Y/300,0),sample={part='UpperTorso',face=1,u=(x+100)/300,v=.5}}
	end,
}
painter.pointerOrigin,painter.hardwareOrigin=nil,nil

-- 按住按下点：白膜停转；按下点画，静止不重复盖墨，死区内移动指针支持手绘。
mouse.Position=R.Vector3.new(0,0,0)
painter:OnInput(mouse,false)
local afterTap=#painter.paintSamples
painter:StepPaintRotation(.05)
painter.presentation.orientation=painter.orientation
painter:Paint(B.time+.05)
check(painter.orientation==C.identity and #painter.paintSamples==afterTap,'holding still at the press point keeps body still with zero duplicate ink')
move.Position=R.Vector3.new(1,0,0)
painter:OnMove(move)
painter:StepPaintRotation(.05)
painter.presentation.orientation=painter.orientation
painter:Paint(B.time+.1)
check(painter.orientation==C.identity and #painter.paintSamples>afterTap,'moving inside the press-point deadzone hand-draws without rotating')
painter:OnRelease(mouse)
check(painter.rotationAnchor==nil,'release clears the press-point rotation anchor')

-- 远离白膜中心按住不动不转；相同拖拽位移给出相同角速度，与离中心远近无关。
painter.pointerOrigin,painter.hardwareOrigin=nil,nil
mouse.Position=R.Vector3.new(400,0,0)
painter.orientation=C.identity
painter:OnInput(mouse,false)
painter:StepPaintRotation(.05)
check(painter.orientation==C.identity and painter.angularSpeed==0,'holding still far from the body center does not rotate')
painter:OnRelease(mouse)
local function dragSpeed(fromX,toX)
	painter.pointerOrigin,painter.hardwareOrigin=nil,nil
	painter.orientation=C.identity
	painter.angularSpeed=0
	mouse.Position=R.Vector3.new(fromX,0,0)
	painter:OnInput(mouse,false)
	move.Position=R.Vector3.new(toX,0,0)
	painter:OnMove(move)
	painter:StepPaintRotation(.05)
	local speed=painter.angularSpeed
	painter:OnRelease(mouse)
	return speed
end
local nearSpeed,farSpeed=dragSpeed(0,200),dragSpeed(300,500)
check(nearSpeed>0 and math.abs(nearSpeed-farSpeed)<1e-6,'equal drag from the press point gives the same angular speed near or far from the body center')
B.workspace.CurrentCamera=nil

local observer=client()
observer.paintId,observer.session=nil,nil
observer.snapshot={tableId='body',session='current'}
observer.items.body={progress=0}
local applied=false
observer.view.Apply=function() applied=true end
observer:OnNotice({kind='PaintPose',id='body',session='current',orientation=C.Angles(-2,1.2,.3),progress=.3})
observer:OnNotice({kind='VisualDelta',id='body',session='current',segments={},orientation=C.identity})
observer:OnNotice({kind='PaintPose',id='body',session='old',orientation=C.identity,progress=.1})
check(applied and observer.presentation.targetOrientation==C.Angles(-2,1.2,.3) and observer.items.body.progress==.3,
	'visual acknowledgement and previous-session pose cannot roll back the observer')
Config.PaintRotationEnabled = false
observer:OnNotice({kind='PaintPose',id='body',session='current',orientation=C.Angles(1,1,1),progress=.4})
check(observer.presentation.targetOrientation==C.identity and observer.items.body.progress==.4,
	'disabled PaintRotationEnabled locks observer targetOrientation to identity')

-- 非旋转模式下鼠标松手不重基指针/不调 SnapPointerToBrush，并清空 pointerOrigin/hardwareOrigin 保持 1:1。
do
	B.workspace.CurrentCamera = {
		CFrame = C.identity,
		WorldToScreenPoint = function(_, p) return R.Vector3.new(p.X * 100, p.Y * 100, 10) end,
		ViewportSize = R.Vector2.new(1920, 1080),
	}
	B.resolve = {
		ellipsoidPoint = function(_orientation, point)
			local nx, ny = point.X / ellipsoidRx, point.Y / ellipsoidRy
			local r = math.sqrt(nx * nx + ny * ny)
			if r <= 1 then
				return point, R.Vector3.new(point.X / 100, point.Y / 100, 0), false
			end
			local clampedTip = R.Vector2.new(point.X / r, point.Y / r)
			return clampedTip, R.Vector3.new(clampedTip.X / 100, clampedTip.Y / 100, 0), true
		end,
		cast = function(_orientation, point)
			return { point = point, localPoint = R.Vector3.new(point.X / 300, point.Y / 300, 0), sample = { part = 'UpperTorso', face = 1, u = 0.5, v = 0.5 } }
		end,
	}
	local flatMouse = client()
	flatMouse.Paint = nil
	flatMouse.orientation = C.identity
	flatMouse.bodies.GetPaintModel = function() return model end
	flatMouse.presentation.model = model
	flatMouse.presentation.geometry = { radius = 3, halfExtents = R.Vector3.new(1.5, 1, 0.8) }
	flatMouse.presentation.orientation = C.identity
	local pressMouse = { UserInputType = R.Enum.UserInputType.MouseButton1, Position = R.Vector3.new(230, 0, 0) }
	local moveMouse = { UserInputType = R.Enum.UserInputType.MouseMovement, Position = R.Vector3.new(235, 0, 0) }
	flatMouse:OnInput(pressMouse, false)
	flatMouse:OnMove(moveMouse)
	flatMouse:OnRelease({ UserInputType = R.Enum.UserInputType.MouseButton1, Position = R.Vector3.new(235, 0, 0) })
	check(flatMouse.pointer == R.Vector2.new(235, 0) and flatMouse.pointerOrigin == nil and flatMouse.hardwareOrigin == nil,
		'non-rotation mouse release keeps raw pointer without SnapPointerToBrush rebase')
	moveMouse.Position = R.Vector3.new(250, 0, 0)
	flatMouse:OnMove(moveMouse)
	check(flatMouse.pointer == R.Vector2.new(250, 0), 'mouse motion after non-rotation release stays 1:1 with system pointer')

	-- 即使存在残留偏移/钳制帧，关闭旋转松手时也会直接清零而不重基到笔尖。
	flatMouse.drawing = true
	flatMouse.pointerOrigin = R.Vector2.new(10, 10)
	flatMouse.hardwareOrigin = R.Vector2.new(50, 50)
	flatMouse.brushFrame = {
		orientation = C.identity,
		pointer = R.Vector2.new(230, 0),
		tip = R.Vector2.new(ellipsoidRx, 0),
		clamped = true,
	}
	flatMouse:OnRelease({ UserInputType = R.Enum.UserInputType.MouseButton1, Position = R.Vector3.new(230, 0, 0) })
	check(flatMouse.pointerOrigin == nil and flatMouse.hardwareOrigin == nil and flatMouse.pointer ~= R.Vector2.new(ellipsoidRx, 0),
		'non-rotation release clears stale pointer origins instead of snapping to clamped brush tip')
	B.workspace.CurrentCamera = nil
end

-- 非旋转模式覆盖目标采用 PaintFlatTarget，且近距离跳过重叠点不冗余插入 breakBefore 锚点。
do
	local flatCov = client()
	flatCov.Paint = nil
	flatCov.orientation = C.identity
	flatCov.presentation.orientation = C.identity
	local flatTorso = R.Instance.new('Part')
	flatTorso.Name, flatTorso.Size = 'UpperTorso', R.Vector3.new(2, 2, 1)
	flatTorso:SetAttribute('Paintable', true)
	flatTorso.CFrame = C.identity
	local flatModel = R.Instance.new('Model')
	flatTorso.Parent = flatModel
	flatCov.bodies.GetPaintModel = function() return flatModel end
	flatCov.presentation.model = flatModel
	flatCov.presentation.geometry = { radius = 3, halfExtents = R.Vector3.new(1, 1, 0.5) }
	flatCov.items.body = { id = 'body', model = flatModel, progress = 0 }
	B.workspace.CurrentCamera = {
		CFrame = C.identity,
		WorldToScreenPoint = function(_, p) return R.Vector3.new(p.X * 100, p.Y * 100, 10) end,
		ViewportSize = R.Vector2.new(1920, 1080),
	}
	local seqSamples = {
		{ point = R.Vector2.new(0, 0), localPoint = R.Vector3.new(-0.5, 0, -0.5), sample = { part = 'UpperTorso', face = 1, u = 0.25, v = 0.5 } },
		{ point = R.Vector2.new(10, 0), localPoint = R.Vector3.new(-0.499, 0, -0.5), sample = { part = 'UpperTorso', face = 1, u = 0.2505, v = 0.5 } },
		{ point = R.Vector2.new(20, 0), localPoint = R.Vector3.new(-0.44, 0, -0.5), sample = { part = 'UpperTorso', face = 1, u = 0.28, v = 0.5 } },
	}
	local idx = 0
	B.resolve = {
		cast = function()
			idx += 1
			local item = seqSamples[math.min(idx, #seqSamples)]
			return { point = item.point, localPoint = item.localPoint, sample = table.clone(item.sample) }
		end,
	}
	Config.PaintRotationEnabled = false
	flatCov.drawing = true
	flatCov.pointer = R.Vector2.new(0, 0)
	flatCov:SamplePaint(B.time)
	flatCov.pointer = R.Vector2.new(4, 0)
	flatCov:SamplePaint(B.time)
	-- 第 1 笔在 u=0.25 落墨，第 2 笔 u=0.2505 无新增面积，第 3 笔 u=0.28（距离 0.059 studs < BrushRadius*1.25）；非旋转不插入 anchor。
	check(#flatCov.paintSamples == 2 and not flatCov.paintSamples[2].breakBefore,
		'non-rotation FilterNewCoverageSamples skips redundant breakBefore anchor within 1.25*BrushRadius')

	-- 对比开启旋转时相同短距跳转仍插入 breakBefore 锚点。
	local rotCov = client()
	rotCov.Paint = nil
	rotCov.orientation = C.identity
	rotCov.presentation.orientation = C.identity
	rotCov.bodies.GetPaintModel = function() return flatModel end
	rotCov.presentation.model = flatModel
	rotCov.presentation.geometry = { radius = 3, halfExtents = R.Vector3.new(1, 1, 0.5) }
	rotCov.items.body = { id = 'body', model = flatModel, progress = 0 }
	idx = 0
	Config.PaintRotationEnabled = true
	rotCov.drawing = true
	rotCov.pointer = R.Vector2.new(0, 0)
	rotCov:SamplePaint(B.time)
	rotCov.pointer = R.Vector2.new(4, 0)
	rotCov:SamplePaint(B.time)
	check(#rotCov.paintSamples == 3 and rotCov.paintSamples[2].breakBefore == true,
		'rotation mode preserves breakBefore anchor clone before new sample')

	-- ActivePaintTarget 在非旋转下按 PaintFlatTarget 同步 PaintPose 面积。
	Config.PaintRotationEnabled = false
	flatCov.localTotalArea = 100
	flatCov.localFrontTotalArea, flatCov.localBackTotalArea = 0, 0
	flatCov.localFrontArea, flatCov.localBackArea = 0, 0
	flatCov.localArea = 0
	flatCov.localProgress = 0
	flatCov:OnNotice({ kind = 'PaintPose', id = 'body', session = 'session', progress = 0.5 })
	local expectedTarget = (Config :: any).PaintFlatTarget or Config.PaintTarget
	check(math.abs(flatCov.localArea - 100 * expectedTarget * 0.5) < 1e-6,
		'ActivePaintTarget uses PaintFlatTarget in non-rotation mode')
	B.workspace.CurrentCamera = nil
	flatModel:Destroy()
end

-- 躺平模式客户端预测：真实曲面模型按正反各自可达总面积独立推进 localFrontArea / localBackArea 并隔离侧面/背面。
do
	local Curve = require('./CurvedSurface')
	local Data = require('./BodySurfaceData')
	local Surface = require('./PaintSurface')
	local realModel = R.Instance.new('Model')
	local realLimb = R.Instance.new('Part')
	realLimb.Name, realLimb.Size = 'LeftLowerArm', Data.Parts.LeftLowerArm.size
	realLimb:SetAttribute('Paintable', true)
	realLimb:SetAttribute('SurfaceVersion', Curve.Version)
	realLimb.CFrame = C.identity
	realLimb.Parent = realModel
	local fTotal, bTotal = Surface.FlatSideTotals(realModel)
	local flatClient = client()
	flatClient.Paint = nil
	flatClient.orientation = C.identity
	flatClient.presentation.orientation = C.identity
	flatClient.bodies.GetPaintModel = function() return realModel end
	flatClient.presentation.model = realModel
	flatClient.presentation.geometry = { radius = 2, halfExtents = R.Vector3.new(1, 1, 0.5) }
	flatClient.items.body = { id = 'body', model = realModel, progress = 0 }
	flatClient.localTotalArea = Surface.Total(realModel)
	flatClient.localFrontTotalArea, flatClient.localBackTotalArea = fTotal, bTotal
	local rimHit = Curve.Intersect(realLimb, R.Vector3.new(realLimb.Size.X * 0.25, 0, -4), R.Vector3.zAxis, 10)
	assert(rimHit, 'client flat rim fixture')
	B.workspace.CurrentCamera = {
		CFrame = C.identity,
		WorldToScreenPoint = function(_, p) return R.Vector3.new(p.X * 100, p.Y * 100, 10) end,
		ViewportSize = R.Vector2.new(1920, 1080),
	}
	B.resolve = {
		cast = function()
			return { point = R.Vector2.new(20, 20), localPoint = Curve.Point(realLimb, rimHit), sample = table.clone(rimHit) }
		end,
	}
	Config.PaintRotationEnabled = false
	flatClient.drawing = true
	flatClient.pointer = R.Vector2.new(20, 20)
	flatClient:SamplePaint(B.time)
	local limbGeo = Curve.Geometry(realLimb)
	local leaked = false
	for k in flatClient.localCovered do
		local triIdx = tonumber(string.match(k, ':(%d+):%d+$'))
		if triIdx and limbGeo.triangles[triIdx].normal.Z >= Curve.FlatCoverageMinDot then
			leaked = true; break
		end
	end
	check(not leaked and flatClient.localFrontArea > 0 and flatClient.localBackArea == 0,
		'client flat prediction isolates front strokes into localFrontArea without staining back cells')
	flatClient.localFrontArea = fTotal * Config.PaintFlatTarget
	flatClient.pointer = R.Vector2.new(22, 20)
	local centerHit = Curve.Intersect(realLimb, R.Vector3.new(0, 0, -4), R.Vector3.zAxis, 10)
	assert(centerHit, 'client flat center fixture')
	B.resolve = {
		cast = function()
			return { point = R.Vector2.new(22, 20), localPoint = Curve.Point(realLimb, centerHit), sample = table.clone(centerHit) }
		end,
	}
	flatClient:SamplePaint(B.time)
	check(flatClient.paintFlipped == true and flatClient.localProgress >= Config.PaintAutoFlipProgress,
		'client flat prediction triggers auto-flip once localFrontArea reaches target')
	B.workspace.CurrentCamera = nil
	realModel:Destroy()
end

-- UpdateAltar 在 tossing 分支中不抹除活跃的 completeFlash 高光，过期后由 Update 清理。
do
	local flashClient, flashLog = client()
	flashClient:OnNotice({ kind = 'FinishPaint', session = 'session' })
	check(flashClient.completeFlash ~= nil and flashClient.completeFlash.id == 'body' and flashClient.view.sacrifices.body ~= nil,
		'FinishPaint starts completeFlash sacrifice highlight')
	flashClient.items.body = { id = 'body', kind = 'Body', location = 'Altar', flyEnds = B.time + 1 }
	flashClient.items.other = { id = 'other', kind = 'Body', location = 'Altar', flyEnds = B.time + 1 }
	flashClient.bodies.GetAltarModel = function() return {} end
	flashClient.bodies.IsAltarTossing = function() return true end
	flashClient.bodies.Fly = function() end
	flashClient.snapshot = { pool = 0, shelf = 0, items = {}, altarEnds = 0, stationVersions = {} }
	flashClient:UpdateAltar(B.time + 0.05)
	check(flashClient.view.sacrifices.body ~= nil and table.find(flashLog, 'clear-sacrifice:body') == nil,
		'UpdateAltar preserves active completeFlash during altar toss')
	check(table.find(flashLog, 'clear-sacrifice:other') ~= nil,
		'UpdateAltar still clears sacrifice on tossing items without active completeFlash')
	B.time += Config.RuneCompleteFlashSeconds + 0.05
	flashClient:Update(1 / 60)
	check(flashClient.completeFlash == nil and flashClient.view.sacrifices.body == nil and table.find(flashLog, 'clear-sacrifice:body') ~= nil,
		'Update clears completeFlash sacrifice after RuneCompleteFlashSeconds')
end

-- 绘画提示随旋转开关切换 PaintingFlat / Painting；带跟随退出先清 HintText 且延后恢复玩家显隐。
do
	local hintClient = client()
	Config.PaintRotationEnabled = false
	hintClient.lastHint = 0
	hintClient:Update(1 / 60)
	check(hintClient.textLog.HintText ~= nil and hintClient.textLog.HintText.textId == 'PaintingFlat',
		'non-rotation paint hint uses PaintingFlat')
	Config.PaintRotationEnabled = true
	hintClient.lastHint = 0
	hintClient:Update(1 / 60)
	check(hintClient.textLog.HintText ~= nil and hintClient.textLog.HintText.textId == 'Painting',
		'rotation paint hint uses Painting')
	Config.PaintRotationEnabled = false

	local charModel = R.Instance.new('Model')
	local hrp = R.Instance.new('Part')
	hrp.Name = 'HumanoidRootPart'
	hrp.Position = R.Vector3.zero
	hrp.Parent = charModel
	B.player.Character = charModel

	local followClient = client()
	local hiddenPart = R.Instance.new('Part')
	hiddenPart.LocalTransparencyModifier = 1
	followClient.hiddenPlayerParts = { [hiddenPart] = true }
	followClient.textLog.HintText = { textId = 'PaintingFlat' }
	followClient.lastHint = B.time
	followClient:ExitView(B.time)
	check(followClient.paintId == nil and followClient.paintCamera.follow ~= nil,
		'ExitView with altarTossStarted enters camera toss follow')
	check(followClient.textLog.HintText == nil and followClient.lastHint == 0,
		'ExitView clears HintText immediately and resets lastHint')
	check(hiddenPart.LocalTransparencyModifier == 1 and next(followClient.hiddenPlayerParts) ~= nil,
		'ExitView with active camera follow defers restoring hidden players')

	followClient.snapshot = { pool = 0, shelf = 0, items = {}, altarEnds = 0, stationVersions = {} }
	followClient:Update(1 / 60)
	check(hiddenPart.LocalTransparencyModifier == 1 and next(followClient.hiddenPlayerParts) ~= nil,
		'Update keeps players hidden while paintCamera.follow is active')
	check(followClient.textLog.HintText == nil,
		'Update skips regular HintText refresh while paintCamera.follow is active')

	followClient.paintCamera.follow = nil
	B.time += 0.2
	followClient:Update(1 / 60)
	check(hiddenPart.LocalTransparencyModifier == 0 and next(followClient.hiddenPlayerParts) == nil,
		'Update restores hidden players immediately after paintCamera.follow ends')
	check(followClient.textLog.HintText ~= nil,
		'Update resumes regular HintText after paintCamera.follow ends')

	local plainExit = client()
	local hiddenPart2 = R.Instance.new('Part')
	hiddenPart2.LocalTransparencyModifier = 1
	plainExit.hiddenPlayerParts = { [hiddenPart2] = true }
	plainExit.textLog.HintText = { textId = 'PaintingFlat' }
	plainExit:ExitView()
	check(plainExit.paintCamera.follow == nil and hiddenPart2.LocalTransparencyModifier == 0 and next(plainExit.hiddenPlayerParts) == nil,
		'ExitView without camera follow restores hidden players immediately')
	check(plainExit.textLog.HintText == nil and plainExit.lastHint == 0,
		'ExitView without camera follow also clears HintText and resets lastHint')

	B.player.Character = nil
	charModel:Destroy()
end
do
	local autoFlipClient = client()
	autoFlipClient.Paint = nil
	autoFlipClient.orientation = C.identity
	autoFlipClient.sentOrientation = C.identity
	autoFlipClient.drawing = true
	autoFlipClient.brushFrame = { orientation = C.identity, pointer = R.Vector2.zero, tip = R.Vector2.zero, clamped = false }
	autoFlipClient:TriggerAutoFlip(true)
	check(autoFlipClient.paintFlipped == true and autoFlipClient.orientation == Rotation.FlipOrientation,
		'TriggerAutoFlip switches client orientation to flipped back side')
	check(autoFlipClient.presentation.flipped == true and autoFlipClient.presentation:IsFlipping() == true,
		'TriggerAutoFlip starts flip presentation animation')
	check(autoFlipClient.textLog.NoticeText and autoFlipClient.textLog.NoticeText.textId == 'PaintFlipped',
		'TriggerAutoFlip shows flip notice text')
	check(autoFlipClient.flipFlash ~= nil and autoFlipClient.flipFlash.id == 'body',
		'TriggerAutoFlip triggers flip flash highlight')
	autoFlipClient.SamplePaint = function() error('must not sample while flipping') end
	autoFlipClient.brushFrame = { orientation = C.identity, pointer = R.Vector2.zero, tip = R.Vector2.zero, clamped = false }
	autoFlipClient:Paint(B.time)
	check(autoFlipClient.brushFrame == nil and autoFlipClient.drawing == true,
		'Paint pauses stroke sampling and breaks stroke while flipping while preserving drawing state')
end
print('PASS: '..count..' production paint client lifecycle assertions')
