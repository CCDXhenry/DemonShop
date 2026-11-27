-- 手动丢置输入：键鼠按住瞄准、移动端摇杆轻点或取消，并提交水平方向
--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Physics = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Net = require(ReplicatedStorage.Scripts.Shared.ProcessingNet)
local PersonalRules = require(ReplicatedStorage.Scripts.Shared.PersonalUpgradeRules)
local Arc = require(ReplicatedStorage.Scripts.Shared.ThrowArc)
local Preview = require(script.Parent.ThrowAimPreview)
local Config = Physics.ManualThrow
local Controller = {}
Controller.__index = Controller
export type Host = {
	TopBody: () -> Types.ItemView?,
	CanAim: () -> boolean,
	CanStore: (Vector3, Vector3?, boolean?, string?) -> boolean,
	ChuteBaffles: () -> Instance?,
	CageTargets: (() -> { Preview.CageTarget })?,
	Ignored: () -> { Instance },
}
export type Controller = typeof(setmetatable(
	{} :: {
		host: Host,
		preview: Preview.Preview,
		stick: Frame?,
		knob: GuiObject?,
		input: InputObject?,
		inputConnection: RBXScriptConnection?,
		equipConnection: RBXScriptConnection?,
		stickConnection: RBXScriptConnection?,
		gestureCharacter: Model?,
		gestureId: string?,
		gestureVersion: number?,
		stickOrigin: Vector2?,
		stickVector: Vector2,
		stickDragged: boolean,
		forward: Vector3,
		direction: Vector3,
		nextThrow: number,
	},
	Controller
))
local player = Players.LocalPlayer

local function ScreenPoint(input: InputObject, screen: ScreenGui?): Vector2
	local point = if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseMovement
		then UserInputService:GetMouseLocation()
		else Vector2.new(input.Position.X, input.Position.Y)
	if screen and not screen.IgnoreGuiInset then
		point -= GuiService:GetGuiInset()
	end
	return point
end

function Controller.Carrying(self: Controller): boolean
	return self.host.TopBody() ~= nil
end

function Controller.Ready(self: Controller): boolean
	return self.host.CanAim() and workspace:GetServerTimeNow() >= self.nextThrow
end

function Controller.Cancel(self: Controller): ()
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
	if self.equipConnection then
		self.equipConnection:Disconnect()
		self.equipConnection = nil
	end
	self.input = nil
	self.gestureCharacter = nil
	self.gestureId = nil
	self.gestureVersion = nil
	self.stickOrigin = nil
	self.stickVector = Vector2.zero
	self.stickDragged = false
	if self.knob then
		self.knob.Position = UDim2.fromScale(0.5, 0.5)
	end
	self.preview:Hide()
end

function Controller.Measure(self: Controller, input: InputObject): ()
	local stick, origin = self.stick, self.stickOrigin
	if not stick or not origin then
		return
	end
	local screen = stick:FindFirstAncestorOfClass("ScreenGui")
	local point = ScreenPoint(input, if screen and screen:IsA("ScreenGui") then screen else nil)
	local size = stick.AbsoluteSize
	local radius = math.min(size.X, size.Y) / 2
	if radius < 1 then
		return
	end
	local delta = point - origin
	if delta.Magnitude > radius then
		delta = delta.Unit * radius
	end
	self.stickVector = Vector2.new(delta.X, -delta.Y) / radius
	if self.stickVector.Magnitude > Config.StickDeadzone then
		self.stickDragged = true
	end
	if self.knob then
		self.knob.Position = UDim2.fromScale(0.5 + delta.X / size.X, 0.5 + delta.Y / size.Y)
	end
end

function Controller.AimDirection(self: Controller): Vector3?
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root or not root:IsA("BasePart") then
		return nil
	end
	self.forward = Arc.Horizontal(camera.CFrame.LookVector, if self.forward.Magnitude > 0.001 then self.forward else root.CFrame.LookVector)
	if self.stickOrigin then
		local direction = Arc.StickDirection(self.stickVector, self.forward)
		if direction then
			return direction
		end
		if self.stickDragged then
			return nil
		end
		return self.forward
	end
	return self.forward
end

function Controller.GestureMatches(self: Controller): boolean
	local top = self.host.TopBody()
	return top ~= nil
		and top.id == self.gestureId
		and top.version == self.gestureVersion
		and player.Character == self.gestureCharacter
		and self:Ready()
end

function Controller.Update(self: Controller, now: number): ()
	if self.input and not self:GestureMatches() then
		self:Cancel()
	end
	local direction = if self.input then self:AimDirection() else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local basis = if root and root:IsA("BasePart") then root else nil
	local top = if direction then self.host.TopBody() else nil
	if direction and basis and top then
		self.direction = direction
		local origin = Arc.Origin(basis.CFrame, direction)
		local ignored = self.host.Ignored()
		table.insert(ignored, self.preview.model)
		local cages = if self.host.CageTargets then self.host.CageTargets() else nil
		self.preview:Update(origin, direction, workspace.Gravity, self.host.CanStore, ignored, now, self.host.ChuteBaffles(), cages)
	else
		self.preview:Hide()
	end
end

function Controller.Begin(self: Controller, input: InputObject, useStick: boolean): boolean
	if not self:Carrying() then
		return false
	end
	if self.input or not self:Ready() then
		return true
	end
	local top = self.host.TopBody()
	if not top then
		return true
	end
	local character = player.Character
	if not character then return true end
	self.input = input
	self.gestureCharacter = character
	self.gestureId = top.id
	self.gestureVersion = top.version
	if useStick and self.stick then
		local screen = self.stick:FindFirstAncestorOfClass("ScreenGui")
		self.stickOrigin = ScreenPoint(input, if screen and screen:IsA("ScreenGui") then screen else nil)
		self.stickVector = Vector2.zero
		self.stickDragged = false
	end
	local function OnInputState(): ()
		if self.input == input and input.UserInputState == Enum.UserInputState.Cancel then
			self:Cancel()
		end
	end
	self.inputConnection = input:GetPropertyChangedSignal("UserInputState"):Connect(OnInputState)
	local function OnEquipped(child: Instance): ()
		if self.input == input and child:IsA("Tool") and PersonalRules.WeaponLevel(child.Name) then
			self:Cancel()
		end
	end
	self.equipConnection = character.ChildAdded:Connect(OnEquipped)
	return true
end

local function IsEffectivelyVisible(node: GuiObject): boolean
	local current: Instance? = node
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("ScreenGui") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

function Controller.OnMouseBegan(self: Controller, input: InputObject): boolean
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return false
	end
	if self.stick and IsEffectivelyVisible(self.stick) then
		return false
	end
	return self:Begin(input, false)
end

function Controller.OnStickBegan(self: Controller, input: InputObject): ()
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		self:Begin(input, true)
	end
end

function Controller.OnInputChanged(self: Controller, input: InputObject): boolean
	if self.input ~= input or not self.stickOrigin then
		return false
	end
	self:Measure(input)
	return true
end

function Controller.OnInputEnded(self: Controller, input: InputObject): boolean
	if input ~= self.input then
		return false
	end
	if self.stickOrigin then
		self:Measure(input)
	end
	local direction = self:AimDirection()
	local commit = input.UserInputState ~= Enum.UserInputState.Cancel and self:GestureMatches() and direction ~= nil
	local target, version = self.gestureId, self.gestureVersion
	self:Cancel()
	if not commit or not target or not version or not direction then
		return true
	end
	self.nextThrow = workspace:GetServerTimeNow() + Config.CooldownSeconds
	Net.FireRequest({ action = "Throw", target = target, version = version, direction = direction })
	return true
end

function Controller.new(stick: Frame, host: Host): Controller
	local knob = stick:WaitForChild("StickButton"):WaitForChild("KnobImage") :: GuiObject
	local self = setmetatable({
		host = host,
		preview = Preview.new(),
		stick = stick,
		knob = knob,
		input = nil,
		inputConnection = nil,
		equipConnection = nil,
		stickConnection = nil :: RBXScriptConnection?,
		gestureCharacter = nil,
		gestureId = nil,
		gestureVersion = nil,
		stickOrigin = nil,
		stickVector = Vector2.zero,
		stickDragged = false,
		forward = Vector3.zAxis,
		direction = Vector3.zAxis,
		nextThrow = 0,
	}, Controller)
	local button = stick:WaitForChild("StickButton") :: ImageButton
	local function OnStick(input: InputObject): ()
		self:OnStickBegan(input)
	end
	self.stickConnection = button.InputBegan:Connect(OnStick)
	return self
end

function Controller.Destroy(self: Controller): ()
	self:Cancel()
	if self.stickConnection then
		self.stickConnection:Disconnect()
		self.stickConnection = nil
	end
	self.preview:Destroy()
	self.stick = nil
	self.knob = nil
end

return Controller
