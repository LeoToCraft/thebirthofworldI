local TechnologyConfig = {}

TechnologyConfig.List = {
	{
		Id = "Pottery",
		Name = "Гончарное дело",
		Detail = "Открывает базовую экономику города и подготовку к ирригации.",
		Unlock = "Стабильный рост городов",
		Seconds = 18,
		Requires = {},
	},
	{
		Id = "Mining",
		Name = "Горное дело",
		Detail = "Позволяет эффективнее использовать камень и руду.",
		Unlock = "+1 производство от улучшенных руд",
		Seconds = 22,
		Requires = { "Pottery" },
	},
	{
		Id = "Archery",
		Name = "Стрельба из лука",
		Detail = "Развивает дальний бой и подготовку лучников.",
		Unlock = "Усиление дальних атак",
		Seconds = 24,
		Requires = { "Pottery" },
	},
	{
		Id = "AnimalHusbandry",
		Name = "Животноводство",
		Detail = "Позволяет лучше использовать скот и лошадей.",
		Unlock = "Стратегический ресурс: лошади",
		Seconds = 20,
		Requires = {},
	},
	{
		Id = "Wheel",
		Name = "Колесо",
		Detail = "Основа транспорта, дорог и более быстрых перемещений.",
		Unlock = "Подготовка дорог",
		Seconds = 26,
		Requires = { "AnimalHusbandry" },
	},
	{
		Id = "BronzeWorking",
		Name = "Бронзовая обработка",
		Detail = "Улучшает военное дело и работу со стратегической рудой.",
		Unlock = "Лучшее использование железа",
		Seconds = 30,
		Requires = { "Mining", "Archery" },
	},
	{
		Id = "Writing",
		Name = "Письменность",
		Detail = "Подготовка к науке, управлению и технологиям следующей эпохи.",
		Unlock = "+1 наука в казну",
		Seconds = 28,
		Requires = { "Pottery" },
	},
	{
		Id = "Statecraft",
		Name = "Государственность",
		Detail = "Законы, управление и дипломатия становятся более осознанными.",
		Unlock = "Расширенная дипломатия",
		Seconds = 34,
		Requires = { "Writing" },
	},
}

TechnologyConfig.ById = {}
for _, technology in TechnologyConfig.List do
	TechnologyConfig.ById[technology.Id] = technology
end

return TechnologyConfig
