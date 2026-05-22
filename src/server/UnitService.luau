local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local UnitService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local UNITS_FOLDER_NAME = "Units"
local REMOTES_FOLDER_NAME = "Remotes"
local MOVE_UNIT_EVENT_NAME = "MoveUnit"

local unitsById = {}
local occupiedTiles = {}
local playerOrder = 0

local function getTileName(x: number, z: number): string
	return string.format("Tile_%03d_%03d", x, z)
end

local function getTileKey(x: number, z: number): string
	return string.format("%d:%d", x, z)
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild(MAP_FOLDER_NAME) :: Folder?
end

local function getUnitsFolder(): Folder
	local unitsFolder = Workspace:FindFirstChild(UNITS_FOLDER_NAME)
	if unitsFolder then
		return unitsFolder :: Folder
	end

	local newUnitsFolder = Instance.new("Folder")
	newUnitsFolder.Name = UNITS_FOLDER_NAME
	newUnitsFolder.Parent = Workspace

	return newUnitsFolder
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

local function getOrCreateMoveEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local moveEvent = remotesFolder:FindFirstChild(MOVE_UNIT_EVENT_NAME)
	if moveEvent and moveEvent:IsA("RemoteEvent") then
		return moveEvent
	end

	local newMoveEvent = Instance.new("RemoteEvent")
	newMoveEvent.Name = MOVE_UNIT_EVENT_NAME
	newMoveEvent.Parent = remotesFolder

	return newMoveEvent
end

local function canUnitEnter(unitType: string, tile: BasePart): boolean
	local unit = UnitConfig.Types[unitType]
	local biome = tile:GetAttribute("Biome")

	return typeof(biome) == "string" and unit.CanEnter[biome] == true
end

local function isOpenForUnit(unitType: string, x: number, z: number): boolean
	local tile = getTile(x, z)
	if not tile then
		return false
	end

	return canUnitEnter(unitType, tile) and occupiedTiles[getTileKey(x, z)] == nil
end

local function setUnitAttributes(instance: Instance, unitId: string, player: Player, unitType: string, x: number, z: number)
	instance:SetAttribute("UnitId", unitId)
	instance:SetAttribute("OwnerUserId", player.UserId)
	instance:SetAttribute("UnitType", unitType)
	instance:SetAttribute("GridX", x)
	instance:SetAttribute("GridZ", z)
	instance:SetAttribute("Health", UnitConfig.Types[unitType].Health)
	instance:SetAttribute("Movement", UnitConfig.Types[unitType].Movement)
	instance:SetAttribute("Attack", UnitConfig.Types[unitType].Attack)
end

local function applyUnitAttributesToParts(model: Model, unitId: string, player: Player, unitType: string, x: number, z: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant:SetAttribute("UnitId", unitId)
			descendant:SetAttribute("OwnerUserId", player.UserId)
			descendant:SetAttribute("UnitType", unitType)
			descendant:SetAttribute("GridX", x)
			descendant:SetAttribute("GridZ", z)
		end
	end
end

local function setUnitGridAttributes(model: Model, x: number, z: number)
	model:SetAttribute("GridX", x)
	model:SetAttribute("GridZ", z)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("GridX", x)
			descendant:SetAttribute("GridZ", z)
		end
	end
end

local function getFirstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function createFallbackModel(unitType: string): Model
	local unit = UnitConfig.Types[unitType]

	local model = Instance.new("Model")
	model.Name = unit.DisplayName

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.Size = Vector3.new(1.35, 1.8, 1.35)
	body.Color = unit.Color
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	local nameplate = Instance.new("BillboardGui")
	nameplate.Name = "Nameplate"
	nameplate.AlwaysOnTop = true
	nameplate.Size = UDim2.fromOffset(90, 28)
	nameplate.StudsOffset = Vector3.new(0, 1.4, 0)
	nameplate.Parent = body

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Size = UDim2.fromScale(1, 1)
	label.Text = unit.DisplayName
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.35
	label.Parent = nameplate

	model.PrimaryPart = body

	return model
end

local function createModel(unitType: string): Model
	local unit = UnitConfig.Types[unitType]
	local storedModel = ServerStorage:FindFirstChild(unit.ModelName)

	if storedModel then
		local clone = storedModel:Clone()
		if clone:IsA("Model") then
			clone.Name = unit.DisplayName
			local primaryPart = clone.PrimaryPart or getFirstBasePart(clone)
			if primaryPart then
				clone.PrimaryPart = primaryPart
			else
				clone:Destroy()
				return createFallbackModel(unitType)
			end

			return clone
		end

		if clone:IsA("BasePart") then
			local model = Instance.new("Model")
			model.Name = unit.DisplayName
			clone.Name = "Body"
			clone.Parent = model
			model.PrimaryPart = clone

			return model
		end
	end

	return createFallbackModel(unitType)
end

local function moveModelToTile(model: Model, tile: BasePart)
	local _, size = model:GetBoundingBox()
	local topY = tile.Position.Y + tile.Size.Y / 2
	local position = Vector3.new(tile.Position.X, topY + size.Y / 2 + 0.05, tile.Position.Z)

	model:PivotTo(CFrame.new(position))
end

local function findSpawnTile(unitType: string, startX: number, startZ: number): (number?, number?)
	local maxRadius = math.max(MapConfig.Map.Width, MapConfig.Map.Length)

	for radius = 0, maxRadius do
		for x = startX - radius, startX + radius do
			for z = startZ - radius, startZ + radius do
				if x >= 1 and x <= MapConfig.Map.Width and z >= 1 and z <= MapConfig.Map.Length then
					if isOpenForUnit(unitType, x, z) then
						return x, z
					end
				end
			end
		end
	end

	return nil, nil
end

local function createUnit(player: Player, unitType: string, x: number, z: number): Model?
	local tile = getTile(x, z)
	if not tile then
		return nil
	end

	local unitId = HttpService:GenerateGUID(false)
	local model = createModel(unitType)
	model.Name = string.format("%s_%s", UnitConfig.Types[unitType].DisplayName, player.Name)
	setUnitAttributes(model, unitId, player, unitType, x, z)
	applyUnitAttributesToParts(model, unitId, player, unitType, x, z)
	model.Parent = getUnitsFolder()
	moveModelToTile(model, tile)

	unitsById[unitId] = {
		Model = model,
		OwnerUserId = player.UserId,
		UnitType = unitType,
		GridX = x,
		GridZ = z,
	}
	occupiedTiles[getTileKey(x, z)] = unitId

	return model
end

local function spawnStartingUnits(player: Player)
	playerOrder += 1

	local centerX = math.floor(MapConfig.Map.Width / 2) + (playerOrder - 1) * 5
	local centerZ = math.floor(MapConfig.Map.Length / 2)

	local settlerX, settlerZ = findSpawnTile("Settler", centerX, centerZ)
	if settlerX and settlerZ then
		createUnit(player, "Settler", settlerX, settlerZ)
	end

	local warriorX, warriorZ = findSpawnTile("Warrior", centerX + 1, centerZ)
	if warriorX and warriorZ then
		createUnit(player, "Warrior", warriorX, warriorZ)
	end
end

local function removePlayerUnits(player: Player)
	for unitId, unitState in unitsById do
		if unitState.OwnerUserId == player.UserId then
			occupiedTiles[getTileKey(unitState.GridX, unitState.GridZ)] = nil
			if unitState.Model then
				unitState.Model:Destroy()
			end
			unitsById[unitId] = nil
		end
	end
end

local function onMoveUnit(player: Player, unitId: string, targetX: number, targetZ: number)
	if typeof(unitId) ~= "string" or typeof(targetX) ~= "number" or typeof(targetZ) ~= "number" then
		return
	end

	targetX = math.floor(targetX)
	targetZ = math.floor(targetZ)

	local unitState = unitsById[unitId]
	if not unitState or unitState.OwnerUserId ~= player.UserId then
		return
	end

	local unit = UnitConfig.Types[unitState.UnitType]
	local distance = math.abs(targetX - unitState.GridX) + math.abs(targetZ - unitState.GridZ)
	if distance < 1 or distance > unit.Movement then
		return
	end

	local tile = getTile(targetX, targetZ)
	if not tile or not canUnitEnter(unitState.UnitType, tile) then
		return
	end

	local targetKey = getTileKey(targetX, targetZ)
	if occupiedTiles[targetKey] then
		return
	end

	occupiedTiles[getTileKey(unitState.GridX, unitState.GridZ)] = nil
	occupiedTiles[targetKey] = unitId

	unitState.GridX = targetX
	unitState.GridZ = targetZ
	setUnitGridAttributes(unitState.Model, targetX, targetZ)
	moveModelToTile(unitState.Model, tile)
end

function UnitService.Start()
	local moveEvent = getOrCreateMoveEvent()
	moveEvent.OnServerEvent:Connect(onMoveUnit)

	Players.PlayerAdded:Connect(spawnStartingUnits)
	Players.PlayerRemoving:Connect(removePlayerUnits)

	for _, player in Players:GetPlayers() do
		spawnStartingUnits(player)
	end
end

return UnitService
