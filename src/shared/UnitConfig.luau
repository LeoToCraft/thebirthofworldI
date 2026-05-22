local UnitConfig = {}

UnitConfig.Animation = {
	MoveTime = 0.35,
}

UnitConfig.Types = {
	Warrior = {
		DisplayName = "Warrior",
		ModelName = "warriorModel",
		Health = 100,
		Attack = 25,
		Movement = 2,
		Color = Color3.fromRGB(190, 58, 52),
		CanEnter = {
			Grass = true,
			Sand = true,
			Winter = true,
			Mountain = true,
		},
	},
	Settler = {
		DisplayName = "Settler",
		ModelName = "settlerModel",
		Health = 70,
		Attack = 0,
		Movement = 2,
		Color = Color3.fromRGB(235, 210, 116),
		CanEnter = {
			Grass = true,
			Sand = true,
			Winter = true,
			Mountain = true,
		},
	},
}

return UnitConfig
