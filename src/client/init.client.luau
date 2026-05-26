local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local CityConfig = require(ReplicatedStorage.Shared.CityConfig)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)
local TechnologyConfig = require(ReplicatedStorage.Shared.TechnologyConfig)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
local mouse = localPlayer:GetMouse()
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local moveUnitEvent = remotesFolder:WaitForChild("MoveUnit") :: RemoteEvent
local unitActionEvent = remotesFolder:WaitForChild("UnitAction") :: RemoteEvent
local createCountryEvent = remotesFolder:WaitForChild("CreateCountry") :: RemoteEvent
local createUnitEvent = remotesFolder:WaitForChild("CreateUnit") :: RemoteEvent
local diplomacyActionEvent = remotesFolder:WaitForChild("DiplomacyAction") :: RemoteEvent
local deleteCityEvent = remotesFolder:WaitForChild("DeleteCity") :: RemoteEvent
local warNotificationEvent = remotesFolder:WaitForChild("WarNotification") :: RemoteEvent
local researchTechnologyEvent = remotesFolder:WaitForChild("ResearchTechnology") :: RemoteEvent

local selectedUnitId: string? = nil
local selectedUnitModel: Model? = nil
local selectedCityModel: Model? = nil
local selectionHighlight: Highlight? = nil
local movementMode = false
local attackMode = false
local attachMode = false
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
local cityProductionGui: ScreenGui? = nil
local cityProductionWindow: Frame? = nil
local cityProductionStatus: TextLabel? = nil
local warNotificationGui: ScreenGui? = nil
local warNotificationWindow: Frame? = nil
local warNotificationTitle: TextLabel? = nil
local warNotificationBody: TextLabel? = nil
local diplomacyGui: ScreenGui? = nil
local diplomacyWindow: Frame? = nil
local diplomacyList: ScrollingFrame? = nil
local cityListGui: ScreenGui? = nil
local cityListWindow: Frame? = nil
local cityListContent: Frame? = nil
local technologyGui: ScreenGui? = nil
local technologyWindow: Frame? = nil
local technologyStatus: TextLabel? = nil
local gameHudGui: ScreenGui? = nil
local hudCountryLabel: TextLabel? = nil
local hudContextTitle: TextLabel? = nil
local hudContextSubtitle: TextLabel? = nil
local hudContextStats: TextLabel? = nil
local hudResourceLabels: { [string]: TextLabel } = {}
local worldMapGrid: Frame? = nil
local worldMapTerritories: Frame? = nil
local worldMapMarkers: Frame? = nil
local avatarImagesByUserId: { [number]: string } = {}

local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "MovementHighlights"
highlightFolder.Parent = Workspace

local HEALTH_BAR_NAME = "UnitHealthBar"
local HUD_DARK = Color3.fromRGB(64, 73, 202)
local HUD_PANEL = Color3.fromRGB(72, 81, 206)
local HUD_PANEL_LIGHT = Color3.fromRGB(78, 88, 216)
local HUD_GOLD = Color3.fromRGB(0, 190, 255)
local HUD_TEXT = Color3.fromRGB(255, 255, 255)
local HUD_MUTED = Color3.fromRGB(218, 231, 255)
local HUD_BLACK_TEXT = Color3.fromRGB(10, 18, 44)
local HUD_WHITE = Color3.fromRGB(248, 252, 255)
local HUD_DIM_BLUE = Color3.fromRGB(45, 54, 178)
local WORLD_MAP_TILE_SIZE = 2
local WORLD_MAP_SIZE = UDim2.fromOffset(
	MapConfig.Map.Width * WORLD_MAP_TILE_SIZE,
	MapConfig.Map.Length * WORLD_MAP_TILE_SIZE
)
local WORLD_MAP_EXPECTED_TILES = MapConfig.Map.Width * MapConfig.Map.Length
local COUNTRY_TERRITORY_RADIUS = CityConfig.Territory.BorderRadius or CityConfig.Territory.Radius
local ACTION_BUTTONS = {
	{ Id = "FoundCity", Text = "Основать город", SettlerOnly = true },
	{ Id = "BuildImprovement", Text = "Улучшить ресурс", BuilderOnly = true },
	{ Id = "Attack", Text = "Атаковать", AttackOnly = true },
	{ Id = "AutoAttack", Text = "Авто-атака", AttackCapableOnly = true },
	{ Id = "AttachTo", Text = "Прикрепить" },
	{ Id = "Detach", Text = "Открепить", AttachedOnly = true },
	{ Id = "Move", Text = "Переместить" },
	{ Id = "Rest", Text = "Отдых" },
	{ Id = "Fortify", Text = "Укрепиться" },
	{ Id = "FortifyHeal", Text = "Укрепиться до исцеления" },
	{ Id = "Delete", Text = "Удалить юнита" },
}
local TECHNOLOGIES = TechnologyConfig.List
local selectedTechnologyName: string? = nil

local function getTileName(x: number, z: number): string
	return string.format("Tile_%03d_%03d", x, z)
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild("GeneratedMap") :: Folder?
end

local function getUnitsFolder(): Folder?
	return Workspace:FindFirstChild("Units") :: Folder?
end

local function getCitiesFolder(): Folder?
	return Workspace:FindFirstChild("Cities") :: Folder?
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

local function findCityModel(instance: Instance?): Model?
	local current = instance

	while current and current ~= Workspace do
		if current:IsA("Model") and current:GetAttribute("CityId") then
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
		if child.Name == "MoveHighlight" or child.Name == "AttackHighlight" then
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

local function getRelationAttributeNameForOwner(ownerUserId: number): string
	if ownerUserId < 0 then
		return "Relation_n" .. tostring(math.abs(ownerUserId))
	end

	return "Relation_p" .. tostring(ownerUserId)
end

local function getTerritoryOwnerAtTile(x: number, z: number): number?
	local citiesFolder = getCitiesFolder()
	if not citiesFolder then
		return nil
	end

	for _, city in citiesFolder:GetChildren() do
		if city:IsA("Model") then
			local ownerUserId = city:GetAttribute("OwnerUserId")
			local cityX = city:GetAttribute("GridX")
			local cityZ = city:GetAttribute("GridZ")
			if typeof(ownerUserId) == "number" and typeof(cityX) == "number" and typeof(cityZ) == "number" then
				local distance = math.max(math.abs(x - cityX), math.abs(z - cityZ))
				if distance <= CityConfig.Territory.Radius then
					return ownerUserId
				end
			end
		end
	end

	return nil
end

local function canLocalPlayerEnterTerritory(tile: BasePart): boolean
	local x = tile:GetAttribute("GridX")
	local z = tile:GetAttribute("GridZ")
	if typeof(x) ~= "number" or typeof(z) ~= "number" then
		return true
	end

	local ownerUserId = getTerritoryOwnerAtTile(x, z)
	if not ownerUserId or ownerUserId == localPlayer.UserId then
		return true
	end

	return localPlayer:GetAttribute(getRelationAttributeNameForOwner(ownerUserId)) == "War"
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

	return UnitConfig.Types[unitType].CanEnter[biome] == true and canLocalPlayerEnterTerritory(tile)
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

local function createAttackHighlight(tile: BasePart)
	local highlight = Instance.new("Part")
	highlight.Name = "AttackHighlight"
	highlight.Anchored = true
	highlight.CanCollide = false
	highlight.CanQuery = false
	highlight.Color = Color3.fromRGB(231, 74, 62)
	highlight.Material = Enum.Material.Neon
	highlight.Size = Vector3.new(MapConfig.Tile.Width, 0.09, MapConfig.Tile.Length)
	highlight.Transparency = 0.42
	highlight.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + 0.12, tile.Position.Z)
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

local function showAttackTargetsForSelectedUnit()
	if not selectedUnitModel then
		return
	end

	local unitType = selectedUnitModel:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	if not unit or unit.Attack <= 0 then
		return
	end

	local originX = selectedUnitModel:GetAttribute("GridX")
	local originZ = selectedUnitModel:GetAttribute("GridZ")
	if typeof(originX) ~= "number" or typeof(originZ) ~= "number" then
		return
	end

	local range = unit.Range or 1
	local unitsFolder = getUnitsFolder()
	if unitsFolder then
		for _, enemy in unitsFolder:GetChildren() do
			if enemy:IsA("Model") and enemy:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
				local x = enemy:GetAttribute("GridX")
				local z = enemy:GetAttribute("GridZ")
				if typeof(x) == "number" and typeof(z) == "number" then
					local distance = math.abs(x - originX) + math.abs(z - originZ)
					local tile = getTile(x, z)
					if distance >= 1 and distance <= range and tile then
						createAttackHighlight(tile)
					end
				end
			end
		end
	end

	local citiesFolder = getCitiesFolder()
	if citiesFolder then
		for _, city in citiesFolder:GetChildren() do
			if city:IsA("Model") and city:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
				local x = city:GetAttribute("GridX")
				local z = city:GetAttribute("GridZ")
				if typeof(x) == "number" and typeof(z) == "number" then
					local distance = math.abs(x - originX) + math.abs(z - originZ)
					local tile = getTile(x, z)
					if distance >= 1 and distance <= range and tile then
						createAttackHighlight(tile)
					end
				end
			end
		end
	end
end

local function isTargetInAttackRange(model: Model, target: Model): boolean
	local unitType = model:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	if not unit or unit.Attack <= 0 then
		return false
	end

	local originX = model:GetAttribute("GridX")
	local originZ = model:GetAttribute("GridZ")
	local targetX = target:GetAttribute("GridX")
	local targetZ = target:GetAttribute("GridZ")
	if typeof(originX) ~= "number" or typeof(originZ) ~= "number" or typeof(targetX) ~= "number" or typeof(targetZ) ~= "number" then
		return false
	end

	local distance = math.abs(targetX - originX) + math.abs(targetZ - originZ)
	return distance >= 1 and distance <= (unit.Range or 1)
end

local function hasAttackTargetInRange(model: Model): boolean
	local unitsFolder = getUnitsFolder()
	if unitsFolder then
		for _, enemy in unitsFolder:GetChildren() do
			if enemy:IsA("Model") and enemy:GetAttribute("OwnerUserId") ~= localPlayer.UserId and isTargetInAttackRange(model, enemy) then
				return true
			end
		end
	end

	local citiesFolder = getCitiesFolder()
	if citiesFolder then
		for _, city in citiesFolder:GetChildren() do
			if city:IsA("Model") and city:GetAttribute("OwnerUserId") ~= localPlayer.UserId and isTargetInAttackRange(model, city) then
				return true
			end
		end
	end

	return false
end

local function addStroke(instance: GuiObject, color: Color3?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or HUD_GOLD
	stroke.Transparency = transparency or 0.12
	stroke.Thickness = 2
	stroke.Parent = instance
	return stroke
end

local function addCorner(instance: GuiObject, radius: UDim?)
	local existingCorner = instance:FindFirstChildOfClass("UICorner")
	if existingCorner then
		existingCorner:Destroy()
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 10)
	corner.Parent = instance
end

local function addPadding(instance: GuiObject, inset: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, inset)
	padding.PaddingLeft = UDim.new(0, inset)
	padding.PaddingRight = UDim.new(0, inset)
	padding.PaddingTop = UDim.new(0, inset)
	padding.Parent = instance
end

local function createHudLabel(parent: Instance, text: string, size: UDim2, textSize: number, bold: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	label.Size = size
	label.Text = text
	label.TextColor3 = HUD_TEXT
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	return label
end

local function createHudButton(parent: Instance, text: string, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = HUD_PANEL_LIGHT
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Size = size
	button.Text = text
	button.TextColor3 = HUD_TEXT
	button.TextSize = 13
	button.TextStrokeColor3 = Color3.fromRGB(18, 28, 90)
	button.TextStrokeTransparency = 0.68
	button.Parent = parent
	addCorner(button, UDim.new(0, 10))
	addStroke(button, HUD_GOLD, 0.1)

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	button.MouseEnter:Connect(function()
		if button.Active and button.AutoButtonColor then
			scale.Scale = 1.035
		end
	end)
	button.MouseLeave:Connect(function()
		scale.Scale = 1
	end)

	return button
end

local function ensureWarNotificationGui()
	if warNotificationGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WarNotificationGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0)
	window.BackgroundColor3 = Color3.fromRGB(92, 23, 32)
	window.BackgroundTransparency = 0.02
	window.BorderSizePixel = 0
	window.Position = UDim2.new(0.5, 0, 0, 76)
	window.Size = UDim2.fromOffset(390, 126)
	window.Visible = false
	window.Parent = gui
	addCorner(window, UDim.new(0, 14))
	addPadding(window, 14)
	addStroke(window, Color3.fromRGB(255, 212, 128), 0.16)

	local title = createHudLabel(window, "Объявлена война", UDim2.new(1, 0, 0, 24), 18, true)
	title.TextColor3 = Color3.fromRGB(255, 232, 180)

	local body = createHudLabel(window, "", UDim2.new(1, 0, 1, -34), 13, false)
	body.Position = UDim2.fromOffset(0, 34)
	body.TextColor3 = Color3.fromRGB(255, 245, 230)
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top

	warNotificationGui = gui
	warNotificationWindow = window
	warNotificationTitle = title
	warNotificationBody = body
end

local function showWarNotification(payload: any)
	ensureWarNotificationGui()
	if not warNotificationWindow or not warNotificationTitle or not warNotificationBody then
		return
	end

	local fromName = typeof(payload) == "table" and tostring(payload.From or "Неизвестная держава") or "Неизвестная держава"
	local toName = typeof(payload) == "table" and tostring(payload.To or "ваша держава") or "ваша держава"
	local reason = typeof(payload) == "table" and tostring(payload.Reason or "Причина не указана") or "Причина не указана"

	warNotificationTitle.Text = "Объявлена война"
	warNotificationBody.Text = string.format("От: %s\nКому: %s\nПричина: %s", fromName, toName, reason)
	warNotificationWindow.Visible = true

	task.delay(6, function()
		if warNotificationWindow and warNotificationBody and warNotificationBody.Text:find(fromName, 1, true) then
			warNotificationWindow.Visible = false
		end
	end)
end

local function createResourceChip(parent: Instance, text: string): TextLabel
	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = HUD_DIM_BLUE
	chip.BackgroundTransparency = 0.12
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromOffset(78, 26)
	chip.Parent = parent
	addCorner(chip, UDim.new(0, 8))
	addStroke(chip, HUD_GOLD, 0.35)

	local label = createHudLabel(chip, text, UDim2.fromScale(1, 1), 11, true)
	label.TextXAlignment = Enum.TextXAlignment.Center

	return label
end

local function getBiomeColor(biome: any): Color3
	if typeof(biome) == "string" then
		local config = MapConfig.Biomes[biome]
		if config then
			return config.Color
		end
	end

	return Color3.fromRGB(50, 55, 60)
end

local function getMapTileCount(): number
	local mapFolder = getMapFolder()
	if not mapFolder then
		return 0
	end

	local count = 0
	for _, child in mapFolder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Biome") then
			count += 1
		end
	end

	return count
end

local function createWorldMapTiles(parent: Frame)
	parent:ClearAllChildren()

	local mapFolder = getMapFolder()
	for z = 1, MapConfig.Map.Length do
		for x = 1, MapConfig.Map.Width do
			local tileColor = Color3.fromRGB(42, 48, 54)
			local tile = mapFolder and mapFolder:FindFirstChild(getTileName(x, z))
			if tile and tile:IsA("BasePart") then
				tileColor = getBiomeColor(tile:GetAttribute("Biome"))
			end

			local cell = Instance.new("Frame")
			cell.Name = string.format("Cell_%03d_%03d", x, z)
			cell.BackgroundColor3 = tileColor
			cell.BorderSizePixel = 0
			cell.Position = UDim2.fromOffset((x - 1) * WORLD_MAP_TILE_SIZE, (z - 1) * WORLD_MAP_TILE_SIZE)
			cell.Size = UDim2.fromOffset(WORLD_MAP_TILE_SIZE, WORLD_MAP_TILE_SIZE)
			cell.ZIndex = 1
			cell.Parent = parent
		end
	end
end

local function getCountryColor(userId: number): Color3
	local hue = ((userId * 37) % 360) / 360
	return Color3.fromHSV(hue, 0.58, 0.95)
end

local function getRelationAttributeName(otherUserId: number): string
	if otherUserId < 0 then
		return "Relation_n" .. tostring(math.abs(otherUserId))
	end

	return "Relation_p" .. tostring(otherUserId)
end

local function getRelationTo(ownerUserId: number): string
	local relation = localPlayer:GetAttribute(getRelationAttributeName(ownerUserId))
	if typeof(relation) == "string" then
		return relation
	end

	return "Peace"
end

local function getCityModels(): { Model }
	local cities = {}
	local citiesFolder = getCitiesFolder()
	if not citiesFolder then
		return cities
	end

	for _, child in citiesFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("CityId") then
			table.insert(cities, child)
		end
	end

	return cities
end

local function getOwnedCityModels(): { Model }
	local cities = {}

	for _, city in getCityModels() do
		if city:GetAttribute("OwnerUserId") == localPlayer.UserId then
			table.insert(cities, city)
		end
	end

	table.sort(cities, function(a, b)
		return tostring(a:GetAttribute("CityName") or "") < tostring(b:GetAttribute("CityName") or "")
	end)

	return cities
end

local function getPlayerMapPosition(userId: number): (number?, number?)
	local citiesFolder = getCitiesFolder()
	if citiesFolder then
		for _, city in citiesFolder:GetChildren() do
			if city:GetAttribute("OwnerUserId") == userId then
				local x = city:GetAttribute("GridX")
				local z = city:GetAttribute("GridZ")
				if typeof(x) == "number" and typeof(z) == "number" then
					return x, z
				end
			end
		end
	end

	local unitsFolder = getUnitsFolder()
	if unitsFolder then
		for _, unit in unitsFolder:GetChildren() do
			if unit:GetAttribute("OwnerUserId") == userId then
				local x = unit:GetAttribute("GridX")
				local z = unit:GetAttribute("GridZ")
				if typeof(x) == "number" and typeof(z) == "number" then
					return x, z
				end
			end
		end
	end

	return nil, nil
end

local function getAvatarImage(userId: number): string
	local cachedImage = avatarImagesByUserId[userId]
	if cachedImage then
		return cachedImage
	end

	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)

	if ok then
		avatarImagesByUserId[userId] = image
		return image
	end

	return ""
end

local function addWorldMapTerritoryCell(x: number, z: number, color: Color3)
	if not worldMapTerritories then
		return
	end

	local cell = Instance.new("Frame")
	cell.BackgroundColor3 = color
	cell.BackgroundTransparency = 0.48
	cell.BorderSizePixel = 0
	cell.Position = UDim2.fromOffset((x - 1) * WORLD_MAP_TILE_SIZE, (z - 1) * WORLD_MAP_TILE_SIZE)
	cell.Size = UDim2.fromOffset(WORLD_MAP_TILE_SIZE, WORLD_MAP_TILE_SIZE)
	cell.ZIndex = 2
	cell.Parent = worldMapTerritories
end

local function getWorldMapTerritoryKey(x: number, z: number): string
	return tostring(x) .. ":" .. tostring(z)
end

local function updateWorldMapTerritories()
	if not worldMapTerritories then
		return
	end

	worldMapTerritories:ClearAllChildren()

	local territoriesByOwner = {}
	for _, city in getCityModels() do
		local ownerUserId = city:GetAttribute("OwnerUserId")
		local cityX = city:GetAttribute("GridX")
		local cityZ = city:GetAttribute("GridZ")
		if typeof(ownerUserId) == "number" and typeof(cityX) == "number" and typeof(cityZ) == "number" then
			if not territoriesByOwner[ownerUserId] then
				territoriesByOwner[ownerUserId] = {}
			end

			for x = cityX - COUNTRY_TERRITORY_RADIUS, cityX + COUNTRY_TERRITORY_RADIUS do
				for z = cityZ - COUNTRY_TERRITORY_RADIUS, cityZ + COUNTRY_TERRITORY_RADIUS do
					local distance = math.max(math.abs(x - cityX), math.abs(z - cityZ))
					if x >= 1 and x <= MapConfig.Map.Width and z >= 1 and z <= MapConfig.Map.Length and distance <= COUNTRY_TERRITORY_RADIUS then
						territoriesByOwner[ownerUserId][getWorldMapTerritoryKey(x, z)] = { X = x, Z = z }
					end
				end
			end
		end
	end

	for ownerUserId, territoryTiles in territoriesByOwner do
		local color = getCountryColor(ownerUserId)
		for _, position in territoryTiles do
			addWorldMapTerritoryCell(position.X, position.Z, color)
		end
	end
end

local function addWorldMapCityLabel(city: Model)
	if not worldMapMarkers then
		return
	end

	local cityName = city:GetAttribute("CityName")
	local x = city:GetAttribute("GridX")
	local z = city:GetAttribute("GridZ")
	if typeof(cityName) ~= "string" or typeof(x) ~= "number" or typeof(z) ~= "number" then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "City_" .. cityName
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.BackgroundColor3 = Color3.fromRGB(11, 13, 16)
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Position = UDim2.fromScale((x - 0.5) / MapConfig.Map.Width, (z - 0.5) / MapConfig.Map.Length)
	label.Size = UDim2.fromOffset(70, 14)
	label.Text = cityName
	label.TextColor3 = HUD_TEXT
	label.TextScaled = true
	label.TextStrokeTransparency = 0.45
	label.ZIndex = 5
	label.Parent = worldMapMarkers
end

local function updateWorldMapMarkers()
	if not worldMapMarkers then
		return
	end

	worldMapMarkers:ClearAllChildren()

	for _, city in getCityModels() do
		addWorldMapCityLabel(city)
	end

	for _, player in Players:GetPlayers() do
		local x, z = getPlayerMapPosition(player.UserId)
		if x and z then
			local marker = Instance.new("ImageLabel")
			marker.Name = "Player_" .. tostring(player.UserId)
			marker.AnchorPoint = Vector2.new(0.5, 0.5)
			marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			marker.BorderSizePixel = 0
			marker.Image = getAvatarImage(player.UserId)
			marker.Position = UDim2.fromScale((x - 0.5) / MapConfig.Map.Width, (z - 0.5) / MapConfig.Map.Length)
			marker.Size = UDim2.fromOffset(20, 20)
			marker.ZIndex = 4
			marker.Parent = worldMapMarkers

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = marker

			local stroke = Instance.new("UIStroke")
			stroke.Color = player == localPlayer and Color3.fromRGB(255, 230, 120) or Color3.fromRGB(255, 255, 255)
			stroke.Thickness = 2
			stroke.Parent = marker
		end
	end
end

local function updateWorldMap()
	updateWorldMapTerritories()
	updateWorldMapMarkers()
end

local function startWorldMapUpdates()
	task.spawn(function()
		while gameHudGui do
			updateWorldMap()
			task.wait(1)
		end
	end)
end

local function startWorldMapTileRefresh()
	task.spawn(function()
		local lastTileCount = -1
		for _ = 1, 12 do
			if not worldMapGrid then
				return
			end

			local tileCount = getMapTileCount()
			if tileCount ~= lastTileCount then
				createWorldMapTiles(worldMapGrid)
				lastTileCount = tileCount
			end

			if tileCount >= WORLD_MAP_EXPECTED_TILES then
				return
			end

			task.wait(1)
		end
	end)
end

local function updateGameHudCountry()
	if not hudCountryLabel then
		return
	end

	local countryName = localPlayer:GetAttribute("CountryName")
	if typeof(countryName) == "string" and countryName ~= "" then
		hudCountryLabel.Text = countryName
	else
		hudCountryLabel.Text = "Новая страна"
	end
end

local function getPlayerNumberAttribute(attributeName: string): number
	local value = localPlayer:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return 0
end

local function updateGameHudResources()
	if hudResourceLabels.Science then
		hudResourceLabels.Science.Text = string.format("Наука %d", getPlayerNumberAttribute("TreasuryScience"))
	end

	if hudResourceLabels.Culture then
		hudResourceLabels.Culture.Text = string.format("Культура %d", getPlayerNumberAttribute("TreasuryCulture"))
	end

	if hudResourceLabels.Gold then
		hudResourceLabels.Gold.Text = string.format("Золото %d", getPlayerNumberAttribute("TreasuryGold"))
	end

	if hudResourceLabels.Iron then
		hudResourceLabels.Iron.Text = string.format("Железо %d", getPlayerNumberAttribute("TreasuryIron"))
	end

	if hudResourceLabels.Horses then
		hudResourceLabels.Horses.Text = string.format("Кони %d", getPlayerNumberAttribute("TreasuryHorses"))
	end

	if hudResourceLabels.Faith then
		hudResourceLabels.Faith.Text = string.format("Вера %d", getPlayerNumberAttribute("TreasuryFaith"))
	end

	if hudResourceLabels.Food then
		hudResourceLabels.Food.Text = string.format("Пища %d", getPlayerNumberAttribute("TreasuryFood"))
	end

	if hudResourceLabels.Production then
		hudResourceLabels.Production.Text = string.format("Произв. %d", getPlayerNumberAttribute("TreasuryProduction"))
	end
end

local function setHudContext(title: string, subtitle: string, stats: string)
	if hudContextTitle then
		hudContextTitle.Text = title
	end

	if hudContextSubtitle then
		hudContextSubtitle.Text = subtitle
	end

	if hudContextStats then
		hudContextStats.Text = stats
	end
end

local function setHudContextForUnit(model: Model)
	local unitType = model:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	local displayName = unit and unit.DisplayName or tostring(unitType or "Юнит")
	local health = model:GetAttribute("Health")
	local maxHealth = getUnitMaxHealth(model)
	local x = model:GetAttribute("GridX")
	local z = model:GetAttribute("GridZ")
	local location = typeof(x) == "number" and typeof(z) == "number" and string.format("Клетка %d:%d", x, z) or "Клетка не выбрана"
	local stats = unit and string.format("HP %d/%d   Атака %d   Ход %d", math.floor((health :: number?) or maxHealth), maxHealth, unit.Attack, unit.Movement)
		or string.format("HP %d/%d", math.floor((health :: number?) or maxHealth), maxHealth)

	setHudContext(displayName, location, stats)
end

local function setHudContextForCity(model: Model)
	local cityName = model:GetAttribute("CityName")
	local countryName = model:GetAttribute("CountryName")
	local population = model:GetAttribute("Population")
	local food = model:GetAttribute("Food")
	local production = model:GetAttribute("Production")
	local health = model:GetAttribute("Health")
	local maxHealth = model:GetAttribute("MaxHealth")
	local x = model:GetAttribute("GridX")
	local z = model:GetAttribute("GridZ")

	local title = typeof(cityName) == "string" and cityName or "Город"
	local subtitleCountry = typeof(countryName) == "string" and countryName or "Неизвестная страна"
	local location = typeof(x) == "number" and typeof(z) == "number" and string.format("Клетка %d:%d", x, z) or "Клетка не выбрана"
	local stats = string.format(
		"HP %d/%d   Население %d   Пища %d   Производство %d",
		typeof(health) == "number" and health or 0,
		typeof(maxHealth) == "number" and maxHealth or 0,
		typeof(population) == "number" and population or 0,
		typeof(food) == "number" and food or 0,
		typeof(production) == "number" and production or 0
	)

	setHudContext(title, subtitleCountry .. "   " .. location, stats)
end

local function hideCityProductionWindow()
	if cityProductionWindow then
		cityProductionWindow.Visible = false
	end
end

local function requestCityUnit(unitType: string)
	if not selectedCityModel then
		return
	end

	local cityId = selectedCityModel:GetAttribute("CityId")
	if typeof(cityId) == "string" then
		createUnitEvent:FireServer(cityId, unitType)
	end
end

local function updateCityProductionStatus(model: Model?)
	if not cityProductionStatus then
		return
	end

	if not model then
		cityProductionStatus.Text = "Выберите производство"
		return
	end

	local queue = model:GetAttribute("ProductionQueue")
	local secondsLeft = model:GetAttribute("ProductionSecondsLeft")
	if typeof(queue) == "string" then
		cityProductionStatus.Text = string.format("Строится: %s (%dс)", queue, typeof(secondsLeft) == "number" and secondsLeft or 0)
	else
		cityProductionStatus.Text = "Город свободен"
	end
end

local function createProductionButton(parent: Instance, text: string, unitType: string, order: number)
	local button = createHudButton(parent, text, UDim2.new(1, 0, 0, 38))
	button.LayoutOrder = order
	button.BackgroundColor3 = order <= 2 and Color3.fromRGB(83, 91, 220) or HUD_PANEL_LIGHT
	button.TextSize = 14
	button.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	button.Activated:Connect(function()
		requestCityUnit(unitType)
	end)
end

local function ensureCityProductionGui()
	if cityProductionGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CityProductionGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 1)
	window.BackgroundColor3 = HUD_DARK
	window.BackgroundTransparency = 0.03
	window.BorderSizePixel = 0
	window.Position = UDim2.new(0.5, 0, 1, -24)
	window.Size = UDim2.fromOffset(372, 342)
	window.Visible = false
	window.Parent = gui
	addCorner(window, UDim.new(0, 16))
	addPadding(window, 16)
	addStroke(window, HUD_GOLD, 0.3)

	local title = createHudLabel(window, "Производство города", UDim2.new(1, -38, 0, 28), 18, true)
	title.TextColor3 = Color3.fromRGB(255, 230, 164)

	local closeButton = createHudButton(window, "X", UDim2.fromOffset(30, 28))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.BackgroundColor3 = Color3.fromRGB(104, 42, 72)
	closeButton.Activated:Connect(hideCityProductionWindow)

	local statusPanel = Instance.new("Frame")
	statusPanel.BackgroundColor3 = HUD_DIM_BLUE
	statusPanel.BackgroundTransparency = 0.15
	statusPanel.BorderSizePixel = 0
	statusPanel.Position = UDim2.fromOffset(0, 42)
	statusPanel.Size = UDim2.new(1, 0, 0, 48)
	statusPanel.Parent = window
	addCorner(statusPanel, UDim.new(0, 12))
	addPadding(statusPanel, 10)

	local status = createHudLabel(statusPanel, "Город свободен", UDim2.new(1, 0, 1, 0), 13, false)
	status.TextColor3 = HUD_MUTED
	status.TextWrapped = true

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(0, 106)
	list.Size = UDim2.new(1, 0, 1, -106)
	list.Parent = window

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 9)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	createProductionButton(list, "Создать поселенца", "Settler", 1)
	createProductionButton(list, "Создать воина", "Warrior", 2)
	createProductionButton(list, "Создать строителя", "Builder", 3)
	createProductionButton(list, "Создать лучника", "Archer", 4)
	createProductionButton(list, "Создать разведчика", "Scout", 5)

	cityProductionGui = gui
	cityProductionWindow = window
	cityProductionStatus = status

	task.spawn(function()
		while cityProductionGui do
			updateCityProductionStatus(selectedCityModel)
			task.wait(1)
		end
	end)
end

local function showCityProductionWindow(model: Model)
	selectedCityModel = model
	ensureCityProductionGui()
	updateCityProductionStatus(model)
	if cityProductionWindow then
		cityProductionWindow.Visible = model:GetAttribute("OwnerUserId") == localPlayer.UserId
	end
end

local function getKnownCivilizations(): { { OwnerUserId: number, CountryName: string } }
	local civilizations = {}
	local seenOwners = {}

	for _, city in getCityModels() do
		local ownerUserId = city:GetAttribute("OwnerUserId")
		local countryName = city:GetAttribute("CountryName")
		if typeof(ownerUserId) == "number" and ownerUserId ~= localPlayer.UserId and not seenOwners[ownerUserId] then
			seenOwners[ownerUserId] = true
			table.insert(civilizations, {
				OwnerUserId = ownerUserId,
				CountryName = typeof(countryName) == "string" and countryName or "Неизвестная держава",
			})
		end
	end

	table.sort(civilizations, function(a, b)
		return a.CountryName < b.CountryName
	end)

	return civilizations
end

local function clearDiplomacyList()
	if not diplomacyList then
		return
	end

	for _, child in diplomacyList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local refreshDiplomacyList

local function createDiplomacyRow(civilization: { OwnerUserId: number, CountryName: string }, order: number)
	if not diplomacyList then
		return
	end

	local relation = getRelationTo(civilization.OwnerUserId)
	local row = Instance.new("Frame")
	row.Name = "NationRow"
	row.BackgroundColor3 = HUD_PANEL
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 76)
	row.Parent = diplomacyList
	addPadding(row, 8)
	addCorner(row, UDim.new(0, 12))
	addStroke(row, HUD_GOLD, 0.35)

	local title = createHudLabel(row, civilization.CountryName, UDim2.new(1, -170, 0, 22), 14, true)
	title.TextColor3 = relation == "War" and Color3.fromRGB(255, 142, 128) or HUD_TEXT

	local status = createHudLabel(row, relation == "War" and "Состояние: война" or "Состояние: мир", UDim2.new(1, -170, 0, 20), 12, false)
	status.Position = UDim2.fromOffset(0, 24)
	status.TextColor3 = HUD_MUTED

	local tradeButton = createHudButton(row, "Торговать", UDim2.fromOffset(120, 26))
	tradeButton.AnchorPoint = Vector2.new(1, 0)
	tradeButton.Position = UDim2.new(1, 0, 0, 0)
	tradeButton.Active = relation ~= "War"
	tradeButton.AutoButtonColor = relation ~= "War"
	tradeButton.BackgroundColor3 = relation == "War" and Color3.fromRGB(55, 58, 64) or HUD_PANEL_LIGHT
	tradeButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	tradeButton.Activated:Connect(function()
		if relation ~= "War" then
			diplomacyActionEvent:FireServer(civilization.OwnerUserId, "Trade")
			task.delay(0.25, refreshDiplomacyList)
		end
	end)

	local warButton = createHudButton(row, relation == "War" and "Заключить мир" or "Объявить войну", UDim2.fromOffset(120, 26))
	warButton.AnchorPoint = Vector2.new(1, 0)
	warButton.Position = UDim2.new(1, 0, 0, 34)
	warButton.BackgroundColor3 = relation == "War" and Color3.fromRGB(74, 118, 80) or Color3.fromRGB(134, 62, 58)
	warButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	warButton.Activated:Connect(function()
		diplomacyActionEvent:FireServer(civilization.OwnerUserId, relation == "War" and "MakePeace" or "DeclareWar")
		task.delay(0.25, refreshDiplomacyList)
	end)
end

function refreshDiplomacyList()
	clearDiplomacyList()

	if not diplomacyList then
		return
	end

	local civilizations = getKnownCivilizations()
	if #civilizations == 0 then
		local empty = createHudLabel(diplomacyList, "Другие государства пока не найдены", UDim2.new(1, 0, 0, 32), 13, false)
		empty.TextColor3 = HUD_MUTED
		return
	end

	for index, civilization in civilizations do
		createDiplomacyRow(civilization, index)
	end
end

local function hideDiplomacyWindow()
	if diplomacyWindow then
		diplomacyWindow.Visible = false
	end
end

local closeTopHudWindows

local function ensureDiplomacyGui()
	if diplomacyGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DiplomacyGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = HUD_DARK
	window.BackgroundTransparency = 0.02
	window.BorderSizePixel = 0
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(430, 420)
	window.Visible = false
	window.Parent = gui
	addPadding(window, 12)
	addStroke(window, HUD_GOLD, 0.35)

	local title = createHudLabel(window, "Список государств", UDim2.new(1, -34, 0, 24), 18, true)
	title.TextColor3 = HUD_WHITE

	local closeButton = createHudButton(window, "X", UDim2.fromOffset(28, 24))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	closeButton.Activated:Connect(hideDiplomacyWindow)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.ClipsDescendants = true
	list.Position = UDim2.fromOffset(0, 36)
	list.ScrollBarImageColor3 = HUD_GOLD
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Size = UDim2.new(1, 0, 1, -36)
	list.Parent = window

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	diplomacyGui = gui
	diplomacyWindow = window
	diplomacyList = list
end

local function showDiplomacyWindow()
	if closeTopHudWindows then
		closeTopHudWindows("Diplomacy")
	end

	ensureDiplomacyGui()
	refreshDiplomacyList()

	if diplomacyWindow then
		diplomacyWindow.Visible = true
	end
end

local function clearCityList()
	if not cityListContent then
		return
	end

	for _, child in cityListContent:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local refreshCityList

local function createCityListUnitButton(parent: Instance, cityId: string, text: string, unitType: string, order: number)
	local button = createHudButton(parent, text, UDim2.fromOffset(82, 25))
	button.LayoutOrder = order
	button.TextSize = 11
	button.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	button.Activated:Connect(function()
		createUnitEvent:FireServer(cityId, unitType)
		task.delay(0.25, refreshCityList)
	end)
end

local function createCityListRow(city: Model, order: number)
	if not cityListContent then
		return
	end

	local cityId = city:GetAttribute("CityId")
	if typeof(cityId) ~= "string" then
		return
	end

	local cityName = city:GetAttribute("CityName")
	local population = city:GetAttribute("Population")
	local queue = city:GetAttribute("ProductionQueue")
	local secondsLeft = city:GetAttribute("ProductionSecondsLeft")

	local row = Instance.new("Frame")
	row.Name = "CityRow"
	row.BackgroundColor3 = HUD_PANEL
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 132)
	row.Parent = cityListContent
	addPadding(row, 8)
	addStroke(row, Color3.fromRGB(95, 104, 116), 0.65)

	local title = createHudLabel(row, typeof(cityName) == "string" and cityName or "Город", UDim2.new(1, -128, 0, 22), 14, true)
	title.TextColor3 = Color3.fromRGB(255, 230, 164)

	local productionText = typeof(queue) == "string"
		and string.format("Строится: %s (%dс)", queue, typeof(secondsLeft) == "number" and secondsLeft or 0)
		or "Производство свободно"
	local stats = createHudLabel(
		row,
		string.format("Население: %d   %s", typeof(population) == "number" and population or 0, productionText),
		UDim2.new(1, -128, 0, 18),
		12,
		false
	)
	stats.Position = UDim2.fromOffset(0, 24)
	stats.TextColor3 = HUD_MUTED

	local improveButton = createHudButton(row, "Улучшить город", UDim2.fromOffset(116, 26))
	improveButton.AnchorPoint = Vector2.new(1, 0)
	improveButton.Position = UDim2.new(1, 0, 0, 0)
	improveButton.Active = false
	improveButton.AutoButtonColor = false
	improveButton.BackgroundColor3 = Color3.fromRGB(57, 59, 65)
	improveButton.Text = "Улучшить город (закрыто)"
	improveButton.TextSize = 10

	local deleteButton = createHudButton(row, "Удалить город", UDim2.fromOffset(116, 26))
	deleteButton.AnchorPoint = Vector2.new(1, 0)
	deleteButton.Position = UDim2.new(1, 0, 0, 34)
	deleteButton.BackgroundColor3 = Color3.fromRGB(134, 62, 58)
	deleteButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	deleteButton.Activated:Connect(function()
		deleteCityEvent:FireServer(cityId)
		task.delay(0.25, refreshCityList)
	end)

	local unitButtons = Instance.new("Frame")
	unitButtons.Name = "UnitButtons"
	unitButtons.BackgroundTransparency = 1
	unitButtons.Position = UDim2.fromOffset(0, 62)
	unitButtons.Size = UDim2.new(1, 0, 0, 60)
	unitButtons.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = unitButtons

	createCityListUnitButton(unitButtons, cityId, "Поселенец", "Settler", 1)
	createCityListUnitButton(unitButtons, cityId, "Воин", "Warrior", 2)
	createCityListUnitButton(unitButtons, cityId, "Строитель", "Builder", 3)
	createCityListUnitButton(unitButtons, cityId, "Лучник", "Archer", 4)
	createCityListUnitButton(unitButtons, cityId, "Разведчик", "Scout", 5)
end

function refreshCityList()
	clearCityList()

	if not cityListContent then
		return
	end

	local cities = getOwnedCityModels()
	if #cities == 0 then
		local empty = createHudLabel(cityListContent, "У государства пока нет городов", UDim2.new(1, 0, 0, 32), 13, false)
		empty.TextColor3 = HUD_MUTED
		return
	end

	for index, city in cities do
		createCityListRow(city, index)
	end
end

local function hideCityListWindow()
	if cityListWindow then
		cityListWindow.Visible = false
	end
end

local function ensureCityListGui()
	if cityListGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CityListGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = HUD_DARK
	window.BackgroundTransparency = 0.02
	window.BorderSizePixel = 0
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(560, 480)
	window.Visible = false
	window.Parent = gui
	addPadding(window, 12)
	addStroke(window, HUD_GOLD, 0.35)

	local title = createHudLabel(window, "Список городов", UDim2.new(1, -34, 0, 24), 18, true)
	title.TextColor3 = Color3.fromRGB(255, 230, 164)

	local closeButton = createHudButton(window, "X", UDim2.fromOffset(28, 24))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	closeButton.Activated:Connect(hideCityListWindow)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Position = UDim2.fromOffset(0, 36)
	list.ScrollBarThickness = 6
	list.Size = UDim2.new(1, 0, 1, -36)
	list.Parent = window

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	cityListGui = gui
	cityListWindow = window
	cityListContent = list

	task.spawn(function()
		while cityListGui do
			if cityListWindow and cityListWindow.Visible then
				refreshCityList()
			end
			task.wait(1)
		end
	end)
end

local function showCityListWindow()
	if closeTopHudWindows then
		closeTopHudWindows("Cities")
	end

	ensureCityListGui()
	refreshCityList()

	if cityListWindow then
		cityListWindow.Visible = true
	end
end

local function hideTechnologyWindow()
	if technologyWindow then
		technologyWindow.Visible = false
	end
end

closeTopHudWindows = function(except: string?)
	if except ~= "Diplomacy" then
		hideDiplomacyWindow()
	end

	if except ~= "Cities" then
		hideCityListWindow()
	end

	if except ~= "Technology" then
		hideTechnologyWindow()
	end
end

local function updateTechnologyStatus()
	if not technologyStatus then
		return
	end

	if selectedTechnologyName then
		technologyStatus.Text = "Исследуется: " .. selectedTechnologyName
	else
		technologyStatus.Text = "Выберите технологию для исследования"
	end
end

updateTechnologyStatus = function()
	if not technologyStatus then
		return
	end

	local currentName = localPlayer:GetAttribute("CurrentResearchName")
	local secondsLeft = localPlayer:GetAttribute("ResearchSecondsLeft")
	if typeof(currentName) == "string" then
		technologyStatus.Text = string.format("Исследуется: %s (%dс)", currentName, typeof(secondsLeft) == "number" and secondsLeft or 0)
	elseif selectedTechnologyName then
		technologyStatus.Text = "Выбрано: " .. selectedTechnologyName
	else
		technologyStatus.Text = "Выберите технологию для исследования"
	end
end

local function createTechnologyRow(parent: Instance, technology: { Name: string, Detail: string }, order: number)
	local row = Instance.new("Frame")
	row.Name = "TechnologyRow"
	row.BackgroundColor3 = HUD_PANEL
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, 76)
	row.Parent = parent
	addPadding(row, 8)
	addStroke(row, Color3.fromRGB(95, 104, 116), 0.65)

	local title = createHudLabel(row, technology.Name, UDim2.new(1, -140, 0, 22), 14, true)
	title.TextColor3 = Color3.fromRGB(255, 230, 164)

	local detail = createHudLabel(row, technology.Detail, UDim2.new(1, -140, 0, 34), 12, false)
	detail.Position = UDim2.fromOffset(0, 26)
	detail.TextColor3 = HUD_MUTED
	detail.TextWrapped = true

	local button = createHudButton(row, "Исследовать", UDim2.fromOffset(120, 28))
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	button.Activated:Connect(function()
		selectedTechnologyName = technology.Name
		if typeof(technology.Id) == "string" then
			researchTechnologyEvent:FireServer(technology.Id)
		end
		updateTechnologyStatus()
	end)
end

local function ensureTechnologyGui()
	if technologyGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TechnologyGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.BackgroundColor3 = HUD_DARK
	window.BackgroundTransparency = 0
	window.BorderSizePixel = 0
	window.Size = UDim2.fromScale(1, 1)
	window.Visible = false
	window.Parent = gui

	local backgroundGradient = Instance.new("UIGradient")
	backgroundGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(78, 88, 220)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(58, 69, 196)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(38, 48, 160)),
	})
	backgroundGradient.Rotation = 90
	backgroundGradient.Parent = window

	local headerBand = Instance.new("Frame")
	headerBand.Name = "HeaderBand"
	headerBand.BackgroundColor3 = Color3.fromRGB(93, 107, 232)
	headerBand.BackgroundTransparency = 0.25
	headerBand.BorderSizePixel = 0
	headerBand.Size = UDim2.new(1, 0, 0, 60)
	headerBand.Parent = window

	local topLine = Instance.new("Frame")
	topLine.Name = "TopLine"
	topLine.BackgroundColor3 = HUD_GOLD
	topLine.BorderSizePixel = 0
	topLine.Position = UDim2.new(0, 0, 0, 56)
	topLine.Size = UDim2.new(1, 0, 0, 4)
	topLine.Parent = window

	local techTitle = createHudLabel(window, "Технологии", UDim2.fromOffset(320, 38), 22, true)
	techTitle.Position = UDim2.fromOffset(235, 13)
	techTitle.TextColor3 = HUD_BLACK_TEXT

	local techSubtitle = createHudLabel(window, "Выберите направление развития", UDim2.fromOffset(340, 24), 13, false)
	techSubtitle.Position = UDim2.fromOffset(235, 42)
	techSubtitle.TextColor3 = HUD_MUTED

	local title = createHudLabel(window, "Технологии", UDim2.new(1, -34, 0, 24), 18, true)
	title.TextColor3 = Color3.fromRGB(255, 230, 164)
	title.Visible = false

	local closeButton = createHudButton(window, "X", UDim2.fromOffset(28, 24))
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	closeButton.Activated:Connect(hideTechnologyWindow)
	closeButton.Size = UDim2.fromOffset(42, 34)
	closeButton.Position = UDim2.new(1, -20, 0, 18)

	local status = createHudLabel(window, "Выберите технологию для исследования", UDim2.new(1, 0, 0, 20), 12, false)
	status.Position = UDim2.fromOffset(0, 34)
	status.TextColor3 = HUD_MUTED
	technologyStatus = status
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0, 88)
	status.Size = UDim2.fromOffset(420, 24)
	status.Text = "Выберите технологию для исследования"
	status.TextColor3 = HUD_WHITE
	status.TextSize = 14
	status.TextXAlignment = Enum.TextXAlignment.Center

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(0, 66)
	list.Size = UDim2.new(1, 0, 1, -66)
	list.Visible = false
	list.Parent = window

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index, technology in TECHNOLOGIES do
		createTechnologyRow(list, technology, index)
	end

	local tree = Instance.new("Frame")
	tree.Name = "TechnologyTree"
	tree.BackgroundTransparency = 1
	tree.Position = UDim2.fromOffset(0, 110)
	tree.Size = UDim2.new(1, 0, 1, -110)
	tree.Parent = window

	local function createConnector(position: UDim2, size: UDim2, rotation: number?)
		local line = Instance.new("Frame")
		line.Name = "Connector"
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BackgroundColor3 = Color3.fromRGB(229, 243, 255)
		line.BackgroundTransparency = 0.08
		line.BorderSizePixel = 0
		line.Position = position
		line.Rotation = rotation or 0
		line.Size = size
		line.ZIndex = 1
		line.Parent = tree

		local arrow = Instance.new("TextLabel")
		arrow.Name = "ConnectorArrow"
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.BackgroundTransparency = 1
		arrow.Font = Enum.Font.GothamBold
		arrow.Position = UDim2.new(position.X.Scale + size.X.Scale / 2, position.X.Offset, position.Y.Scale, position.Y.Offset)
		arrow.Rotation = rotation or 0
		arrow.Size = UDim2.fromOffset(18, 18)
		arrow.Text = ">"
		arrow.TextColor3 = Color3.fromRGB(255, 232, 180)
		arrow.TextSize = 16
		arrow.ZIndex = 1
		arrow.Parent = tree
	end

	createConnector(UDim2.fromScale(0.27, 0.34), UDim2.fromScale(0.13, 0.006), -12)
	createConnector(UDim2.fromScale(0.27, 0.52), UDim2.fromScale(0.13, 0.006), 12)
	createConnector(UDim2.fromScale(0.46, 0.35), UDim2.fromScale(0.13, 0.006), 0)
	createConnector(UDim2.fromScale(0.46, 0.52), UDim2.fromScale(0.13, 0.006), 0)
	createConnector(UDim2.fromScale(0.63, 0.44), UDim2.fromScale(0.12, 0.006), 18)
	createConnector(UDim2.fromScale(0.30, 0.73), UDim2.fromScale(0.16, 0.006), 0)
	createConnector(UDim2.fromScale(0.56, 0.74), UDim2.fromScale(0.16, 0.006), 0)

	local techNodeStrokes = {}
	local function refreshTechNodeStyles()
		for node, stroke in techNodeStrokes do
			local selected = node:GetAttribute("TechnologyName") == selectedTechnologyName
			node.BackgroundColor3 = selected and Color3.fromRGB(98, 122, 255) or HUD_PANEL
			stroke.Color = selected and HUD_WHITE or HUD_GOLD
			stroke.Thickness = selected and 4 or 2
			stroke.Transparency = selected and 0 or 0.05
		end
	end

	local function createTechNode(technology: any, position: UDim2, size: UDim2)
		local shadow = Instance.new("Frame")
		shadow.Name = "TechNodeShadow"
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.BackgroundColor3 = Color3.fromRGB(20, 28, 112)
		shadow.BackgroundTransparency = 0.5
		shadow.BorderSizePixel = 0
		shadow.Position = UDim2.new(position.X.Scale, position.X.Offset + 7, position.Y.Scale, position.Y.Offset + 9)
		shadow.Size = size
		shadow.ZIndex = 1
		shadow.Parent = tree
		addCorner(shadow, UDim.new(0, 22))

		local node = Instance.new("TextButton")
		node.Name = "TechNode"
		node.AnchorPoint = Vector2.new(0.5, 0.5)
		node.AutoButtonColor = true
		node.BackgroundColor3 = HUD_PANEL
		node.BackgroundTransparency = 0.04
		node.BorderSizePixel = 0
		node.Font = Enum.Font.GothamBold
		node.Position = position
		node.Size = size
		node.Text = ""
		node.ZIndex = 2
		node:SetAttribute("TechnologyName", technology.Name)
		node.Parent = tree
		addCorner(node, UDim.new(0, 22))
		local nodeStroke = addStroke(node, HUD_GOLD, 0.05)
		techNodeStrokes[node] = nodeStroke

		local nodeGradient = Instance.new("UIGradient")
		nodeGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(102, 116, 245)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 65, 178)),
		})
		nodeGradient.Rotation = 90
		nodeGradient.Parent = node

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.BackgroundColor3 = HUD_GOLD
		accent.BorderSizePixel = 0
		accent.Position = UDim2.fromOffset(16, 9)
		accent.Size = UDim2.new(1, -32, 0, 4)
		accent.Parent = node
		addCorner(accent, UDim.new(1, 0))

		local titleLabel = createHudLabel(node, technology.Name, UDim2.new(1, -24, 0, 26), 18, true)
		titleLabel.Position = UDim2.fromOffset(12, 20)
		titleLabel.TextColor3 = HUD_WHITE
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center

		local detail = createHudLabel(node, technology.Detail, UDim2.new(1, -24, 1, -70), 12, false)
		detail.Position = UDim2.fromOffset(12, 50)
		detail.TextColor3 = HUD_MUTED
		detail.TextWrapped = true
		detail.TextXAlignment = Enum.TextXAlignment.Center
		detail.TextYAlignment = Enum.TextYAlignment.Top

		local unlock = createHudLabel(
			node,
			string.format("%dс   %s", technology.Seconds or 0, technology.Unlock or "Открытие"),
			UDim2.new(1, -24, 0, 18),
			11,
			true
		)
		unlock.AnchorPoint = Vector2.new(0, 1)
		unlock.BackgroundColor3 = Color3.fromRGB(31, 43, 145)
		unlock.BackgroundTransparency = 0.12
		unlock.BorderSizePixel = 0
		unlock.Position = UDim2.new(0, 12, 1, -10)
		unlock.TextColor3 = Color3.fromRGB(255, 232, 180)
		unlock.TextXAlignment = Enum.TextXAlignment.Center
		addCorner(unlock, UDim.new(0, 8))

		node.MouseButton1Down:Connect(function()
			ignoreNextWorldClick = true
		end)
		node.Activated:Connect(function()
			selectedTechnologyName = technology.Name
			if typeof(technology.Id) == "string" then
				researchTechnologyEvent:FireServer(technology.Id)
			end
			updateTechnologyStatus()
			refreshTechNodeStyles()
		end)
	end

	local treeNodes = {
		{ Technology = TECHNOLOGIES[1], Position = UDim2.fromScale(0.18, 0.55), Size = UDim2.fromOffset(290, 104) },
		{ Technology = TECHNOLOGIES[2], Position = UDim2.fromScale(0.42, 0.38), Size = UDim2.fromOffset(290, 106) },
		{ Technology = TECHNOLOGIES[3], Position = UDim2.fromScale(0.42, 0.56), Size = UDim2.fromOffset(290, 106) },
		{ Technology = TECHNOLOGIES[4], Position = UDim2.fromScale(0.50, 0.75), Size = UDim2.fromOffset(290, 106) },
		{ Technology = { Name = "Колесо", Detail = "Будущая ветка транспорта и быстрых перемещений." }, Position = UDim2.fromScale(0.79, 0.39), Size = UDim2.fromOffset(290, 106) },
		{ Technology = { Name = "Государственность", Detail = "Будущая ветка политики, законов и управления." }, Position = UDim2.fromScale(0.79, 0.58), Size = UDim2.fromOffset(290, 106) },
	}

	treeNodes = {
		{ Technology = TECHNOLOGIES[1], Position = UDim2.fromScale(0.16, 0.42), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[4], Position = UDim2.fromScale(0.16, 0.68), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[2], Position = UDim2.fromScale(0.38, 0.32), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[3], Position = UDim2.fromScale(0.38, 0.52), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[5], Position = UDim2.fromScale(0.38, 0.76), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[6], Position = UDim2.fromScale(0.62, 0.42), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[7], Position = UDim2.fromScale(0.62, 0.72), Size = UDim2.fromOffset(260, 128) },
		{ Technology = TECHNOLOGIES[8], Position = UDim2.fromScale(0.84, 0.72), Size = UDim2.fromOffset(260, 128) },
	}

	for _, node in treeNodes do
		createTechNode(node.Technology, node.Position, node.Size)
	end
	refreshTechNodeStyles()

	technologyGui = gui
	technologyWindow = window
	updateTechnologyStatus()
end

local function showTechnologyWindow()
	if closeTopHudWindows then
		closeTopHudWindows("Technology")
	end

	ensureTechnologyGui()
	updateTechnologyStatus()

	if technologyWindow then
		technologyWindow.Visible = true
	end
end

local function ensureGameHud()
	if gameHudGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "StrategyHudGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundColor3 = HUD_DARK
	topBar.BackgroundTransparency = 0
	topBar.BorderSizePixel = 0
	topBar.Size = UDim2.new(1, 0, 0, 60)
	topBar.Parent = gui
	addStroke(topBar, HUD_GOLD, 0.55)

	local topLine = Instance.new("Frame")
	topLine.Name = "TopLine"
	topLine.BackgroundColor3 = HUD_GOLD
	topLine.BorderSizePixel = 0
	topLine.Position = UDim2.new(0, 0, 1, -4)
	topLine.Size = UDim2.new(1, 0, 0, 4)
	topLine.Parent = topBar

	local country = createHudLabel(topBar, "Новая страна", UDim2.fromOffset(210, 46), 16, true)
	country.Position = UDim2.fromOffset(16, 0)
	country.TextColor3 = Color3.fromRGB(255, 230, 164)
	hudCountryLabel = country
	country.Position = UDim2.fromOffset(235, 8)
	country.Size = UDim2.fromOffset(290, 32)
	country.TextColor3 = HUD_BLACK_TEXT
	country.TextSize = 17

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "PlayerAvatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.BackgroundColor3 = HUD_WHITE
	avatar.BorderSizePixel = 0
	avatar.Image = getAvatarImage(localPlayer.UserId)
	avatar.Position = UDim2.fromOffset(152, -6)
	avatar.Size = UDim2.fromOffset(134, 134)
	avatar.ZIndex = 5
	avatar.Parent = gui
	addCorner(avatar, UDim.new(1, 0))
	addStroke(avatar, HUD_GOLD, 0)

	local resources = Instance.new("Frame")
	resources.Name = "Resources"
	resources.BackgroundTransparency = 1
	resources.AnchorPoint = Vector2.new(1, 0)
	resources.Position = UDim2.new(1, -18, 0, 16)
	resources.Size = UDim2.fromOffset(700, 28)
	resources.Parent = topBar

	local resourceLayout = Instance.new("UIListLayout")
	resourceLayout.FillDirection = Enum.FillDirection.Horizontal
	resourceLayout.Padding = UDim.new(0, 6)
	resourceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resourceLayout.Parent = resources

	hudResourceLabels.Science = createResourceChip(resources, "Наука 0")
	hudResourceLabels.Culture = createResourceChip(resources, "Культура 0")
	hudResourceLabels.Gold = createResourceChip(resources, "Золото 0")
	hudResourceLabels.Iron = createResourceChip(resources, "Железо 0")
	hudResourceLabels.Horses = createResourceChip(resources, "Кони 0")
	hudResourceLabels.Faith = createResourceChip(resources, "Вера 0")
	hudResourceLabels.Food = createResourceChip(resources, "Пища 0")
	hudResourceLabels.Production = createResourceChip(resources, "Произв. 0")

	local topActions = Instance.new("Frame")
	topActions.Name = "TopActions"
	topActions.AnchorPoint = Vector2.new(0.5, 0)
	topActions.BackgroundTransparency = 1
	topActions.Position = UDim2.new(0.5, 0, 0, 29)
	topActions.Size = UDim2.fromOffset(204, 54)
	topActions.Parent = topBar

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionsLayout.Padding = UDim.new(0, 10)
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionsLayout.Parent = topActions

	local nationsButton = createHudButton(topActions, "Список государств", UDim2.fromOffset(150, 28))
	nationsButton.LayoutOrder = 1
	nationsButton.BackgroundColor3 = HUD_DIM_BLUE
	nationsButton.Size = UDim2.fromOffset(54, 54)
	nationsButton.Text = "⚑"
	nationsButton.TextSize = 28
	addCorner(nationsButton, UDim.new(1, 0))
	nationsButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	nationsButton.Activated:Connect(showDiplomacyWindow)

	local citiesButton = createHudButton(topActions, "Список городов", UDim2.fromOffset(136, 28))
	citiesButton.LayoutOrder = 2
	citiesButton.BackgroundColor3 = HUD_DIM_BLUE
	citiesButton.Size = UDim2.fromOffset(54, 54)
	citiesButton.Text = "⌂"
	citiesButton.TextSize = 28
	addCorner(citiesButton, UDim.new(1, 0))
	citiesButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	citiesButton.Activated:Connect(showCityListWindow)

	local technologiesButton = createHudButton(topActions, "Технологии", UDim2.fromOffset(112, 28))
	technologiesButton.LayoutOrder = 3
	technologiesButton.BackgroundColor3 = HUD_DIM_BLUE
	technologiesButton.Size = UDim2.fromOffset(54, 54)
	technologiesButton.Text = "⚗"
	technologiesButton.TextSize = 28
	addCorner(technologiesButton, UDim.new(1, 0))
	technologiesButton.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)
	technologiesButton.Activated:Connect(showTechnologyWindow)

	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.BackgroundColor3 = HUD_DARK
	rightPanel.BackgroundTransparency = 0.08
	rightPanel.BorderSizePixel = 0
	rightPanel.Position = UDim2.new(1, -12, 0, 64)
	rightPanel.Size = UDim2.fromOffset(220, 168)
	rightPanel.Parent = gui
	addPadding(rightPanel, 12)
	addStroke(rightPanel, HUD_GOLD, 0.6)

	local rightTitle = createHudLabel(rightPanel, "Мир", UDim2.new(1, 0, 0, 22), 15, true)
	rightTitle.TextColor3 = Color3.fromRGB(255, 230, 164)

	local rightText = createHudLabel(rightPanel, "Рейтинги\nДипломатия\nГорода-государства\nТорговля", UDim2.new(1, 0, 1, -30), 13, false)
	rightText.Position = UDim2.fromOffset(0, 30)
	rightText.TextColor3 = HUD_MUTED
	rightText.TextYAlignment = Enum.TextYAlignment.Top

	local miniMap = Instance.new("Frame")
	miniMap.Name = "MiniMapPanel"
	miniMap.AnchorPoint = Vector2.new(0, 1)
	miniMap.BackgroundColor3 = HUD_DARK
	miniMap.BackgroundTransparency = 0.04
	miniMap.BorderSizePixel = 0
	miniMap.Position = UDim2.new(0, 16, 1, -16)
	miniMap.Size = UDim2.fromOffset(264, 306)
	miniMap.Parent = gui
	addPadding(miniMap, 10)
	addStroke(miniMap, HUD_GOLD, 0.45)

	local miniTitle = createHudLabel(miniMap, "Вся карта мира", UDim2.new(1, 0, 0, 20), 13, true)
	miniTitle.TextColor3 = Color3.fromRGB(255, 230, 164)

	local mapBox = Instance.new("Frame")
	mapBox.Name = "MapBox"
	mapBox.BackgroundColor3 = Color3.fromRGB(13, 18, 22)
	mapBox.BorderSizePixel = 0
	mapBox.ClipsDescendants = true
	mapBox.Position = UDim2.fromOffset(0, 28)
	mapBox.Size = WORLD_MAP_SIZE
	mapBox.Parent = miniMap
	addStroke(mapBox, Color3.fromRGB(96, 121, 111), 0.45)

	worldMapGrid = Instance.new("Frame")
	worldMapGrid.Name = "TileGrid"
	worldMapGrid.BackgroundTransparency = 1
	worldMapGrid.Size = UDim2.fromScale(1, 1)
	worldMapGrid.Parent = mapBox

	worldMapTerritories = Instance.new("Frame")
	worldMapTerritories.Name = "CountryTerritories"
	worldMapTerritories.BackgroundTransparency = 1
	worldMapTerritories.Size = UDim2.fromScale(1, 1)
	worldMapTerritories.ZIndex = 2
	worldMapTerritories.Parent = mapBox

	worldMapMarkers = Instance.new("Frame")
	worldMapMarkers.Name = "PlayerMarkers"
	worldMapMarkers.BackgroundTransparency = 1
	worldMapMarkers.Size = UDim2.fromScale(1, 1)
	worldMapMarkers.ZIndex = 3
	worldMapMarkers.Parent = mapBox

	local legend = createHudLabel(miniMap, "каждая точка = клетка, круг = игрок", UDim2.new(1, 0, 0, 18), 11, false)
	legend.Position = UDim2.fromOffset(0, 274)
	legend.TextColor3 = HUD_MUTED

	gameHudGui = gui
	updateGameHudCountry()
	updateGameHudResources()
	createWorldMapTiles(worldMapGrid)
	updateWorldMap()
	startWorldMapUpdates()
	startWorldMapTileRefresh()

	if not getMapFolder() then
		Workspace.ChildAdded:Connect(function(child)
			if child.Name == "GeneratedMap" and worldMapGrid then
				startWorldMapTileRefresh()
			end
		end)
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
	window.BackgroundColor3 = HUD_DARK
	window.BackgroundTransparency = 0.03
	window.BorderSizePixel = 0
	window.Position = UDim2.new(1, -16, 1, -16)
	window.Size = UDim2.fromOffset(282, 318)
	window.Visible = false
	window.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 12)
	padding.Parent = window

	local stroke = Instance.new("UIStroke")
	stroke.Color = HUD_GOLD
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Text = "Команды"
	title.TextColor3 = Color3.fromRGB(255, 230, 164)
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
	status.TextColor3 = HUD_MUTED
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
	attackMode = false
	attachMode = false

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
		attackMode = false
		attachMode = false
		clearMovementHighlights()
		showMovementForSelectedUnit()
		setActionStatus("Выберите клетку назначения")
		return
	end

	if actionId == "Attack" then
		movementMode = false
		attackMode = true
		attachMode = false
		clearMovementHighlights()
		showAttackTargetsForSelectedUnit()
		setActionStatus("Выберите вражеский юнит или город")
		return
	end

	if actionId == "AttachTo" then
		movementMode = false
		attackMode = false
		attachMode = true
		clearMovementHighlights()
		setActionStatus("Выберите свой юнит для сопровождения")
		return
	end

	if actionId == "FoundCity" then
		showCityNameDialog()
		return
	end

	movementMode = false
	attackMode = false
	attachMode = false
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
	button.BackgroundColor3 = HUD_PANEL_LIGHT
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamSemibold
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 29)
	button.Text = text
	button.TextColor3 = HUD_TEXT
	button.TextSize = 13
	button.Parent = unitActionList
	addStroke(button, Color3.fromRGB(120, 129, 140), 0.65)

	button.MouseButton1Down:Connect(function()
		ignoreNextWorldClick = true
	end)

	button.Activated:Connect(function()
		handleUnitAction(actionId, text)
	end)
end

local function showUnitActionWindow(model: Model)
	ensureGameHud()
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

	setHudContextForUnit(model)

	if typeof(health) == "number" then
		setActionStatus(string.format("HP %d/%d", math.max(0, math.floor(health + 0.5)), math.floor(maxHealth + 0.5)))
	else
		setActionStatus("Выберите действие")
	end

	local order = 0
	local attackTargetInRange = hasAttackTargetInRange(model)
	for _, action in ACTION_BUTTONS do
		if (not action.SettlerOnly or unitType == "Settler")
			and (not action.BuilderOnly or unitType == "Builder")
			and (not action.AttackOnly or (unit and unit.Attack > 0 and attackTargetInRange))
			and (not action.AttackCapableOnly or (unit and unit.Attack > 0))
			and (not action.AttachedOnly or model:GetAttribute("AttachedToUnitId") ~= nil) then
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
	hideCityProductionWindow()
	selectedUnitId = nil
	selectedUnitModel = nil
	selectedCityModel = nil
	setHudContext("Империя", "Выберите юнит или город", "Режим: без ходов")
end

local function selectUnit(model: Model)
	ensureGameHud()
	clearHighlights()
	hideCityProductionWindow()
	movementMode = true
	attackMode = false
	attachMode = false

	selectedUnitModel = model
	selectedUnitId = model:GetAttribute("UnitId") :: string
	selectedCityModel = nil

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
	showAttackTargetsForSelectedUnit()
end

local function findEnemyUnitAtTile(tile: BasePart): Model?
	local x = tile:GetAttribute("GridX")
	local z = tile:GetAttribute("GridZ")
	if typeof(x) ~= "number" or typeof(z) ~= "number" then
		return nil
	end

	local unitsFolder = getUnitsFolder()
	if not unitsFolder then
		return nil
	end

	for _, unit in unitsFolder:GetChildren() do
		if unit:IsA("Model")
			and unit:GetAttribute("OwnerUserId") ~= localPlayer.UserId
			and unit:GetAttribute("GridX") == x
			and unit:GetAttribute("GridZ") == z then
			return unit
		end
	end

	return nil
end

local function findEnemyCityAtTile(tile: BasePart): Model?
	local x = tile:GetAttribute("GridX")
	local z = tile:GetAttribute("GridZ")
	if typeof(x) ~= "number" or typeof(z) ~= "number" then
		return nil
	end

	local citiesFolder = getCitiesFolder()
	if not citiesFolder then
		return nil
	end

	for _, city in citiesFolder:GetChildren() do
		if city:IsA("Model")
			and city:GetAttribute("OwnerUserId") ~= localPlayer.UserId
			and city:GetAttribute("GridX") == x
			and city:GetAttribute("GridZ") == z then
			return city
		end
	end

	return nil
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

local function requestAttack(targetModel: Model)
	if not selectedUnitId or not selectedUnitModel or not isTargetInAttackRange(selectedUnitModel, targetModel) then
		return
	end

	local targetUnitId = targetModel:GetAttribute("UnitId")
	if typeof(targetUnitId) ~= "string" then
		return
	end

	unitActionEvent:FireServer(selectedUnitId, "Attack", targetUnitId)
	clearSelection()
end

local function requestAttackCity(targetCity: Model)
	if not selectedUnitId or not selectedUnitModel or not isTargetInAttackRange(selectedUnitModel, targetCity) then
		return
	end

	local cityId = targetCity:GetAttribute("CityId")
	if typeof(cityId) ~= "string" then
		return
	end

	unitActionEvent:FireServer(selectedUnitId, "AttackCity", cityId)
	clearSelection()
end

local function requestAttach(targetModel: Model)
	if not selectedUnitId or not attachMode or targetModel == selectedUnitModel then
		return
	end

	local targetUnitId = targetModel:GetAttribute("UnitId")
	if typeof(targetUnitId) ~= "string" then
		return
	end

	unitActionEvent:FireServer(selectedUnitId, "AttachTo", targetUnitId)
	clearSelection()
end

mouse.Button1Down:Connect(function()
	if ignoreNextWorldClick then
		ignoreNextWorldClick = false
		return
	end

	local target = mouse.Target
	local unitModel = findUnitModel(target)

	if unitModel then
		if isOwnedUnit(unitModel) then
			if attachMode then
				requestAttach(unitModel)
			else
				selectUnit(unitModel)
			end
		elseif selectedUnitId and selectedUnitModel and isTargetInAttackRange(selectedUnitModel, unitModel) then
			requestAttack(unitModel)
		end
		return
	end

	local cityModel = findCityModel(target)
	if cityModel then
		if selectedUnitId and selectedUnitModel and cityModel:GetAttribute("OwnerUserId") ~= localPlayer.UserId and isTargetInAttackRange(selectedUnitModel, cityModel) then
			requestAttackCity(cityModel)
			return
		end

		clearHighlights()
		hideUnitActionWindow()
		closeCityNameDialog()
		selectedUnitId = nil
		selectedUnitModel = nil
		selectedCityModel = cityModel
		setHudContextForCity(cityModel)
		showCityProductionWindow(cityModel)
		return
	end

	local tile = findTile(target)
	if tile then
		local enemyUnit = findEnemyUnitAtTile(tile)
		if enemyUnit and selectedUnitId and selectedUnitModel and isTargetInAttackRange(selectedUnitModel, enemyUnit) then
			requestAttack(enemyUnit)
			return
		end

		local enemyCity = findEnemyCityAtTile(tile)
		if enemyCity and selectedUnitId and selectedUnitModel and isTargetInAttackRange(selectedUnitModel, enemyCity) then
			requestAttackCity(enemyCity)
			return
		end

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
	updateGameHudCountry()

	if localPlayer:GetAttribute("CountryName") then
		hideCountryMenu()
	end
end)

for _, attributeName in {
	"TreasuryScience",
	"TreasuryCulture",
	"TreasuryGold",
	"TreasuryIron",
	"TreasuryHorses",
	"TreasuryFaith",
	"TreasuryFood",
	"TreasuryProduction",
} do
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(updateGameHudResources)
end

for _, attributeName in {
	"CurrentResearchName",
	"ResearchSecondsLeft",
	"LastResearchMessage",
} do
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(updateTechnologyStatus)
end

warNotificationEvent.OnClientEvent:Connect(showWarNotification)

ensureGameHud()
showCountryMenu()
