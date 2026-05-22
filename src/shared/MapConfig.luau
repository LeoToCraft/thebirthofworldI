local MapConfig = {}

MapConfig.Tile = {
	Width = 3,
	Length = 3,
	Height = 0.8,
}

MapConfig.Map = {
	Width = 120,
	Length = 120,
	Seed = 1846,
	Origin = Vector3.new(0, 0, 0),
}

MapConfig.Biomes = {
	Water = {
		DisplayName = "Water",
		Color = Color3.fromRGB(36, 122, 202),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Reflectance = 0.15,
	},
	Sand = {
		DisplayName = "Sand",
		Color = Color3.fromRGB(221, 194, 120),
		Material = Enum.Material.Sand,
	},
	Grass = {
		DisplayName = "Grass",
		Color = Color3.fromRGB(70, 150, 72),
		Material = Enum.Material.Grass,
	},
	Winter = {
		DisplayName = "Winter",
		Color = Color3.fromRGB(226, 238, 242),
		Material = Enum.Material.Snow,
	},
	Mountain = {
		DisplayName = "Mountain",
		Color = Color3.fromRGB(104, 105, 99),
		Material = Enum.Material.Rock,
		MinHeight = 2,
		MaxHeight = 8,
	},
}

return MapConfig
