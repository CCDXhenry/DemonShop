-- 正式画符服务的离线回归：序号、姿态、遮挡、完成与笔划预算
local Roblox = require('@lune/roblox')
local Painting = require('./Painting')
local Config = require('./GameConfig')
local Surface = require('./PaintSurface')
local World = require('./PaintingWorld')
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local container = Roblox.Instance.new('Model')
local model = { PivotTo = function() end }
local part = Roblox.Instance.new('Part')
part.Name, part.Size = 'UpperTorso', Roblox.Vector3.new(2,2,1)
part:SetAttribute('Paintable',true)
part.Parent = container
function model:FindFirstChild(name) return container:FindFirstChild(name) end
World.part = part
local session = { token = 'session', sequence = 0, last = 0, yaw = 0, pitch = 0 }
local item = { model = model, covered = {}, area = 0, totalArea = 100, paintSeconds = 0, progress = 0, strokes = {}, strokePoints = 0 }
local sample = { part = 'UpperTorso', face = 1, u = .5, v = .5 }
local request = { sequence = 1, yaw = 0, pitch = 0, samples = {sample} }
local origin = Roblox.Vector3.new(0,0,-10)
local pose = Roblox.CFrame.identity
local first = Painting.Apply(session,item,request,pose,origin,.1)
check(first and first.stroke and #first.stroke.samples == 1,'accepted samples retain continuous stroke coordinates')
check(item.area > 0 and item.progress > 0,'visible accepted sample adds coverage')
local area = item.area
check(Painting.Apply(session,item,request,pose,origin,.2) == nil,'duplicate sequence rejected')
check(item.area == area and #item.strokes == 1,'duplicate does not append strokes or coverage')
request.sequence = 2
Painting.Apply(session,item,request,pose,origin,.2)
check(item.area == area,'repainting does not increase progress')
World.visible = false
request.sequence = 3
request.yaw = .1
local occluded = Painting.Apply(session,item,request,pose,origin,.3)
check(occluded and not occluded.stroke and session.yaw == 0,'occluded sample ignores rotation and leaves no stroke')
check(item.area == area,'occlusion cannot paint through body')
World.visible = true
request.sequence, request.yaw = 4, 2
local fast = Painting.Apply(session,item,request,pose,origin,.4)
check(fast and fast.stroke and session.yaw == 0,'fast local rotation is ignored and does not reject the stroke')
request.sequence, request.yaw = 5, 0
item.totalArea = item.area / Config.PaintTarget
local complete = Painting.Apply(session,item,request,pose,origin,.5)
check(complete and complete.complete and item.progress == 1 and item.paintSeconds < 12,'coverage completes without hidden 12 second gate')
item.strokePoints = Config.PaintStrokePointBudget
request.sequence = 6
local capped = Painting.Apply(session,item,request,pose,origin,.6)
check(capped and not capped.stroke and item.strokePoints == Config.PaintStrokePointBudget,'visual budget remains bounded independently of coverage')
request.sequence, request.yaw, request.pitch, request.samples = 7, math.pi + .2, 99, {}
local beforeEmpty = item.area
local empty = Painting.Apply(session,item,request,pose,origin,.7)
check(empty and not empty.stroke and item.area == beforeEmpty,'pose-only batch cannot award coverage')
check(math.abs(session.yaw) < .00001 and session.pitch == 0,'presentation angles stay fixed while painting')
request.sequence = 6
request.yaw = 0
check(Painting.Apply(session,item,request,pose,origin,.8) == nil and session.yaw == 0,'old batch cannot roll pose back')
container:Destroy()
print(string.format('PASS: %d painting assertions (production module; mocked raycast boundary)',checks))
