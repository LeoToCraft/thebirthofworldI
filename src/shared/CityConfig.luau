local CityConfig = {}

CityConfig.Starting = {
	Population = 1,
	Food = 0,
	Production = 0,
}

CityConfig.Economy = {
	TickSeconds = 6,
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
	Radius = 4,
	FillTransparency = 0.72,
	BorderTransparency = 0.5,
}

CityConfig.Visual = {
	ModelName = "city1",
	Color = Color3.fromRGB(214, 174, 82),
	Material = Enum.Material.Brick,
}

return CityConfig
