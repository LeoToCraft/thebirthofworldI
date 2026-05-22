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
local COUNTRY_NAME_ATTRIBUTE = "CountryName"

local citiesById = {}
local cityCountByOwner = {}
local treasuryByOwner: { [number]: { Food: number, Production: number, Gold: number } } = {}

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

	return string.format("%s City %d", player.Name, nextIndex)
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

local function isTerritoryEdge(centerX: number, centerZ: number, x: number, z: number): boolean
	local radius = CityConfig.Territory.Radius
	local distance = math.abs(x - centerX) + math.abs(z - centerZ)

	return distance == radius
end

local function createTerritoryMarker(cityId: string, ownerUserId: number, centerX: number, centerZ: number)
	local parent = getTerritoryFolder()
	local existing = parent:FindFirstChild(cityId)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = cityId
	folder:SetAttribute("OwnerUserId", ownerUserId)
	folder:SetAttribute("GridX", centerX)
	folder:SetAttribute("GridZ", centerZ)
	folder.Parent = parent

	local color = getCountryColor(ownerUserId)
	local radius = CityConfig.Territory.Radius
	for x = centerX - radius, centerX + radius do
		for z = centerZ - radius, centerZ + radius do
			if x >= 1 and x <= MapConfig.Map.Width and z >= 1 and z <= MapConfig.Map.Length and isTerritoryEdge(centerX, centerZ, x, z) then
				local tile = getTile(x, z)
				if tile then
					local marker = Instance.new("Part")
					marker.Name = "Border"
					marker.Anchored = true
					marker.CanCollide = false
					marker.CanQuery = false
					marker.Color = color
					marker.Material = Enum.Material.Neon
					marker.Size = Vector3.new(MapConfig.Tile.Width, 0.06, MapConfig.Tile.Length)
					marker.Transparency = 0.52
					marker.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + 0.16, tile.Position.Z)
					marker:SetAttribute("CityId", cityId)
					marker:SetAttribute("OwnerUserId", ownerUserId)
					marker:SetAttribute("GridX", x)
					marker:SetAttribute("GridZ", z)
					marker.Parent = folder
				end
			end
		end
	end
end

local function getOwnerTreasury(ownerUserId: number)
	if not treasuryByOwner[ownerUserId] then
		treasuryByOwner[ownerUserId] = {
			Food = 0,
			Production = 0,
			Gold = 0,
		}
	end

	return treasuryByOwner[ownerUserId]
end

local function syncPlayerTreasury(player: Player)
	local treasury = getOwnerTreasury(player.UserId)
	player:SetAttribute("TreasuryFood", treasury.Food)
	player:SetAttribute("TreasuryProduction", treasury.Production)
	player:SetAttribute("TreasuryGold", treasury.Gold)
	player:SetAttribute("TreasuryScience", player:GetAttribute("TreasuryScience") or 0)
	player:SetAttribute("TreasuryCulture", player:GetAttribute("TreasuryCulture") or 0)
	player:SetAttribute("TreasuryFaith", player:GetAttribute("TreasuryFaith") or 0)
end

local function addTreasury(ownerUserId: number, food: number, production: number, gold: number)
	local treasury = getOwnerTreasury(ownerUserId)
	treasury.Food += food
	treasury.Production += production
	treasury.Gold += gold

	local player = Players:GetPlayerByUserId(ownerUserId)
	if player then
		syncPlayerTreasury(player)
	end
end

local function calculateCityYields(centerX: number, centerZ: number): (number, number, number)
	local food = 0
	local production = 0
	local gold = 0
	local radius = CityConfig.Territory.Radius

	for x = centerX - radius, centerX + radius do
		for z = centerZ - radius, centerZ + radius do
			local distance = math.abs(x - centerX) + math.abs(z - centerZ)
			if distance <= radius then
				local tile = getTile(x, z)
				if tile and (tile:GetAttribute("HasCity") == true or tile:GetAttribute("ImprovedResource") == true) then
					food += getNumberAttribute(tile, "FoodYield")
					production += getNumberAttribute(tile, "ProductionYield")
					gold += getNumberAttribute(tile, "GoldYield")
				end
			end
		end
	end

	return food, production, gold
end

local function setCityYields(cityState, food: number, production: number, gold: number)
	cityState.FoodPerTurn = food
	cityState.ProductionPerTurn = production
	cityState.GoldPerTurn = gold

	if cityState.Model then
		cityState.Model:SetAttribute("FoodPerTurn", food)
		cityState.Model:SetAttribute("ProductionPerTurn", production)
		cityState.Model:SetAttribute("GoldPerTurn", gold)
	end
end

local function refreshCityYields(cityId: string)
	local cityState = citiesById[cityId]
	if not cityState then
		return
	end

	local food, production, gold = calculateCityYields(cityState.GridX, cityState.GridZ)
	setCityYields(cityState, food, production, gold)
end

local function startEconomyLoop()
	task.spawn(function()
		while true do
			task.wait(CityConfig.Economy.TickSeconds)

			for cityId, cityState in citiesById do
				refreshCityYields(cityId)
				addTreasury(cityState.OwnerUserId, cityState.FoodPerTurn or 0, cityState.ProductionPerTurn or 0, cityState.GoldPerTurn or 0)
			end
		end
	end)
end

local function onCreateCountry(player: Player, requestedCountryName: string)
	local countryName = sanitizeName(requestedCountryName, player.Name, 32)
	player:SetAttribute(COUNTRY_NAME_ATTRIBUTE, countryName)
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
		FoodPerTurn = cityModel:GetAttribute("FoodPerTurn"),
		ProductionPerTurn = cityModel:GetAttribute("ProductionPerTurn"),
		GoldPerTurn = cityModel:GetAttribute("GoldPerTurn"),
	}
	refreshCityYields(cityId)
	createTerritoryMarker(cityId, player.UserId, x, z)

	return cityModel, nil
end

function CityService.GetCity(cityId: string)
	return citiesById[cityId]
end

function CityService.GetCities()
	return citiesById
end

function CityService.RefreshYieldsNear(ownerUserId: number, x: number, z: number)
	for cityId, cityState in citiesById do
		if cityState.OwnerUserId == ownerUserId then
			local distance = math.abs(x - cityState.GridX) + math.abs(z - cityState.GridZ)
			if distance <= CityConfig.Territory.Radius then
				refreshCityYields(cityId)
			end
		end
	end
end

function CityService.AddTreasury(ownerUserId: number, food: number, production: number, gold: number)
	addTreasury(ownerUserId, food, production, gold)
end

function CityService.Start()
	getCitiesFolder()
	getTerritoryFolder()
	getOrCreateCreateCountryEvent().OnServerEvent:Connect(onCreateCountry)

	Players.PlayerAdded:Connect(syncPlayerTreasury)
	for _, player in Players:GetPlayers() do
		syncPlayerTreasury(player)
	end

	startEconomyLoop()
end

return CityService
