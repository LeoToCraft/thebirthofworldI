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
local healthBarConnections: { [Model]: { RBXScriptConnection } } = {}

local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "MovementHighlights"
highlightFolder.Parent = Workspace

local HEALTH_BAR_NAME = "UnitHealthBar"

local function getTileName(x: number, z: number): string
	return string.format("Tile_%03d_%03d", x, z)
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild("GeneratedMap") :: Folder?
end

local function getUnitsFolder(): Folder?
	return Workspace:FindFirstChild("Units") :: Folder?
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
	if healthBarConnections[model] then
		updateHealthBar(model)
		return
	end

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
	healthBar.Size = UDim2.fromOffset(74, 18)
	healthBar.StudsOffset = Vector3.new(0, modelSize.Y / 2 + 0.65, 0)
	healthBar.Parent = adornee

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	container.BorderSizePixel = 0
	container.Position = UDim2.fromScale(0.5, 1)
	container.Size = UDim2.new(1, 0, 0, 7)
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

	healthBarConnections[model] = {
		model:GetAttributeChangedSignal("Health"):Connect(function()
			updateHealthBar(model)
		end),
		model:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			updateHealthBar(model)
		end),
		model.Destroying:Connect(function()
			local connections = healthBarConnections[model]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				healthBarConnections[model] = nil
			end
		end),
	}

	updateHealthBar(model)
end

local function watchUnitsFolder(unitsFolder: Folder)
	for _, child in unitsFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("UnitId") then
			createHealthBar(child)
		end
	end

	unitsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			if child:GetAttribute("UnitId") then
				createHealthBar(child)
				return
			end

			local connection: RBXScriptConnection?
			connection = child:GetAttributeChangedSignal("UnitId"):Connect(function()
				if child:GetAttribute("UnitId") and connection then
					connection:Disconnect()
					createHealthBar(child)
				end
			end)
		end
	end)
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

local unitsFolder = getUnitsFolder()
if unitsFolder then
	watchUnitsFolder(unitsFolder)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Units" and child:IsA("Folder") then
			watchUnitsFolder(child)
		end
	end)
end
