local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
local mouse = localPlayer:GetMouse()
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local moveUnitEvent = remotesFolder:WaitForChild("MoveUnit") :: RemoteEvent
local unitActionEvent = remotesFolder:WaitForChild("UnitAction") :: RemoteEvent
local createCountryEvent = remotesFolder:WaitForChild("CreateCountry") :: RemoteEvent

local selectedUnitId: string? = nil
local selectedUnitModel: Model? = nil
local selectionHighlight: Highlight? = nil
local movementMode = false
local ignoreNextWorldClick = false
local healthBarConnections: { [Model]: { RBXScriptConnection } } = {}
local unitActionGui: ScreenGui? = nil
local unitActionWindow: Frame? = nil
local unitActionTitle: TextLabel? = nil
local unitActionStatus: TextLabel? = nil
local unitActionList: Frame? = nil
local cityNameGui: ScreenGui? = nil
local cityNameWindow: Frame? = nil
local cityNameInput: TextBox? = nil
local countryMenuGui: ScreenGui? = nil
local countryNameInput: TextBox? = nil

local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "MovementHighlights"
highlightFolder.Parent = Workspace

local HEALTH_BAR_NAME = "UnitHealthBar"
local ACTION_BUTTONS = {
	{ Id = "FoundCity", Text = "Основать город", SettlerOnly = true },
	{ Id = "Move", Text = "Переместить" },
	{ Id = "Rest", Text = "Отдых" },
	{ Id = "Fortify", Text = "Укрепиться" },
	{ Id = "FortifyHeal", Text = "Укрепиться до исцеления" },
	{ Id = "Delete", Text = "Удалить юнита" },
}

local function getTileName(x: number, z: number): string
	return string.format("Tile_%03d_%03d", x, z)
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild("GeneratedMap") :: Folder?
end

local function getUnitsFolder(): Folder?
	return Workspace:FindFirstChild("Units") :: Folder?
end

local function getFirstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getTile(x: number, z: number): BasePart?
	local mapFolder = getMapFolder()
	if not mapFolder then
		return nil
	end

	local tile = mapFolder:FindFirstChild(getTileName(x, z))
	if tile and tile:IsA("BasePart") then
		return tile
	end

	return nil
end

local function findUnitModel(instance: Instance?): Model?
	local current = instance

	while current and current ~= Workspace do
		if current:IsA("Model") and current:GetAttribute("UnitId") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function findTile(instance: Instance?): BasePart?
	local current = instance

	while current and current ~= Workspace do
		if current:IsA("BasePart") and current:GetAttribute("GridX") and current:GetAttribute("GridZ") and current:GetAttribute("Biome") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function isOwnedUnit(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == localPlayer.UserId
end

local function isTileOccupied(x: number, z: number): boolean
	local unitsFolder = getUnitsFolder()
	if not unitsFolder then
		return false
	end

	for _, unitModel in unitsFolder:GetChildren() do
		if unitModel:GetAttribute("GridX") == x and unitModel:GetAttribute("GridZ") == z then
			return unitModel ~= selectedUnitModel
		end
	end

	return false
end

local function getUnitMaxHealth(model: Model): number
	local maxHealth = model:GetAttribute("MaxHealth")
	if typeof(maxHealth) == "number" and maxHealth > 0 then
		return maxHealth
	end

	local unitType = model:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	if unit then
		return unit.Health
	end

	return 1
end

local function updateHealthBar(model: Model)
	local adornee = model.PrimaryPart or getFirstBasePart(model)
	if not adornee then
		return
	end

	local healthBar = adornee:FindFirstChild(HEALTH_BAR_NAME)
	if not healthBar or not healthBar:IsA("BillboardGui") then
		return
	end

	local container = healthBar:FindFirstChild("Container")
	local fill = container and container:FindFirstChild("Fill")
	local label = healthBar:FindFirstChild("HealthText")
	if not container or not container:IsA("Frame") or not fill or not fill:IsA("Frame") then
		return
	end

	local maxHealth = getUnitMaxHealth(model)
	local health = model:GetAttribute("Health")
	if typeof(health) ~= "number" then
		health = maxHealth
	end

	local ratio = math.clamp(health / maxHealth, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)

	if ratio > 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(82, 214, 116)
	elseif ratio > 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(245, 195, 75)
	else
		fill.BackgroundColor3 = Color3.fromRGB(231, 74, 62)
	end

	if label and label:IsA("TextLabel") then
		label.Text = string.format("%d/%d", math.max(0, math.floor(health + 0.5)), math.floor(maxHealth + 0.5))
	end
end

local function createHealthBar(model: Model)
	if healthBarConnections[model] then
		updateHealthBar(model)
		return
	end

	local adornee = model.PrimaryPart or getFirstBasePart(model)
	if not adornee then
		return
	end

	local existing = adornee:FindFirstChild(HEALTH_BAR_NAME)
	if existing and existing:IsA("BillboardGui") then
		return
	end

	if existing then
		existing:Destroy()
	end

	local healthBar = Instance.new("BillboardGui")
	local _, modelSize = model:GetBoundingBox()
	healthBar.Name = HEALTH_BAR_NAME
	healthBar.AlwaysOnTop = true
	healthBar.Size = UDim2.fromOffset(74, 18)
	healthBar.StudsOffset = Vector3.new(0, modelSize.Y / 2 + 0.65, 0)
	healthBar.Parent = adornee

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	container.BorderSizePixel = 0
	container.Position = UDim2.fromScale(0.5, 1)
	container.Size = UDim2.new(1, 0, 0, 7)
	container.Parent = healthBar

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.25
	stroke.Thickness = 1
	stroke.Parent = container

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(82, 214, 116)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "HealthText"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Position = UDim2.fromOffset(0, 0)
	label.Size = UDim2.new(1, 0, 0, 10)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.35
	label.Parent = healthBar

	healthBarConnections[model] = {
		model:GetAttributeChangedSignal("Health"):Connect(function()
			updateHealthBar(model)
		end),
		model:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			updateHealthBar(model)
		end),
		model.Destroying:Connect(function()
			local connections = healthBarConnections[model]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				healthBarConnections[model] = nil
			end
		end),
	}

	updateHealthBar(model)
end

local function watchUnitsFolder(unitsFolder: Folder)
	for _, child in unitsFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("UnitId") then
			createHealthBar(child)
		end
	end

	unitsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			if child:GetAttribute("UnitId") then
				createHealthBar(child)
				return
			end

			local connection: RBXScriptConnection?
			connection = child:GetAttributeChangedSignal("UnitId"):Connect(function()
				if child:GetAttribute("UnitId") and connection then
					connection:Disconnect()
					createHealthBar(child)
				end
			end)
		end
	end)
end

local function clearMovementHighlights()
	for _, child in highlightFolder:GetChildren() do
		if child.Name == "MoveHighlight" then
			child:Destroy()
		end
	end
end

local function clearHighlights()
	highlightFolder:ClearAllChildren()

	if selectionHighlight then
		selectionHighlight:Destroy()
		selectionHighlight = nil
	end
end

local function canSelectedUnitEnter(tile: BasePart): boolean
	if not selectedUnitModel then
		return false
	end

	local unitType = selectedUnitModel:GetAttribute("UnitType")
	local biome = tile:GetAttribute("Biome")
	if typeof(unitType) ~= "string" or typeof(biome) ~= "string" then
		return false
	end

	return UnitConfig.Types[unitType].CanEnter[biome] == true
end

local function createMovementHighlight(tile: BasePart)
	local highlight = Instance.new("Part")
	highlight.Name = "MoveHighlight"
	highlight.Anchored = true
	highlight.CanCollide = false
	highlight.CanQuery = false
	highlight.Color = Color3.fromRGB(255, 226, 92)
	highlight.Material = Enum.Material.Neon
	highlight.Size = Vector3.new(MapConfig.Tile.Width, 0.08, MapConfig.Tile.Length)
	highlight.Transparency = 0.45
	highlight.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + 0.08, tile.Position.Z)
	highlight.Parent = highlightFolder
end

local function showMovementForSelectedUnit()
	if not selectedUnitModel then
		return
	end

	local unitType = selectedUnitModel:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	if not unit then
		return
	end

	local originX = selectedUnitModel:GetAttribute("GridX")
	local originZ = selectedUnitModel:GetAttribute("GridZ")
	if typeof(originX) ~= "number" or typeof(originZ) ~= "number" then
		return
	end

	for x = originX - unit.Movement, originX + unit.Movement do
		for z = originZ - unit.Movement, originZ + unit.Movement do
			local distance = math.abs(x - originX) + math.abs(z - originZ)
			if distance >= 1 and distance <= unit.Movement then
				local tile = getTile(x, z)
				if tile and canSelectedUnitEnter(tile) and not isTileOccupied(x, z) then
					createMovementHighlight(tile)
				end
			end
		end
	end
end

local function ensureUnitActionGui()
	if unitActionGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "UnitActionGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(1, 1)
	window.BackgroundColor3 = Color3.fromRGB(28, 31, 36)
	window.BorderSizePixel = 0
	window.Position = UDim2.new(1, -18, 1, -18)
	window.Size = UDim2.fromOffset(240, 284)
	window.Visible = false
	window.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 12)
	padding.Parent = window

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(232, 220, 170)
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Text = "Юнит"
	title.TextColor3 = Color3.fromRGB(255, 247, 214)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = window

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.Position = UDim2.fromOffset(0, 24)
	status.Size = UDim2.new(1, 0, 0, 18)
	status.Text = "Выберите действие"
	status.TextColor3 = Color3.fromRGB(198, 205, 214)
	status.TextSize = 12
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = window

	local list = Instance.new("Frame")
	list.Name = "Actions"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(0, 52)
	list.Size = UDim2.new(1, 0, 1, -52)
	list.Parent = window

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	unitActionGui = gui
	unitActionWindow = window
	unitActionTitle = title
	unitActionStatus = status
	unitActionList = list
end

local function hideUnitActionWindow()
	movementMode = false

	if unitActionWindow then
		unitActionWindow.Visible = false
	end
end

local function setActionStatus(text: string)
	if unitActionStatus then
		unitActionStatus.Text = text
	end
end

local function clearActionButtons()
	if not unitActionList then
		return
	end

	for _, child in unitActionList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function closeCityNameDialog()
	if cityNameWindow then
		cityNameWindow.Visible = false
	end
end

local function submitCityName()
	if not selectedUnitId then
		closeCityNameDialog()
		return
	end

	local cityName = "New City"
	if cityNameInput and cityNameInput.Text ~= "" then
		cityName = cityNameInput.Text
	end

	unitActionEvent:FireServer(selectedUnitId, "FoundCity", cityName)
	closeCityNameDialog()
	clearHighlights()
	hideUnitActionWindow()
	selectedUnitId = nil
	selectedUnitModel = nil
end

local function ensureCityNameGui()
	if cityNameGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CityNameGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = Color3.fromRGB(28, 31, 36)
	window.BorderSizePixel = 0
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(320, 156)
	window.Visible = false
	window.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(232, 220, 170)
	stroke.Transparency = 0.25
	stroke.Thickness = 1
	stroke.Parent = window

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 14)
	padding.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Text = "Название города"
	title.TextColor3 = Color3.fromRGB(255, 247, 214)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = window

	local input = Instance.new("TextBox")
	input.Name = "CityNameInput"
	input.BackgroundColor3 = Color3.fromRGB(45, 51, 60)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.PlaceholderText = "Введите название"
	input.Position = UDim2.fromOffset(0, 42)
	input.Size = UDim2.new(1, 0, 0, 36)
	input.Text = ""
	input.TextColor3 = Color3.fromRGB(245, 247, 250)
	input.TextSize = 14
	input.Parent = window

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 10)
	inputPadding.PaddingRight = UDim.new(0, 10)
	inputPadding.Parent = input

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.BackgroundColor3 = Color3.fromRGB(58, 64, 74)
	cancelButton.BorderSizePixel = 0
	cancelButton.Font = Enum.Font.GothamSemibold
	cancelButton.Position = UDim2.new(0, 0, 1, -36)
	cancelButton.Size = UDim2.new(0.5, -5, 0, 32)
	cancelButton.Text = "Отмена"
	cancelButton.TextColor3 = Color3.fromRGB(245, 247, 250)
	cancelButton.TextSize = 13
	cancelButton.Parent = window

	local confirmButton = Instance.new("TextButton")
	confirmButton.Name = "ConfirmButton"
	confirmButton.BackgroundColor3 = Color3.fromRGB(78, 126, 86)
	confirmButton.BorderSizePixel = 0
	confirmButton.Font = Enum.Font.GothamSemibold
	confirmButton.Position = UDim2.new(0.5, 5, 1, -36)
	confirmButton.Size = UDim2.new(0.5, -5, 0, 32)
	confirmButton.Text = "Основать"
	confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmButton.TextSize = 13
	confirmButton.Parent = window

	cancelButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)

	confirmButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)

	cancelButton.Activated:Connect(function()
		closeCityNameDialog()
	end)

	confirmButton.Activated:Connect(submitCityName)

	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitCityName()
		end
	end)

	cityNameGui = gui
	cityNameWindow = window
	cityNameInput = input
end

local function showCityNameDialog()
	ensureCityNameGui()
	movementMode = false
	clearMovementHighlights()

	if cityNameInput then
		cityNameInput.Text = ""
	end

	if cityNameWindow then
		cityNameWindow.Visible = true
	end

	if cityNameInput then
		cityNameInput:CaptureFocus()
	end
end

local function hideCountryMenu()
	if countryMenuGui then
		countryMenuGui.Enabled = false
	end
end

local function submitCountryName()
	local countryName = "Моя страна"
	if countryNameInput and countryNameInput.Text ~= "" then
		countryName = countryNameInput.Text
	end

	createCountryEvent:FireServer(countryName)
	hideCountryMenu()
end

local function ensureCountryMenuGui()
	if countryMenuGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CountryMenuGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Color3.fromRGB(15, 19, 24)
	backdrop.BackgroundTransparency = 0.08
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = Color3.fromRGB(28, 31, 36)
	window.BorderSizePixel = 0
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(360, 180)
	window.Parent = backdrop

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(232, 220, 170)
	stroke.Transparency = 0.2
	stroke.Thickness = 1
	stroke.Parent = window

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.PaddingTop = UDim.new(0, 18)
	padding.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Text = "Создать страну"
	title.TextColor3 = Color3.fromRGB(255, 247, 214)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = window

	local input = Instance.new("TextBox")
	input.Name = "CountryNameInput"
	input.BackgroundColor3 = Color3.fromRGB(45, 51, 60)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.PlaceholderText = "Название страны"
	input.Position = UDim2.fromOffset(0, 48)
	input.Size = UDim2.new(1, 0, 0, 38)
	input.Text = ""
	input.TextColor3 = Color3.fromRGB(245, 247, 250)
	input.TextSize = 15
	input.Parent = window

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 10)
	inputPadding.PaddingRight = UDim.new(0, 10)
	inputPadding.Parent = input

	local button = Instance.new("TextButton")
	button.Name = "CreateButton"
	button.BackgroundColor3 = Color3.fromRGB(78, 126, 86)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamSemibold
	button.Position = UDim2.new(0, 0, 1, -38)
	button.Size = UDim2.new(1, 0, 0, 36)
	button.Text = "Создать"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 14
	button.Parent = window

	button.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)

	button.Activated:Connect(submitCountryName)

	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitCountryName()
		end
	end)

	countryMenuGui = gui
	countryNameInput = input
end

local function showCountryMenu()
	ensureCountryMenuGui()

	if localPlayer:GetAttribute("CountryName") then
		hideCountryMenu()
		return
	end

	if countryMenuGui then
		countryMenuGui.Enabled = true
	end

	if countryNameInput then
		countryNameInput.Text = ""
		countryNameInput:CaptureFocus()
	end
end

local function handleUnitAction(actionId: string, actionText: string)
	if actionId == "Move" then
		movementMode = true
		clearMovementHighlights()
		showMovementForSelectedUnit()
		setActionStatus("Выберите подсвеченную клетку")
		return
	end

	if actionId == "FoundCity" then
		showCityNameDialog()
		return
	end

	movementMode = false
	clearMovementHighlights()

	if selectedUnitId then
		unitActionEvent:FireServer(selectedUnitId, actionId)
	end

	if actionId == "Delete" then
		clearHighlights()
		hideUnitActionWindow()
		selectedUnitId = nil
		selectedUnitModel = nil
		return
	end

	setActionStatus(actionText)
end

local function createActionButton(actionId: string, text: string, order: number)
	if not unitActionList then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = actionId .. "Button"
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(48, 55, 64)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamSemibold
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 29)
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 247, 250)
	button.TextSize = 13
	button.Parent = unitActionList

	button.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)

	button.Activated:Connect(function()
		handleUnitAction(actionId, text)
	end)
end

local function showUnitActionWindow(model: Model)
	ensureUnitActionGui()
	clearActionButtons()

	local unitType = model:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	local displayName = unit and unit.DisplayName or tostring(unitType or "Юнит")
	local health = model:GetAttribute("Health")
	local maxHealth = getUnitMaxHealth(model)

	if unitActionTitle then
		unitActionTitle.Text = displayName
	end

	if typeof(health) == "number" then
		setActionStatus(string.format("HP %d/%d", math.max(0, math.floor(health + 0.5)), math.floor(maxHealth + 0.5)))
	else
		setActionStatus("Выберите действие")
	end

	local order = 0
	for _, action in ACTION_BUTTONS do
		if not action.SettlerOnly or unitType == "Settler" then
			order += 1
			createActionButton(action.Id, action.Text, order)
		end
	end

	if unitActionWindow then
		unitActionWindow.Visible = true
	end
end

local function clearSelection()
	clearHighlights()
	hideUnitActionWindow()
	closeCityNameDialog()
	selectedUnitId = nil
	selectedUnitModel = nil
end

local function selectUnit(model: Model)
	clearHighlights()
	movementMode = true

	selectedUnitModel = model
	selectedUnitId = model:GetAttribute("UnitId") :: string

	selectionHighlight = Instance.new("Highlight")
	selectionHighlight.Name = "SelectedUnitHighlight"
	selectionHighlight.Adornee = model
	selectionHighlight.FillColor = Color3.fromRGB(255, 226, 92)
	selectionHighlight.FillTransparency = 0.78
	selectionHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	selectionHighlight.OutlineTransparency = 0
	selectionHighlight.Parent = highlightFolder

	showUnitActionWindow(model)
	showMovementForSelectedUnit()
end

local function requestMove(tile: BasePart)
	if not selectedUnitId or not movementMode or not canSelectedUnitEnter(tile) then
		return
	end

	local targetX = tile:GetAttribute("GridX")
	local targetZ = tile:GetAttribute("GridZ")
	if typeof(targetX) ~= "number" or typeof(targetZ) ~= "number" then
		return
	end

	moveUnitEvent:FireServer(selectedUnitId, targetX, targetZ)
	clearSelection()
end

mouse.Button1Down:Connect(function()
	if ignoreNextWorldClick then
		ignoreNextWorldClick = false
		return
	end

	local target = mouse.Target
	local unitModel = findUnitModel(target)

	if unitModel and isOwnedUnit(unitModel) then
		selectUnit(unitModel)
		return
	end

	local tile = findTile(target)
	if tile then
		if movementMode then
			requestMove(tile)
		end
		return
	end

	clearSelection()
end)

local unitsFolder = getUnitsFolder()
if unitsFolder then
	watchUnitsFolder(unitsFolder)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Units" and child:IsA("Folder") then
			watchUnitsFolder(child)
		end
	end)
end

localPlayer:GetAttributeChangedSignal("CountryName"):Connect(function()
	if localPlayer:GetAttribute("CountryName") then
		hideCountryMenu()
	end
end)

showCountryMenu()
