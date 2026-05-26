local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CityService = require(script.Parent.CityService)
local CityConfig = require(ReplicatedStorage.Shared.CityConfig)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local ResourceConfig = require(ReplicatedStorage.Shared.ResourceConfig)
local UnitConfig = require(ReplicatedStorage.Shared.UnitConfig)

local UnitService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local UNITS_FOLDER_NAME = "Units"
local REMOTES_FOLDER_NAME = "Remotes"
local MOVE_UNIT_EVENT_NAME = "MoveUnit"
local UNIT_ACTION_EVENT_NAME = "UnitAction"
local CREATE_UNIT_EVENT_NAME = "CreateUnit"
local HEALTH_BAR_NAME = "UnitHealthBar"
local IMPROVEMENTS_FOLDER_NAME = "Improvements"
local BOT_ACTION_SECONDS = 1.5
local AUTO_MOVE_STEP = 2
local BOT_PRODUCTION_SECONDS = 2
local BOT_UNIT_PRODUCTION_SECONDS = 5
local BOT_MAX_UNITS_PER_OWNER = 10
local BOT_MAX_BUILDERS_PER_OWNER = 2

local unitsById = {}
local occupiedTiles = {}
local playerOrder = 0
local botOwners = {
	{ UserId = -101, Name = "Рим", CountryName = "Римская держава", CityNamePrefix = "Рим" },
	{ UserId = -102, Name = "Египет", CountryName = "Египетское царство", CityNamePrefix = "Мемфис" },
	{ UserId = -103, Name = "Япония", CountryName = "Ямато", CityNamePrefix = "Киото" },
	{ UserId = -104, Name = "Греция", CountryName = "Эллада", CityNamePrefix = "Афины" },
	{ UserId = -105, Name = "Ацтеки", CountryName = "Союз ацтеков", CityNamePrefix = "Теночтитлан" },
	{ UserId = -106, Name = "Норвегия", CountryName = "Северное королевство", CityNamePrefix = "Берген" },
}
local setUnitActionState
local removeUnit

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

local function getOrCreateCreateUnitEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local createUnitEvent = remotesFolder:FindFirstChild(CREATE_UNIT_EVENT_NAME)
	if createUnitEvent and createUnitEvent:IsA("RemoteEvent") then
		return createUnitEvent
	end

	local newCreateUnitEvent = Instance.new("RemoteEvent")
	newCreateUnitEvent.Name = CREATE_UNIT_EVENT_NAME
	newCreateUnitEvent.Parent = remotesFolder

	return newCreateUnitEvent
end

local function canUnitEnter(unitType: string, tile: BasePart, ownerUserId: number?): boolean
	local unit = UnitConfig.Types[unitType]
	local biome = tile:GetAttribute("Biome")

	if typeof(biome) ~= "string" or unit.CanEnter[biome] ~= true then
		return false
	end

	if typeof(ownerUserId) == "number" then
		local x = tile:GetAttribute("GridX")
		local z = tile:GetAttribute("GridZ")
		if typeof(x) == "number" and typeof(z) == "number" and not CityService.CanOwnerEnterTile(ownerUserId, x, z) then
			return false
		end
	end

	return true
end

local function isOpenForUnit(unitType: string, x: number, z: number, ownerUserId: number?): boolean
	local tile = getTile(x, z)
	if not tile then
		return false
	end

	return canUnitEnter(unitType, tile, ownerUserId) and occupiedTiles[getTileKey(x, z)] == nil
end

local function setUnitAttributes(instance: Instance, unitId: string, player: any, unitType: string, x: number, z: number)
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
	instance:SetAttribute("AttachedToUnitId", nil)
	instance:SetAttribute("ActionState", "Ready")

	local buildCharges = UnitConfig.Types[unitType].BuildCharges
	if typeof(buildCharges) == "number" then
		instance:SetAttribute("BuildCharges", buildCharges)
	end
end

local function applyUnitAttributesToParts(model: Model, unitId: string, player: any, unitType: string, x: number, z: number)
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

local function findSpawnTile(unitType: string, startX: number, startZ: number, ownerUserId: number?): (number?, number?)
	local maxRadius = math.max(MapConfig.Map.Width, MapConfig.Map.Length)

	for radius = 0, maxRadius do
		for x = startX - radius, startX + radius do
			for z = startZ - radius, startZ + radius do
				if x >= 1 and x <= MapConfig.Map.Width and z >= 1 and z <= MapConfig.Map.Length then
					if isOpenForUnit(unitType, x, z, ownerUserId) then
						return x, z
					end
				end
			end
		end
	end

	return nil, nil
end

local function createUnit(player: any, unitType: string, x: number, z: number): Model?
	if not UnitConfig.Types[unitType] then
		return nil
	end

	local tile = getTile(x, z)
	if not tile or not canUnitEnter(unitType, tile, player.UserId) or occupiedTiles[getTileKey(x, z)] then
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
		MoveToken = 0,
		AttachedToUnitId = nil,
		BuildCharges = UnitConfig.Types[unitType].BuildCharges,
	}
	occupiedTiles[getTileKey(x, z)] = unitId

	return model
end

local function findOpenAdjacentTile(unitType: string, x: number, z: number, ownerUserId: number?): (number?, number?)
	for radius = 1, 3 do
		for targetX = x - radius, x + radius do
			for targetZ = z - radius, z + radius do
				local distance = math.abs(targetX - x) + math.abs(targetZ - z)
				if distance <= math.max(radius, 1) and isOpenForUnit(unitType, targetX, targetZ, ownerUserId) then
					return targetX, targetZ
				end
			end
		end
	end

	return nil, nil
end

local function findOpenNeighborNear(unitType: string, x: number, z: number, ownerUserId: number?): (number?, number?)
	local offsets = {
		{ X = 1, Z = 0 },
		{ X = -1, Z = 0 },
		{ X = 0, Z = 1 },
		{ X = 0, Z = -1 },
		{ X = 1, Z = 1 },
		{ X = 1, Z = -1 },
		{ X = -1, Z = 1 },
		{ X = -1, Z = -1 },
	}

	for _, offset in offsets do
		local targetX = x + offset.X
		local targetZ = z + offset.Z
		if isOpenForUnit(unitType, targetX, targetZ, ownerUserId) then
			return targetX, targetZ
		end
	end

	return nil, nil
end

local function buildPath(unitType: string, startX: number, startZ: number, targetX: number, targetZ: number, ownerUserId: number?): { { X: number, Z: number } }?
	local targetTile = getTile(targetX, targetZ)
	if not targetTile or not canUnitEnter(unitType, targetTile, ownerUserId) or occupiedTiles[getTileKey(targetX, targetZ)] then
		return nil
	end

	local startKey = getTileKey(startX, startZ)
	local targetKey = getTileKey(targetX, targetZ)
	local queue = { { X = startX, Z = startZ } }
	local head = 1
	local visited = { [startKey] = true }
	local cameFrom: { [string]: string } = {}
	local positionsByKey = { [startKey] = { X = startX, Z = startZ } }
	local directions = {
		{ X = 1, Z = 0 },
		{ X = -1, Z = 0 },
		{ X = 0, Z = 1 },
		{ X = 0, Z = -1 },
	}

	while head <= #queue do
		local current = queue[head]
		head += 1
		local currentKey = getTileKey(current.X, current.Z)

		if currentKey == targetKey then
			local path = {}
			local pathKey = targetKey

			while pathKey ~= startKey do
				table.insert(path, 1, positionsByKey[pathKey])
				pathKey = cameFrom[pathKey]
			end

			return path
		end

		for _, direction in directions do
			local nextX = current.X + direction.X
			local nextZ = current.Z + direction.Z
			local nextKey = getTileKey(nextX, nextZ)
			if not visited[nextKey] then
				local tile = getTile(nextX, nextZ)
				if tile and canUnitEnter(unitType, tile, ownerUserId) and not occupiedTiles[nextKey] then
					visited[nextKey] = true
					cameFrom[nextKey] = currentKey
					positionsByKey[nextKey] = { X = nextX, Z = nextZ }
					table.insert(queue, positionsByKey[nextKey])
				end
			end
		end
	end

	return nil
end

local function getImprovementsFolder(): Folder
	local folder = Workspace:FindFirstChild(IMPROVEMENTS_FOLDER_NAME)
	if folder then
		return folder :: Folder
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = IMPROVEMENTS_FOLDER_NAME
	newFolder.Parent = Workspace

	return newFolder
end

local function removeResourceVisual(resourceId: any)
	if typeof(resourceId) ~= "string" then
		return
	end

	local resourcesFolder = Workspace:FindFirstChild("Resources")
	if not resourcesFolder then
		return
	end

	for _, child in resourcesFolder:GetChildren() do
		if child:GetAttribute("ResourceId") == resourceId then
			child:Destroy()
			return
		end

		for _, descendant in child:GetDescendants() do
			if descendant:GetAttribute("ResourceId") == resourceId then
				child:Destroy()
				return
			end
		end
	end
end

local function getVisualBaseParts(instance: Instance): { BasePart }
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getVisualBounds(instance: Instance): (CFrame, Vector3)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return CFrame.new(), Vector3.zero
end

local function getPartWorldCorner(part: BasePart, x: number, y: number, z: number): Vector3
	return (part.CFrame * CFrame.new(
		part.Size.X * x / 2,
		part.Size.Y * y / 2,
		part.Size.Z * z / 2
	)).Position
end

local function getVisualMinY(instance: Instance): number?
	local minY = nil

	for _, part in getVisualBaseParts(instance) do
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = getPartWorldCorner(part, x, y, z)
					if minY == nil or corner.Y < minY then
						minY = corner.Y
					end
				end
			end
		end
	end

	return minY
end

local function scaleVisualToTile(instance: Instance, maxSize: number)
	local boundsCFrame, boundsSize = getVisualBounds(instance)
	local largestAxis = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z)
	if largestAxis <= maxSize or largestAxis <= 0 then
		return
	end

	local scale = maxSize / largestAxis
	if instance:IsA("BasePart") then
		instance.Size *= scale
		return
	end

	for _, part in getVisualBaseParts(instance) do
		local localCFrame = boundsCFrame:ToObjectSpace(part.CFrame)
		local localPosition = localCFrame.Position * scale
		local localRotation = localCFrame - localCFrame.Position
		part.Size *= scale
		part.CFrame = boundsCFrame * CFrame.new(localPosition) * localRotation
	end
end

local function placeVisualOnTile(instance: Instance, tile: BasePart, heightOffset: number)
	local tileTopY = tile.Position.Y + tile.Size.Y / 2
	local targetPosition = Vector3.new(tile.Position.X, tileTopY, tile.Position.Z)

	if instance:IsA("Model") then
		local boundingBoxCFrame, size = getVisualBounds(instance)
		local targetCenter = targetPosition + Vector3.new(0, size.Y / 2 + heightOffset, 0)
		local delta = targetCenter - boundingBoxCFrame.Position
		instance:PivotTo(CFrame.new(delta) * instance:GetPivot())

		local minY = getVisualMinY(instance)
		if minY then
			instance:PivotTo(CFrame.new(0, tileTopY + heightOffset - minY, 0) * instance:GetPivot())
		end
	elseif instance:IsA("BasePart") then
		instance.Position = targetPosition + Vector3.new(0, instance.Size.Y / 2 + heightOffset, 0)
	end
end

local function prepareImprovementVisual(instance: Instance, resourceType: string, resourceId: any, tile: BasePart)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	for _, part in getVisualBaseParts(instance) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part:SetAttribute("ResourceId", resourceId)
		part:SetAttribute("ResourceType", resourceType)
		part:SetAttribute("GridX", tile:GetAttribute("GridX"))
		part:SetAttribute("GridZ", tile:GetAttribute("GridZ"))
	end

	instance:SetAttribute("ResourceId", resourceId)
	instance:SetAttribute("ResourceType", resourceType)
	instance:SetAttribute("GridX", tile:GetAttribute("GridX"))
	instance:SetAttribute("GridZ", tile:GetAttribute("GridZ"))
end

local function createImprovementVisual(tile: BasePart, resourceType: string): Instance?
	local resource = ResourceConfig.Types[resourceType]
	if not resource then
		return nil
	end

	local modelName = (resource.ModelName or string.lower(resourceType)) .. "_up"
	local storedModel = ServerStorage:FindFirstChild(modelName)
	if not storedModel then
		return nil
	end

	local visual = storedModel:Clone()
	if visual:IsA("Folder") then
		local model = Instance.new("Model")
		for _, child in visual:GetChildren() do
			child.Parent = model
		end
		visual:Destroy()
		visual = model
	elseif not visual:IsA("Model") and not visual:IsA("BasePart") then
		visual:Destroy()
		return nil
	end

	visual.Name = modelName
	prepareImprovementVisual(visual, resourceType, tile:GetAttribute("ResourceId"), tile)
	if #getVisualBaseParts(visual) == 0 then
		visual:Destroy()
		return nil
	end

	visual.Parent = getImprovementsFolder()
	scaleVisualToTile(visual, ResourceConfig.Visual.ImprovedMaxSize or ResourceConfig.Visual.MaxSize)
	local yOffsetByType = ResourceConfig.Visual.ImprovedYOffsetByType or {}
	local heightOffset = (ResourceConfig.Visual.ImprovedHeightOffset or ResourceConfig.Visual.HeightOffset) + (yOffsetByType[resourceType] or 0)
	placeVisualOnTile(visual, tile, heightOffset)

	return visual
end

local function createFallbackImprovementMarker(tile: BasePart, resourceType: string): BasePart
	local resource = ResourceConfig.Types[resourceType]
	local marker = Instance.new("Part")
	marker.Name = resourceType .. "_up"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Color = resource and resource.Color or Color3.fromRGB(140, 210, 120)
	marker.Material = Enum.Material.SmoothPlastic
	marker.Size = Vector3.new(0.8, 0.18, 0.8)
	marker.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + marker.Size.Y / 2 + 0.08, tile.Position.Z)
	prepareImprovementVisual(marker, resourceType, tile:GetAttribute("ResourceId"), tile)
	marker.Parent = getImprovementsFolder()

	return marker
end

local function scaleTreasuryYield(value: number): number
	if value <= 0 then
		return 0
	end

	return math.max(1, math.floor(value * (CityConfig.Economy.YieldMultiplier or 1) + 0.5))
end

local function buildResourceImprovement(unitId: string, unitState)
	if unitState.UnitType ~= "Builder" then
		return
	end

	local maxCharges = UnitConfig.Types.Builder.BuildCharges or 2
	local charges = unitState.BuildCharges
	if typeof(charges) ~= "number" then
		charges = unitState.Model:GetAttribute("BuildCharges")
	end
	if typeof(charges) ~= "number" then
		charges = maxCharges
	end
	if charges <= 0 then
		setUnitActionState(unitState, "NoBuildCharges", false, false)
		return
	end

	local tile = getTile(unitState.GridX, unitState.GridZ)
	if not tile or tile:GetAttribute("ResourceId") == nil or tile:GetAttribute("ImprovedResource") == true then
		setUnitActionState(unitState, "BuildFailed", false, false)
		return
	end

	local resourceId = tile:GetAttribute("ResourceId")
	local resourceType = tile:GetAttribute("ResourceType")
	if typeof(resourceType) ~= "string" then
		setUnitActionState(unitState, "BuildFailed", false, false)
		return
	end

	tile:SetAttribute("ImprovedResource", true)
	removeResourceVisual(resourceId)
	tile:SetAttribute("FoodYield", (tile:GetAttribute("FoodYield") or 0) + 1)
	tile:SetAttribute("ProductionYield", (tile:GetAttribute("ProductionYield") or 0) + 1)
	CityService.RefreshYieldsNear(unitState.OwnerUserId, unitState.GridX, unitState.GridZ)
	CityService.AddTreasury(
		unitState.OwnerUserId,
		scaleTreasuryYield(tile:GetAttribute("FoodYield") or 0),
		scaleTreasuryYield(tile:GetAttribute("ProductionYield") or 0),
		scaleTreasuryYield(tile:GetAttribute("GoldYield") or 0)
	)

	if not createImprovementVisual(tile, resourceType) then
		createFallbackImprovementMarker(tile, resourceType)
	end

	charges -= 1
	unitState.BuildCharges = charges
	if unitState.Model then
		unitState.Model:SetAttribute("BuildCharges", charges)
	end

	if charges <= 0 then
		removeUnit(unitId, unitState)
	else
		setUnitActionState(unitState, "BuiltImprovement", false, false)
	end
end

local function isAllowedProducedUnit(unitType: string): boolean
	if unitType ~= "Warrior" and unitType ~= "Settler" and unitType ~= "Builder" and unitType ~= "Archer" and unitType ~= "Scout" then
		return false
	end

	return true
end

local function startCityProduction(owner: any, cityId: string, unitType: string)
	if not isAllowedProducedUnit(unitType) then
		return
	end

	local cityState = CityService.GetCity(cityId)
	if not cityState or cityState.OwnerUserId ~= owner.UserId then
		return
	end

	if cityState.ProductionQueue ~= nil then
		return
	end

	cityState.ProductionQueue = unitType
	local productionSeconds = owner.UserId < 0 and BOT_UNIT_PRODUCTION_SECONDS or CityConfig.Economy.UnitProductionSeconds
	if cityState.Model then
		cityState.Model:SetAttribute("ProductionQueue", unitType)
		cityState.Model:SetAttribute("ProductionSecondsLeft", productionSeconds)
	end

	task.spawn(function()
		for secondsLeft = productionSeconds, 1, -1 do
			if not CityService.GetCity(cityId) then
				return
			end

			if cityState.Model then
				cityState.Model:SetAttribute("ProductionSecondsLeft", secondsLeft)
			end

			task.wait(1)
		end

		local currentCityState = CityService.GetCity(cityId)
		if not currentCityState or currentCityState.ProductionQueue ~= unitType then
			return
		end

		local x, z = findOpenAdjacentTile(unitType, currentCityState.GridX, currentCityState.GridZ, currentCityState.OwnerUserId)
		if x and z then
			createUnit(owner, unitType, x, z)
		end

		currentCityState.ProductionQueue = nil
		if currentCityState.Model then
			currentCityState.Model:SetAttribute("ProductionQueue", nil)
			currentCityState.Model:SetAttribute("ProductionSecondsLeft", 0)
		end
	end)
end

local function onCreateUnit(player: Player, cityId: string, unitType: string)
	if typeof(cityId) ~= "string" or typeof(unitType) ~= "string" then
		return
	end

	startCityProduction(player, cityId, unitType)
end

local function spawnStartingUnits(player: Player)
	playerOrder += 1

	local centerX = math.floor(MapConfig.Map.Width / 2) + (playerOrder - 1) * 5
	local centerZ = math.floor(MapConfig.Map.Length / 2)

	local settlerX, settlerZ = findSpawnTile("Settler", centerX, centerZ, player.UserId)
	if settlerX and settlerZ then
		createUnit(player, "Settler", settlerX, settlerZ)
	end

	local warriorX, warriorZ = findSpawnTile("Warrior", centerX + 1, centerZ, player.UserId)
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

function removeUnit(unitId: string, unitState)
	occupiedTiles[getTileKey(unitState.GridX, unitState.GridZ)] = nil

	if unitState.Model then
		unitState.Model:Destroy()
	end

	unitsById[unitId] = nil
end

local function damageUnit(targetUnitId: string, targetState, amount: number)
	local currentHealth = targetState.Model:GetAttribute("Health")
	if typeof(currentHealth) ~= "number" then
		currentHealth = UnitConfig.Types[targetState.UnitType].Health
	end

	local nextHealth = currentHealth - amount
	targetState.Model:SetAttribute("Health", math.max(0, nextHealth))

	if nextHealth <= 0 then
		removeUnit(targetUnitId, targetState)
	end
end

local function attackUnit(attackerUnitId: string, attackerState, targetUnitId: string, targetState): boolean
	if attackerUnitId == targetUnitId or attackerState.OwnerUserId == targetState.OwnerUserId then
		return false
	end

	local attackerConfig = UnitConfig.Types[attackerState.UnitType]
	if not attackerConfig or attackerConfig.Attack <= 0 then
		return false
	end

	local range = attackerConfig.Range or 1
	local distance = math.abs(targetState.GridX - attackerState.GridX) + math.abs(targetState.GridZ - attackerState.GridZ)
	if distance < 1 or distance > range then
		return false
	end

	if not CityService.AreAtWar(attackerState.OwnerUserId, targetState.OwnerUserId) then
		CityService.SetWar(attackerState.OwnerUserId, targetState.OwnerUserId, true, "Военное нападение")
	end

	local damage = attackerConfig.Attack
	if targetState.Model:GetAttribute("Fortified") == true then
		damage = math.floor(damage * 0.75)
	end

	damageUnit(targetUnitId, targetState, damage)
	setUnitActionState(attackerState, "Attacked", false, false)

	return true
end

local function attackCity(attackerState, cityId: string): boolean
	local cityState = CityService.GetCity(cityId)
	if not cityState or cityState.OwnerUserId == attackerState.OwnerUserId then
		return false
	end

	local attackerConfig = UnitConfig.Types[attackerState.UnitType]
	if not attackerConfig or attackerConfig.Attack <= 0 then
		return false
	end

	local range = attackerConfig.Range or 1
	local distance = math.abs(cityState.GridX - attackerState.GridX) + math.abs(cityState.GridZ - attackerState.GridZ)
	if distance < 1 or distance > range then
		return false
	end

	CityService.DamageCity(attackerState.OwnerUserId, cityId, attackerConfig.Attack)
	setUnitActionState(attackerState, "AttackedCity", false, false)

	return true
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

function setUnitActionState(unitState, actionState: string, fortified: boolean, fortifyUntilHealed: boolean)
	unitState.Model:SetAttribute("ActionState", actionState)
	unitState.Model:SetAttribute("Fortified", fortified)
	unitState.Model:SetAttribute("FortifyUntilHealed", fortifyUntilHealed)
end

local moveUnitToTile

local function moveAttachedFollowers(leaderUnitId: string, leaderState)
	for followerUnitId, followerState in unitsById do
		if followerState.AttachedToUnitId == leaderUnitId and not followerState.IsMoving then
			local targetX, targetZ = findOpenNeighborNear(followerState.UnitType, leaderState.GridX, leaderState.GridZ, followerState.OwnerUserId)
			if targetX and targetZ then
				moveUnitToTile(followerUnitId, followerState, targetX, targetZ, false)
			end
		end
	end
end

function moveUnitToTile(unitId: string, unitState, targetX: number, targetZ: number, moveFollowers: boolean?): boolean
	local tile = getTile(targetX, targetZ)
	if not tile or not canUnitEnter(unitState.UnitType, tile, unitState.OwnerUserId) or occupiedTiles[getTileKey(targetX, targetZ)] then
		return false
	end

	occupiedTiles[getTileKey(unitState.GridX, unitState.GridZ)] = nil
	occupiedTiles[getTileKey(targetX, targetZ)] = unitId

	unitState.GridX = targetX
	unitState.GridZ = targetZ
	unitState.IsMoving = true
	unitState.Model:SetAttribute("IsMoving", true)
	setUnitActionState(unitState, "Moving", false, false)
	setUnitGridAttributes(unitState.Model, targetX, targetZ)

	tweenModelToTile(unitState.Model, tile, function()
		if unitsById[unitId] == unitState then
			unitState.IsMoving = false
			unitState.Model:SetAttribute("IsMoving", false)
			if moveFollowers ~= false then
				moveAttachedFollowers(unitId, unitState)
			end
		end
	end)

	return true
end

local function startAutoMove(unitId: string, unitState, targetX: number, targetZ: number)
	unitState.MoveToken = (unitState.MoveToken or 0) + 1
	local moveToken = unitState.MoveToken

	task.spawn(function()
		while unitsById[unitId] == unitState and unitState.MoveToken == moveToken do
			if unitState.GridX == targetX and unitState.GridZ == targetZ then
				setUnitActionState(unitState, "Ready", false, false)
				return
			end

			if unitState.IsMoving then
				task.wait(0.1)
				continue
			end

			local path = buildPath(unitState.UnitType, unitState.GridX, unitState.GridZ, targetX, targetZ, unitState.OwnerUserId)
			if not path or #path == 0 then
				setUnitActionState(unitState, "MoveBlocked", false, false)
				return
			end

			local step = path[math.min(AUTO_MOVE_STEP, #path)]
			if not moveUnitToTile(unitId, unitState, step.X, step.Z, true) then
				setUnitActionState(unitState, "MoveBlocked", false, false)
				return
			end

			task.wait(UnitConfig.Animation.MoveTime + BOT_ACTION_SECONDS)
		end
	end)
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

	local distance = math.abs(targetX - unitState.GridX) + math.abs(targetZ - unitState.GridZ)
	if distance < 1 then
		return
	end

	local tile = getTile(targetX, targetZ)
	if not tile or not canUnitEnter(unitState.UnitType, tile, unitState.OwnerUserId) then
		return
	end

	local targetKey = getTileKey(targetX, targetZ)
	if occupiedTiles[targetKey] then
		return
	end

	if distance <= AUTO_MOVE_STEP then
		unitState.MoveToken = (unitState.MoveToken or 0) + 1
		moveUnitToTile(unitId, unitState, targetX, targetZ, true)
	else
		startAutoMove(unitId, unitState, targetX, targetZ)
	end
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
	elseif actionId == "BuildImprovement" then
		buildResourceImprovement(unitId, unitState)
	elseif actionId == "Attack" then
		if typeof(actionValue) ~= "string" then
			return
		end

		local targetState = unitsById[actionValue]
		if targetState then
			attackUnit(unitId, unitState, actionValue, targetState)
		end
	elseif actionId == "AttackCity" then
		if typeof(actionValue) == "string" then
			attackCity(unitState, actionValue)
		end
	elseif actionId == "AttachTo" then
		if typeof(actionValue) ~= "string" or actionValue == unitId then
			return
		end

		local targetState = unitsById[actionValue]
		local distance = targetState and (math.abs(targetState.GridX - unitState.GridX) + math.abs(targetState.GridZ - unitState.GridZ)) or math.huge
		if targetState and targetState.OwnerUserId == unitState.OwnerUserId and targetState.AttachedToUnitId ~= unitId and distance <= 3 then
			unitState.AttachedToUnitId = actionValue
			unitState.Model:SetAttribute("AttachedToUnitId", actionValue)
			setUnitActionState(unitState, "Attached", false, false)
		end
	elseif actionId == "Detach" then
		unitState.AttachedToUnitId = nil
		unitState.Model:SetAttribute("AttachedToUnitId", nil)
		setUnitActionState(unitState, "Detached", false, false)
	end
end

local function findBotAttackTarget(unitState): (string?, any?)
	local unit = UnitConfig.Types[unitState.UnitType]
	if not unit or unit.Attack <= 0 then
		return nil, nil
	end

	local range = unit.Range or 1
	for targetUnitId, targetState in unitsById do
		if targetState.OwnerUserId ~= unitState.OwnerUserId then
			local distance = math.abs(targetState.GridX - unitState.GridX) + math.abs(targetState.GridZ - unitState.GridZ)
			if distance >= 1 and distance <= range then
				return targetUnitId, targetState
			end
		end
	end

	return nil, nil
end

local function findBotCityTarget(unitState): string?
	local unit = UnitConfig.Types[unitState.UnitType]
	if not unit or unit.Attack <= 0 then
		return nil
	end

	local range = unit.Range or 1
	for cityId, cityState in CityService.GetCities() do
		if cityState.OwnerUserId ~= unitState.OwnerUserId then
			local distance = math.abs(cityState.GridX - unitState.GridX) + math.abs(cityState.GridZ - unitState.GridZ)
			if distance >= 1 and distance <= range then
				return cityId
			end
		end
	end

	return nil
end

local function spawnBotUnits()
	local spawnPoints = {
		{ X = 16, Z = 16 },
		{ X = MapConfig.Map.Width - 16, Z = 18 },
		{ X = 18, Z = MapConfig.Map.Length - 16 },
		{ X = MapConfig.Map.Width - 18, Z = MapConfig.Map.Length - 18 },
		{ X = math.floor(MapConfig.Map.Width / 2), Z = 14 },
		{ X = math.floor(MapConfig.Map.Width / 2), Z = MapConfig.Map.Length - 14 },
	}

	for index, bot in botOwners do
		local point = spawnPoints[index]
		local settlerX, settlerZ = findSpawnTile("Settler", point.X, point.Z, bot.UserId)
		if settlerX and settlerZ then
			createUnit(bot :: any, "Settler", settlerX, settlerZ)
		end

		local warriorX, warriorZ = findSpawnTile("Warrior", point.X + 2, point.Z, bot.UserId)
		if warriorX and warriorZ then
			createUnit(bot :: any, "Warrior", warriorX, warriorZ)
		end
	end
end

local function getBotOwner(ownerUserId: number)
	for _, owner in botOwners do
		if owner.UserId == ownerUserId then
			return owner
		end
	end

	return nil
end

local function getBotUnitCounts(ownerUserId: number): (number, number)
	local totalUnits = 0
	local builders = 0

	for _, unitState in unitsById do
		if unitState.OwnerUserId == ownerUserId then
			totalUnits += 1
			if unitState.UnitType == "Builder" then
				builders += 1
			end
		end
	end

	return totalUnits, builders
end

local function chooseBotProducedUnit(random: Random, ownerUserId: number): string?
	local totalUnits, builders = getBotUnitCounts(ownerUserId)
	if totalUnits >= BOT_MAX_UNITS_PER_OWNER then
		return nil
	end

	local producedUnits = { "Warrior", "Archer", "Scout" }
	if builders < BOT_MAX_BUILDERS_PER_OWNER then
		table.insert(producedUnits, "Builder")
	end

	return producedUnits[random:NextInteger(1, #producedUnits)]
end

local function startBotProductionLoop()
	local random = Random.new()

	while true do
		task.wait(BOT_PRODUCTION_SECONDS)

		for cityId, cityState in CityService.GetCities() do
			if cityState.OwnerUserId < 0 and cityState.ProductionQueue == nil then
				local botOwner = getBotOwner(cityState.OwnerUserId)
				if botOwner then
					local unitType = chooseBotProducedUnit(random, cityState.OwnerUserId)
					if unitType then
						startCityProduction(botOwner, cityId, unitType)
					end
				end
			end
		end
	end
end

local function moveBotUnits()
	local random = Random.new()

	while true do
		task.wait(BOT_ACTION_SECONDS)

		for unitId, unitState in unitsById do
			if unitState.OwnerUserId < 0 and not unitState.IsMoving then
				if unitState.UnitType == "Settler" then
					local botOwner
					for _, owner in botOwners do
						if owner.UserId == unitState.OwnerUserId then
							botOwner = owner
							break
						end
					end

					if botOwner then
						local cityModel = CityService.FoundCity(botOwner :: any, unitState.GridX, unitState.GridZ, botOwner.CityNamePrefix)
						if cityModel then
							removeUnit(unitId, unitState)
							continue
						end
					end
				end

				local targetUnitId, targetState = findBotAttackTarget(unitState)
				if targetUnitId and targetState and attackUnit(unitId, unitState, targetUnitId, targetState) then
					continue
				end

				local targetCityId = findBotCityTarget(unitState)
				if targetCityId and attackCity(unitState, targetCityId) then
					continue
				end

				local unit = UnitConfig.Types[unitState.UnitType]
				local directions = {
					{ X = 1, Z = 0 },
					{ X = -1, Z = 0 },
					{ X = 0, Z = 1 },
					{ X = 0, Z = -1 },
				}
				local direction = directions[random:NextInteger(1, #directions)]
				local targetX = unitState.GridX + direction.X * math.max(1, math.min(unit.Movement, 2))
				local targetZ = unitState.GridZ + direction.Z * math.max(1, math.min(unit.Movement, 2))
				local tile = getTile(targetX, targetZ)
				local targetKey = getTileKey(targetX, targetZ)

				if tile and canUnitEnter(unitState.UnitType, tile, unitState.OwnerUserId) and not occupiedTiles[targetKey] then
					occupiedTiles[getTileKey(unitState.GridX, unitState.GridZ)] = nil
					occupiedTiles[targetKey] = unitId
					unitState.GridX = targetX
					unitState.GridZ = targetZ
					unitState.IsMoving = true
					unitState.Model:SetAttribute("IsMoving", true)
					setUnitGridAttributes(unitState.Model, targetX, targetZ)
					tweenModelToTile(unitState.Model, tile, function()
						if unitsById[unitId] == unitState then
							unitState.IsMoving = false
							unitState.Model:SetAttribute("IsMoving", false)
						end
					end)
				end
			end
		end
	end
end

function UnitService.Start()
	local moveEvent = getOrCreateMoveEvent()
	local unitActionEvent = getOrCreateUnitActionEvent()
	local createUnitEvent = getOrCreateCreateUnitEvent()
	moveEvent.OnServerEvent:Connect(onMoveUnit)
	unitActionEvent.OnServerEvent:Connect(onUnitAction)
	createUnitEvent.OnServerEvent:Connect(onCreateUnit)

	Players.PlayerAdded:Connect(spawnStartingUnits)
	Players.PlayerRemoving:Connect(removePlayerUnits)

	for _, player in Players:GetPlayers() do
		spawnStartingUnits(player)
	end

	spawnBotUnits()
	task.spawn(moveBotUnits)
	task.spawn(startBotProductionLoop)
end

return UnitService
