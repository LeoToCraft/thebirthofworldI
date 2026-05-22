local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()
local moveUnitEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MoveUnit")

local selectedUnitId: string? = nil
local selectedUnitModel: Model? = nil
local selectionHighlight: Highlight? = nil

local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "MovementHighlights"
highlightFolder.Parent = Workspace

local function getTileName(x: number, z: number): string
	return string.format("Tile_%03d_%03d", x, z)
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild("GeneratedMap") :: Folder?
end

local function getUnitsFolder(): Folder?
	return Workspace:FindFirstChild("Units") :: Folder?
end

local function getTile(x: number, z: number): BasePart?
	local mapFolder = getMapFolder()
	if not mapFolder then
		return nil
	end

	local tile = mapFolder:FindFirstChild(getTileName(x, z))
	if tile and tile:IsA("BasePart") then
		return tile
	end

	return nil
end

local function findUnitModel(instance: Instance?): Model?
	local current = instance

	while current and current ~= Workspace do
		if current:IsA("Model") and current:GetAttribute("UnitId") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function findTile(instance: Instance?): BasePart?
	local current = instance

	while current and current ~= Workspace do
		if current:IsA("BasePart") and current:GetAttribute("GridX") and current:GetAttribute("GridZ") and current:GetAttribute("Biome") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function isOwnedUnit(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == localPlayer.UserId
end

local function isTileOccupied(x: number, z: number): boolean
	local unitsFolder = getUnitsFolder()
	if not unitsFolder then
		return false
	end

	for _, unitModel in unitsFolder:GetChildren() do
		if unitModel:GetAttribute("GridX") == x and unitModel:GetAttribute("GridZ") == z then
			return unitModel ~= selectedUnitModel
		end
	end

	return false
end

local function clearHighlights()
	highlightFolder:ClearAllChildren()

	if selectionHighlight then
		selectionHighlight:Destroy()
		selectionHighlight = nil
	end
end

local function canSelectedUnitEnter(tile: BasePart): boolean
	if not selectedUnitModel then
		return false
	end

	local unitType = selectedUnitModel:GetAttribute("UnitType")
	local biome = tile:GetAttribute("Biome")
	if typeof(unitType) ~= "string" or typeof(biome) ~= "string" then
		return false
	end

	return UnitConfig.Types[unitType].CanEnter[biome] == true
end

local function createMovementHighlight(tile: BasePart)
	local highlight = Instance.new("Part")
	highlight.Name = "MoveHighlight"
	highlight.Anchored = true
	highlight.CanCollide = false
	highlight.CanQuery = false
	highlight.Color = Color3.fromRGB(255, 226, 92)
	highlight.Material = Enum.Material.Neon
	highlight.Size = Vector3.new(MapConfig.Tile.Width, 0.08, MapConfig.Tile.Length)
	highlight.Transparency = 0.45
	highlight.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + 0.08, tile.Position.Z)
	highlight.Parent = highlightFolder
end

local function showMovementForSelectedUnit()
	if not selectedUnitModel then
		return
	end

	local unitType = selectedUnitModel:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	if not unit then
		return
	end

	local originX = selectedUnitModel:GetAttribute("GridX")
	local originZ = selectedUnitModel:GetAttribute("GridZ")
	if typeof(originX) ~= "number" or typeof(originZ) ~= "number" then
		return
	end

	for x = originX - unit.Movement, originX + unit.Movement do
		for z = originZ - unit.Movement, originZ + unit.Movement do
			local distance = math.abs(x - originX) + math.abs(z - originZ)
			if distance >= 1 and distance <= unit.Movement then
				local tile = getTile(x, z)
				if tile and canSelectedUnitEnter(tile) and not isTileOccupied(x, z) then
					createMovementHighlight(tile)
				end
			end
		end
	end
end

local function selectUnit(model: Model)
	clearHighlights()

	selectedUnitModel = model
	selectedUnitId = model:GetAttribute("UnitId") :: string

	selectionHighlight = Instance.new("Highlight")
	selectionHighlight.Name = "SelectedUnitHighlight"
	selectionHighlight.Adornee = model
	selectionHighlight.FillColor = Color3.fromRGB(255, 226, 92)
	selectionHighlight.FillTransparency = 0.78
	selectionHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	selectionHighlight.OutlineTransparency = 0
	selectionHighlight.Parent = highlightFolder

	showMovementForSelectedUnit()
end

local function requestMove(tile: BasePart)
	if not selectedUnitId or not canSelectedUnitEnter(tile) then
		return
	end

	local targetX = tile:GetAttribute("GridX")
	local targetZ = tile:GetAttribute("GridZ")
	if typeof(targetX) ~= "number" or typeof(targetZ) ~= "number" then
		return
	end

	moveUnitEvent:FireServer(selectedUnitId, targetX, targetZ)
	clearHighlights()
	selectedUnitId = nil
	selectedUnitModel = nil
end

mouse.Button1Down:Connect(function()
	local target = mouse.Target
	local unitModel = findUnitModel(target)

	if unitModel and isOwnedUnit(unitModel) then
		selectUnit(unitModel)
		return
	end

	local tile = findTile(target)
	if tile then
		requestMove(tile)
		return
	end

	clearHighlights()
	selectedUnitId = nil
	selectedUnitModel = nil
end)
