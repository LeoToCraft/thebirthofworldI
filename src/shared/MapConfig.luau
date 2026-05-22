local MapConfig = {}

MapConfig.Tile = {
	Width = 3,
	Length = 3,
	Height = 0.8,
}

MapConfig.Map = {
	Width = 40,
	Length = 40,
	Seed = 1846,
	Origin = Vector3.new(0, 0, 0),
}

MapConfig.Biomes = {
	Water = {
		DisplayName = "Water",
		Color = Color3.fromRGB(43, 117, 189),
		Material = Enum.Material.SmoothPlastic,
	},
	Sand = {
		DisplayName = "Sand",
		Color = Color3.fromRGB(221, 194, 120),
		Material = Enum.Material.Sand,
	},
	Earth = {
		DisplayName = "Earth",
		Color = Color3.fromRGB(107, 86, 58),
		Material = Enum.Material.Ground,
	},
	Tropics = {
		DisplayName = "Tropics",
		Color = Color3.fromRGB(45, 145, 72),
		Material = Enum.Material.Grass,
	},
	Winter = {
		DisplayName = "Winter",
		Color = Color3.fromRGB(226, 238, 242),
		Material = Enum.Material.Snow,
	},
}

return MapConfig
