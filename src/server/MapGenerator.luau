local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local MapGenerator = {}

local MAP_FOLDER_NAME = "GeneratedMap"

local function scaledNoise(x: number, z: number, scale: number, seedOffset: number): number
	return math.noise((x + seedOffset) / scale, (z - seedOffset) / scale, MapConfig.Map.Seed)
end

local function layeredNoise(x: number, z: number, seedOffset: number): number
	local broad = scaledNoise(x, z, 32, seedOffset)
	local medium = scaledNoise(x, z, 14, seedOffset + 90) * 0.55
	local detail = scaledNoise(x, z, 6, seedOffset - 140) * 0.25

	return broad + medium + detail
end

local function getLatitudeColdness(z: number): number
	local mapCenterZ = (MapConfig.Map.Length + 1) / 2
	return math.abs(z - mapCenterZ) / mapCenterZ
end

local function getMountainHeight(elevation: number, mountainShape: number): number
	local mountain = MapConfig.Biomes.Mountain
	local heightRange = mountain.MaxHeight - mountain.MinHeight
	local strength = math.clamp((elevation + mountainShape - 0.9) / 0.75, 0, 1)

	return mountain.MinHeight + math.floor(strength * heightRange + 0.5)
end

local function chooseTile(x: number, z: number): (string, number)
	local elevation = layeredNoise(x, z, 0)
	local moisture = layeredNoise(x, z, 220)
	local mountainShape = scaledNoise(x, z, 11, -360)
	local latitudeColdness = getLatitudeColdness(z)
	local temperature = layeredNoise(x, z, -180) - latitudeColdness * 0.85

	if elevation < -0.24 then
		return "Water", MapConfig.Tile.WaterHeight
	end

	if elevation > 0.46 and mountainShape > 0.1 then
		return "Mountain", getMountainHeight(elevation, mountainShape)
	end

	if temperature < -0.42 then
		return "Winter", MapConfig.Tile.Height
	end

	if moisture < -0.28 then
		return "Sand", MapConfig.Tile.Height
	end

	return "Grass", MapConfig.Tile.Height
end

local function getTilePosition(x: number, z: number, height: number): Vector3
	local tile = MapConfig.Tile
	local map = MapConfig.Map
	local offsetX = (x - (map.Width + 1) / 2) * tile.Width
	local offsetZ = (z - (map.Length + 1) / 2) * tile.Length

	return map.Origin + Vector3.new(offsetX, height / 2, offsetZ)
end

local function createTile(parent: Instance, x: number, z: number, biomeName: string, height: number): Part
	local tileConfig = MapConfig.Tile
	local biome = MapConfig.Biomes[biomeName]

	local tile = Instance.new("Part")
	tile.Name = string.format("Tile_%03d_%03d", x, z)
	tile.Anchored = true
	tile.Size = Vector3.new(tileConfig.Width, height, tileConfig.Length)
	tile.Position = getTilePosition(x, z, height)
	tile.Color = biome.Color
	tile.Material = biome.Material
	tile.Transparency = biome.Transparency or 0
	tile.Reflectance = biome.Reflectance or 0
	tile.TopSurface = Enum.SurfaceType.Smooth
	tile.BottomSurface = Enum.SurfaceType.Smooth
	tile:SetAttribute("GridX", x)
	tile:SetAttribute("GridZ", z)
	tile:SetAttribute("Biome", biome.DisplayName)
	tile:SetAttribute("Height", height)
	tile.Parent = parent

	return tile
end

function MapGenerator.Generate()
	Workspace:SetAttribute("MapGenerating", true)

	local previousMap = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if previousMap then
		previousMap:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME
	mapFolder.Parent = Workspace

	local createdTiles = 0
	local batchSize = MapConfig.Generation.TileBatchSize

	for x = 1, MapConfig.Map.Width do
		for z = 1, MapConfig.Map.Length do
			local biomeName, height = chooseTile(x, z)
			createTile(mapFolder, x, z, biomeName, height)
			createdTiles += 1

			if createdTiles % batchSize == 0 then
				Workspace:SetAttribute("MapGeneratedTiles", createdTiles)
				task.wait()
			end
		end
	end

	Workspace:SetAttribute("MapGeneratedTiles", createdTiles)
	Workspace:SetAttribute("MapGenerating", false)

	return mapFolder
end

return MapGenerator
