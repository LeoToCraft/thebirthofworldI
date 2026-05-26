local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local ResourceConfig = require(ReplicatedStorage.Shared.ResourceConfig)

local ResourceService = {}

local MAP_FOLDER_NAME = "GeneratedMap"
local RESOURCES_FOLDER_NAME = "Resources"

local resourcesById = {}
local candidatesByBiome: { [string]: { string } } = {}

local function getResourcesFolder(): Folder
	local resourcesFolder = Workspace:FindFirstChild(RESOURCES_FOLDER_NAME)
	if resourcesFolder then
		return resourcesFolder :: Folder
	end

	local newResourcesFolder = Instance.new("Folder")
	newResourcesFolder.Name = RESOURCES_FOLDER_NAME
	newResourcesFolder.Parent = Workspace

	return newResourcesFolder
end

local function clearResources()
	table.clear(resourcesById)

	local resourcesFolder = Workspace:FindFirstChild(RESOURCES_FOLDER_NAME)
	if resourcesFolder then
		resourcesFolder:Destroy()
	end
end

local function getMapFolder(): Folder?
	return Workspace:FindFirstChild(MAP_FOLDER_NAME) :: Folder?
end

local function getResourceCandidates(biomeName: string): { string }
	if candidatesByBiome[biomeName] then
		return candidatesByBiome[biomeName]
	end

	local candidates = {}

	for resourceName, resource in ResourceConfig.Types do
		if resource.AllowedBiomes[biomeName] == true then
			table.insert(candidates, resourceName)
		end
	end

	candidatesByBiome[biomeName] = candidates

	return candidates
end

local function isResourceAllowedOnTile(resourceName: string, biomeName: string): boolean
	if biomeName == "Mountain" then
		return false
	end

	if biomeName == "Water" then
		return resourceName == "Fish"
	end

	return resourceName ~= "Fish"
end

local function shouldPlaceResource(random: Random, resourceName: string?): boolean
	local rarity = 1
	if resourceName then
		rarity = ResourceConfig.Types[resourceName].Rarity or 1
	end

	return random:NextNumber() < ResourceConfig.Generation.BaseChance * rarity
end

local function chooseResource(candidates: { string }, random: Random): string?
	local totalWeight = 0
	for _, resourceName in candidates do
		totalWeight += ResourceConfig.Types[resourceName].Weight
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = random:NextNumber(0, totalWeight)
	local runningWeight = 0

	for _, resourceName in candidates do
		runningWeight += ResourceConfig.Types[resourceName].Weight
		if roll <= runningWeight then
			return resourceName
		end
	end

	return candidates[#candidates]
end

local function getInstanceBasePart(instance: Instance): BasePart?
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

local function setResourceVisualAttributes(instance: Instance, resourceName: string)
	local resource = ResourceConfig.Types[resourceName]

	instance:SetAttribute("Resource", resource.DisplayName)
	instance:SetAttribute("ResourceType", resourceName)

	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant:SetAttribute("Resource", resource.DisplayName)
			descendant:SetAttribute("ResourceType", resourceName)
		end
	end
end

local function scaleResourceVisual(instance: Instance)
	local maxSize = ResourceConfig.Visual.MaxSize

	if instance:IsA("Model") then
		local _, size = instance:GetBoundingBox()
		local largestAxis = math.max(size.X, size.Y, size.Z)
		if largestAxis > maxSize and largestAxis > 0 then
			instance:ScaleTo(maxSize / largestAxis)
		end
	elseif instance:IsA("BasePart") then
		local largestAxis = math.max(instance.Size.X, instance.Size.Y, instance.Size.Z)
		if largestAxis > maxSize and largestAxis > 0 then
			instance.Size *= maxSize / largestAxis
		end
	end
end

local function placeResourceVisual(instance: Instance, tile: BasePart)
	local tileTopY = tile.Position.Y + tile.Size.Y / 2
	local targetPosition = Vector3.new(tile.Position.X, tileTopY, tile.Position.Z)
	local heightOffset = ResourceConfig.Visual.HeightOffset

	if instance:IsA("Model") then
		local boundingBoxCFrame, size = instance:GetBoundingBox()
		local targetBoundingBoxCFrame = CFrame.new(targetPosition + Vector3.new(0, size.Y / 2 + heightOffset, 0))
		local currentPivot = instance:GetPivot()
		local targetPivot = targetBoundingBoxCFrame * boundingBoxCFrame:Inverse() * currentPivot

		instance:PivotTo(targetPivot)
	elseif instance:IsA("BasePart") then
		instance.Position = targetPosition + Vector3.new(0, instance.Size.Y / 2 + heightOffset, 0)
	end
end

local function createFallbackResourceMarker(tile: BasePart, resourceName: string): BasePart
	local resource = ResourceConfig.Types[resourceName]
	local marker = Instance.new("Part")
	marker.Name = resourceName .. "Resource"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Color = resource.Color
	marker.Material = Enum.Material.Neon
	marker.Shape = resource.Shape
	marker.Size = Vector3.new(0.55, 0.55, 0.55)
	marker.Position = Vector3.new(tile.Position.X, tile.Position.Y + tile.Size.Y / 2 + marker.Size.Y / 2 + 0.08, tile.Position.Z)

	return marker
end

local function createResourceVisual(parent: Instance, tile: BasePart, resourceName: string): Instance
	local resource = ResourceConfig.Types[resourceName]
	local storedModel = resource.ModelName and ServerStorage:FindFirstChild(resource.ModelName)
	local visual: Instance

	if storedModel then
		visual = storedModel:Clone()
		if visual:IsA("Folder") then
			local model = Instance.new("Model")
			for _, child in visual:GetChildren() do
				child.Parent = model
			end
			visual:Destroy()
			visual = model
		elseif not visual:IsA("Model") and not visual:IsA("BasePart") then
			visual:Destroy()
			visual = createFallbackResourceMarker(tile, resourceName)
		end
	else
		visual = createFallbackResourceMarker(tile, resourceName)
	end

	visual.Name = resourceName .. "Resource"

	local basePart = getInstanceBasePart(visual)
	if not basePart then
		visual:Destroy()
		visual = createFallbackResourceMarker(tile, resourceName)
	end

	setResourceVisualAttributes(visual, resourceName)
	visual:SetAttribute("GridX", tile:GetAttribute("GridX"))
	visual:SetAttribute("GridZ", tile:GetAttribute("GridZ"))
	visual.Parent = parent
	scaleResourceVisual(visual)
	placeResourceVisual(visual, tile)

	return visual
end

local function applyResourceToTile(tile: BasePart, resourceName: string, marker: Instance)
	local resource = ResourceConfig.Types[resourceName]
	local resourceId = HttpService:GenerateGUID(false)

	tile:SetAttribute("ResourceId", resourceId)
	tile:SetAttribute("ResourceType", resourceName)
	tile:SetAttribute("Resource", resource.DisplayName)
	tile:SetAttribute("ResourceCategory", resource.Category or "Common")
	tile:SetAttribute("StrategicYield", resource.StrategicYield or 0)
	tile:SetAttribute("FoodYield", resource.Yields.Food)
	tile:SetAttribute("ProductionYield", resource.Yields.Production)
	tile:SetAttribute("GoldYield", resource.Yields.Gold)
	marker:SetAttribute("ResourceId", resourceId)
	marker:SetAttribute("ResourceCategory", resource.Category or "Common")
	for _, descendant in marker:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("ResourceId", resourceId)
			descendant:SetAttribute("ResourceCategory", resource.Category or "Common")
			descendant:SetAttribute("GridX", tile:GetAttribute("GridX"))
			descendant:SetAttribute("GridZ", tile:GetAttribute("GridZ"))
		end
	end

	resourcesById[resourceId] = {
		Marker = marker,
		Tile = tile,
		ResourceType = resourceName,
		Category = resource.Category or "Common",
		GridX = tile:GetAttribute("GridX"),
		GridZ = tile:GetAttribute("GridZ"),
		Food = resource.Yields.Food,
		Production = resource.Yields.Production,
		Gold = resource.Yields.Gold,
	}
end

function ResourceService.Generate()
	Workspace:SetAttribute("ResourcesGenerating", true)
	clearResources()

	local mapFolder = getMapFolder()
	if not mapFolder then
		Workspace:SetAttribute("ResourcesGenerating", false)
		return
	end

	local resourcesFolder = getResourcesFolder()
	local random = Random.new(os.time() + math.floor(os.clock() * 1000000))
	local checkedTiles = 0
	local placedResources = 0
	local batchSize = MapConfig.Generation.ResourceBatchSize

	for _, tile in mapFolder:GetChildren() do
		if tile:IsA("BasePart") then
			checkedTiles += 1

			local x = tile:GetAttribute("GridX")
			local z = tile:GetAttribute("GridZ")
			local biomeName = tile:GetAttribute("Biome")

			if typeof(x) == "number" and typeof(z) == "number" and typeof(biomeName) == "string" then
				local candidates = getResourceCandidates(biomeName)
				if #candidates > 0 then
					local resourceName = chooseResource(candidates, random)
					if resourceName and isResourceAllowedOnTile(resourceName, biomeName) and shouldPlaceResource(random, resourceName) then
						local marker = createResourceVisual(resourcesFolder, tile, resourceName)
						applyResourceToTile(tile, resourceName, marker)
						placedResources += 1
					end
				end
			end

			if checkedTiles % batchSize == 0 then
				Workspace:SetAttribute("ResourceCheckedTiles", checkedTiles)
				Workspace:SetAttribute("PlacedResources", placedResources)
				task.wait()
			end
		end
	end

	Workspace:SetAttribute("ResourceCheckedTiles", checkedTiles)
	Workspace:SetAttribute("PlacedResources", placedResources)
	Workspace:SetAttribute("ResourcesGenerating", false)
end

return ResourceService
