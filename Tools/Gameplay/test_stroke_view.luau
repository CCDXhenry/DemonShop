-- 统一线段生产视图回归：客户端、服务端和观察者使用相同几何与版本
local Roblox=require('@lune/roblox')
local View=require('./PaintView')
local Rules=require('./VisualRules')
local Boundary=require('./StrokeViewBoundary')
local checks=0
local function check(v,m) assert(v,m);checks+=1 end
local model=Roblox.Instance.new('Model')
local torso=Roblox.Instance.new('Part')
torso.Name,torso.Size,torso.Parent='UpperTorso',Roblox.Vector3.new(2,2,1),model
local function sample(u,v,gap) return {part='UpperTorso',face=1,u=u,v=v,breakBefore=gap} end
local owner,remote=View.new(),View.new()
owner:Bind('body',model)
owner:DrawLocal('body','owner',1,{sample(.1,.5),sample(.3,.5)})
local changes=owner:Drain('body')
local key,segment=next(changes)
check(key~=nil and owner.counts.body==1,'local geometry generates a stable segment')
local frame=owner.frames['body:'..key]
local width=frame.Size.X.Offset
owner:DrawLocal('body','owner',1,{sample(.3,.5),sample(.9,.5)})
local latest=owner:Drain('body')[key]
check(latest.version>segment.version and owner.counts.body==1 and frame.Size.X.Offset>width,'extension updates one existing ID')
local state=Rules.New()
local accepted=Rules.Apply(state,{latest},'owner')
check(accepted and #accepted==1 and state.count==1,'server stores exact visible segment')
remote:Apply('body',accepted)
check(next(remote.frames)==nil,'history can arrive before model replication')
remote:Bind('body',model)
local counterpart=remote.frames['body:'..key]
check(counterpart.Position==frame.Position and counterpart.Size==frame.Size and counterpart.Rotation==frame.Rotation,'remote reconstructs identical geometry')
owner:Apply('body',accepted)
check(owner.frames['body:'..key]==frame and frame.Parent~=nil,'confirmation retains local frame without replacement')
remote:Apply('body',{segment})
check(counterpart.Size==frame.Size,'old snapshot cannot roll newer segment back')
remote:Apply('body',accepted)
check(remote.counts.body==1,'duplicate delta creates no duplicate instance')
owner:DrawLocal('body','owner',1,{sample(.2,.5,true)})
check(owner.counts.body==2,'missed ray creates separate contact')
owner:DrawLocal('body','owner',2,{sample(.7,.8)})
check(owner.counts.body==3,'new gesture never joins old stroke')
local original=frame
owner:Remove('body')
check(next(owner.segments)==nil and next(owner.tips)==nil and next(owner.dirty)==nil and original.Parent==nil,'removal clears geometry queues and frames')
owner:Destroy();remote:Destroy()
check(#Boundary.gui:GetChildren()==0,'all surface guis are released')
model:Destroy()
print(string.format('PASS: %d canonical visual assertions (production renderer and server rules)',checks))
