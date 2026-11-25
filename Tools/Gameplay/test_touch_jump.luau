-- 自研触控跳跃与原生 JumpButton 屏蔽回归
local U = require('./FoundationUIBoundary')
local TouchJump = require('./TouchJumpController')
local R = require('@lune/roblox')

local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end

local function makeInput(kind)
	local input = U.Node('Input', 'InputObject')
	input.UserInputType = kind
	input.UserInputState = R.Enum.UserInputState.Begin
	return input
end

local player = U.Players.LocalPlayer
local char = U.Node('Character', 'Model')
local humanoid = U.Node('Humanoid', 'Humanoid')
humanoid.Health = 100
humanoid.Jump = false
humanoid.Parent = char
player.Character = char

-- 预置原生 TouchGui（包含左摇杆与原生 JumpButton）
local touchGui = U.Node('TouchGui', 'ScreenGui')
touchGui.Enabled = true
touchGui.Parent = U.playerGui
local touchControlFrame = U.Node('TouchControlFrame', 'Frame')
touchControlFrame.Visible = true
touchControlFrame.Parent = touchGui
local thumbstick = U.Node('DynamicThumbstickFrame', 'Frame')
thumbstick.Visible = true
thumbstick.Parent = touchControlFrame
local nativeJump = U.Node('JumpButton', 'ImageButton')
nativeJump.Visible = true
nativeJump.Active = true
nativeJump.Selectable = true
nativeJump.Position = R.UDim2.fromOffset(500, 300)
nativeJump.Parent = touchControlFrame

-- 自研跳跃按钮挂在 CenterFrame.TouchControlsFrame.TouchJumpFrame 下
local center = U.gui:WaitForChild('CenterFrame')
local touchControls = center:WaitForChild('TouchControlsFrame')
local touchJumpFrame = touchControls:WaitForChild('TouchJumpFrame')
local jumpButton = touchJumpFrame:WaitForChild('JumpButton')
touchControls.Visible = true
touchJumpFrame.Visible = true
jumpButton.Visible = true

local allowJump = true
local controller = TouchJump.new(jumpButton, function()
	return allowJump
end)

-- 1. 原生 JumpButton 被压制，且 TouchGui 与左摇杆保持可见
check(not nativeJump.Visible and not nativeJump.Active and not nativeJump.Selectable, 'native JumpButton is suppressed on init')
check(nativeJump.Position == R.UDim2.fromOffset(-9999, -9999), 'native JumpButton is moved off-screen')
check(touchGui.Enabled and thumbstick.Visible, 'native TouchGui and left thumbstick remain enabled')
check(jumpButton.Visible and touchControls.Visible, 'custom JumpButton is never suppressed')

-- 2. 引擎恢复原生 JumpButton.Visible 时自动反压制
nativeJump.Visible = true
nativeJump:GetPropertyChangedSignal('Visible'):Fire()
check(not nativeJump.Visible, 'native JumpButton is re-suppressed when engine restores Visible')

-- 3. 重生后新加入的原生 JumpButton 同样被压制
local lateNativeJump = U.Node('JumpButton', 'ImageButton')
lateNativeJump.Visible = true
lateNativeJump.Parent = touchControlFrame
check(not lateNativeJump.Visible, 'late native JumpButton added via DescendantAdded is suppressed')

-- 4. 按下自研跳跃按钮立即起跳，按住期间 RenderStepped 持续连跳，抬手停止
local touchInput = makeInput(R.Enum.UserInputType.Touch)
jumpButton.InputBegan:Fire(touchInput)
check(humanoid.Jump, 'pressing JumpButton triggers immediate jump')
humanoid.Jump = false
U.RunService.RenderStepped:Fire()
check(humanoid.Jump, 'holding JumpButton triggers continuous jump on RenderStepped')
humanoid.Jump = false
touchInput.UserInputState = R.Enum.UserInputState.End
touchInput:GetPropertyChangedSignal('UserInputState'):Fire()
U.RunService.RenderStepped:Fire()
check(not humanoid.Jump, 'releasing JumpButton stops jumping')

-- 5. Cancel / MenuOpened / 失焦 / 进入画符 / 容器隐藏 / 角色移除 均中断跳跃
local function assertInterruptedBy(label, triggerFn)
	humanoid.Jump = false
	local input = makeInput(R.Enum.UserInputType.Touch)
	jumpButton.InputBegan:Fire(input)
	check(humanoid.Jump, label .. ': starts jumping')
	humanoid.Jump = false
	triggerFn(input)
	U.RunService.RenderStepped:Fire()
	check(not humanoid.Jump, label .. ': stops jumping')
end

assertInterruptedBy('InputCancel', function(input)
	input.UserInputState = R.Enum.UserInputState.Cancel
	input:GetPropertyChangedSignal('UserInputState'):Fire()
end)
assertInterruptedBy('MenuOpened', function()
	U.GuiService.MenuOpened:Fire()
end)
assertInterruptedBy('WindowFocusReleased', function()
	U.UserInputService.WindowFocusReleased:Fire()
end)
assertInterruptedBy('PaintingStarted', function()
	player:SetAttribute('Painting', true)
	player:GetAttributeChangedSignal('Painting'):Fire()
end)
player:SetAttribute('Painting', false)
assertInterruptedBy('TouchControlsHidden', function()
	touchControls.Visible = false
	touchControls:GetPropertyChangedSignal('Visible'):Fire()
end)
touchControls.Visible = true
assertInterruptedBy('CharacterRemoving', function()
	player.CharacterRemoving:Fire()
end)

-- 6. canJump() 为 false（例如打开弹窗/画符）时不可触发跳跃
allowJump = false
humanoid.Jump = false
jumpButton.InputBegan:Fire(makeInput(R.Enum.UserInputType.Touch))
check(not humanoid.Jump, 'canJump=false blocks jump start')

-- 7. Destroy 幂等清理全部监听
controller:Destroy()
controller:Destroy()
check(jumpButton.InputBegan:Count() == 0 and U.playerGui.DescendantAdded:Count() == 0, 'Destroy cleanly disconnects all signals')

print('PASS: ' .. checks .. ' touch jump controller assertions')
