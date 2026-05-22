local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CityService = require(script.Parent.CityService)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local UnitService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local UNITS_FOLDER_NAME = "Units"
local REMOTES_FOLDER_NAME = "Remotes"
local MOVE_UNIT_EVENT_NAME = "MoveUnit"
local UNIT_ACTION_EVENT_NAME = "UnitAction"
local HEALTH_BAR_NAME = "UnitHealthBar"

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

local function getOrCreateUnitActionEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local actionEvent = remotesFolder:FindFirstChild(UNIT_ACTION_EVENT_NAME)
	if actionEvent and actionEvent:IsA("RemoteEvent") then
		return actionEvent
	end

	local newActionEvent = Instance.new("RemoteEvent")
	newActionEvent.Name = UNIT_ACTION_EVENT_NAME
	newActionEvent.Parent = remotesFolder

	return newActionEvent
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
	instance:SetAttribute("MaxHealth", UnitConfig.Types[unitType].Health)
	instance:SetAttribute("Health", UnitConfig.Types[unitType].Health)
	instance:SetAttribute("Movement", UnitConfig.Types[unitType].Movement)
	instance:SetAttribute("Attack", UnitConfig.Types[unitType].Attack)
	instance:SetAttribute("IsMoving", false)
	instance:SetAttribute("Fortified", false)
	instance:SetAttribute("FortifyUntilHealed", false)
	instance:SetAttribute("ActionState", "Ready")
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

local function getUnitMaxHealth(model: Model): number
	local maxHealth = model:GetAttribute("MaxHealth")
	if typeof(maxHealth) == "number" and maxHealth > 0 then
		return maxHealth
	end

	local unitType = model:GetAttribute("UnitType")
	local unit = typeof(unitType) == "string" and UnitConfig.Types[unitType] or nil
	if unit then
		return unit.Health
	end

	return 1
end

local function updateHealthBar(model: Model)
	local adornee = model.PrimaryPart or getFirstBasePart(model)
	if not adornee then
		return
	end

	local healthBar = adornee:FindFirstChild(HEALTH_BAR_NAME)
	if not healthBar or not healthBar:IsA("BillboardGui") then
		return
	end

	local container = healthBar:FindFirstChild("Container")
	local fill = container and container:FindFirstChild("Fill")
	local label = healthBar:FindFirstChild("HealthText")
	if not container or not container:IsA("Frame") or not fill or not fill:IsA("Frame") then
		return
	end

	local maxHealth = getUnitMaxHealth(model)
	local health = model:GetAttribute("Health")
	if typeof(health) ~= "number" then
		health = maxHealth
	end

	local ratio = math.clamp(health / maxHealth, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)

	if ratio > 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(82, 214, 116)
	elseif ratio > 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(245, 195, 75)
	else
		fill.BackgroundColor3 = Color3.fromRGB(231, 74, 62)
	end

	if label and label:IsA("TextLabel") then
		label.Text = string.format("%d/%d", math.max(0, math.floor(health + 0.5)), math.floor(maxHealth + 0.5))
	end
end

local function createHealthBar(model: Model)
	local adornee = model.PrimaryPart or getFirstBasePart(model)
	if not adornee then
		return
	end

	local existing = adornee:FindFirstChild(HEALTH_BAR_NAME)
	if existing then
		existing:Destroy()
	end

	local healthBar = Instance.new("BillboardGui")
	local _, modelSize = model:GetBoundingBox()
	healthBar.Name = HEALTH_BAR_NAME
	healthBar.AlwaysOnTop = true
	healthBar.MaxDistance = 300
	healthBar.Size = UDim2.fromOffset(86, 18)
	healthBar.StudsOffset = Vector3.new(0, modelSize.Y / 2 + 0.75, 0)
	healthBar.Parent = adornee

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	container.BorderSizePixel = 0
	container.Position = UDim2.fromScale(0.5, 1)
	container.Size = UDim2.new(1, 0, 0, 8)
	container.Parent = healthBar

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.25
	stroke.Thickness = 1
	stroke.Parent = container

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(82, 214, 116)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "HealthText"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Position = UDim2.fromOffset(0, 0)
	label.Size = UDim2.new(1, 0, 0, 10)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.35
	label.Parent = healthBar

	local healthConnection = model:GetAttributeChangedSignal("Health"):Connect(function()
		updateHealthBar(model)
	end)
	local maxHealthConnection = model:GetAttributeChangedSignal("MaxHealth"):Connect(function()
		updateHealthBar(model)
	end)
	local destroyingConnection
	destroyingConnection = model.Destroying:Connect(function()
		healthConnection:Disconnect()
		maxHealthConnection:Disconnect()
		destroyingConnection:Disconnect()
	end)

	updateHealthBar(model)
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

local function getModelTileCFrame(model: Model, tile: BasePart): CFrame
	local _, size = model:GetBoundingBox()
	local topY = tile.Position.Y + tile.Size.Y / 2
	local position = Vector3.new(tile.Position.X, topY + size.Y / 2 + 0.05, tile.Position.Z)

	return CFrame.new(position)
end

local function moveModelToTile(model: Model, tile: BasePart)
	model:PivotTo(getModelTileCFrame(model, tile))
end

local function tweenModelToTile(model: Model, tile: BasePart, onComplete: () -> ())
	local targetCFrame = getModelTileCFrame(model, tile)
	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = model:GetPivot()

	local connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:PivotTo(pivotValue.Value)
		end
	end)

	local tween = TweenService:Create(
		pivotValue,
		TweenInfo.new(UnitConfig.Animation.MoveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = targetCFrame }
	)

	tween.Completed:Connect(function()
		connection:Disconnect()
		pivotValue:Destroy()

		if model.Parent then
			model:PivotTo(targetCFrame)
		end

		onComplete()
	end)

	tween:Play()
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
	createHealthBar(model)
	model.Parent = getUnitsFolder()
	moveModelToTile(model, tile)

	unitsById[unitId] = {
		Model = model,
		OwnerUserId = player.UserId,
		UnitType = unitType,
		GridX = x,
		GridZ = z,
		IsMoving = false,
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

local function removeUnit(unitId: string, unitState)
	occupiedTiles[getTileKey(unitState.GridX, unitState.GridZ)] = nil

	if unitState.Model then
		unitState.Model:Destroy()
	end

	unitsById[unitId] = nil
end

local function healUnit(unitState, amount: number)
	local maxHealth = unitState.Model:GetAttribute("MaxHealth")
	local currentHealth = unitState.Model:GetAttribute("Health")
	if typeof(maxHealth) ~= "number" or typeof(currentHealth) ~= "number" then
		return
	end

	local nextHealth = math.min(maxHealth, currentHealth + amount)
	unitState.Model:SetAttribute("Health", nextHealth)
end

local function setUnitActionState(unitState, actionState: string, fortified: boolean, fortifyUntilHealed: boolean)
	unitState.Model:SetAttribute("ActionState", actionState)
	unitState.Model:SetAttribute("Fortified", fortified)
	unitState.Model:SetAttribute("FortifyUntilHealed", fortifyUntilHealed)
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

	if unitState.IsMoving then
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
	unitState.IsMoving = true
	unitState.Model:SetAttribute("IsMoving", true)
	setUnitActionState(unitState, "Ready", false, false)
	setUnitGridAttributes(unitState.Model, targetX, targetZ)
	tweenModelToTile(unitState.Model, tile, function()
		if unitsById[unitId] == unitState then
			unitState.IsMoving = false
			unitState.Model:SetAttribute("IsMoving", false)
		end
	end)
end

local function onUnitAction(player: Player, unitId: string, actionId: string, actionValue: any)
	if typeof(unitId) ~= "string" or typeof(actionId) ~= "string" then
		return
	end

	local unitState = unitsById[unitId]
	if not unitState or unitState.OwnerUserId ~= player.UserId or unitState.IsMoving then
		return
	end

	if actionId == "Rest" then
		healUnit(unitState, 10)
		setUnitActionState(unitState, "Resting", false, false)
	elseif actionId == "Fortify" then
		setUnitActionState(unitState, "Fortified", true, false)
	elseif actionId == "FortifyHeal" then
		healUnit(unitState, 15)
		setUnitActionState(unitState, "FortifyHeal", true, true)
	elseif actionId == "Delete" then
		removeUnit(unitId, unitState)
	elseif actionId == "FoundCity" then
		if unitState.UnitType ~= "Settler" then
			return
		end

		local cityName = typeof(actionValue) == "string" and actionValue or nil
		local cityModel = CityService.FoundCity(player, unitState.GridX, unitState.GridZ, cityName)
		if cityModel then
			removeUnit(unitId, unitState)
		else
			setUnitActionState(unitState, "FoundCityFailed", false, false)
		end
	end
end

function UnitService.Start()
	local moveEvent = getOrCreateMoveEvent()
	local unitActionEvent = getOrCreateUnitActionEvent()
	moveEvent.OnServerEvent:Connect(onMoveUnit)
	unitActionEvent.OnServerEvent:Connect(onUnitAction)

	Players.PlayerAdded:Connect(spawnStartingUnits)
	Players.PlayerRemoving:Connect(removePlayerUnits)

	for _, player in Players:GetPlayers() do
		spawnStartingUnits(player)
	end
end

return UnitService
