local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CityConfig = require(ReplicatedStorage.Shared.CityConfig)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local CityService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local CITIES_FOLDER_NAME = "Cities"
local REMOTES_FOLDER_NAME = "Remotes"
local CREATE_COUNTRY_EVENT_NAME = "CreateCountry"
local COUNTRY_NAME_ATTRIBUTE = "CountryName"

local citiesById = {}
local cityCountByOwner = {}

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

local function getNextCityName(player: Player): string
	local nextIndex = (cityCountByOwner[player.UserId] or 0) + 1
	cityCountByOwner[player.UserId] = nextIndex

	return string.format("%s City %d", player.Name, nextIndex)
end

local function getCityName(player: Player, requestedCityName: string?): string
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

local function getCountryName(player: Player): string
	return sanitizeName(player:GetAttribute(COUNTRY_NAME_ATTRIBUTE), player.Name, 32)
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

local function setCityAttributes(model: Model, cityId: string, player: Player, cityName: string, countryName: string, x: number, z: number)
	model:SetAttribute("CityId", cityId)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("CityName", cityName)
	model:SetAttribute("CountryName", countryName)
	model:SetAttribute("GridX", x)
	model:SetAttribute("GridZ", z)
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

function CityService.FoundCity(player: Player, x: number, z: number, requestedCityName: string?): (Model?, string?)
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

	return cityModel, nil
end

function CityService.Start()
	getCitiesFolder()
	getOrCreateCreateCountryEvent().OnServerEvent:Connect(onCreateCountry)
end

return CityService
