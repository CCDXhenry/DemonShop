-- 平面符文印记视图回归：点击落印、等距拖动、笔势转向、边缘缩放跳过、共享 EditableImage 及远程重建
local Roblox = require('@lune/roblox')
local View = require('./PaintView')
local Rules = require('./VisualRules')
local Config = require('./GameConfig')
local Boundary = require('./StrokeViewBoundary')
local checks = 0
local function check(v, m) assert(v, m); checks += 1 end

local model = Roblox.Instance.new('Model')
local torso = Roblox.Instance.new('Part')
torso.Name, torso.Size, torso.Parent = 'UpperTorso', Roblox.Vector3.new(2, 2, 1), model
local head = Roblox.Instance.new('Part')
head.Name, head.Size, head.Parent = 'Head', Roblox.Vector3.new(1, 1, 1), model

local function sample(u, v, gap, partName)
	return { part = partName or 'UpperTorso', face = 1, u = u, v = v, breakBefore = gap }
end

local owner, remote = View.new(), View.new()
owner:Bind('body', model)

-- 1. 点击仅落一枚，且部位正向 (angle=0)，原地停留不增加印记
owner:DrawLocal('body', 'owner', 1, { sample(0.5, 0.5), sample(0.5, 0.5) })
local firstChanges = owner:Drain('body')
local key1, seg1 = next(firstChanges)
check(key1 ~= nil and owner.counts.body == 1, 'click and hold in place stamps exactly one rune')
check(seg1.angle == 0 and seg1.glyph == 1 and seg1.scale == 1, 'first stamp is upright, glyph 1, full scale')
local label1 = owner.cells.cells['body:' .. key1].node
check(label1:IsA('ImageLabel'), 'flat model clones PaintRuneImage ImageLabel')

-- 2. 沿同一路线快慢拖动间距一致，后续依序循环 2->3->1 并随笔势转向
owner:DrawLocal('body', 'owner', 1, { sample(0.5, 0.5), sample(0.5 - 0.38 / 2, 0.5) }) -- face 1: guiU = 1 - u, 减小 u 等价向右 +X 移动 0.38 stud
local drag1 = owner:Drain('body')
local key2, seg2 = next(drag1)
check(key2 ~= nil and owner.counts.body == 2, 'dragging 0.38 stud places second rune')
check(seg2.glyph == 2 and math.abs(seg2.angle - math.pi / 2) < 1e-3, 'second rune cycles to glyph 2 and turns right (+pi/2)')

-- 3. 慢拖多步累加满 0.38 stud 同样只放 1 枚（验证快慢一致）
owner:DrawLocal('body', 'owner', 1, {
	sample(0.5 - 0.50 / 2, 0.5),
	sample(0.5 - 0.62 / 2, 0.5),
	sample(0.5 - 0.76 / 2, 0.5),
})
local drag2 = owner:Drain('body')
local key3, seg3 = next(drag2)
check(key3 ~= nil and owner.counts.body == 3 and seg3.glyph == 3, 'multi-step slow drag over 0.38 stud places exactly one rune with glyph 3')
check(#Boundary.images == 3, 'all three glyphs share exactly 3 client EditableImages')

-- 4. 服务端保存、晚加入历史重建、重发幂等与换模型重绑
local state = Rules.New()
local all = { seg1, seg2, seg3 }
local accepted = Rules.Apply(state, all, 'owner')
check(accepted and #accepted == 3 and state.count == 3, 'server stores all 3 rune stamps')
remote:Apply('body', accepted)
check(next(remote.cells.cells) == nil, 'history can arrive before model replication')
remote:Bind('body', model)
local counterpart = remote.cells.cells['body:' .. key2].node
local orig2 = owner.cells.cells['body:' .. key2].node
check(counterpart.Position == orig2.Position and counterpart.Size == orig2.Size and counterpart.Rotation == orig2.Rotation, 'remote reconstructs identical rune geometry')
remote:Apply('body', accepted)
check(remote.counts.body == 3, 'duplicate delta creates no duplicate stamp')

-- 5. 边缘等比缩至 [0.5, 1]，仍放不下时跳过
local edgeOk = (Config.RuneStampSize * 0.32) / 2 -- 距边界 0.32 * RuneStampSize，fit = 0.64 (>= 0.5)
owner:DrawLocal('body', 'owner', 2, { sample(edgeOk, 0.5, true) })
local edgeChange = owner:Drain('body')
local _, edgeSeg = next(edgeChange)
check(edgeSeg ~= nil and edgeSeg.scale >= Config.RuneMinScale and edgeSeg.scale < 1, 'edge stamp scales down proportionally to fit')

local edgeSkip = 0.02 / 2 -- 距边界 0.02 stud，fit < 0.5 -> 跳过
local countBeforeSkip = owner.counts.body
owner:DrawLocal('body', 'owner', 3, { sample(edgeSkip, 0.5, true) })
check(owner.counts.body == countBeforeSkip and next(owner:Drain('body')) == nil, 'stamp skipped when even 0.5 scale does not fit')

-- 6. 跨部位重新起笔（正向落下）
owner:DrawLocal('body', 'owner', 4, { sample(0.5, 0.5, false, 'Head') })
local _, headSeg = next(owner:Drain('body'))
check(headSeg ~= nil and headSeg.part == 'Head' and headSeg.angle == 0, 'crossing to new part starts fresh upright stamp')

-- 7. 献祭高亮与恢复
owner:SetSacrifice('body', 1, 0.5)
check(label1.ImageColor3 == Config.AltarStrokeHighlight and math.abs(label1.ImageTransparency - 0.5) < 1e-4, 'sacrifice highlights ImageColor3 and fades ImageTransparency')
owner:ClearSacrifice('body')
check(label1.ImageColor3 == Config.RuneBaseColor and label1.ImageTransparency == 0, 'clearing sacrifice restores rune color and transparency')

-- 8. 换模型重绑、释放与对象池复用
local replacement = model:Clone()
owner:Bind('body', replacement)
check(label1.Parent.Adornee == replacement:FindFirstChild('UpperTorso'), 'model replacement rebinds existing SurfaceGui')
owner:Remove('body')
check(next(owner.segments) == nil and next(owner.tips) == nil and next(owner.dirty) == nil and label1.Parent == nil, 'removal clears records and returns labels')
local pooled = table.clone(owner.cells.pool)
owner:Bind('next', replacement)
owner:DrawLocal('next', 'next-session', 1, { sample(0.5, 0.5) })
local reused = next(owner.cells.cells)
check(reused ~= nil and table.find(pooled, owner.cells.cells[reused].node) ~= nil, 'next body reuses pooled PaintRuneImage')

owner:Destroy(); remote:Destroy()
check(#Boundary.gui:GetChildren() == 0, 'all surface guis released on destroy')
model:Destroy(); replacement:Destroy()
print(string.format('PASS: %d flat rune view assertions (production renderer and server rules)', checks))
