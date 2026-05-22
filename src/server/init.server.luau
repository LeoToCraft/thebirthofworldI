local MapGenerator = require(script.MapGenerator)
local ResourceService = require(script.ResourceService)
local CityService = require(script.CityService)
local UnitService = require(script.UnitService)

MapGenerator.Generate()
ResourceService.Generate()
CityService.Start()
UnitService.Start()
