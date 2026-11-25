-- 按本地输入发送冲刺意图并显示服务端耐力
--!strict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Config = require(Shared.GameConfig)
local Lifecycle = require(Shared.LifecycleTool)
local Net = require(Shared.ProcessingNet)
local Rules = require(Shared.PersonalUpgradeRules)

local Sprint = {}
local player = Players.LocalPlayer
local ActionName = "DemonShopSprint"

function Sprint.Init(hud: Frame, button: ImageButton, modal: GuiButton?, scope: Lifecycle.Lifecycle): () -> ()
	local stamina = hud:FindFirstChild("StaminaFrame") :: Frame
	local track = stamina:FindFirstChild("TrackFrame") :: Frame
	local fill = track:FindFirstChild("FillFrame") :: Frame
	local idleColor = button:GetAttribute("IdleColor") :: Color3
	local activeColor = button:GetAttribute("ActiveColor") :: Color3
	local characterScope = Lifecycle.new()
	local requested = false
	local humanoid: Humanoid? = nil

	local function CanSprint(): boolean
		return player:GetAttribute("Painting") ~= true and not GuiService.MenuIsOpen
			and (modal == nil or not modal.Visible) and humanoid ~= nil and humanoid.Health > 0
	end

	local function Request(wanted: boolean): ()
		if requested ~= wanted then
			requested = wanted
			Net.RequestSprint(wanted)
		end
	end

	local function Refresh(): ()
		local character = player.Character
		local canSprint = CanSprint()
		if not canSprint then Request(false) end
		local active = character ~= nil and character:GetAttribute("PersonalSprinting") == true
		local energy = if character then character:GetAttribute("PersonalStamina") :: number? else nil
		local level = if character then character:GetAttribute("Upgrade_moveSpeed") :: number? else nil
		button.Visible = canSprint and UserInputService.PreferredInput == Enum.PreferredInput.Touch
		button.ImageColor3 = if active then activeColor else idleColor
		stamina.Visible = canSprint and energy ~= nil and not Rules.GetMoveTier(level or 1).unlimited
			and (active or energy < Config.Sprint.stamina)
		fill.Size = UDim2.fromScale(math.clamp((energy or Config.Sprint.stamina) / Config.Sprint.stamina, 0, 1), 1)
	end

	local function OnCharacter(character: Model): ()
		characterScope:Destroy()
		characterScope = Lifecycle.new()
		requested = false -- 新角色的服务端冲刺状态已重置。
		local function OnHumanoid(): ()
			local current = character:FindFirstChildOfClass("Humanoid")
			if current and current ~= humanoid then
				humanoid = current
				characterScope:Connect(current.Died:Connect(Refresh))
				Refresh()
			end
		end
		humanoid = nil
		characterScope:Connect(character.ChildAdded:Connect(OnHumanoid))
		for _, attribute in {"PersonalSprinting", "PersonalStamina", "Upgrade_moveSpeed"} do
			characterScope:Connect(character:GetAttributeChangedSignal(attribute):Connect(Refresh))
		end
		OnHumanoid()
		Refresh()
	end

	local function OnSprintAction(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			Request(false)
		end
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin and CanSprint() then Request(true) end
		return Enum.ContextActionResult.Sink
	end
	local function Stop(): () Request(false) end
	local function OnPreferredInput(): ()
		Stop()
		Refresh()
	end
	local function OnToggle(): ()
		if CanSprint() then Request(not requested) end
	end
	local function OnRemoving(): ()
		Stop()
		characterScope:Destroy()
		humanoid = nil
		Refresh()
	end
	if modal then scope:Connect(modal:GetPropertyChangedSignal("Visible"):Connect(Refresh)) end
	scope:Connect(GuiService.MenuOpened:Connect(Refresh))
	scope:Connect(GuiService.MenuClosed:Connect(Refresh))
	scope:Connect(player:GetAttributeChangedSignal("Painting"):Connect(Refresh))
	scope:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(OnPreferredInput))
	ContextActionService:BindActionAtPriority(ActionName, OnSprintAction, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift)
	scope:Connect(UserInputService.WindowFocusReleased:Connect(Stop))
	scope:Connect(UserInputService.TextBoxFocused:Connect(Stop))
	scope:Connect(player.CharacterAdded:Connect(OnCharacter))
	scope:Connect(player.CharacterRemoving:Connect(OnRemoving))
	scope:Connect(button.Activated:Connect(OnToggle))
	if player.Character then OnCharacter(player.Character) end

	return function(): ()
		ContextActionService:UnbindAction(ActionName)
		Stop()
		characterScope:Destroy()
	end
end

return Sprint
