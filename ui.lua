local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Camera = Workspace.CurrentCamera
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")

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
local freeCamConnection = nil
local originalCFrame = nil

-- ==================== FREECAM VARIABLEN ====================
local cameraPos = Vector3.new()
local cameraRot = Vector2.new()

-- ==================== FREECAM FUNKTIONEN ====================

-- FreeCam Toggle
local function StartFreecam()
	if freeCamActive then return end
	
	freeCamActive = true
	print("FreeCam aktiviert")
	
	-- Character Bewegung deaktivieren
	if humanoid then
		originalWalkSpeed = humanoid.WalkSpeed
		originalJumpPower = humanoid.JumpPower
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.PlatformStand = true
	end
	
	-- Character unsichtbar machen für FreeCam
	if character then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 1
			end
		end
	end
	
	-- Originale Kamera speichern
	originalCFrame = Camera.CFrame
	
	-- Kamera von Character lösen
	Camera.CameraType = Enum.CameraType.Scriptable
	
	-- FreeCam Position setzen
	local cameraCFrame = Camera.CFrame
	cameraPos = cameraCFrame.p
	cameraRot = Vector2.new(cameraCFrame:toEulerAnglesYXZ())
	
	-- Maussteuerung für FreeCam
	local function handleMouseMove(inputObject, gameProcessed)
		if gameProcessed then return end
		if not freeCamActive then return end
		
		local delta = UserInputService:GetMouseDelta()
		if delta.X ~= 0 or delta.Y ~= 0 then
			local sensitivity = 0.003
			local yaw = -delta.X * sensitivity
			local pitch = -delta.Y * sensitivity
			
			cameraRot = cameraRot + Vector2.new(pitch, yaw)
			cameraRot = Vector2.new(
				math.clamp(cameraRot.X, -math.pi/2, math.pi/2),
				cameraRot.Y
			)
			
			local newCFrame = CFrame.new(cameraPos) * CFrame.fromOrientation(cameraRot.X, cameraRot.Y, 0)
			Camera.CFrame = newCFrame
		end
	end
	
	-- Tastatursteuerung für FreeCam
	local moveForward = false
	local moveBackward = false
	local moveLeft = false
	local moveRight = false
	local moveUp = false
	local moveDown = false
	local freeCamSpeed = 50
	
	local function onKeyDown(input, event)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local key = input.KeyCode
			if key == Enum.KeyCode.W then moveForward = true end
			if key == Enum.KeyCode.S then moveBackward = true end
			if key == Enum.KeyCode.A then moveLeft = true end
			if key == Enum.KeyCode.D then moveRight = true end
			if key == Enum.KeyCode.Space then moveUp = true end
			if key == Enum.KeyCode.LeftShift then moveDown = true end
			if key == Enum.KeyCode.R then
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
		end
	end
	
	local function onKeyUp(input, event)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local key = input.KeyCode
			if key == Enum.KeyCode.W then moveForward = false end
			if key == Enum.KeyCode.S then moveBackward = false end
			if key == Enum.KeyCode.A then moveLeft = false end
			if key == Enum.KeyCode.D then moveRight = false end
			if key == Enum.KeyCode.Space then moveUp = false end
			if key == Enum.KeyCode.LeftShift then moveDown = false end
		end
	end
	
	UserInputService.InputBegan:Connect(onKeyDown)
	UserInputService.InputEnded:Connect(onKeyUp)
	
	-- Mouse Movement für Rotation
	local mouseConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and freeCamActive then
			handleMouseMove(input, false)
		end
	end)
	
	-- FreeCam Update Loop
	freeCamConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not freeCamActive then return end
		
		local direction = Vector3.new()
		local lookVector = Camera.CFrame.LookVector
		local rightVector = Camera.CFrame.RightVector
		
		if moveForward then direction = direction + lookVector end
		if moveBackward then direction = direction - lookVector end
		if moveLeft then direction = direction - rightVector end
		if moveRight then direction = direction + rightVector end
		if moveUp then direction = direction + Vector3.new(0, 1, 0) end
		if moveDown then direction = direction - Vector3.new(0, 1, 0) end
		
		if direction.Magnitude > 0 then
			direction = direction.Unit * freeCamSpeed * deltaTime
			cameraPos = cameraPos + direction
			local newCFrame = CFrame.new(cameraPos) * CFrame.fromOrientation(cameraRot.X, cameraRot.Y, 0)
			Camera.CFrame = newCFrame
		end
	end)
	
	WindUI:Notify({
		Title = "FreeCam",
		Content = "FreeCam aktiviert! (WASD Bewegung, Maus Rotation, R für Cursor)",
		Icon = "camera",
		Duration = 3,
	})
end

local function StopFreecam()
	if not freeCamActive then return end
	
	freeCamActive = false
	print("FreeCam deaktiviert")
	
	-- Character Bewegung wieder aktivieren
	if humanoid then
		humanoid.WalkSpeed = originalWalkSpeed
		humanoid.JumpPower = originalJumpPower
		humanoid.PlatformStand = false
	end
	
	-- Character wieder sichtbar machen
	if character then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 0
			end
		end
	end
	
	-- FreeCam Connections beenden
	if freeCamConnection then
		freeCamConnection:Disconnect()
		freeCamConnection = nil
	end
	
	-- Kamera zurücksetzen
	if originalCFrame then
		Camera.CFrame = originalCFrame
		originalCFrame = nil
	end
	
	Camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = false
	cursorLocked = false
	
	WindUI:Notify({
		Title = "FreeCam",
		Content = "FreeCam deaktiviert!",
		Icon = "camera-off",
		Duration = 3,
	})
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

-- Invisible Funktion (fixed - alle Teile werden unsichtbar)
local function toggleInvisible(state)
	invisibleActive = state
	if character then
		-- Alle Teile des Charakters finden und transparent machen
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = state and 1 or 0
			end
			-- Accessoires und Kleidung verstecken
			if part:IsA("Accessory") or part:IsA("Clothing") then
				part.Enabled = not state
			end
			-- Haare verstecken (Accessoires sind oft als Accessory klassifiziert)
			if part:IsA("Model") and part:FindFirstChild("Handle") then
				for _, child in ipairs(part:GetDescendants()) do
					if child:IsA("BasePart") then
						child.Transparency = state and 1 or 0
					end
				end
			end
		end
		-- HumanoidRootPart speziell behandeln
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

-- ==================== CURSOR TOGGLE (NUR IN FREECAM) ====================
-- Wird jetzt in der FreeCam Funktion behandelt

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

-- Home Tab
local HomeTab = Window:Tab({
	Title = "Home",
	Icon = "solar:home-2-bold",
	IconColor = Color3.fromHex("#FFFFFF"),
	IconShape = "Square",
	Border = true,
})

local HomeSection = HomeTab:Section({
	Title = "Welcome to Vertex",
})

HomeSection:Section({
	Title = "Vertex Menu",
	TextSize = 28,
	FontWeight = Enum.FontWeight.Bold,
})

HomeSection:Space()

HomeSection:Section({
	Title = "Ein modernes Roblox Script Hub Interface.\n\nWähle einen Tab aus der Sidebar um zu beginnen.",
	TextSize = 18,
	TextTransparency = 0.35,
	FontWeight = Enum.FontWeight.Medium,
})

-- ==================== PLAYER OPTIONS TAB ====================
local PlayerOptionsTab = Window:Tab({
	Title = "Player Options",
	Icon = "solar:user-bold",
	IconColor = Color3.fromHex("#FF4B69"),
	IconShape = "Square",
	Border = true,
})

local PlayerSection = PlayerOptionsTab:Section({
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
		if state then
			StartFreecam()
		else
			StopFreecam()
		end
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
