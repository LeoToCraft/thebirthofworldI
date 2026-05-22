local MapGenerator = require(script.MapGenerator)
local CityService = require(script.CityService)
local UnitService = require(script.UnitService)

MapGenerator.Generate()
CityService.Start()
UnitService.Start()
