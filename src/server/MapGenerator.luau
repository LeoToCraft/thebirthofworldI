local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local MapGenerator = {}

local MAP_FOLDER_NAME = "GeneratedMap"

local function scaledNoise(x: number, z: number, scale: number, seedOffset: number): number
	return math.noise((x + seedOffset) / scale, (z - seedOffset) / scale, MapConfig.Map.Seed)
end

local function chooseBiome(x: number, z: number): string
	local elevation = scaledNoise(x, z, 10, 0)
	local moisture = scaledNoise(x, z, 7, 80)
	local temperature = scaledNoise(x, z, 13, -150)

	if elevation < -0.22 then
		return "Water"
	end

	if temperature < -0.3 then
		return "Winter"
	end

	if moisture > 0.32 and temperature > -0.05 then
		return "Tropics"
	end

	if moisture < -0.25 or elevation < -0.06 then
		return "Sand"
	end

	return "Earth"
end

local function getTilePosition(x: number, z: number): Vector3
	local tile = MapConfig.Tile
	local map = MapConfig.Map
	local offsetX = (x - (map.Width + 1) / 2) * tile.Width
	local offsetZ = (z - (map.Length + 1) / 2) * tile.Length

	return map.Origin + Vector3.new(offsetX, tile.Height / 2, offsetZ)
end

local function createTile(parent: Instance, x: number, z: number, biomeName: string): Part
	local tileConfig = MapConfig.Tile
	local biome = MapConfig.Biomes[biomeName]

	local tile = Instance.new("Part")
	tile.Name = string.format("%s_%02d_%02d", biomeName, x, z)
	tile.Anchored = true
	tile.Size = Vector3.new(tileConfig.Width, tileConfig.Height, tileConfig.Length)
	tile.Position = getTilePosition(x, z)
	tile.Color = biome.Color
	tile.Material = biome.Material
	tile.TopSurface = Enum.SurfaceType.Smooth
	tile.BottomSurface = Enum.SurfaceType.Smooth
	tile:SetAttribute("GridX", x)
	tile:SetAttribute("GridZ", z)
	tile:SetAttribute("Biome", biome.DisplayName)
	tile.Parent = parent

	return tile
end

function MapGenerator.Generate()
	local previousMap = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if previousMap then
		previousMap:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = MAP_FOLDER_NAME
	mapFolder.Parent = Workspace

	for x = 1, MapConfig.Map.Width do
		for z = 1, MapConfig.Map.Length do
			local biomeName = chooseBiome(x, z)
			createTile(mapFolder, x, z, biomeName)
		end
	end

	return mapFolder
end

return MapGenerator
