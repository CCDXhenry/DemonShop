-- 本地连续笔迹几何回归：跨帧、快拖、曲线、抬笔、部位切换与合并预算
local Path = require('./StrokePath')
local Vector2 = require('@lune/roblox').Vector2
local count = 0
local function check(value, message) assert(value,message); count += 1 end
local function sample(u,v,part,face,breakBefore) return {u=u,v=v,part=part or 'UpperTorso',face=face or 1,breakBefore=breakBefore} end
local dimensions = Vector2.new(2,2)
local first = Path.Next(nil,sample(.1,.5),dimensions)
check(not first.reuse and not first.skip and first.tip.from == first.tip.point,'first contact creates dot')
local fast = Path.Next(first.tip,sample(.9,.5),dimensions)
check(fast.reuse and (fast.tip.point-fast.tip.from).Magnitude > 1.5,'fast same-face drag connects instead of spacing cutoff')
local tip, segments = nil, 0
for i=0,100 do
 local next = Path.Next(tip,sample(i/100,.5),dimensions)
 if not next.reuse and not next.skip then segments += 1 end
 if not next.skip then tip = next.tip end
end
check(segments == 1,'one hundred straight samples merge into one frame')
local repeatPoint = Path.Next(tip,sample(1,.5),dimensions)
check(repeatPoint.skip,'stationary contact adds no instances')
local turn = Path.Next(tip,sample(1,.9),dimensions)
check(not turn.reuse and turn.tip.from == tip.point,'corner starts connected new segment')
local lifted = Path.Next(tip,sample(.2,.5,nil,nil,true),dimensions)
check(not lifted.reuse and lifted.tip.from == lifted.tip.point,'pen lift or missed ray never bridges air')
local otherPart = Path.Next(tip,sample(.2,.5,'Head'),dimensions)
check(not otherPart.reuse and otherPart.tip.from == otherPart.tip.point,'part boundary creates separate surface segment')
local otherFace = Path.Next(tip,sample(.2,.5,nil,2),dimensions)
check(not otherFace.reuse and otherFace.tip.from == otherFace.tip.point,'face boundary does not draw through body')
check(math.abs(first.tip.point.X-1.8)<.00001,'side face UV matches renderer direction')
print(string.format('PASS: %d stroke path assertions (production local geometry)',count))
