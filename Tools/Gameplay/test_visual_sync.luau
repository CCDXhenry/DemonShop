-- 视觉同步回归：版本、原样保存、预算、限频队列、确认延迟及收尾
local Rules=require('./VisualRules')
local Upload=require('./VisualUpload')
local Net=require('./VisualNet')
local Config=require('./GameConfig')
local Protocol=require('./VisualProtocol')
local checks=0
local function check(v,m) assert(v,m);checks+=1 end
local function segment(index,version)
 return {key='session:1:'..index,gesture=1,version=version or 1,part='UpperTorso',face=1,u0=.1,v0=.2,u1=.8,v1=.6}
end
local state=Rules.New()
local first=segment(1)
check(Rules.Validate(first),'valid visible segment')
local accepted=Rules.Apply(state,{first},'session')
check(accepted and state.count==1 and state.segments[first.key].u1==.8,'canonical geometry saved without coverage filtering')
local duplicate=Rules.Apply(state,{first},'session')
check(duplicate and #duplicate==0 and state.count==1,'duplicates are idempotent')
local longer=segment(1,2);longer.u1=.9
Rules.Apply(state,{longer},'session')
Rules.Apply(state,{first},'session')
check(state.segments[first.key].u1==.9,'older version cannot undo extension')
local invalid=segment(2);invalid.u1=0/0
check(not Rules.Validate(invalid),'NaN rejected')
invalid.u1=1.1
check(not Rules.Validate(invalid),'out of face coordinates rejected')
check(Rules.Apply(state,{segment(2)},'wrong-session')==nil,'wrong session key rejected')
local moved=segment(1,3);moved.u0=.3
check(Rules.Apply(state,{moved},'session')==nil,'stable segment origin enforced')
state.count=Config.PaintLocalSegmentBudget
check(Rules.Apply(state,{segment(2)},'session')==nil,'whole-body budget enforced')
local extended=Rules.Apply(state,{segment(1,3)},'session')
check(extended and #extended==1,'existing segment may update at full budget')
local upload=Upload.new();upload:Begin('session')
upload:Update({[first.key]=first},.01,10,0,0,false)
upload:Update({[first.key]=longer},.02,10,0,0,false)
check(#Net.requests==0,'rendering updates do not send each frame')
upload:Update({},.1,10,0,0,false)
check(#Net.requests==1 and #Net.requests[1].segments==1 and Net.requests[1].segments[1].version==2,'queue coalesces latest geometry by ID')
upload.closing=true
upload:Update({},.2,10,0,0,true)
check(#Net.requests==1,'exit waits for acknowledgement')
upload:Update({},1.2,11,0,0,true)
check(#Net.requests==2 and Net.requests[2].sequence==1,'unacknowledged batch retries with original sequence')
upload:Ack(1)
upload:Update({},1.3,11,0,0,true)
check(Net.requests[3].action=='EndPaint' and Net.requests[3].sequence==1,'finish references fully acknowledged final batch')
upload:Update({},1.4,11,0,0,true)
check(#Net.requests==3,'finish submitted once')
table.clear(Net.requests);upload:Begin('session')
local many={}
for i=1,130 do local s=segment(i);many[s.key]=s end
upload:Update(many,2,12,0,0,true)
check(#Net.requests==3 and #Net.requests[1].segments==64 and #Net.requests[3].segments==2,'large flush splits into bounded packets')
upload.closing=true;upload:Ack(2)
upload:Update({},2.2,12,0,0,true)
check(#Net.requests==3,'200 ms delayed final acknowledgement cannot release ownership early')
upload:Ack(3);upload:Update({},2.3,12,0,0,true)
check(Net.requests[4].action=='EndPaint','final acknowledgement releases closing session')
upload:Clear()
check(next(upload.pending)==nil and next(upload.flight)==nil and upload.session==nil,'session destruction clears upload resources')
table.clear(Net.requests);upload:Begin('session')
many={}
for i=1,1000 do local s=segment(i);many[s.key]=s end
upload:Update(many,3,13,0,0,true)
check(#Net.requests==4,'large release flush has bounded immediate burst')
upload:Update({},3.01,13,0,0,true)
check(#Net.requests==4,'closing drain does not bypass rate limit every render frame')
upload:Update({},3.1,13,0,0,true)
check(#Net.requests==8,'remaining release geometry continues in bounded ticks')
local packet={action='PaintVisual',session='session',sequence=1,started=10,segments={segment(1)}}
check(Protocol.Validate(packet),'visual wire packet accepted')
packet.segments={unexpected=segment(1)}
check(not Protocol.Validate(packet),'dictionary cannot bypass array packet limit')
packet.segments={[1]=segment(1),[4]=segment(4)}
check(not Protocol.Validate(packet),'sparse visual packet rejected')
packet.segments={}
for i=1,65 do table.insert(packet.segments,segment(i)) end
check(not Protocol.Validate(packet),'wire packet capped at 64 segments')
packet.segments={segment(1)};packet.started=math.huge
check(not Protocol.Validate(packet),'nonfinite presentation timestamp rejected')
packet.started=10;packet.sequence=1.5
check(not Protocol.Validate(packet),'fractional wire sequence rejected')
local extra=segment(1);extra.unrecognized='must not be retained'
local cleanState=Rules.New();Rules.Apply(cleanState,{extra},'session')
check(cleanState.segments[extra.key].unrecognized==nil,'canonical storage strips fields outside visual protocol')
print(string.format('PASS: %d visual protocol and queue assertions (production modules)',checks))
