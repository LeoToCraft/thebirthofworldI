local ResourceConfig = {}

ResourceConfig.Generation = {
	BaseChance = 0.06,
}

ResourceConfig.Visual = {
	MaxSize = 1.35,
	HeightOffset = 0.06,
}

ResourceConfig.Types = {
	Wheat = {
		DisplayName = "Wheat",
		ModelName = "wheat",
		AllowedBiomes = {
			Grass = true,
			Sand = true,
		},
		Weight = 18,
		Color = Color3.fromRGB(226, 197, 84),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 2,
			Production = 0,
			Gold = 0,
		},
	},
	Cattle = {
		DisplayName = "Cattle",
		ModelName = "cattle",
		AllowedBiomes = {
			Grass = true,
		},
		Weight = 14,
		Color = Color3.fromRGB(142, 103, 67),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 1,
			Production = 1,
			Gold = 0,
		},
	},
	Wood = {
		DisplayName = "Wood",
		ModelName = "wood",
		AllowedBiomes = {
			Grass = true,
			Winter = true,
		},
		Weight = 16,
		Color = Color3.fromRGB(56, 111, 65),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 0,
			Production = 1,
			Gold = 0,
		},
	},
	Fish = {
		DisplayName = "Fish",
		ModelName = "fish",
		AllowedBiomes = {
			Water = true,
		},
		Weight = 20,
		Color = Color3.fromRGB(129, 211, 232),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 2,
			Production = 0,
			Gold = 0,
		},
	},
	Stone = {
		DisplayName = "Stone",
		ModelName = "stone",
		Rarity = 0.35,
		AllowedBiomes = {
			Sand = true,
		},
		Weight = 4,
		Color = Color3.fromRGB(142, 145, 139),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 0,
			Production = 2,
			Gold = 0,
		},
	},
	Iron = {
		DisplayName = "Iron",
		ModelName = "iron",
		Rarity = 0.28,
		AllowedBiomes = {
			Grass = true,
			Winter = true,
		},
		Weight = 2,
		Color = Color3.fromRGB(91, 94, 101),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 0,
			Production = 2,
			Gold = 0,
		},
	},
	Gold = {
		DisplayName = "Gold",
		ModelName = "gold",
		Rarity = 0.22,
		AllowedBiomes = {
			Sand = true,
		},
		Weight = 1,
		Color = Color3.fromRGB(245, 197, 66),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 0,
			Production = 0,
			Gold = 3,
		},
	},
	Furs = {
		DisplayName = "Furs",
		ModelName = "furs",
		AllowedBiomes = {
			Winter = true,
		},
		Weight = 9,
		Color = Color3.fromRGB(228, 229, 217),
		Shape = Enum.PartType.Ball,
		Yields = {
			Food = 1,
			Production = 0,
			Gold = 2,
		},
	},
}

return ResourceConfig
