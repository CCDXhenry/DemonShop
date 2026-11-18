-- 持续输入压力回归：真实时钟测量正式渲染器；模拟时间只表达输入帧和等待帧数。
local R=require('@lune/roblox')
local Process=require('@lune/process')
local View=require('./CurvedPaintView')
local Curve=require('./CurvedSurface')
local Data=require('./BodySurfaceData')
local B=require('./CurvedRasterBoundary')
local part=R.Instance.new('Part')
part.Name,part.Size='UpperTorso',Data.Parts.UpperTorso.size
part:SetAttribute('SurfaceVersion',Curve.Version)
-- 以 160 屏幕像素/stud 将往复曲线按 3 像素弧长重采样；不把生成输入的耗时算入渲染。
local samples={}
local previous=R.Vector2.new(0,part.Size.Y*.28)
local remaining=0
for index=1,2048 do
 local phase=index/2048*math.pi*2
 local point=R.Vector2.new(math.sin(phase)*part.Size.X*.36,math.cos(phase*3)*part.Size.Y*.28)
 local distance=(point-previous).Magnitude
 while remaining<=distance do
  local p=previous:Lerp(point,if distance>0 then remaining/distance else 0)
  table.insert(samples,Curve.ProjectLocal(part,R.Vector3.new(p.X,p.Y,-part.Size.Z*.5)))
  remaining+=3/160
 end
 remaining-=distance
 previous=point
end
local function segment(serial,a,b,gesture)
 return {key='stream:'..serial,version=1,gesture=gesture,part=part.Name,face=1,u0=a.u,v0=a.v,u1=b.u,v1=b.v,triangle0=a.triangle,triangle1=b.triangle,surfaceVersion=Curve.Version}
end
local count=0
for _,fps in {30,60} do for _,pixels in {100,300} do
 if Process.args[1] and (fps~=tonumber(Process.args[1]) or pixels~=tonumber(Process.args[2])) then continue end
 local records={}
 local view=View.new()
 view.diagnostics={submitted=0,completed=0,scanned=0,commits=0,commitSeconds=0}
 view:Bind('body',B.Model({part}),records)
 B.os.clock=os.clock
 view:Update('body')
 local serial,cursor,oldest,maxPending,maxWait,updateSeconds=0,0,1,0,0,0
 local submittedAt,waits={},{}
 -- 直接压力测试渲染器，故意超过业务层单身体 8192 条上限，避免达到上限后停止输入掩盖积压。
 local frameCount=fps*30
 local maxUpdate=0
 for frame=1,frameCount do
  -- 每两秒插入一次快速反复落笔；每个新笔划从一个点开始，不能与旧端点连接。
  local points=math.ceil(pixels/3)
  local gesture=if frame%(fps*2)<fps/4 then frame else math.floor(frame/(fps*2))
  for index=1,points do
   local a=samples[cursor%#samples+1]
   cursor+=1
   local b=samples[cursor%#samples+1]
   if index==1 and frame%(fps*2)<fps/4 then a=b end
   serial+=1
   local s=segment(serial,a,b,gesture)
   records[s.key]=s;view:Apply('body',s);submittedAt[serial]=frame
  end
  local before=os.clock()
  view:Update('body')
  local duration=os.clock()-before
  updateSeconds+=duration;maxUpdate=math.max(maxUpdate,duration)
  -- completed 是真实完成栅格化的线段，不能把已从队列取出但仍挂起的任务算作完成。
  local completed=view.diagnostics.completed
  while oldest<=completed do table.insert(waits,frame-submittedAt[oldest]);oldest+=1 end
  local pending=serial-completed
  maxPending=math.max(maxPending,pending)
  if pending>0 then maxWait=math.max(maxWait,frame-submittedAt[oldest]) end
 end
 local tail=0
 while not view:IsReady('body') and tail<600 do
  view:Update('body');tail+=1
 end
 table.sort(waits)
 local p95=waits[math.max(1,math.ceil(#waits*.95))] or frameCount
 local d=view.diagnostics
 print(string.format('STREAM continuous %dfps %dpx/frame: input=%d peakPending=%d oldest=%dframes completedP95=%dframes tail=%d ready=%s updateCPU=%.3fs maxUpdate=%.4fs scanned=%d commitCPU=%.4fs',fps,pixels,serial,maxPending,maxWait,p95,tail,tostring(view:IsReady('body')),updateSeconds,maxUpdate,d.scanned,d.commitSeconds))
  assert(view:IsReady('body') and d.completed==serial,'every submitted stroke must finish without loss')
  assert(p95<=2 and tail<=2,'sustained Lune input exceeded two-frame latency target')
 count+=2
 view:Destroy()
 -- 图片边界保留观测记录；每个场景结束后释放，不把四张大图计入下一轮内存压力。
 table.clear(B.images)
end end
part:Destroy()
print('PASS: '..count..' sustained raster assertions (Lune CPU and mocked image writes; not Studio FPS)')
