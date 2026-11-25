-- 移动端自研跳跃控制与原生跳跃键屏蔽：固定画布跳跃长按连跳并保留左摇杆
--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lifecycle = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared"):WaitForChild("LifecycleTool"))

local Controller = {}
Controller.__index = Controller

export type Controller = typeof(setmetatable(
	{} :: {
		scope: Lifecycle.Lifecycle,
		suppressed: { [GuiObject]: Lifecycle.Lifecycle },
		jumpButton: ImageButton,
		canJump: () -> boolean,
		activeInput: InputObject?,
		inputStateConn: RBXScriptConnection?,
		holdConn: RBXScriptConnection?,
		destroyed: boolean,
	},
	Controller
))

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

local function SuppressNativeJump(button: GuiObject): ()
	button.Visible = false
	button.Active = false
	button.Selectable = false
	button.Position = UDim2.fromOffset(-9999, -9999)
end

function Controller.Stop(self: Controller): ()
	if self.inputStateConn then
		self.inputStateConn:Disconnect()
		self.inputStateConn = nil
	end
	if self.holdConn then
		self.holdConn:Disconnect()
		self.holdConn = nil
	end
	self.activeInput = nil
end

function Controller.new(jumpButton: ImageButton, canJump: () -> boolean): Controller
	local player = Players.LocalPlayer
	assert(player, "TouchJumpController requires a local player")
	local playerGui = player:WaitForChild("PlayerGui")
	local self: Controller = setmetatable(
		{
			scope = Lifecycle.new(),
			suppressed = {},
			jumpButton = jumpButton,
			canJump = canJump,
			activeInput = nil :: InputObject?,
			inputStateConn = nil :: RBXScriptConnection?,
			holdConn = nil :: RBXScriptConnection?,
			destroyed = false,
		},
		Controller
	)

	local function WatchNativeJump(instance: Instance): ()
		if self.destroyed or instance.Name ~= "JumpButton" or not instance:IsA("GuiObject") then
			return
		end
		if not instance:FindFirstAncestor("TouchGui") then
			return
		end
		if self.suppressed[instance] then
			SuppressNativeJump(instance)
			return
		end
		local entryScope = Lifecycle.new()
		self.suppressed[instance] = entryScope
		local function Enforce(): ()
			if not self.destroyed and instance.Parent and instance:FindFirstAncestor("TouchGui") then
				SuppressNativeJump(instance)
			end
		end
		entryScope:Connect(instance:GetPropertyChangedSignal("Visible"):Connect(Enforce))
		entryScope:Connect(instance.AncestryChanged:Connect(function(): ()
			if instance.Parent == nil or not instance:FindFirstAncestor("TouchGui") then
				entryScope:Destroy()
				self.suppressed[instance] = nil
			else
				Enforce()
			end
		end))
		Enforce()
	end

	for _, instance in playerGui:GetDescendants() do
		WatchNativeJump(instance)
	end
	self.scope:Connect(playerGui.DescendantAdded:Connect(WatchNativeJump))

	local function TriggerJump(): ()
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			humanoid.Jump = true
		end
	end

	self.scope:Connect(jumpButton.InputBegan:Connect(function(input: InputObject): ()
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if self.destroyed or self.activeInput ~= nil or not self.canJump() or not IsEffectivelyVisible(jumpButton) then
			return
		end
		self.activeInput = input
		TriggerJump()
		self.inputStateConn = input:GetPropertyChangedSignal("UserInputState"):Connect(function(): ()
			if self.activeInput == input and (input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel) then
				self:Stop()
			end
		end)
		self.holdConn = RunService.RenderStepped:Connect(function(): ()
			if self.destroyed or self.activeInput == nil or not self.canJump() or not IsEffectivelyVisible(jumpButton) then
				self:Stop()
				return
			end
			TriggerJump()
		end)
	end))

	self.scope:Connect(UserInputService.InputEnded:Connect(function(input: InputObject): ()
		if input == self.activeInput then
			self:Stop()
		end
	end))
	self.scope:Connect(GuiService.MenuOpened:Connect(function(): ()
		self:Stop()
	end))
	self.scope:Connect(UserInputService.WindowFocusReleased:Connect(function(): ()
		self:Stop()
	end))
	self.scope:Connect(player:GetAttributeChangedSignal("Painting"):Connect(function(): ()
		if player:GetAttribute("Painting") == true then
			self:Stop()
		end
	end))
	self.scope:Connect(player.CharacterRemoving:Connect(function(): ()
		self:Stop()
	end))
	self.scope:Connect(player.CharacterAdded:Connect(function(): ()
		self:Stop()
	end))

	local watched: { Instance? } = {
		jumpButton,
		jumpButton.Parent,
		if jumpButton.Parent then jumpButton.Parent.Parent else nil,
	}
	for _, node in watched do
		if node and node:IsA("GuiObject") then
			local guiObj = node
			self.scope:Connect(guiObj:GetPropertyChangedSignal("Visible"):Connect(function(): ()
				if not guiObj.Visible then
					self:Stop()
				end
			end))
		end
	end

	return self
end

function Controller.Destroy(self: Controller): ()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:Stop()
	self.scope:Destroy()
	for _, entryScope in self.suppressed do
		entryScope:Destroy()
	end
	table.clear(self.suppressed)
end

return Controller
