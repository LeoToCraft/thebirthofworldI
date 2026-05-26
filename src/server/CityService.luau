local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CityConfig = require(ReplicatedStorage.Shared.CityConfig)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local CityService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local CITIES_FOLDER_NAME = "Cities"
local TERRITORY_FOLDER_NAME = "CityBorders"
local REMOTES_FOLDER_NAME = "Remotes"
local CREATE_COUNTRY_EVENT_NAME = "CreateCountry"
local DIPLOMACY_ACTION_EVENT_NAME = "DiplomacyAction"
local DELETE_CITY_EVENT_NAME = "DeleteCity"
local WAR_NOTIFICATION_EVENT_NAME = "WarNotification"
local COUNTRY_NAME_ATTRIBUTE = "CountryName"
local CITY_HEALTH_BAR_NAME = "CityHealthBar"

local citiesById = {}
local cityCountByOwner = {}
local treasuryByOwner: { [number]: { Food: number, Production: number, Gold: number, Iron: number, Horses: number } } = {}
local diplomacyByPair: { [string]: string } = {}

local function getTileName(x: number, z: number): string
	return string.format("Tile_%03d_%03d", x, z)
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild(MAP_FOLDER_NAME) :: Folder?
end

local function getCitiesFolder(): Folder
	local citiesFolder = Workspace:FindFirstChild(CITIES_FOLDER_NAME)
	if citiesFolder then
		return citiesFolder :: Folder
	end

	local newCitiesFolder = Instance.new("Folder")
	newCitiesFolder.Name = CITIES_FOLDER_NAME
	newCitiesFolder.Parent = Workspace

	return newCitiesFolder
end

local function getTerritoryFolder(): Folder
	local territoryFolder = Workspace:FindFirstChild(TERRITORY_FOLDER_NAME)
	if territoryFolder then
		return territoryFolder :: Folder
	end

	local newTerritoryFolder = Instance.new("Folder")
	newTerritoryFolder.Name = TERRITORY_FOLDER_NAME
	newTerritoryFolder.Parent = Workspace

	return newTerritoryFolder
end

local function getOrCreateCreateCountryEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local createCountryEvent = remotesFolder:FindFirstChild(CREATE_COUNTRY_EVENT_NAME)
	if createCountryEvent and createCountryEvent:IsA("RemoteEvent") then
		return createCountryEvent
	end

	local newCreateCountryEvent = Instance.new("RemoteEvent")
	newCreateCountryEvent.Name = CREATE_COUNTRY_EVENT_NAME
	newCreateCountryEvent.Parent = remotesFolder

	return newCreateCountryEvent
end

local function getOrCreateDiplomacyActionEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local diplomacyActionEvent = remotesFolder:FindFirstChild(DIPLOMACY_ACTION_EVENT_NAME)
	if diplomacyActionEvent and diplomacyActionEvent:IsA("RemoteEvent") then
		return diplomacyActionEvent
	end

	local newDiplomacyActionEvent = Instance.new("RemoteEvent")
	newDiplomacyActionEvent.Name = DIPLOMACY_ACTION_EVENT_NAME
	newDiplomacyActionEvent.Parent = remotesFolder

	return newDiplomacyActionEvent
end

local function getOrCreateDeleteCityEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local deleteCityEvent = remotesFolder:FindFirstChild(DELETE_CITY_EVENT_NAME)
	if deleteCityEvent and deleteCityEvent:IsA("RemoteEvent") then
		return deleteCityEvent
	end

	local newDeleteCityEvent = Instance.new("RemoteEvent")
	newDeleteCityEvent.Name = DELETE_CITY_EVENT_NAME
	newDeleteCityEvent.Parent = remotesFolder

	return newDeleteCityEvent
end

local function getOrCreateWarNotificationEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local warNotificationEvent = remotesFolder:FindFirstChild(WAR_NOTIFICATION_EVENT_NAME)
	if warNotificationEvent and warNotificationEvent:IsA("RemoteEvent") then
		return warNotificationEvent
	end

	local newWarNotificationEvent = Instance.new("RemoteEvent")
	newWarNotificationEvent.Name = WAR_NOTIFICATION_EVENT_NAME
	newWarNotificationEvent.Parent = remotesFolder

	return newWarNotificationEvent
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

local function isAllowedCityTile(tile: BasePart): boolean
	local biome = tile:GetAttribute("Biome")

	return typeof(biome) == "string" and CityConfig.Placement.AllowedBiomes[biome] == true
end

local function hasCity(tile: BasePart): boolean
	return tile:GetAttribute("HasCity") == true
end

local function isFarEnoughFromCities(x: number, z: number): boolean
	for _, cityState in citiesById do
		local distance = math.max(math.abs(x - cityState.GridX), math.abs(z - cityState.GridZ))
		if distance < CityConfig.Placement.MinDistanceFromOtherCities then
			return false
		end
	end

	return true
end

local function getNextCityName(player: any): string
	local nextIndex = (cityCountByOwner[player.UserId] or 0) + 1
	cityCountByOwner[player.UserId] = nextIndex
	local prefix = "Город"
	if typeof(player) ~= "Instance" and typeof(player.CityNamePrefix) == "string" then
		prefix = player.CityNamePrefix
	end

	return string.format("%s %d", prefix, nextIndex)
end

local function getCityName(player: any, requestedCityName: string?): string
	if typeof(requestedCityName) == "string" then
		local trimmed = requestedCityName:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			return string.sub(trimmed, 1, 40)
		end
	end

	return getNextCityName(player)
end

local function sanitizeName(name: any, fallback: string, maxLength: number): string
	if typeof(name) == "string" then
		local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			return string.sub(trimmed, 1, maxLength)
		end
	end

	return fallback
end

local function getCountryName(player: any): string
	if typeof(player) == "Instance" and player:IsA("Player") then
		return sanitizeName(player:GetAttribute(COUNTRY_NAME_ATTRIBUTE), player.Name, 32)
	end

	return sanitizeName(player.CountryName, player.Name or "Bot", 32)
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

local function addCityNameplate(model: Model, cityName: string, countryName: string, tile: BasePart)
	local existing = model:FindFirstChild("CityNameAnchor")
	if existing then
		existing:Destroy()
	end

	local tileTopY = tile.Position.Y + tile.Size.Y / 2

	local anchor = Instance.new("Part")
	anchor.Name = "CityNameAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = Vector3.new(tile.Position.X, tileTopY + 2.35, tile.Position.Z)
	anchor.Parent = model

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "CityNameplate"
	nameplate.AlwaysOnTop = true
	nameplate.MaxDistance = 400
	nameplate.Size = UDim2.fromOffset(180, 48)
	nameplate.StudsOffset = Vector3.new(0, 0, 0)
	nameplate.Parent = anchor

	local countryLabel = Instance.new("TextLabel")
	countryLabel.Name = "CountryName"
	countryLabel.BackgroundTransparency = 1
	countryLabel.Font = Enum.Font.GothamBold
	countryLabel.Position = UDim2.fromScale(0, 0)
	countryLabel.Size = UDim2.new(1, 0, 0.45, 0)
	countryLabel.Text = countryName
	countryLabel.TextColor3 = Color3.fromRGB(166, 222, 255)
	countryLabel.TextScaled = true
	countryLabel.TextStrokeTransparency = 0.25
	countryLabel.Parent = nameplate

	local label = Instance.new("TextLabel")
	label.Name = "CityName"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Position = UDim2.fromScale(0, 0.43)
	label.Size = UDim2.new(1, 0, 0.57, 0)
	label.Text = cityName
	label.TextColor3 = Color3.fromRGB(255, 247, 214)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.Parent = nameplate
end

local function getCityMaxHealth(model: Model): number
	local maxHealth = model:GetAttribute("MaxHealth")
	if typeof(maxHealth) == "number" and maxHealth > 0 then
		return maxHealth
	end

	return CityConfig.Starting.Health
end

local function updateCityHealthBar(model: Model)
	local anchor = model:FindFirstChild("CityNameAnchor")
	local adornee = anchor and anchor:IsA("BasePart") and anchor or model.PrimaryPart or getFirstBasePart(model)
	if not adornee then
		return
	end

	local healthBar = adornee:FindFirstChild(CITY_HEALTH_BAR_NAME)
	if not healthBar or not healthBar:IsA("BillboardGui") then
		return
	end

	local container = healthBar:FindFirstChild("Container")
	local fill = container and container:FindFirstChild("Fill")
	local label = healthBar:FindFirstChild("HealthText")
	if not container or not container:IsA("Frame") or not fill or not fill:IsA("Frame") then
		return
	end

	local maxHealth = getCityMaxHealth(model)
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

local function addCityHealthBar(model: Model)
	local anchor = model:FindFirstChild("CityNameAnchor")
	local adornee = anchor and anchor:IsA("BasePart") and anchor or model.PrimaryPart or getFirstBasePart(model)
	if not adornee then
		return
	end

	local existing = adornee:FindFirstChild(CITY_HEALTH_BAR_NAME)
	if existing then
		existing:Destroy()
	end

	local healthBar = Instance.new("BillboardGui")
	healthBar.Name = CITY_HEALTH_BAR_NAME
	healthBar.AlwaysOnTop = true
	healthBar.MaxDistance = 420
	healthBar.Size = UDim2.fromOffset(110, 18)
	healthBar.StudsOffset = Vector3.new(0, -0.35, 0)
	healthBar.Parent = adornee

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	container.BorderSizePixel = 0
	container.Position = UDim2.fromScale(0.5, 1)
	container.Size = UDim2.new(1, 0, 0, 8)
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

	local healthConnection = model:GetAttributeChangedSignal("Health"):Connect(function()
		updateCityHealthBar(model)
	end)
	local maxHealthConnection = model:GetAttributeChangedSignal("MaxHealth"):Connect(function()
		updateCityHealthBar(model)
	end)
	local destroyingConnection
	destroyingConnection = model.Destroying:Connect(function()
		healthConnection:Disconnect()
		maxHealthConnection:Disconnect()
		destroyingConnection:Disconnect()
	end)

	updateCityHealthBar(model)
end

local function placeCityModel(model: Model, tile: BasePart)
	local boundingBoxCFrame, size = model:GetBoundingBox()
	local tileTopY = tile.Position.Y + tile.Size.Y / 2
	local position = Vector3.new(tile.Position.X, tileTopY + size.Y / 2 + 0.04, tile.Position.Z)
	local targetBoundingBoxCFrame = CFrame.new(position)
	local currentPivot = model:GetPivot()
	local targetPivot = targetBoundingBoxCFrame * boundingBoxCFrame:Inverse() * currentPivot

	model:PivotTo(targetPivot)
end

local function createFallbackCityVisual(cityName: string, tile: BasePart): Model
	local model = Instance.new("Model")
	model.Name = cityName

	local base = Instance.new("Part")
	base.Name = "CityCenter"
	base.Anchored = true
	base.CanCollide = false
	base.Color = CityConfig.Visual.Color
	base.Material = CityConfig.Visual.Material
	base.Size = Vector3.new(MapConfig.Tile.Width * 0.82, 0.65, MapConfig.Tile.Length * 0.82)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	local tower = Instance.new("Part")
	tower.Name = "Tower"
	tower.Anchored = true
	tower.CanCollide = false
	tower.Color = Color3.fromRGB(232, 214, 156)
	tower.Material = Enum.Material.Slate
	tower.Size = Vector3.new(0.8, 1.25, 0.8)
	tower.TopSurface = Enum.SurfaceType.Smooth
	tower.BottomSurface = Enum.SurfaceType.Smooth
	tower.Parent = model

	model.PrimaryPart = base

	local tileTopY = tile.Position.Y + tile.Size.Y / 2
	base.Position = Vector3.new(tile.Position.X, tileTopY + base.Size.Y / 2 + 0.04, tile.Position.Z)
	tower.Position = Vector3.new(tile.Position.X, base.Position.Y + base.Size.Y / 2 + tower.Size.Y / 2, tile.Position.Z)

	return model
end

local function createCityVisual(cityName: string, tile: BasePart): Model
	local storedModel = ServerStorage:FindFirstChild(CityConfig.Visual.ModelName)
	if not storedModel then
		return createFallbackCityVisual(cityName, tile)
	end

	local clone = storedModel:Clone()
	local model: Model

	if clone:IsA("Model") then
		model = clone
	elseif clone:IsA("BasePart") then
		model = Instance.new("Model")
		clone.Parent = model
		model.PrimaryPart = clone
	else
		clone:Destroy()
		return createFallbackCityVisual(cityName, tile)
	end

	model.Name = cityName

	local primaryPart = model.PrimaryPart or getFirstBasePart(model)
	if not primaryPart then
		model:Destroy()
		return createFallbackCityVisual(cityName, tile)
	end

	model.PrimaryPart = primaryPart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	placeCityModel(model, tile)

	return model
end

local function setCityAttributes(model: Model, cityId: string, player: any, cityName: string, countryName: string, x: number, z: number)
	model:SetAttribute("CityId", cityId)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("CityName", cityName)
	model:SetAttribute("CountryName", countryName)
	model:SetAttribute("GridX", x)
	model:SetAttribute("GridZ", z)
	model:SetAttribute("TerritoryRadius", CityConfig.Territory.Radius)
	model:SetAttribute("Population", CityConfig.Starting.Population)
	model:SetAttribute("Food", CityConfig.Starting.Food)
	model:SetAttribute("Production", CityConfig.Starting.Production)
	model:SetAttribute("MaxHealth", CityConfig.Starting.Health)
	model:SetAttribute("Health", CityConfig.Starting.Health)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("CityId", cityId)
			descendant:SetAttribute("OwnerUserId", player.UserId)
			descendant:SetAttribute("CountryName", countryName)
			descendant:SetAttribute("GridX", x)
			descendant:SetAttribute("GridZ", z)
		end
	end
end

local function getNumberAttribute(instance: Instance, attributeName: string): number
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return 0
end

local function setCityYieldAttributes(model: Model, tile: BasePart)
	local food = getNumberAttribute(tile, "FoodYield")
	local production = getNumberAttribute(tile, "ProductionYield")
	local gold = getNumberAttribute(tile, "GoldYield")

	model:SetAttribute("FoodPerTurn", food)
	model:SetAttribute("ProductionPerTurn", production)
	model:SetAttribute("GoldPerTurn", gold)
end

local function getCountryColor(userId: number): Color3
	local hue = ((userId * 37) % 360) / 360
	return Color3.fromHSV(hue, 0.58, 0.95)
end

local function getOwnerTerritoryFolderName(ownerUserId: number): string
	if ownerUserId < 0 then
		return "Owner_n" .. tostring(math.abs(ownerUserId))
	end

	return "Owner_p" .. tostring(ownerUserId)
end

local function getTerritoryKey(x: number, z: number): string
	return tostring(x) .. ":" .. tostring(z)
end

local function addCityTerritoryToSet(territoryTiles: { [string]: { X: number, Z: number } }, centerX: number, centerZ: number)
	local radius = CityConfig.Territory.Radius

	for x = centerX - radius, centerX + radius do
		for z = centerZ - radius, centerZ + radius do
			if x >= 1 and x <= MapConfig.Map.Width and z >= 1 and z <= MapConfig.Map.Length then
				territoryTiles[getTerritoryKey(x, z)] = { X = x, Z = z }
			end
		end
	end
end

local function addCityBorderToSet(borderTiles: { [string]: { X: number, Z: number } }, centerX: number, centerZ: number)
	local radius = CityConfig.Territory.BorderRadius or CityConfig.Territory.Radius

	for x = centerX - radius, centerX + radius do
		for z = centerZ - radius, centerZ + radius do
			if x >= 1 and x <= MapConfig.Map.Width and z >= 1 and z <= MapConfig.Map.Length then
				borderTiles[getTerritoryKey(x, z)] = { X = x, Z = z }
			end
		end
	end
end

local function isTerritoryEdge(territoryTiles: { [string]: { X: number, Z: number } }, x: number, z: number): boolean
	local directions = {
		{ X = 1, Z = 0 },
		{ X = -1, Z = 0 },
		{ X = 0, Z = 1 },
		{ X = 0, Z = -1 },
		{ X = 1, Z = 1 },
		{ X = 1, Z = -1 },
		{ X = -1, Z = 1 },
		{ X = -1, Z = -1 },
	}

	for _, direction in directions do
		if not territoryTiles[getTerritoryKey(x + direction.X, z + direction.Z)] then
			return true
		end
	end

	return false
end

local function rebuildOwnerTerritory(ownerUserId: number)
	local parent = getTerritoryFolder()
	local folderName = getOwnerTerritoryFolderName(ownerUserId)
	local existing = parent:FindFirstChild(folderName)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder:SetAttribute("OwnerUserId", ownerUserId)
	folder.Parent = parent

	local territoryTiles = {}
	local borderTiles = {}
	for _, cityState in citiesById do
		if cityState.OwnerUserId == ownerUserId then
			addCityTerritoryToSet(territoryTiles, cityState.GridX, cityState.GridZ)
			addCityBorderToSet(borderTiles, cityState.GridX, cityState.GridZ)
		end
	end

	local color = getCountryColor(ownerUserId)

	for _, position in territoryTiles do
		local tile = getTile(position.X, position.Z)
		if tile then
			local marker = Instance.new("Part")
			marker.Name = "Territory"
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.Color = color
			marker.Material = Enum.Material.SmoothPlastic
			marker.Size = Vector3.new(MapConfig.Tile.Width * 0.98, 0.035, MapConfig.Tile.Length * 0.98)
			marker.Transparency = CityConfig.Territory.FillTransparency
			marker.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + 0.11, tile.Position.Z)
			marker:SetAttribute("OwnerUserId", ownerUserId)
			marker:SetAttribute("GridX", position.X)
			marker:SetAttribute("GridZ", position.Z)
			marker.Parent = folder
		end
	end

	local borderDirections = {
		{ X = 1, Z = 0 },
		{ X = -1, Z = 0 },
		{ X = 0, Z = 1 },
		{ X = 0, Z = -1 },
	}
	local thickness = 0.16

	for _, position in borderTiles do
		local tile = getTile(position.X, position.Z)
		if tile then
			for _, direction in borderDirections do
				if not borderTiles[getTerritoryKey(position.X + direction.X, position.Z + direction.Z)] then
					local marker = Instance.new("Part")
					marker.Name = "Border"
					marker.Anchored = true
					marker.CanCollide = false
					marker.CanQuery = false
					marker.Color = color
					marker.Material = Enum.Material.SmoothPlastic
					marker.Transparency = CityConfig.Territory.BorderTransparency
					marker.Size = direction.X ~= 0
						and Vector3.new(thickness, 0.09, MapConfig.Tile.Length * 1.04)
						or Vector3.new(MapConfig.Tile.Width * 1.04, 0.09, thickness)
					marker.Position = Vector3.new(
						tile.Position.X + direction.X * MapConfig.Tile.Width / 2,
						tile.Position.Y + tile.Size.Y / 2 + 0.14,
						tile.Position.Z + direction.Z * MapConfig.Tile.Length / 2
					)
					marker:SetAttribute("OwnerUserId", ownerUserId)
					marker:SetAttribute("GridX", position.X)
					marker:SetAttribute("GridZ", position.Z)
					marker.Parent = folder
				end
			end
		end
	end
end

local function getRelationAttributeName(otherUserId: number): string
	if otherUserId < 0 then
		return "Relation_n" .. tostring(math.abs(otherUserId))
	end

	return "Relation_p" .. tostring(otherUserId)
end

local function getPairKey(firstUserId: number, secondUserId: number): string
	if firstUserId < secondUserId then
		return tostring(firstUserId) .. ":" .. tostring(secondUserId)
	end

	return tostring(secondUserId) .. ":" .. tostring(firstUserId)
end

local function getRelation(firstUserId: number, secondUserId: number): string
	if firstUserId == secondUserId then
		return "Self"
	end

	return diplomacyByPair[getPairKey(firstUserId, secondUserId)] or "Peace"
end

local function getOwnerDisplayName(ownerUserId: number): string
	local player = Players:GetPlayerByUserId(ownerUserId)
	if player then
		return sanitizeName(player:GetAttribute(COUNTRY_NAME_ATTRIBUTE), player.Name, 32)
	end

	for _, cityState in citiesById do
		if cityState.OwnerUserId == ownerUserId then
			return sanitizeName(cityState.CountryName, "Неизвестная держава", 32)
		end
	end

	return ownerUserId < 0 and "Бот" or "Игрок"
end

local function notifyWarDeclared(attackerUserId: number, defenderUserId: number, reason: string)
	local defender = Players:GetPlayerByUserId(defenderUserId)
	if not defender then
		return
	end

	getOrCreateWarNotificationEvent():FireClient(defender, {
		From = getOwnerDisplayName(attackerUserId),
		To = getOwnerDisplayName(defenderUserId),
		Reason = reason,
	})
end

local function setRelation(firstUserId: number, secondUserId: number, relation: string, reason: string?)
	if firstUserId == secondUserId then
		return
	end

	local pairKey = getPairKey(firstUserId, secondUserId)
	local previousRelation = diplomacyByPair[pairKey] or "Peace"
	diplomacyByPair[pairKey] = relation

	for _, player in Players:GetPlayers() do
		if player.UserId == firstUserId then
			player:SetAttribute(getRelationAttributeName(secondUserId), relation)
		elseif player.UserId == secondUserId then
			player:SetAttribute(getRelationAttributeName(firstUserId), relation)
		end
	end

	if relation == "War" and previousRelation ~= "War" then
		notifyWarDeclared(firstUserId, secondUserId, reason or "Причина не указана")
	end
end

local function ownerHasCity(ownerUserId: number): boolean
	for _, cityState in citiesById do
		if cityState.OwnerUserId == ownerUserId then
			return true
		end
	end

	return false
end

local function syncPlayerDiplomacy(player: Player)
	for _, cityState in citiesById do
		if cityState.OwnerUserId ~= player.UserId then
			player:SetAttribute(getRelationAttributeName(cityState.OwnerUserId), getRelation(player.UserId, cityState.OwnerUserId))
		end
	end
end

local function getOwnerTreasury(ownerUserId: number)
	if not treasuryByOwner[ownerUserId] then
		treasuryByOwner[ownerUserId] = {
			Food = 0,
			Production = 0,
			Gold = 0,
			Iron = 0,
			Horses = 0,
		}
	end

	return treasuryByOwner[ownerUserId]
end

local function syncPlayerTreasury(player: Player)
	local treasury = getOwnerTreasury(player.UserId)
	player:SetAttribute("TreasuryFood", treasury.Food)
	player:SetAttribute("TreasuryProduction", treasury.Production)
	player:SetAttribute("TreasuryGold", treasury.Gold)
	player:SetAttribute("TreasuryIron", treasury.Iron)
	player:SetAttribute("TreasuryHorses", treasury.Horses)
	player:SetAttribute("TreasuryScience", player:GetAttribute("TreasuryScience") or 0)
	player:SetAttribute("TreasuryCulture", player:GetAttribute("TreasuryCulture") or 0)
	player:SetAttribute("TreasuryFaith", player:GetAttribute("TreasuryFaith") or 0)
end

local function addTreasury(ownerUserId: number, food: number, production: number, gold: number, iron: number?, horses: number?)
	local treasury = getOwnerTreasury(ownerUserId)
	treasury.Food += food or 0
	treasury.Production += production or 0
	treasury.Gold += gold or 0
	treasury.Iron += iron or 0
	treasury.Horses += horses or 0

	local player = Players:GetPlayerByUserId(ownerUserId)
	if player then
		syncPlayerTreasury(player)
	end
end

local function scaleYield(value: number): number
	if value <= 0 then
		return 0
	end

	return math.max(1, math.floor(value * (CityConfig.Economy.YieldMultiplier or 1) + 0.5))
end

local function calculateCityYields(centerX: number, centerZ: number): (number, number, number, number, number)
	local food = 0
	local production = 0
	local gold = 0
	local iron = 0
	local horses = 0
	local radius = CityConfig.Territory.Radius

	for x = centerX - radius, centerX + radius do
		for z = centerZ - radius, centerZ + radius do
			local distance = math.max(math.abs(x - centerX), math.abs(z - centerZ))
			if distance <= radius then
				local tile = getTile(x, z)
				if tile and (tile:GetAttribute("HasCity") == true or tile:GetAttribute("ImprovedResource") == true) then
					food += getNumberAttribute(tile, "FoodYield")
					production += getNumberAttribute(tile, "ProductionYield")
					gold += getNumberAttribute(tile, "GoldYield")
					local strategicYield = getNumberAttribute(tile, "StrategicYield")
					if tile:GetAttribute("ImprovedResource") == true and strategicYield > 0 then
						local resourceType = tile:GetAttribute("ResourceType")
						if resourceType == "Iron" then
							iron += strategicYield
						elseif resourceType == "Horses" then
							horses += strategicYield
						end
					end
				end
			end
		end
	end

	return food, production, gold, iron, horses
end

local function setCityYields(cityState, food: number, production: number, gold: number, iron: number, horses: number)
	cityState.FoodPerTurn = food
	cityState.ProductionPerTurn = production
	cityState.GoldPerTurn = gold
	cityState.IronPerTurn = iron
	cityState.HorsesPerTurn = horses

	if cityState.Model then
		cityState.Model:SetAttribute("FoodPerTurn", food)
		cityState.Model:SetAttribute("ProductionPerTurn", production)
		cityState.Model:SetAttribute("GoldPerTurn", gold)
		cityState.Model:SetAttribute("IronPerTurn", iron)
		cityState.Model:SetAttribute("HorsesPerTurn", horses)
	end
end

local function refreshCityYields(cityId: string)
	local cityState = citiesById[cityId]
	if not cityState then
		return
	end

	local food, production, gold, iron, horses = calculateCityYields(cityState.GridX, cityState.GridZ)
	setCityYields(cityState, food, production, gold, iron, horses)
end

local function startEconomyLoop()
	task.spawn(function()
		while true do
			task.wait(CityConfig.Economy.TickSeconds)

			for cityId, cityState in citiesById do
				refreshCityYields(cityId)
				addTreasury(
					cityState.OwnerUserId,
					scaleYield(cityState.FoodPerTurn or 0),
					scaleYield(cityState.ProductionPerTurn or 0),
					scaleYield(cityState.GoldPerTurn or 0),
					scaleYield(cityState.IronPerTurn or 0),
					scaleYield(cityState.HorsesPerTurn or 0)
				)
			end
		end
	end)
end

local function onCreateCountry(player: Player, requestedCountryName: string)
	local countryName = sanitizeName(requestedCountryName, player.Name, 32)
	player:SetAttribute(COUNTRY_NAME_ATTRIBUTE, countryName)
end

local function onDiplomacyAction(player: Player, targetOwnerUserId: number, actionId: string)
	if typeof(targetOwnerUserId) ~= "number" or typeof(actionId) ~= "string" or targetOwnerUserId == player.UserId then
		return
	end

	if not ownerHasCity(targetOwnerUserId) then
		return
	end

	if actionId == "DeclareWar" then
		setRelation(player.UserId, targetOwnerUserId, "War", "Дипломатическое объявление войны")
		player:SetAttribute("LastDiplomacyMessage", "Война объявлена")
	elseif actionId == "MakePeace" then
		setRelation(player.UserId, targetOwnerUserId, "Peace")
		player:SetAttribute("LastDiplomacyMessage", "Мир заключён")
	elseif actionId == "Trade" and getRelation(player.UserId, targetOwnerUserId) ~= "War" then
		addTreasury(player.UserId, 0, 0, CityConfig.Economy.TradeGold)
		local targetPlayer = Players:GetPlayerByUserId(targetOwnerUserId)
		if targetPlayer then
			addTreasury(targetOwnerUserId, 0, 0, CityConfig.Economy.TradeGold)
		end
		player:SetAttribute("LastDiplomacyMessage", "Сделка принесла золото")
	end
end

local function removeCity(cityId: string)
	local cityState = citiesById[cityId]
	if not cityState then
		return
	end

	local tile = getTile(cityState.GridX, cityState.GridZ)
	if tile then
		tile:SetAttribute("HasCity", false)
		tile:SetAttribute("CityId", nil)
	end

	if cityState.Model then
		cityState.Model:Destroy()
	end

	citiesById[cityId] = nil
	rebuildOwnerTerritory(cityState.OwnerUserId)
	for _, existingPlayer in Players:GetPlayers() do
		syncPlayerDiplomacy(existingPlayer)
	end
end

local function onDeleteCity(player: Player, cityId: string)
	if typeof(cityId) ~= "string" then
		return
	end

	local cityState = citiesById[cityId]
	if not cityState or cityState.OwnerUserId ~= player.UserId then
		return
	end

	removeCity(cityId)
end

function CityService.CanFoundCity(x: number, z: number): (boolean, string?)
	local tile = getTile(x, z)
	if not tile then
		return false, "No tile at this position"
	end

	if not isAllowedCityTile(tile) then
		return false, "Cities can be founded only on land"
	end

	if hasCity(tile) then
		return false, "This tile already has a city"
	end

	if not isFarEnoughFromCities(x, z) then
		return false, "Another city is too close"
	end

	return true, nil
end

function CityService.FoundCity(player: any, x: number, z: number, requestedCityName: string?): (Model?, string?)
	local canFound, reason = CityService.CanFoundCity(x, z)
	if not canFound then
		return nil, reason
	end

	local tile = getTile(x, z)
	if not tile then
		return nil, "No tile at this position"
	end

	local cityId = HttpService:GenerateGUID(false)
	local cityName = getCityName(player, requestedCityName)
	local countryName = getCountryName(player)
	local cityModel = createCityVisual(cityName, tile)
	setCityAttributes(cityModel, cityId, player, cityName, countryName, x, z)
	setCityYieldAttributes(cityModel, tile)
	addCityNameplate(cityModel, cityName, countryName, tile)
	addCityHealthBar(cityModel)
	cityModel.Parent = getCitiesFolder()
	tile:SetAttribute("HasCity", true)
	tile:SetAttribute("CityId", cityId)

	citiesById[cityId] = {
		Model = cityModel,
		OwnerUserId = player.UserId,
		CountryName = countryName,
		GridX = x,
		GridZ = z,
		Population = CityConfig.Starting.Population,
		Food = CityConfig.Starting.Food,
		Production = CityConfig.Starting.Production,
		Health = CityConfig.Starting.Health,
		MaxHealth = CityConfig.Starting.Health,
		FoodPerTurn = cityModel:GetAttribute("FoodPerTurn"),
		ProductionPerTurn = cityModel:GetAttribute("ProductionPerTurn"),
		GoldPerTurn = cityModel:GetAttribute("GoldPerTurn"),
		IronPerTurn = cityModel:GetAttribute("IronPerTurn"),
		HorsesPerTurn = cityModel:GetAttribute("HorsesPerTurn"),
	}
	refreshCityYields(cityId)
	rebuildOwnerTerritory(player.UserId)
	for _, existingPlayer in Players:GetPlayers() do
		syncPlayerDiplomacy(existingPlayer)
	end

	return cityModel, nil
end

function CityService.GetCity(cityId: string)
	return citiesById[cityId]
end

function CityService.GetCities()
	return citiesById
end

function CityService.DamageCity(attackerOwnerUserId: number, cityId: string, amount: number): boolean
	local cityState = citiesById[cityId]
	if not cityState or cityState.OwnerUserId == attackerOwnerUserId or amount <= 0 then
		return false
	end

	if not CityService.AreAtWar(attackerOwnerUserId, cityState.OwnerUserId) then
		CityService.SetWar(attackerOwnerUserId, cityState.OwnerUserId, true, "Военное нападение")
	end

	local nextHealth = math.max(0, (cityState.Health or CityConfig.Starting.Health) - amount)
	cityState.Health = nextHealth

	if cityState.Model then
		cityState.Model:SetAttribute("Health", nextHealth)
	end

	if nextHealth > 0 then
		return true
	end

	local tile = getTile(cityState.GridX, cityState.GridZ)
	if tile then
		tile:SetAttribute("HasCity", false)
		tile:SetAttribute("CityId", nil)
	end

	if cityState.Model then
		cityState.Model:Destroy()
	end

	citiesById[cityId] = nil
	rebuildOwnerTerritory(cityState.OwnerUserId)
	for _, existingPlayer in Players:GetPlayers() do
		syncPlayerDiplomacy(existingPlayer)
	end

	return true
end

function CityService.RefreshYieldsNear(ownerUserId: number, x: number, z: number)
	for cityId, cityState in citiesById do
		if cityState.OwnerUserId == ownerUserId then
			local distance = math.max(math.abs(x - cityState.GridX), math.abs(z - cityState.GridZ))
			if distance <= CityConfig.Territory.Radius then
				refreshCityYields(cityId)
			end
		end
	end
end

function CityService.AddTreasury(ownerUserId: number, food: number, production: number, gold: number, iron: number?, horses: number?)
	addTreasury(ownerUserId, food, production, gold, iron, horses)
end

function CityService.AreAtWar(firstUserId: number, secondUserId: number): boolean
	return getRelation(firstUserId, secondUserId) == "War"
end

function CityService.GetTerritoryOwnerAt(x: number, z: number): number?
	local radius = CityConfig.Territory.Radius
	local bestOwnerUserId = nil
	local bestDistance = math.huge

	for _, cityState in citiesById do
		local distance = math.max(math.abs(x - cityState.GridX), math.abs(z - cityState.GridZ))
		if distance <= radius and distance < bestDistance then
			bestOwnerUserId = cityState.OwnerUserId
			bestDistance = distance
		end
	end

	return bestOwnerUserId
end

function CityService.CanOwnerEnterTile(ownerUserId: number, x: number, z: number): boolean
	local territoryOwnerUserId = CityService.GetTerritoryOwnerAt(x, z)
	if not territoryOwnerUserId or territoryOwnerUserId == ownerUserId then
		return true
	end

	return CityService.AreAtWar(ownerUserId, territoryOwnerUserId)
end

function CityService.SetWar(firstUserId: number, secondUserId: number, atWar: boolean, reason: string?)
	setRelation(firstUserId, secondUserId, atWar and "War" or "Peace", reason)
end

function CityService.Start()
	getCitiesFolder()
	getTerritoryFolder()
	getOrCreateWarNotificationEvent()
	getOrCreateCreateCountryEvent().OnServerEvent:Connect(onCreateCountry)
	getOrCreateDiplomacyActionEvent().OnServerEvent:Connect(onDiplomacyAction)
	getOrCreateDeleteCityEvent().OnServerEvent:Connect(onDeleteCity)

	Players.PlayerAdded:Connect(function(player)
		syncPlayerTreasury(player)
		syncPlayerDiplomacy(player)
	end)
	for _, player in Players:GetPlayers() do
		syncPlayerTreasury(player)
		syncPlayerDiplomacy(player)
	end

	startEconomyLoop()
end

return CityService
