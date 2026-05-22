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
		},
	},
	Builder = {
		DisplayName = "Builder",
		ModelName = "builderModel",
		Health = 60,
		Attack = 0,
		Movement = 2,
		Color = Color3.fromRGB(83, 169, 226),
		CanBuild = true,
		CanEnter = {
			Grass = true,
			Sand = true,
			Winter = true,
		},
	},
	Archer = {
		DisplayName = "Archer",
		ModelName = "archerModel",
		Health = 80,
		Attack = 35,
		Range = 2,
		Movement = 2,
		Color = Color3.fromRGB(96, 180, 92),
		CanEnter = {
			Grass = true,
			Sand = true,
			Winter = true,
		},
	},
	Scout = {
		DisplayName = "Scout",
		ModelName = "scoutModel",
		Health = 70,
		Attack = 15,
		Movement = 3,
		Color = Color3.fromRGB(219, 145, 58),
		CanEnter = {
			Grass = true,
			Sand = true,
			Winter = true,
		},
	},
}

return UnitConfig
