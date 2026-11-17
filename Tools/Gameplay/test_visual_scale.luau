-- 视觉预算规模回归：真实构造整身体预算、历史重建和全部资源回收（非 Studio 性能数据）
local Roblox=require('@lune/roblox')
local Rules=require('./VisualRules')
local View=require('./PaintView')
local Config=require('./GameConfig')
local Boundary=require('./StrokeViewBoundary')
local state=Rules.New()
local model=Roblox.Instance.new('Model')
local part=Roblox.Instance.new('Part')
part.Name,part.Size,part.Parent='UpperTorso',Roblox.Vector3.new(2,2,1),model
local view=View.new();view:Bind('scale-body',model)
local batches=0
local started=os.clock()
for first=1,Config.PaintLocalSegmentBudget,Config.PaintVisualBatchSize do
 local batch={}
 for index=first,math.min(first+Config.PaintVisualBatchSize-1,Config.PaintLocalSegmentBudget) do
  table.insert(batch,{key='scale:1:'..index,version=1,gesture=1,part='UpperTorso',face=2,u0=.1,v0=.2,u1=.8,v1=.7})
 end
 local accepted,reason=Rules.Apply(state,batch,'scale')
 assert(accepted,reason)
 view:Apply('scale-body',accepted)
 batches+=1
end
assert(state.count==8192 and view.counts['scale-body']==8192,'full budget history reconstructed')
local count=0
for _ in view.frames do count+=1 end
assert(count==8192,'every canonical segment has exactly one frame')
view:DrawLocal('scale-body','next',1,{{part='UpperTorso',face=2,u=.5,v=.5}})
assert(view.budgetReached and view.counts['scale-body']==8192,'client blocks unsavable new segment at full shared budget')
view:Remove('scale-body')
assert(next(view.frames)==nil and next(view.dirty)==nil and #view.pool<=Config.PaintPreviewPoolBudget,'full body removal bounds cached frames')
view:Bind('unpainted',model)
view:Destroy()
assert(next(view.models)==nil and #view.pool==0 and #Boundary.gui:GetChildren()==0,'destroy clears painted and unpainted bindings')
model:Destroy()
print(string.format('PASS: 5 full-budget visual assertions (%d batches, 8192 GUI frames, %.3fs Lune; not Studio FPS)',batches,os.clock()-started))
