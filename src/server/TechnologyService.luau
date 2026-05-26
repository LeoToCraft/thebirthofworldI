local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TechnologyConfig = require(ReplicatedStorage.Shared.TechnologyConfig)

local TechnologyService = {}

local REMOTES_FOLDER_NAME = "Remotes"
local RESEARCH_EVENT_NAME = "ResearchTechnology"

local researchTokensByPlayer: { [Player]: number } = {}

local function getOrCreateResearchEvent(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local researchEvent = remotesFolder:FindFirstChild(RESEARCH_EVENT_NAME)
	if researchEvent and researchEvent:IsA("RemoteEvent") then
		return researchEvent
	end

	local newResearchEvent = Instance.new("RemoteEvent")
	newResearchEvent.Name = RESEARCH_EVENT_NAME
	newResearchEvent.Parent = remotesFolder
	return newResearchEvent
end

local function hasCompleted(player: Player, technologyId: string): boolean
	return player:GetAttribute("CompletedTech_" .. technologyId) == true
end

local function hasPrerequisites(player: Player, technology): boolean
	for _, requiredId in technology.Requires or {} do
		if not hasCompleted(player, requiredId) then
			return false
		end
	end

	return true
end

local function clearCurrentResearch(player: Player)
	player:SetAttribute("CurrentResearchId", nil)
	player:SetAttribute("CurrentResearchName", nil)
	player:SetAttribute("ResearchSecondsLeft", 0)
end

local function completeResearch(player: Player, technology)
	player:SetAttribute("CompletedTech_" .. technology.Id, true)
	player:SetAttribute("LastResearchMessage", "Исследовано: " .. technology.Name)
	clearCurrentResearch(player)

	if technology.Id == "Writing" then
		player:SetAttribute("TreasuryScience", (player:GetAttribute("TreasuryScience") or 0) + 1)
	end
end

local function startResearch(player: Player, technologyId: string)
	local technology = TechnologyConfig.ById[technologyId]
	if not technology then
		return
	end

	if player:GetAttribute("CurrentResearchId") ~= nil then
		player:SetAttribute("LastResearchMessage", "Уже идёт исследование")
		return
	end

	if hasCompleted(player, technologyId) then
		player:SetAttribute("LastResearchMessage", "Технология уже изучена")
		return
	end

	if not hasPrerequisites(player, technology) then
		player:SetAttribute("LastResearchMessage", "Нужны предыдущие исследования")
		return
	end

	local token = (researchTokensByPlayer[player] or 0) + 1
	researchTokensByPlayer[player] = token

	player:SetAttribute("CurrentResearchId", technology.Id)
	player:SetAttribute("CurrentResearchName", technology.Name)
	player:SetAttribute("ResearchSecondsLeft", technology.Seconds)
	player:SetAttribute("LastResearchMessage", "Исследуется: " .. technology.Name)

	task.spawn(function()
		for secondsLeft = technology.Seconds, 1, -1 do
			if not player.Parent or researchTokensByPlayer[player] ~= token then
				return
			end

			player:SetAttribute("ResearchSecondsLeft", secondsLeft)
			task.wait(1)
		end

		if player.Parent and researchTokensByPlayer[player] == token then
			completeResearch(player, technology)
		end
	end)
end

local function onResearchTechnology(player: Player, technologyId: string)
	if typeof(technologyId) ~= "string" then
		return
	end

	startResearch(player, technologyId)
end

function TechnologyService.Start()
	getOrCreateResearchEvent().OnServerEvent:Connect(onResearchTechnology)

	Players.PlayerRemoving:Connect(function(player)
		researchTokensByPlayer[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("ResearchSecondsLeft") == nil then
			player:SetAttribute("ResearchSecondsLeft", 0)
		end
	end
end

return TechnologyService
