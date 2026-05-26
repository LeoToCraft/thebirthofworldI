local CityConfig = {}

CityConfig.Starting = {
	Population = 1,
	Food = 0,
	Production = 0,
	Health = 260,
}

CityConfig.Economy = {
	TickSeconds = 4,
	YieldMultiplier = 0.5,
	UnitProductionSeconds = 15,
	TradeGold = 5,
}

CityConfig.Placement = {
	MinDistanceFromOtherCities = 4,
	AllowedBiomes = {
		Grass = true,
		Sand = true,
		Winter = true,
	},
}

CityConfig.Territory = {
	Radius = 1,
	BorderRadius = 2,
	FillTransparency = 0.78,
	BorderTransparency = 0.42,
}

CityConfig.Visual = {
	ModelName = "city1",
	Color = Color3.fromRGB(214, 174, 82),
	Material = Enum.Material.Brick,
}

return CityConfig
