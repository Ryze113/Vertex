local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local HttpService = cloneref(game:GetService("HttpService"))

local WindUI

do
	local ok, result = pcall(function()
		return require("./src/Init")
	end)

	if ok then
		WindUI = result
	else
		if cloneref(game:GetService("RunService")):IsStudio() then
			WindUI = require(cloneref(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init")))
		else
			WindUI =
				loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
		end
	end
end

-- ==================== FEATURE VARIABLEN ====================
local godModeActive = false
local invisibleActive = false
local freeCamActive = false
local cursorLocked = false
local originalWalkSpeed = 16
local originalJumpPower = 50

-- ==================== FREECAM TEMPLATE VARIABLEN ====================
local pi    = math.pi
local abs   = math.abs
local clamp = math.clamp
local exp   = math.exp
local rad   = math.rad
local sign  = math.sign
local sqrt  = math.sqrt
local tan   = math.tan

local FREECAM_ENABLED_ATTRIBUTE_NAME = "FreecamEnabled"
local TOGGLE_INPUT_PRIORITY = Enum.ContextActionPriority.Low.Value
local INPUT_PRIORITY = Enum.ContextActionPriority.High.Value
local FREECAM_MACRO_KB = {Enum.KeyCode.LeftShift, Enum.KeyCode.P}

local NAV_GAIN = Vector3.new(1, 1, 1)*64
local PAN_GAIN = Vector2.new(0.75, 1)*8
local FOV_GAIN = 300

local PITCH_LIMIT = rad(90)

local VEL_STIFFNESS = 1.5
local PAN_STIFFNESS = 1.0
local FOV_STIFFNESS = 4.0

-- ==================== SPRING CLASS ====================
local Spring = {} do
	Spring.__index = Spring

	function Spring.new(freq, pos)
		local self = setmetatable({}, Spring)
		self.f = freq
		self.p = pos
		self.v = pos*0
		return self
	end

	function Spring:Update(dt, goal)
		local f = self.f*2*pi
		local p0 = self.p
		local v0 = self.v

		local offset = goal - p0
		local decay = exp(-f*dt)

		local p1 = goal + (v0*dt - offset*(f*dt + 1))*decay
		local v1 = (f*dt*(offset*f - v0) + v0)*decay

		self.p = p1
		self.v = v1

		return p1
	end

	function Spring:Reset(pos)
		self.p = pos
		self.v = pos*0
	end
end

-- ==================== FREECAM VARIABLEN ====================
local cameraPos = Vector3.new()
local cameraRot = Vector2.new()
local cameraFov = 0

local velSpring = Spring.new(VEL_STIFFNESS, Vector3.new())
local panSpring = Spring.new(PAN_STIFFNESS, Vector2.new())
local fovSpring = Spring.new(FOV_STIFFNESS, 0)

-- ==================== FREECAM INPUT ====================
local Input = {} do
	local thumbstickCurve do
		local K_CURVATURE = 2.0
		local K_DEADZONE = 0.15

		local function fCurve(x)
			return (exp(K_CURVATURE*x) - 1)/(exp(K_CURVATURE) - 1)
		end

		local function fDeadzone(x)
			return fCurve((x - K_DEADZONE)/(1 - K_DEADZONE))
		end

		function thumbstickCurve(x)
			return sign(x)*clamp(fDeadzone(abs(x)), 0, 1)
		end
	end

	local gamepad = {
		ButtonX = 0,
		ButtonY = 0,
		DPadDown = 0,
		DPadUp = 0,
		ButtonL2 = 0,
		ButtonR2 = 0,
		Thumbstick1 = Vector2.new(),
		Thumbstick2 = Vector2.new(),
	}

	local keyboard = {
		W = 0,
		A = 0,
		S = 0,
		D = 0,
		E = 0,
		Q = 0,
		U = 0,
		H = 0,
		J = 0,
		K = 0,
		I = 0,
		Y = 0,
		Up = 0,
		Down = 0,
		LeftShift = 0,
		RightShift = 0,
	}

	local mouse = {
		Delta = Vector2.new(),
		MouseWheel = 0,
	}

	local NAV_GAMEPAD_SPEED  = Vector3.new(1, 1, 1)
	local NAV_KEYBOARD_SPEED = Vector3.new(1, 1, 1)
	local PAN_MOUSE_SPEED    = Vector2.new(1, 1)*(pi/64)
	local PAN_GAMEPAD_SPEED  = Vector2.new(1, 1)*(pi/8)
	local FOV_WHEEL_SPEED    = 1.0
	local FOV_GAMEPAD_SPEED  = 0.25
	local NAV_ADJ_SPEED      = 0.75
	local NAV_SHIFT_MUL      = 0.25

	local navSpeed = 1

	function Input.Vel(dt)
		navSpeed = clamp(navSpeed + dt*(keyboard.Up - keyboard.Down)*NAV_ADJ_SPEED, 0.01, 4)

		local kGamepad = Vector3.new(
			thumbstickCurve(gamepad.Thumbstick1.X),
			thumbstickCurve(gamepad.ButtonR2) - thumbstickCurve(gamepad.ButtonL2),
			thumbstickCurve(-gamepad.Thumbstick1.Y)
		)*NAV_GAMEPAD_SPEED

		local kKeyboard = Vector3.new(
			keyboard.D - keyboard.A + keyboard.K - keyboard.H,
			keyboard.E - keyboard.Q + keyboard.I - keyboard.Y,
			keyboard.S - keyboard.W + keyboard.J - keyboard.U
		)*NAV_KEYBOARD_SPEED

		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

		return (kGamepad + kKeyboard)*(navSpeed*(shift and NAV_SHIFT_MUL or 1))
	end

	function Input.Pan(dt)
		local kGamepad = Vector2.new(
			thumbstickCurve(gamepad.Thumbstick2.Y),
			thumbstickCurve(-gamepad.Thumbstick2.X)
		)*PAN_GAMEPAD_SPEED
		local kMouse = mouse.Delta*PAN_MOUSE_SPEED
		mouse.Delta = Vector2.new()
		return kGamepad + kMouse
	end

	function Input.Fov(dt)
		local kGamepad = (gamepad.ButtonX - gamepad.ButtonY)*FOV_GAMEPAD_SPEED
		local kMouse = mouse.MouseWheel*FOV_WHEEL_SPEED
		mouse.MouseWheel = 0
		return kGamepad + kMouse
	end

	do
		local function Keypress(action, state, input)
			keyboard[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
			return Enum.ContextActionResult.Sink
		end

		local function GpButton(action, state, input)
			gamepad[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
			return Enum.ContextActionResult.Sink
		end

		local function MousePan(action, state, input)
			local delta = input.Delta
			mouse.Delta = Vector2.new(-delta.y, -delta.x)
			return Enum.ContextActionResult.Sink
		end

		local function Thumb(action, state, input)
			gamepad[input.KeyCode.Name] = input.Position
			return Enum.ContextActionResult.Sink
		end

		local function Trigger(action, state, input)
			gamepad[input.KeyCode.Name] = input.Position.z
			return Enum.ContextActionResult.Sink
		end

		local function MouseWheel(action, state, input)
			mouse[input.UserInputType.Name] = -input.Position.z
			return Enum.ContextActionResult.Sink
		end

		local function Zero(t)
			for k, v in pairs(t) do
				t[k] = v*0
			end
		end

		function Input.StartCapture()
			ContextActionService:BindActionAtPriority("FreecamKeyboard", Keypress, false, INPUT_PRIORITY,
				Enum.KeyCode.W, Enum.KeyCode.U,
				Enum.KeyCode.A, Enum.KeyCode.H,
				Enum.KeyCode.S, Enum.KeyCode.J,
				Enum.KeyCode.D, Enum.KeyCode.K,
				Enum.KeyCode.E, Enum.KeyCode.I,
				Enum.KeyCode.Q, Enum.KeyCode.Y,
				Enum.KeyCode.Up, Enum.KeyCode.Down
			)
			ContextActionService:BindActionAtPriority("FreecamMousePan",          MousePan,   false, INPUT_PRIORITY, Enum.UserInputType.MouseMovement)
			ContextActionService:BindActionAtPriority("FreecamMouseWheel",        MouseWheel, false, INPUT_PRIORITY, Enum.UserInputType.MouseWheel)
			ContextActionService:BindActionAtPriority("FreecamGamepadButton",     GpButton,   false, INPUT_PRIORITY, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY)
			ContextActionService:BindActionAtPriority("FreecamGamepadTrigger",    Trigger,    false, INPUT_PRIORITY, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)
			ContextActionService:BindActionAtPriority("FreecamGamepadThumbstick", Thumb,      false, INPUT_PRIORITY, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2)
		end

		function Input.StopCapture()
			navSpeed = 1
			Zero(gamepad)
			Zero(keyboard)
			Zero(mouse)
			ContextActionService:UnbindAction("FreecamKeyboard")
			ContextActionService:UnbindAction("FreecamMousePan")
			ContextActionService:UnbindAction("FreecamMouseWheel")
			ContextActionService:UnbindAction("FreecamGamepadButton")
			ContextActionService:UnbindAction("FreecamGamepadTrigger")
			ContextActionService:UnbindAction("FreecamGamepadThumbstick")
		end
	end
end

-- ==================== FREECAM FUNKTIONEN ====================
local function StepFreecam(dt)
	local vel = velSpring:Update(dt, Input.Vel(dt))
	local pan = panSpring:Update(dt, Input.Pan(dt))
	local fov = fovSpring:Update(dt, Input.Fov(dt))

	local zoomFactor = sqrt(tan(rad(70/2))/tan(rad(cameraFov/2)))

	cameraFov = clamp(cameraFov + fov*FOV_GAIN*(dt/zoomFactor), 1, 120)
	cameraRot = cameraRot + pan*PAN_GAIN*(dt/zoomFactor)
	cameraRot = Vector2.new(clamp(cameraRot.x, -PITCH_LIMIT, PITCH_LIMIT), cameraRot.y%(2*pi))

	local cameraCFrame = CFrame.new(cameraPos)*CFrame.fromOrientation(cameraRot.x, cameraRot.y, 0)*CFrame.new(vel*NAV_GAIN*dt)
	cameraPos = cameraCFrame.p

	Camera.CFrame = cameraCFrame
	Camera.Focus = cameraCFrame 
	Camera.FieldOfView = cameraFov
end

local PlayerState = {} do
	local mouseBehavior
	local mouseIconEnabled
	local cameraType
	local cameraFocus
	local cameraCFrame
	local cameraFieldOfView
	local screenGuis = {}
	local coreGuis = {
		Backpack = true,
		Chat = true,
		Health = true,
		PlayerList = true,
	}
	local setCores = {
		BadgesNotificationsActive = true,
		PointsNotificationsActive = true,
	}

	function PlayerState.Push()
		for name in pairs(coreGuis) do
			coreGuis[name] = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType[name])
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], false)
		end
		for name in pairs(setCores) do
			setCores[name] = StarterGui:GetCore(name)
			StarterGui:SetCore(name, false)
		end
		local playergui = player:FindFirstChildOfClass("PlayerGui")
		if playergui then
			for _, gui in pairs(playergui:GetChildren()) do
				if gui:IsA("ScreenGui") and gui.Enabled then
					screenGuis[#screenGuis + 1] = gui
					gui.Enabled = false
				end
			end
		end

		cameraFieldOfView = Camera.FieldOfView
		Camera.FieldOfView = 70

		cameraType = Camera.CameraType
		Camera.CameraType = Enum.CameraType.Custom

		cameraCFrame = Camera.CFrame
		cameraFocus = Camera.Focus

		mouseIconEnabled = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = false

		mouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	function PlayerState.Pop()
		for name, isEnabled in pairs(coreGuis) do
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], isEnabled)
		end
		for name, isEnabled in pairs(setCores) do
			StarterGui:SetCore(name, isEnabled)
		end
		for _, gui in pairs(screenGuis) do
			if gui.Parent then
				gui.Enabled = true
			end
		end

		Camera.FieldOfView = cameraFieldOfView
		cameraFieldOfView = nil

		Camera.CameraType = cameraType
		cameraType = nil

		Camera.CFrame = cameraCFrame
		cameraCFrame = nil

		Camera.Focus = cameraFocus
		cameraFocus = nil

		UserInputService.MouseIconEnabled = mouseIconEnabled
		mouseIconEnabled = nil

		UserInputService.MouseBehavior = mouseBehavior
		mouseBehavior = nil
	end
end

-- ==================== FREECAM TOGGLE ====================
local function StartFreecam()
	if freeCamActive then return end
	
	freeCamActive = true
	print("FreeCam aktiviert")
	
	if humanoid then
		originalWalkSpeed = humanoid.WalkSpeed
		originalJumpPower = humanoid.JumpPower
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.PlatformStand = true
	end

	local cameraCFrame = Camera.CFrame
	cameraRot = Vector2.new(cameraCFrame:toEulerAnglesYXZ())
	cameraPos = cameraCFrame.p
	cameraFov = Camera.FieldOfView

	velSpring:Reset(Vector3.new())
	panSpring:Reset(Vector2.new())
	fovSpring:Reset(0)

	PlayerState.Push()
	RunService:BindToRenderStep("Freecam", Enum.RenderPriority.Camera.Value, StepFreecam)
	Input.StartCapture()
	
	cursorLocked = false
end

local function StopFreecam()
	if not freeCamActive then return end
	
	freeCamActive = false
	print("FreeCam deaktiviert")
	
	if humanoid then
		humanoid.WalkSpeed = originalWalkSpeed
		humanoid.JumpPower = originalJumpPower
		humanoid.PlatformStand = false
	end

	Input.StopCapture()
	RunService:UnbindFromRenderStep("Freecam")
	PlayerState.Pop()
	
	cursorLocked = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = false
end

-- ==================== FEATURE FUNKTIONEN ====================

-- GodMode Funktion
local function toggleGodMode(state)
	godModeActive = state
	if state then
		if humanoid then
			humanoid.MaxHealth = math.huge
			humanoid.Health = math.huge
			humanoid.BreakJointsOnDeath = false
		end
		WindUI:Notify({
			Title = "God Mode",
			Content = "God Mode aktiviert!",
			Icon = "shield-check",
			Duration = 3,
		})
	else
		if humanoid then
			humanoid.MaxHealth = 100
			humanoid.Health = 100
			humanoid.BreakJointsOnDeath = true
		end
		WindUI:Notify({
			Title = "God Mode",
			Content = "God Mode deaktiviert!",
			Icon = "shield-off",
			Duration = 3,
		})
	end
end

-- Invisible Funktion
local function toggleInvisible(state)
	invisibleActive = state
	if character then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = state and 1 or 0
			end
			if part:IsA("Accessory") or part:IsA("Clothing") then
				part.Enabled = not state
			end
		end
		if character:FindFirstChild("HumanoidRootPart") then
			character.HumanoidRootPart.Transparency = state and 1 or 0
			character.HumanoidRootPart.CanCollide = not state
		end
	end
	WindUI:Notify({
		Title = "Invisible",
		Content = state and "Unsichtbar aktiviert!" or "Unsichtbar deaktiviert!",
		Icon = state and "eye-closed" or "eye",
		Duration = 3,
	})
end

-- FreeCam Toggle
local function toggleFreeCam(state)
	if state then
		StartFreecam()
	else
		StopFreecam()
	end
	WindUI:Notify({
		Title = "FreeCam",
		Content = state and "FreeCam aktiviert! (R für Cursor)" or "FreeCam deaktiviert!",
		Icon = state and "camera" or "camera-off",
		Duration = 3,
	})
end

-- ==================== CURSOR TOGGLE (NUR IN FREECAM) ====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.R then
		if freeCamActive then
			cursorLocked = not cursorLocked
			if cursorLocked then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
				WindUI:Notify({
					Title = "Cursor",
					Content = "Maus-Cursor aktiviert",
					Icon = "mouse",
					Duration = 2,
				})
			else
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = false
				WindUI:Notify({
					Title = "Cursor",
					Content = "Maus-Cursor deaktiviert",
					Icon = "mouse-off",
					Duration = 2,
				})
			end
		end
	end
end)

-- ==================== WINDOW ====================
local Window = WindUI:CreateWindow({
	Title = "Vertex Menu",
	Folder = "Vertex",
	Icon = "solar:folder-2-bold-duotone",
	NewElements = true,

	OpenButton = {
		Title = "Open Vertex Menu",
		CornerRadius = UDim.new(1, 0),
		StrokeThickness = 3,
		Enabled = true,
		Draggable = true,
		OnlyMobile = false,
		Scale = 0.5,
		Color = ColorSequence.new(
			Color3.fromHex("#FF4B69"),
			Color3.fromHex("#825AFF")
		),
	},
	Topbar = {
		Height = 44,
		ButtonsType = "Mac",
	},
})

-- Tags
Window:Tag({
	Title = "v1.0",
	Icon = "github",
	Color = Color3.fromHex("#1c1c1c"),
	Border = true,
})

-- ==================== TABS ====================

-- Player Tab
local PlayerTab = Window:Tab({
	Title = "Player",
	Icon = "solar:user-bold",
	IconColor = Color3.fromHex("#FF4B69"),
	IconShape = "Square",
	Border = true,
})

-- Player Options Section
local PlayerSection = PlayerTab:Section({
	Title = "Player Options",
})

-- God Mode Toggle
PlayerSection:Toggle({
	Title = "God Mode",
	Desc = "Macht dich unsterblich",
	Icon = "shield-check",
	Value = false,
	Callback = function(state)
		toggleGodMode(state)
	end,
})

PlayerSection:Space()

-- Invisible Toggle
PlayerSection:Toggle({
	Title = "Invisible",
	Desc = "Macht dich unsichtbar für andere Spieler",
	Icon = "eye-closed",
	Value = false,
	Callback = function(state)
		toggleInvisible(state)
	end,
})

PlayerSection:Space()

-- FreeCam Toggle
PlayerSection:Toggle({
	Title = "FreeCam",
	Desc = "Aktiviere freie Kamerabewegung (R für Cursor)",
	Icon = "camera",
	Value = false,
	Callback = function(state)
		toggleFreeCam(state)
	end,
})

-- ==================== INFORMATION TAB ====================
local InfoTab = Window:Tab({
	Title = "Info",
	Icon = "solar:info-square-bold",
	IconColor = Color3.fromHex("#825AFF"),
	IconShape = "Square",
	Border = true,
})

local InfoSection = InfoTab:Section({
	Title = "About Vertex",
})

InfoSection:Image({
	Image = "https://repository-images.githubusercontent.com/880118829/22c020eb-d1b1-4b34-ac4d-e33fd88db38d",
	AspectRatio = "16:9",
	Radius = 9,
})

InfoSection:Space({ Columns = 3 })

InfoSection:Section({
	Title = "Vertex Menu",
	TextSize = 24,
	FontWeight = Enum.FontWeight.SemiBold,
})

InfoSection:Space()

InfoSection:Section({
	Title = "Ein modernes Roblox Script Hub Interface.\nEntwickelt mit WindUI.\n\nFeatures:\n• God Mode\n• Invisible\n• FreeCam\n\nVersion: 1.0",
	TextSize = 18,
	TextTransparency = 0.35,
	FontWeight = Enum.FontWeight.Medium,
})

InfoTab:Space({ Columns = 4 })

InfoTab:Button({
	Title = "Destroy Window",
	Color = Color3.fromHex("#ff4830"),
	Justify = "Center",
	Icon = "shredder",
	IconAlign = "Left",
	Callback = function()
		Window:Destroy()
	end,
})
