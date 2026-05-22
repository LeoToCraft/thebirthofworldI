local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CityConfig = require(ReplicatedStorage.Shared.CityConfig)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local CityService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local CITIES_FOLDER_NAME = "Cities"

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

local function createCityVisual(cityName: string, tile: BasePart): Model
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

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "CityNameplate"
	nameplate.AlwaysOnTop = true
	nameplate.MaxDistance = 400
	nameplate.Size = UDim2.fromOffset(130, 28)
	nameplate.StudsOffset = Vector3.new(0, 1.9, 0)
	nameplate.Parent = tower

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Size = UDim2.fromScale(1, 1)
	label.Text = cityName
	label.TextColor3 = Color3.fromRGB(255, 247, 214)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.Parent = nameplate

	model.PrimaryPart = base

	local tileTopY = tile.Position.Y + tile.Size.Y / 2
	base.Position = Vector3.new(tile.Position.X, tileTopY + base.Size.Y / 2 + 0.04, tile.Position.Z)
	tower.Position = Vector3.new(tile.Position.X, base.Position.Y + base.Size.Y / 2 + tower.Size.Y / 2, tile.Position.Z)

	return model
end

local function setCityAttributes(model: Model, cityId: string, player: Player, cityName: string, x: number, z: number)
	model:SetAttribute("CityId", cityId)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("CityName", cityName)
	model:SetAttribute("GridX", x)
	model:SetAttribute("GridZ", z)
	model:SetAttribute("Population", CityConfig.Starting.Population)
	model:SetAttribute("Food", CityConfig.Starting.Food)
	model:SetAttribute("Production", CityConfig.Starting.Production)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("CityId", cityId)
			descendant:SetAttribute("OwnerUserId", player.UserId)
			descendant:SetAttribute("GridX", x)
			descendant:SetAttribute("GridZ", z)
		end
	end
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

function CityService.FoundCity(player: Player, x: number, z: number): (Model?, string?)
	local canFound, reason = CityService.CanFoundCity(x, z)
	if not canFound then
		return nil, reason
	end

	local tile = getTile(x, z)
	if not tile then
		return nil, "No tile at this position"
	end

	local cityId = HttpService:GenerateGUID(false)
	local cityName = getNextCityName(player)
	local cityModel = createCityVisual(cityName, tile)
	setCityAttributes(cityModel, cityId, player, cityName, x, z)
	cityModel.Parent = getCitiesFolder()
	tile:SetAttribute("HasCity", true)
	tile:SetAttribute("CityId", cityId)

	citiesById[cityId] = {
		Model = cityModel,
		OwnerUserId = player.UserId,
		GridX = x,
		GridZ = z,
		Population = CityConfig.Starting.Population,
		Food = CityConfig.Starting.Food,
		Production = CityConfig.Starting.Production,
	}

	return cityModel, nil
end

function CityService.Start()
	getCitiesFolder()
end

return CityService
