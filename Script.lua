-- ═══════════════════════════════════════════════════════════════
--  PXZD HUB DUELS · MVSD EDITION
--  SOURCE PXZD HUB · POWERED BY NEXY · TAKEN BY CHEMXHUB
-- ═══════════════════════════════════════════════════════════════

-- ═══ CAPA ANTI-DETECCIÓN ═══
if getgenv().PxzdHubDuelsLoaded then return end
getgenv().PxzdHubDuelsLoaded = true

local oldGetFenv = getfenv
getfenv = newcclosure(function(level)
    local ok, env = pcall(oldGetFenv, level)
    if ok and type(env) == "table" then
        env.getgenv = nil; env.syn = nil; env.identifyexecutor = nil
        env.getexecutorname = nil; env.request = nil; env.http = nil
        return env
    end
    return env
end)

local oldNamecallGlobal = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if checkcaller() then return oldNamecallGlobal(self, ...) end
    return oldNamecallGlobal(self, ...)
end))

pcall(function()
    local oldNewProxy = newproxy
    newproxy = newcclosure(function(addMeta)
        local proxy = oldNewProxy(addMeta)
        if addMeta then
            local mt = getmetatable(proxy)
            if mt then mt.__tostring = function() return "" end end
        end
        return proxy
    end)
end)

-- ═══ SERVICIOS ═══
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local player = Player
local getgenv = getgenv or function() return _G end

local isEnemy, estaEnLobby, IsInMatchStrict
local esEnemigoValido, esCuchillo, esPistola, obtenerPistola
local startTargetMonitor, stopTargetMonitor

do
local playerGui = player:WaitForChild("PlayerGui")
local dmvsInvalidateRedirectSelection
local dmvsClearTargetParts
local function dmvsDisconnectConnectionList(list)
    if not list then return end
    for i = #list, 1, -1 do
        local connection = list[i]
        list[i] = nil
        if connection and connection.Connected then connection:Disconnect() end
    end
end
local dmvsIsInfectionMode
local function dmvsIsTargetAlive(target)
    local character = target
    if typeof(target) == "Instance" and target:IsA("Player") then
        character = target.Character
    end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    if dmvsIsInfectionMode and dmvsIsInfectionMode() then
        return character:GetAttribute("InfectionDowned") ~= true
    end
    return humanoid.Health >= 99
end
local function dmvsGetInGameScoreboard()
    local gui = player:FindFirstChild("PlayerGui")
    local main = gui and gui:FindFirstChild("Main")
    local frame = main and main:FindFirstChild("MainGameFrame")
    return frame and frame:FindFirstChild("IngameScore") or nil
end

local dmvsTeamResolverState = {
    Snapshot = {}, Scoreboard = nil, InGame = false, LocalGame = nil,
    LastRefresh = 0, RefreshInterval = 2, Dirty = true, WatchConnections = {}
}

local function dmvsInvalidateScoreboard()
    dmvsTeamResolverState.Dirty = true
end

local function dmvsWatchScoreboard(score)
    local state = dmvsTeamResolverState
    if state.Scoreboard == score then return end
    dmvsDisconnectConnectionList(state.WatchConnections)
    state.Scoreboard = score
    if not score then return end
    local watchTeams
    watchTeams = function()
        dmvsInvalidateScoreboard()
        dmvsDisconnectConnectionList(state.WatchConnections)
        state.WatchConnections[#state.WatchConnections + 1] = score.ChildAdded:Connect(watchTeams)
        state.WatchConnections[#state.WatchConnections + 1] = score.ChildRemoved:Connect(watchTeams)
        for _, name in ipairs({"TeamRed", "TeamBlue"}) do
            local folder = score:FindFirstChild(name)
            if folder then
                state.WatchConnections[#state.WatchConnections + 1] = folder.ChildAdded:Connect(dmvsInvalidateScoreboard)
                state.WatchConnections[#state.WatchConnections + 1] = folder.ChildRemoved:Connect(dmvsInvalidateScoreboard)
            end
        end
    end
    watchTeams()
end

local function dmvsRefreshScoreboardTeams(force)
    local state = dmvsTeamResolverState
    local now = os.clock()
    local localGame = player:GetAttribute("Game")
    if not force and not state.Dirty and now - state.LastRefresh < state.RefreshInterval
        and state.LocalGame == localGame
        and (not state.Scoreboard or state.Scoreboard.Parent) then
        return state.Snapshot
    end
    state.LastRefresh = now
    state.LocalGame = localGame
    local snapshot = {}
    local score = dmvsGetInGameScoreboard()
    if score ~= state.Scoreboard then dmvsWatchScoreboard(score) end
    for _, teamName in ipairs({"TeamRed", "TeamBlue"}) do
        local teamFolder = score and score:FindFirstChild(teamName)
        if teamFolder then
            local team = teamName == "TeamRed" and "Red" or "Blue"
            for _, entry in ipairs(teamFolder:GetChildren()) do
                if entry:IsA("GuiObject") then
                    snapshot[string.lower(entry.Name)] = team
                end
            end
        end
    end
    state.Snapshot = snapshot
    state.Dirty = false
    state.InGame = score ~= nil and snapshot[string.lower(player.Name)] ~= nil
    return snapshot
end

local dmvsInfectionRoleAttributes = {"InfectionInfected", "IsInfected", "Infected", "IsZombie", "Zombie"}
local dmvsInfectionModeAttributes = {"GameMode", "MatchMode", "Mode"}
local dmvsInfectionState = {
    Active = false, LastRefresh = -math.huge, RefreshInterval = 0.4,
    RoleTeams = {}, Inferred = {}, Targets = {}, Converted = {}, ConvertedAt = {},
    Pending = {}, LateJoiners = {}, LastLocalGame = nil, LastMatchId = nil,
    HasMatchContext = false, RoundEnded = false
}

local function dmvsInfectionReadMarker(holder)
    if not holder then return nil end
    if holder:GetAttribute("InfectionPatientZero") == true then return true end
    local sawSurvivor = false
    for _, name in ipairs(dmvsInfectionRoleAttributes) do
        local value = holder:GetAttribute(name)
        if typeof(value) == "boolean" then
            if value then return true end
            sawSurvivor = true
        elseif typeof(value) == "string" then
            local normalized = value:lower()
            if normalized == "infected" or normalized == "infection" or normalized == "zombie" or normalized == "true" then
                return true
            end
            if normalized == "survivor" or normalized == "human" or normalized == "false" then
                sawSurvivor = true
            end
        end
    end
    if sawSurvivor then return false end
    return nil
end

local function dmvsInfectionHasPatientZero(other)
    if other:GetAttribute("InfectionPatientZero") == true then return true end
    local character = other.Character
    if not character then return false end
    if character:GetAttribute("InfectionPatientZero") == true then return true end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid:GetAttribute("InfectionPatientZero") == true
end

local function dmvsInfectionAttribute(playerInstance)
    if not playerInstance then return nil end
    local character = playerInstance.Character
    local characterStatus = dmvsInfectionReadMarker(character)
    local playerStatus = dmvsInfectionReadMarker(playerInstance)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local humanoidStatus = dmvsInfectionReadMarker(humanoid)
    if characterStatus == true or playerStatus == true or humanoidStatus == true then return true end
    if characterStatus == false or playerStatus == false or humanoidStatus == false then return false end
    return nil
end

local function dmvsReadInfectionRoster(teams)
    local frame = playerGui:FindFirstChild("Main")
    frame = frame and frame:FindFirstChild("MainGameFrame")
    if not frame then return end
    local playerFrame = frame:FindFirstChild("PlayersFrame")
    local regularFrame = frame:FindFirstChild("IngameScore")
    local playerNames = {}
    local displayCandidates = {}
    local ambiguousDisplays = {}
    for _, other in ipairs(Players:GetPlayers()) do
        playerNames[other.Name:lower()] = other
        playerNames[tostring(other.UserId)] = other
        local displayKey = other.DisplayName:lower()
        if displayCandidates[displayKey] then ambiguousDisplays[displayKey] = true end
        displayCandidates[displayKey] = other
    end
    for displayKey, other in pairs(displayCandidates) do
        if not ambiguousDisplays[displayKey] and not playerNames[displayKey] then
            playerNames[displayKey] = other
        end
    end
    local function collect(group, team)
        if not group then return end
        for _, entry in ipairs(group:GetChildren()) do
            if entry:IsA("GuiObject") then
                local other = playerNames[entry.Name:lower():gsub("^@", "")]
                if not other then
                    local entryUserId = entry:GetAttribute("UserId")
                    if entryUserId then other = playerNames[tostring(entryUserId)] end
                end
                if not other then
                    for _, sub in ipairs(entry:GetDescendants()) do
                        if sub:IsA("TextLabel") and (sub.Name == "PlayerName" or sub.Name == "TextLabel") then
                            other = playerNames[sub.Text:lower():gsub("^@", "")]
                            if other then break end
                        end
                    end
                end
                if other then teams[other] = team end
            end
        end
    end
    if regularFrame then
        collect(regularFrame:FindFirstChild("TeamRed"), "Red")
        collect(regularFrame:FindFirstChild("TeamBlue"), "Blue")
    end
    if playerFrame then
        collect(playerFrame:FindFirstChild("TeamRedFrame"), "Red")
        collect(playerFrame:FindFirstChild("TeamBlueFrame"), "Blue")
    end
end

local function dmvsClearInfectionRound(ended)
    local state = dmvsInfectionState
    table.clear(state.Converted); table.clear(state.ConvertedAt)
    table.clear(state.Pending); table.clear(state.LateJoiners)
    table.clear(state.Inferred); table.clear(state.Targets)
    table.clear(state.RoleTeams)
    state.Active = false
    state.RoundEnded = ended == true
    state.LastRefresh = -math.huge
    if dmvsInvalidateRedirectSelection then dmvsInvalidateRedirectSelection() end
endlocal function dmvsRefreshInfectionState(force)
    local state = dmvsInfectionState
    local now = os.clock()
    local localGame = player:GetAttribute("Game")
    local matchId = player:GetAttribute("MatchId")
    if state.HasMatchContext and (localGame ~= state.LastLocalGame or matchId ~= state.LastMatchId) then
        dmvsClearInfectionRound(false)
    end
    state.HasMatchContext = true
    state.LastLocalGame = localGame
    state.LastMatchId = matchId
    if not force and now - state.LastRefresh < state.RefreshInterval then return state end
    state.LastRefresh = now
    local regularRoster = dmvsRefreshScoreboardTeams(false)
    local foundPatientZero = false
    local ownCharacter = player.Character
    local myRoot = ownCharacter and ownCharacter:FindFirstChild("HumanoidRootPart")
    local allPlayers = Players:GetPlayers()
    for _, other in ipairs(allPlayers) do
        if dmvsInfectionHasPatientZero(other) then
            local compatible = other == player
            if not compatible then
                compatible = true
                local otherGame = other:GetAttribute("Game")
                local otherMatch = other:GetAttribute("MatchId")
                if localGame ~= nil and localGame ~= "" and otherGame ~= nil and otherGame ~= "" and localGame ~= otherGame then compatible = false end
                if (localGame == nil or localGame == "") and otherGame ~= nil and otherGame ~= "" then compatible = false end
                if matchId ~= nil and matchId ~= "" and otherMatch ~= nil and otherMatch ~= "" and matchId ~= otherMatch then compatible = false end
                local theirCharacter = other.Character
                local theirRoot = theirCharacter and theirCharacter:FindFirstChild("HumanoidRootPart")
                if myRoot and theirRoot and (myRoot.Position - theirRoot.Position).Magnitude > 1200 then compatible = false end
            end
            if compatible then foundPatientZero = true; break end
        end
    end
    local modeAttribute
    for _, name in ipairs(dmvsInfectionModeAttributes) do
        local value = player:GetAttribute(name)
        if typeof(value) == "string" and value ~= "" then modeAttribute = value:lower(); break end
    end
    if not modeAttribute then
        for _, name in ipairs(dmvsInfectionModeAttributes) do
            local value = workspace:GetAttribute(name)
            if typeof(value) == "string" and value ~= "" then modeAttribute = value:lower(); break end
        end
    end
    local active = not state.RoundEnded and (modeAttribute == "infection" or
        (not modeAttribute and (foundPatientZero or (state.Active and not dmvsTeamResolverState.InGame))))
    if not active then
        if modeAttribute and modeAttribute ~= "infection" and next(state.LateJoiners) ~= nil then table.clear(state.LateJoiners) end
        if state.Active or next(state.Targets) ~= nil then
            if modeAttribute and modeAttribute ~= "infection" then
                dmvsClearInfectionRound(false)
            else
                state.Active = false
                table.clear(state.Targets); table.clear(state.Inferred); table.clear(state.RoleTeams)
                if dmvsInvalidateRedirectSelection then dmvsInvalidateRedirectSelection() end
            end
        end
        return state
    end
    state.Active = true
    local teams = {}
    dmvsReadInfectionRoster(teams)
    state.RoleTeams = teams
    local infectedTeam, ambiguousTeam = nil, false
    local markers = {}
    for _, other in ipairs(allPlayers) do
        local marker = dmvsInfectionAttribute(other)
        markers[other] = marker
        if marker == true or state.Converted[other] == true then
            local team = teams[other]
            if team then
                if infectedTeam and infectedTeam ~= team then ambiguousTeam = true end
                infectedTeam = team
            end
        end
    end
    local inferred = {}
    if infectedTeam and not ambiguousTeam then
        for other, team in pairs(teams) do
            if team == infectedTeam and markers[other] ~= false then inferred[other] = true end
        end
    end
    state.Inferred = inferred
    local function createTargets()
        local targets = {}
        for _, other in ipairs(allPlayers) do
            if markers[other] == true or state.Converted[other] == true
                or (markers[other] ~= false and inferred[other] == true) then
                targets[other] = true
            end
        end
        return targets
    end
    local targets = createTargets()
    local infectedRoots = {}
    for infectedPlayer in pairs(targets) do
        local infectedCharacter = infectedPlayer.Character
        local infectedRoot = infectedCharacter and infectedCharacter:FindFirstChild("HumanoidRootPart")
        if infectedRoot and infectedRoot:IsA("BasePart") then infectedRoots[#infectedRoots + 1] = infectedRoot end
    end
    for _, other in ipairs(allPlayers) do
        if other ~= player and state.LateJoiners[other] and markers[other] == nil and not targets[other] and other.Character then
            local rosterTeam = teams[other] or regularRoster[other.Name:lower()]
            local otherGame = other:GetAttribute("Game")
            local otherMatch = other:GetAttribute("MatchId")
            local sameGame = localGame ~= nil and localGame ~= "" and otherGame == localGame
            local sameMatch = matchId ~= nil and matchId ~= "" and otherMatch == matchId
            local differentGame = localGame ~= nil and localGame ~= "" and otherGame ~= nil and otherGame ~= "" and otherGame ~= localGame
            local differentMatch = matchId ~= nil and matchId ~= "" and otherMatch ~= nil and otherMatch ~= "" and otherMatch ~= matchId
            if not differentGame and not differentMatch then
                local sharesInfectedTeam = false
                for infectedPlayer in pairs(targets) do
                    local infectedRobloxTeam = infectedPlayer.Team
                    if infectedRobloxTeam and other.Team == infectedRobloxTeam
                        and (markers[infectedPlayer] == true or state.Converted[infectedPlayer] == true or inferred[infectedPlayer] == true) then
                        sharesInfectedTeam = true; break
                    end
                end
                local nearInfected = false
                if not rosterTeam and not sameGame and not sameMatch and not sharesInfectedTeam then
                    local characterRoot = other.Character:FindFirstChild("HumanoidRootPart")
                    if characterRoot and characterRoot:IsA("BasePart") then
                        local position = characterRoot.Position
                        for _, infectedRoot in ipairs(infectedRoots) do
                            if (infectedRoot.Position - position).Magnitude <= 300 then nearInfected = true; break end
                        end
                    end
                end
                local participates = rosterTeam ~= nil or sameGame or sameMatch or sharesInfectedTeam or nearInfected
                if participates and (not infectedTeam or ambiguousTeam or not rosterTeam or rosterTeam == infectedTeam) then
                    targets[other] = true
                end
            end
        end
    end
    local pending = state.Pending
    local changed = true
    while changed do
        changed = false
        for index = #pending, 1, -1 do
            local entry = pending[index]
            if now - entry.Time > 10 or entry.Killer.Parent ~= Players or entry.Victim.Parent ~= Players then
                table.remove(pending, index)
            elseif targets[entry.Killer] and not targets[entry.Victim]
                and (not state.ConvertedAt[entry.Killer] or state.ConvertedAt[entry.Killer] <= entry.Time) then
                state.Converted[entry.Victim] = true
                state.ConvertedAt[entry.Victim] = entry.Time
                targets[entry.Victim] = true
                table.remove(pending, index); changed = true
            elseif targets[entry.Killer] then
                table.remove(pending, index)
            end
        end
    end
    local previous = state.Targets
    local targetChanged = false
    for other in pairs(previous) do if not targets[other] then targetChanged = true; break end end
    if not targetChanged then
        for other in pairs(targets) do if not previous[other] then targetChanged = true; break end end
    end
    state.Targets = targets
    if targetChanged and dmvsInvalidateRedirectSelection then dmvsInvalidateRedirectSelection() end
    return state
end

dmvsIsInfectionMode = function() return dmvsRefreshInfectionState(false).Active end

local function dmvsIsInfectedTarget(targetPlayer)
    if not targetPlayer then return false end
    local state = dmvsRefreshInfectionState(false)
    return state.Active and state.Targets[targetPlayer] == true
end

local function dmvsInfectionMatchAllowed(targetPlayer, allowMissingCharacter)
    if not targetPlayer or targetPlayer == player or not targetPlayer.Parent
        or (not allowMissingCharacter and not targetPlayer.Character) then return false end
    local myGame = player:GetAttribute("Game")
    local targetGame = targetPlayer:GetAttribute("Game")
    if myGame ~= nil and myGame ~= "" and targetGame ~= nil and targetGame ~= "" and myGame ~= targetGame then return false end
    if (myGame == nil or myGame == "") and targetGame ~= nil and targetGame ~= "" then return false end
    local myMatch = player:GetAttribute("MatchId")
    local targetMatch = targetPlayer:GetAttribute("MatchId")
    if myMatch ~= nil and myMatch ~= "" and targetMatch ~= nil and targetMatch ~= "" and myMatch ~= targetMatch then return false end
    local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local otherRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if myRoot and otherRoot and (myRoot.Position - otherRoot.Position).Magnitude > 1200 then return false end
    return true
end

local function dmvsInfectionMarkDirty() dmvsInfectionState.LastRefresh = -math.huge end

local function dmvsInfectionOnKill(killer, victim)
    if typeof(killer) ~= "Instance" or not killer:IsA("Player")
        or typeof(victim) ~= "Instance" or not victim:IsA("Player")
        or killer == victim or not dmvsIsInfectionMode()
        or (killer ~= player and not dmvsInfectionMatchAllowed(killer, true))
        or (victim ~= player and not dmvsInfectionMatchAllowed(victim, true)) then return end
    local state = dmvsRefreshInfectionState(false)
    if state.Targets[victim] then return end
    if state.Targets[killer] then
        state.Converted[victim] = true
        state.ConvertedAt[victim] = os.clock()
        state.LastRefresh = -math.huge
        dmvsRefreshInfectionState(true)
    else
        if #state.Pending >= 96 then table.remove(state.Pending, 1) end
        state.Pending[#state.Pending + 1] = {Killer = killer, Victim = victim, Time = os.clock()}
        state.LastRefresh = -math.huge
    end
end

local dmvsIsInSameGame
dmvsIsInSameGame = function(targetPlayer)
    if not targetPlayer or targetPlayer == player or not targetPlayer.Parent then return false end
    if dmvsIsInfectionMode() then return dmvsInfectionMatchAllowed(targetPlayer) and dmvsIsInfectedTarget(targetPlayer) end
    local roster = dmvsRefreshScoreboardTeams(false)
    if not dmvsTeamResolverState.InGame or not roster[string.lower(targetPlayer.Name)] then return false end
    local myGame = player:GetAttribute("Game")
    local targetGame = targetPlayer:GetAttribute("Game")
    if myGame ~= nil and myGame ~= "" and targetGame ~= nil and targetGame ~= "" then
        if myGame ~= targetGame then return false end
    elseif (myGame == nil or myGame == "") and targetGame ~= nil and targetGame ~= "" then return false end
    local myMatch = player:GetAttribute("MatchId")
    local targetMatch = targetPlayer:GetAttribute("MatchId")
    if myMatch ~= nil and myMatch ~= "" and targetMatch ~= nil and targetMatch ~= "" and myMatch ~= targetMatch then return false end
    return true
end

local function dmvsResolvePlayerTeam(targetPlayer)
    if not targetPlayer then return nil end
    local snapshot = dmvsRefreshScoreboardTeams(false)
    local byName = snapshot[string.lower(targetPlayer.Name)]
    if not byName and targetPlayer.DisplayName then byName = snapshot[string.lower(targetPlayer.DisplayName)] end
    if byName then return byName end
    local attr = targetPlayer:GetAttribute("Team") or targetPlayer:GetAttribute("team")
    if attr ~= nil and tostring(attr) ~= "" then return tostring(attr) end
    if targetPlayer.Team then return targetPlayer.Team.Name end
    local teamColor = targetPlayer.TeamColor
    if teamColor and teamColor.Name ~= "White" and teamColor.Name ~= "Medium stone grey" then return "Color:" .. teamColor.Name end
    return nil
end

local function dmvsPlayersAreEnemies(firstPlayer, secondPlayer)
    if not firstPlayer or not secondPlayer or firstPlayer == secondPlayer then return false end
    if dmvsIsInfectionMode() then return dmvsIsInfectedTarget(secondPlayer) end
    local firstTeam = dmvsResolvePlayerTeam(firstPlayer)
    local secondTeam = dmvsResolvePlayerTeam(secondPlayer)
    if firstTeam ~= nil and secondTeam ~= nil then return firstTeam ~= secondTeam end
    return true
end

local function updateMyTeam()
    dmvsInvalidateScoreboard()
    if dmvsInvalidateRedirectSelection then dmvsInvalidateRedirectSelection() end
end
local function updateEnemy()
    dmvsInvalidateScoreboard(); dmvsInfectionMarkDirty()
    if dmvsInvalidateRedirectSelection then dmvsInvalidateRedirectSelection() end
end

local dmvsTeamPlayerConnections = {}
local dmvsInfectionCharacterConnections = {}

local function disconnectPlayerTeamEvents(p)
    dmvsDisconnectConnectionList(dmvsInfectionCharacterConnections[p])
    dmvsInfectionCharacterConnections[p] = nil
    local connections = dmvsTeamPlayerConnections[p]
    if connections then
        dmvsDisconnectConnectionList(connections)
        dmvsTeamPlayerConnections[p] = nil
    end
end

local function dmvsWatchInfectionCharacter(p, character)
    dmvsDisconnectConnectionList(dmvsInfectionCharacterConnections[p])
    dmvsInfectionCharacterConnections[p] = nil
    if not character then return end
    local connections = {}
    dmvsInfectionCharacterConnections[p] = connections
    local function changed(name)
        if name == "InfectionPatientZero" or name == "InfectionInfected" or name == "IsInfected"
            or name == "Infected" or name == "IsZombie" or name == "Zombie" then
            dmvsInfectionMarkDirty(); updateEnemy()
        end
    end
    connections[#connections + 1] = character.AttributeChanged:Connect(changed)
    local function bindHumanoid(humanoid)
        if humanoid and humanoid:IsA("Humanoid") then
            connections[#connections + 1] = humanoid.AttributeChanged:Connect(changed)
        end
    end
    bindHumanoid(character:FindFirstChildOfClass("Humanoid"))
    connections[#connections + 1] = character.ChildAdded:Connect(function(child)
        if child:IsA("Humanoid") then bindHumanoid(child); dmvsInfectionMarkDirty() end
    end)
end

local function setupPlayerEvents(p)
    if not p or p == player or not p.Parent then return end
    disconnectPlayerTeamEvents(p)
    dmvsTeamPlayerConnections[p] = {
        p:GetPropertyChangedSignal("Team"):Connect(updateEnemy),
        p:GetPropertyChangedSignal("TeamColor"):Connect(updateEnemy),
        p:GetAttributeChangedSignal("Team"):Connect(updateEnemy),
        p:GetAttributeChangedSignal("team"):Connect(updateEnemy),
        p:GetAttributeChangedSignal("Game"):Connect(updateEnemy),
        p:GetAttributeChangedSignal("MatchId"):Connect(updateEnemy),
        p.AttributeChanged:Connect(function(name)
            if name == "InfectionPatientZero" or name == "InfectionInfected" or name == "IsInfected"
                or name == "Infected" or name == "IsZombie" or name == "Zombie" then
                dmvsInfectionMarkDirty(); updateEnemy()
            end
        end),
        p.CharacterAdded:Connect(function(character)
            dmvsWatchInfectionCharacter(p, character); dmvsInfectionMarkDirty(); updateEnemy()
        end),
        p.CharacterRemoving:Connect(function(character)
            dmvsWatchInfectionCharacter(p, nil); dmvsInfectionMarkDirty()
            if dmvsClearTargetParts then dmvsClearTargetParts(character) end
        end)
    }
    dmvsWatchInfectionCharacter(p, p.Character)
    updateEnemy()
endlocal nexvyrTargetConnections = {}
local nexvyrTargetMonitorActive = false
local nexvyrTargetMonitorSession = 0
local function nexvyrMonitorConnection(connection)
    nexvyrTargetConnections[#nexvyrTargetConnections + 1] = connection
    return connection
end
local function nexvyrStartTargetMonitor()
    if nexvyrTargetMonitorActive then return end
    nexvyrTargetMonitorActive = true
    nexvyrTargetMonitorSession += 1
    local session = nexvyrTargetMonitorSession
    local function localChanged() updateMyTeam(); dmvsInfectionMarkDirty() end
    for _, name in ipairs({"Team", "TeamColor"}) do
        nexvyrMonitorConnection(player:GetPropertyChangedSignal(name):Connect(localChanged))
    end
    for _, name in ipairs({"Team", "team", "Game", "MatchId", "GameMode", "MatchMode", "Mode"}) do
        nexvyrMonitorConnection(player:GetAttributeChangedSignal(name):Connect(localChanged))
    end
    nexvyrMonitorConnection(player.AttributeChanged:Connect(function(name)
        if name == "InfectionPatientZero" or name == "InfectionInfected" or name == "IsInfected"
            or name == "Infected" or name == "IsZombie" or name == "Zombie" then dmvsInfectionMarkDirty() end
    end))
    nexvyrMonitorConnection(player.CharacterAdded:Connect(dmvsInfectionMarkDirty))
    nexvyrMonitorConnection(playerGui.DescendantAdded:Connect(function(instance)
        if instance.Name == "IngameScore" or instance.Name == "TeamRed" or instance.Name == "TeamBlue" then
            dmvsInvalidateScoreboard(); dmvsInfectionMarkDirty()
        end
    end))
    nexvyrMonitorConnection(playerGui.DescendantRemoving:Connect(function(instance)
        if instance == dmvsTeamResolverState.Scoreboard or instance.Name == "IngameScore"
            or instance.Name == "TeamRed" or instance.Name == "TeamBlue" then
            dmvsInvalidateScoreboard(); dmvsInfectionMarkDirty()
        end
    end))
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then setupPlayerEvents(other) end
    end
    nexvyrMonitorConnection(Players.PlayerAdded:Connect(function(other)
        dmvsInfectionState.LateJoiners[other] = true
        setupPlayerEvents(other)
        dmvsInfectionMarkDirty()
    end))
    nexvyrMonitorConnection(Players.PlayerRemoving:Connect(function(other)
        disconnectPlayerTeamEvents(other)
        for i = #dmvsInfectionState.Pending, 1, -1 do
            local entry = dmvsInfectionState.Pending[i]
            if entry.Killer == other or entry.Victim == other then table.remove(dmvsInfectionState.Pending, i) end
        end
        for _, bucket in ipairs({"Converted", "ConvertedAt", "LateJoiners", "Inferred", "Targets", "RoleTeams"}) do
            dmvsInfectionState[bucket][other] = nil
        end
        updateEnemy()
    end))
    dmvsInvalidateScoreboard()
    dmvsInfectionMarkDirty()
    task.spawn(function()
        local registered = {}
        local listeners = {
            ["RE/Combat/Killed"] = dmvsInfectionOnKill,
            ["RE/Match/PlayerRespawned"] = dmvsInfectionMarkDirty,
            ["RE/Match/StartRoundGui"] = function() dmvsClearInfectionRound(false) end,
            ["RE/Match/MatchResults"] = function()
                if dmvsInfectionState.Active then dmvsClearInfectionRound(true) end
            end
        }
        while nexvyrTargetMonitorActive and session == nexvyrTargetMonitorSession do
            local packages = ReplicatedStorage:FindFirstChild("Packages")
            local networking = packages and packages:FindFirstChild("Networking")
            local finished = true
            for name, callback in pairs(listeners) do
                if not registered[name] then
                    local remote = networking and networking:FindFirstChild(name)
                    if remote and remote:IsA("RemoteEvent") then
                        nexvyrMonitorConnection(remote.OnClientEvent:Connect(callback))
                        registered[name] = true
                    else
                        finished = false
                    end
                end
            end
            if finished then break end
            task.wait(2)
        end
    end)
end
local function nexvyrStopTargetMonitor()
    if not nexvyrTargetMonitorActive then return end
    nexvyrTargetMonitorActive = false
    nexvyrTargetMonitorSession += 1
    dmvsDisconnectConnectionList(nexvyrTargetConnections)
    for other in pairs(dmvsTeamPlayerConnections) do disconnectPlayerTeamEvents(other) end
    dmvsDisconnectConnectionList(dmvsTeamResolverState.WatchConnections)
    dmvsTeamResolverState.Scoreboard = nil
    dmvsTeamResolverState.Snapshot = {}
    dmvsTeamResolverState.InGame = false
    dmvsTeamResolverState.Dirty = true
    dmvsClearInfectionRound(false)
end
startTargetMonitor = nexvyrStartTargetMonitor
stopTargetMonitor = nexvyrStopTargetMonitor

isEnemy = function(targetPlayer)
    if not dmvsIsInSameGame(targetPlayer) or not targetPlayer.Character then return false end
    if not dmvsIsTargetAlive(targetPlayer) then return false end
    return dmvsPlayersAreEnemies(player, targetPlayer)
end
local SAFE_ZONES = {
    {Center = Vector3.new(-320.50, 280.82, 16.00), Radius = 500},
    {Center = Vector3.new(1564.14, -155.45, 40.04), Radius = 300}
}
estaEnLobby = function()
    local character = player.Character
    if not character then return true end
    if character:FindFirstChildOfClass("ForceField") then return true end
    if player.Team then
        local name = player.Team.Name:lower()
        if name:find("lobby") or name:find("spectat") or name:find("espectador")
            or name:find("menu") or name:find("dead") then return true end
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root then
        for _, zone in ipairs(SAFE_ZONES) do
            if (root.Position - zone.Center).Magnitude <= zone.Radius then return true end
        end
    end
    return false
end
IsInMatchStrict = function()
    if estaEnLobby() then return false end
    dmvsRefreshScoreboardTeams(false)
    return dmvsTeamResolverState.InGame or dmvsIsInfectionMode()
end
esEnemigoValido = function(other)
    if not isEnemy(other) then return false end
    local character = other.Character
    return character ~= nil and not character:FindFirstChildOfClass("ForceField")
        and dmvsIsTargetAlive(other)
end
esCuchillo = function(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:FindFirstChild("Slash") or tool:FindFirstChild("SlashStart") then return true end
    local name = tool.Name:lower()
    return name:find("knife", 1, true) ~= nil or name:find("cuchillo", 1, true) ~= nil
        or name:find("dagger", 1, true) ~= nil
end
esPistola = function(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local beam = tool:FindFirstChild("showBeam")
    return beam ~= nil and beam:IsA("RemoteEvent")
end
obtenerPistola = function()
    local character = player.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if esPistola(tool) then return tool end
        end
    end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if esPistola(tool) then return tool end
        end
    end
    return nil
end
end

getgenv().RoxHubAutoEventFarm = false

task.spawn(function()
    local Networking, RemoteFarm
    while task.wait(0.05) do
        if not getgenv().RoxHubAutoEventFarm then continue end
        pcall(function()
            if not RemoteFarm then
                Networking = ReplicatedStorage:FindFirstChild("Packages")
                Networking = Networking and Networking:FindFirstChild("Networking")
                RemoteFarm = Networking and Networking:FindFirstChild("RE/Events/CollectEventSpawnable")
            end
            if RemoteFarm then RemoteFarm:FireServer() end
        end)
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local container = workspace:FindFirstChild("SpawnablesClient")
            if container then
                for _, obj in ipairs(container:GetChildren()) do
                    if not getgenv().RoxHubAutoEventFarm then break end
                    local touchPart = obj:FindFirstChild("Touch")
                    if touchPart then
                        pcall(function()
                            firetouchinterest(hrp, touchPart, 0)
                            firetouchinterest(hrp, touchPart, 1)
                        end)
                    end
                end
            end
        end
    end
end)

local KILLALL_MOVE_SPEED               = 39.9
local KILLALL_APPROACH_DISTANCE        = 2.5
local KILLALL_APPROACH_TOLERANCE       = 0.35
local KILLALL_SWING_INTERVAL           = 0.5
local KILLALL_SAFE_GROUND_THRESHOLD    = 3
local KILLALL_STICK_MAX_TIME           = 2.5
local KILLALL_STICK_MAX_DISTANCE       = 20
local KILLALL_VOID_PROTECTION          = 15
local KILLALL_HEALTH_STALL_TIME        = 1.5
local KILLALL_TARGET_GRACE_TIME        = 1.2
local KILLALL_PITCH_DEGREES            = 90
local KILLALL_HEIGHT_OFFSET            = 1.9
local KILLALL_HIDE_DEPTH               = 4
local KILLALL_HIDE_DURATION            = 0.5
local KILLALL_KNIFE_RANGE_Y            = 4.5
local KILLALL_PREDICTION_TIME          = 0.08
local KILLALL_JITTER_AMPLITUDE         = 0.8
local KILLALL_JITTER_SWITCH_MIN        = 0.05
local KILLALL_JITTER_SWITCH_MAX        = 0.12
local KILLALL_JITTER_LERP_SPEED        = 25
local KILLALL_UNDERGROUND_DEPTH        = 5
local KILLALL_UNDERGROUND_TOLERANCE    = 1.5
local KILLALL_TRIGGER_RADIUS           = 6.0
local KILLALL_VALIDATION_TOLERANCE     = 1.0
local KILLALL_VALIDATION_FRAMES        = 3

local RoxConnectionManager = {}
RoxConnectionManager.__index = RoxConnectionManager
function RoxConnectionManager.new() return setmetatable({ Items = {} }, RoxConnectionManager) end
function RoxConnectionManager:Add(task) self.Items[#self.Items + 1] = task; return task end
function RoxConnectionManager:Cleanup()
    for i = #self.Items, 1, -1 do
        local item = self.Items[i]
        self.Items[i] = nil
        local t = typeof(item)
        if t == "RBXScriptConnection" then pcall(function() item:Disconnect() end)
        elseif t == "Instance" then pcall(function() item:Destroy() end)
        elseif t == "function" then pcall(item) end
    end
end

local RoxKillAll = {}
RoxKillAll.__index = RoxKillAll

function RoxKillAll.new()
    return setmetatable({
        running = false, connections = RoxConnectionManager.new(),
        savedCollisions = {}, swingAccumulator = 0, safePosition = nil,
        sticking = false, stickingStartTime = 0, lastEnemyHealth = nil,
        lastHealthChangeTime = 0, lastTargetSeenTime = 0, currentTarget = nil,
        lockedTargetPlayer = nil, lastStickTarget = nil, lastStickTargetHum = nil,
        hiding = false, hidingUntil = 0, targetFloor = nil, targetFloorY = nil,
        lastFloorTarget = nil, inKnifeRangeNow = false, forceDescent = false,
        jitterSide = 1, jitterCurrent = 0, jitterNextSwitch = 0,
        lastSetCFrame = nil, validFrames = 0, killActivated = false,
    }, RoxKillAll)
end

function RoxKillAll:DisableCollisions()
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            if self.savedCollisions[part] == nil then self.savedCollisions[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end

function RoxKillAll:RestoreCollisions()
    for part, value in pairs(self.savedCollisions) do
        if part.Parent then pcall(function() part.CanCollide = value end) end
    end
    table.clear(self.savedCollisions)
end

function RoxKillAll:GetRoot(p)
    local char = p and p.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    return nil
end

function RoxKillAll:GetHumanoid(p)
    local char = p and p.Character
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end

function RoxKillAll:GetFloorY(targetRoot)
    local hum = targetRoot.Parent and targetRoot.Parent:FindFirstChildOfClass("Humanoid")
    local hip = hum and tonumber(hum.HipHeight) or 2
    return targetRoot.Position.Y - hip - targetRoot.Size.Y / 2
end

function RoxKillAll:GetPlatformFloorY(targetRoot)
    if not targetRoot then return nil end
    if self.lastFloorTarget == targetRoot and self.targetFloorY then return self.targetFloorY end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character, targetRoot.Parent }
    local origin = targetRoot.Position + Vector3.new(0, 3, 0)
    local result = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
    if result then
        self.targetFloorY = result.Position.Y
        self.lastFloorTarget = targetRoot
        return self.targetFloorY
    end
    self.targetFloorY = self:GetFloorY(targetRoot)
    self.lastFloorTarget = targetRoot
    return self.targetFloorY
end

function RoxKillAll:IsInKnifeRange(myRoot, targetRoot)
    if not myRoot or not targetRoot then return false end
    local delta = targetRoot.Position - myRoot.Position
    local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
    local vertical = math.abs(delta.Y)
    return horizontal <= (KILLALL_APPROACH_DISTANCE + KILLALL_APPROACH_TOLERANCE) and vertical <= KILLALL_KNIFE_RANGE_Y
end

function RoxKillAll:IsLockedTargetValid()
    local lp = self.lockedTargetPlayer
    if not lp or not lp.Parent or not esEnemigoValido(lp) then return false end
    local char = lp.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return false end
    return root
end

function RoxKillAll:GetClosestEnemy()
    local myRoot = self:GetRoot(player)
    if not myRoot then return nil end
    local lockedRoot = self:IsLockedTargetValid()
    if lockedRoot then return lockedRoot end
    self.lockedTargetPlayer = nil
    self.currentTarget = nil
    local best, bestDist, bestPlayer = nil, nil, nil
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and esEnemigoValido(other) then
            local hum = self:GetHumanoid(other)
            local root = self:GetRoot(other)
            if root and hum and hum.Health > 0 then
                local dist = (root.Position - myRoot.Position).Magnitude
                if not bestDist or dist < bestDist then best, bestDist, bestPlayer = root, dist, other end
            end
        end
    end
    if bestPlayer then self.lockedTargetPlayer = bestPlayer end
    return best
end

function RoxKillAll:IsInMatch() return IsInMatchStrict() end

function RoxKillAll:ResetState()
    self.sticking = false; self.stickingStartTime = 0
    self.lastEnemyHealth = nil; self.lastHealthChangeTime = 0
    self.targetFloor = nil; self.inKnifeRangeNow = false
    self.forceDescent = false; self.jitterSide = 1
    self.jitterCurrent = 0; self.jitterNextSwitch = 0
    self.lastSetCFrame = nil; self.validFrames = 0
    self.killActivated = false
    self:RestoreCollisions()
    local hum = self:GetHumanoid(player)
    if hum and hum.PlatformStand then pcall(function() hum.PlatformStand = false end) end
end

function RoxKillAll:ReturnToSafePosition(myRoot)
    if not self.safePosition or not myRoot then return end
    if myRoot.Position.Y < (self.safePosition.Y - KILLALL_SAFE_GROUND_THRESHOLD) then
        pcall(function()
            myRoot.CFrame = CFrame.new(self.safePosition)
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

function RoxKillAll:ForceReturnToSafe(myRoot)
    if not self.safePosition or not myRoot then return end
    pcall(function()
        myRoot.CFrame = CFrame.new(self.safePosition)
        myRoot.AssemblyLinearVelocity = Vector3.zero
        myRoot.AssemblyAngularVelocity = Vector3.zero
    end)
end

function RoxKillAll:IsFallingIntoVoid(myRoot)
    if not self.safePosition or not myRoot then return false end
    return myRoot.Position.Y < (self.safePosition.Y - KILLALL_VOID_PROTECTION)
end

function RoxKillAll:HideBelowMap()
    local myRoot = self:GetRoot(player)
    if not myRoot then return end
    local baseY = self.safePosition and self.safePosition.Y or myRoot.Position.Y
    local hideY = baseY - KILLALL_HIDE_DEPTH
    local x, z = myRoot.Position.X, myRoot.Position.Z
    pcall(function()
        myRoot.CFrame = CFrame.new(x, hideY, z)
        myRoot.AssemblyLinearVelocity = Vector3.zero
        myRoot.AssemblyAngularVelocity = Vector3.zero
    end)
    self.hiding = true
    self.hidingUntil = os.clock() + KILLALL_HIDE_DURATION
end

function RoxKillAll:IsKnife(tool)
    if not (tool and tool:IsA("Tool")) then return false end
    if tool:FindFirstChild("fire") or tool:FindFirstChild("showBeam") then return false end
    return tool:FindFirstChild("Slash") ~= nil or tool:FindFirstChild("SlashStart") ~= nil
end

function RoxKillAll:FindKnife()
    local char = player.Character
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if self:IsKnife(child) then return child, true end
        end
    end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if self:IsKnife(child) then return child, false end
        end
    end
    return nil, false
end

function RoxKillAll:SwingKnife(dt)
    self.swingAccumulator = self.swingAccumulator + dt
    if self.swingAccumulator < KILLALL_SWING_INTERVAL then return end
    self.swingAccumulator = 0
    local tool, equipped = self:FindKnife()
    if not tool then return end
    if not equipped then
        local hum = self:GetHumanoid(player)
        if not hum then return end
        pcall(function() hum:EquipTool(tool) end)
        if tool.Parent ~= player.Character then return end
    end
    pcall(function() tool:Activate() end)
end-- ═══════════════════════════════════════════════════════════════
--  UI PXZD HUB DUELS
-- ═══════════════════════════════════════════════════════════════
local IMAGE_ID = "rbxassetid://97787846637167"

local function LoadHub()
    local oldGui = PlayerGui:FindFirstChild("PxzdHubDuels")
    if oldGui then oldGui:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "PxzdHubDuels"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = PlayerGui

    local Theme = {
        Bg        = Color3.fromRGB(12, 8, 20),
        Panel     = Color3.fromRGB(18, 10, 30),
        Card      = Color3.fromRGB(25, 14, 42),
        Line      = Color3.fromRGB(70, 35, 110),
        Accent    = Color3.fromRGB(138, 43, 226),
        AccentDim = Color3.fromRGB(85, 25, 140),
        Text      = Color3.fromRGB(230, 220, 245),
        Dim       = Color3.fromRGB(140, 125, 165),
        Off       = Color3.fromRGB(30, 18, 50),
        Green     = Color3.fromRGB(0, 255, 128),
        Orange    = Color3.fromRGB(255, 140, 70),
        Red       = Color3.fromRGB(255, 50, 50),
        Link      = Color3.fromRGB(0, 230, 200),
    }
    local FONT_TITLE = Enum.Font.Garamond
    local FONT       = Enum.Font.GothamMedium
    local FONT_BOLD  = Enum.Font.GothamBold
    local DISCORD_URL = "https://discord.gg/mWBffStfJ"

    local function make(class, props, parent)
        local o = Instance.new(class)
        if class == "TextLabel" or class == "TextButton" or class == "TextBox" then o.AutoLocalize = false end
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(o, r) return make("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
    local function stroke(o, color, thickness, transparency)
        return make("UIStroke", {
            Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, o)
    end
    local function line(parent, props, mode, rotation)
        props.BorderSizePixel = 0
        local l = make("Frame", props, parent)
        local keys
        if mode == "center" then
            keys = {NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1)}
        else
            keys = {NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}
        end
        make("UIGradient", {Transparency = NumberSequence.new(keys), Rotation = rotation or 0}, l)
        return l
    end
    local function diamond(parent, x, y, size, color)
        return make("Frame", {
            Size = UDim2.new(0, size, 0, size), Position = UDim2.new(x[1], x[2], y[1], y[2]),
            BackgroundColor3 = color or Theme.Accent, BorderSizePixel = 0, Rotation = 45, ZIndex = 4,
        }, parent)
    end
    local function nextOrder(parent)
        local n = (parent:GetAttribute("_n") or 0) + 1
        parent:SetAttribute("_n", n)
        return n
    end

    local MainButton = make("ImageButton", {
        Name = "MainButton", Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0.5, -23, 0, 12),
        BackgroundColor3 = Theme.Bg, BorderSizePixel = 0, Image = IMAGE_ID,
        ScaleType = Enum.ScaleType.Fit, Active = true, Draggable = true,
    }, ScreenGui)
    corner(MainButton, 8)
    stroke(MainButton, Theme.AccentDim, 1, 0.1)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
    }, MainButton)

    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local baseScale = math.clamp(math.min((vp.X - 24) / 600, (vp.Y - 90) / 410), 0.5, 1)

    local MainFrame = make("Frame", {
        Name = "MainFrame", Size = UDim2.new(0, 600, 0, 410), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 18), BackgroundColor3 = Theme.Bg, BorderSizePixel = 0,
        Visible = false, Active = true, Draggable = true, ClipsDescendants = true,
    }, ScreenGui)
    corner(MainFrame, 6)
    stroke(MainFrame, Theme.AccentDim, 1, 0.35)
    local uiScale = make("UIScale", {Scale = baseScale}, MainFrame)

    local Backdrop = make("ImageLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Image = IMAGE_ID,
        ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.45,
        ImageColor3 = Color3.fromRGB(200, 170, 240), ZIndex = 0,
    }, MainFrame)
    corner(Backdrop, 6)

    local Header = make("Frame", {
        Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, ZIndex = 3,
    }, MainFrame)
    corner(Header, 6)

    -- Logo circular animado
    local LogoFrame = make("Frame", {
        Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(0, 16, 0.5, -19),
        BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, ZIndex = 4,
    }, Header)
    corner(LogoFrame, 999)
    local LogoStroke = stroke(LogoFrame, Theme.Accent, 2, 0)
    local LogoStroke2 = stroke(LogoFrame, Theme.Green, 1, 0.6)
    make("ImageLabel", {
        Size = UDim2.new(1, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2),
        BackgroundTransparency = 1, Image = IMAGE_ID, ScaleType = Enum.ScaleType.Crop, ZIndex = 5,
    }, LogoFrame)
    task.spawn(function()
        while LogoFrame.Parent do
            TweenService:Create(LogoStroke, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {Transparency = 0.85}):Play()
            TweenService:Create(LogoStroke2, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {Color = Theme.Red}):Play()
            task.wait(1.2)
            if not LogoFrame.Parent then break end
            TweenService:Create(LogoStroke, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {Transparency = 0}):Play()
            TweenService:Create(LogoStroke2, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {Color = Theme.Green}):Play()
            task.wait(1.2)
        end
    end)

    make("TextLabel", {
        Size = UDim2.new(1, -180, 0, 26), Position = UDim2.new(0, 62, 0, 6), BackgroundTransparency = 1,
        Text = "PXZD HUB DUELS", Font = FONT_TITLE, TextSize = 22, TextTruncate = Enum.TextTruncate.AtEnd,
        TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
    }, Header)
    make("TextLabel", {
        Size = UDim2.new(1, -180, 0, 14), Position = UDim2.new(0, 62, 0, 32), BackgroundTransparency = 1,
        Text = "SOURCE PXZD HUB · POWERED BY NEXY · TAKEN BY CHEMXHUB",
        Font = FONT, TextSize = 8, TextTruncate = Enum.TextTruncate.AtEnd,
        TextColor3 = Theme.AccentDim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
    }, Header)

    local MinimizeBtn = make("TextButton", {
        Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -96, 0, 15),
        BackgroundColor3 = Theme.Card, Text = "—", Font = FONT_BOLD,
        TextSize = 18, TextColor3 = Theme.Text, AutoButtonColor = false, ZIndex = 5,
    }, Header)
    corner(MinimizeBtn, 6)
    local minStroke = stroke(MinimizeBtn, Theme.Line, 1, 0.1)

    local CloseBtn = make("TextButton", {
        Size = UDim2.new(0, 28, 0, 28), Position = UDim2.new(1, -62, 0, 15),
        BackgroundColor3 = Theme.Card, Text = "✕", Font = FONT_BOLD,
        TextSize = 14, TextColor3 = Theme.Text, AutoButtonColor = false, ZIndex = 5,
    }, Header)
    corner(CloseBtn, 6)
    local closeStroke = stroke(CloseBtn, Theme.Line, 1, 0.1)

    local function hoverBtn(btn, strk, on)
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = on and Theme.Red or Theme.Card}):Play()
        TweenService:Create(strk, TweenInfo.new(0.15), {Color = on and Theme.Red or Theme.Line}):Play()
    end
    MinimizeBtn.MouseEnter:Connect(function() hoverBtn(MinimizeBtn, minStroke, true) end)
    MinimizeBtn.MouseLeave:Connect(function() hoverBtn(MinimizeBtn, minStroke, false) end)
    CloseBtn.MouseEnter:Connect(function() hoverBtn(CloseBtn, closeStroke, true) end)
    CloseBtn.MouseLeave:Connect(function() hoverBtn(CloseBtn, closeStroke, false) end)

    line(MainFrame, {
        Size = UDim2.new(1, -40, 0, 1), Position = UDim2.new(0, 20, 0, 58),
        BackgroundColor3 = Theme.Accent, ZIndex = 3,
    }, "center")
    diamond(MainFrame, {0.5, -3}, {0, 55}, 7)

    local SIDE_W, TOP_H, FOOT_H = 168, 62, 12
    local SEARCH_H = 38
    make("Frame", {
        Size = UDim2.new(0, SIDE_W, 1, -(TOP_H + FOOT_H)), Position = UDim2.new(0, 0, 0, TOP_H),
        BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 1,
    }, MainFrame)
    local Side = make("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, TOP_H + SEARCH_H), Size = UDim2.new(0, SIDE_W, 1, -(TOP_H + SEARCH_H + FOOT_H)),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 2,
    }, MainFrame)
    make("UIListLayout", {
        Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    }, Side)
    make("UIPadding", {PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8)}, Side)

    local SearchFrame = make("Frame", {
        Size = UDim2.new(0, SIDE_W - 24, 0, 28), Position = UDim2.new(0, 12, 0, TOP_H + 6),
        BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 3,
    }, MainFrame)
    corner(SearchFrame, 6)
    local searchStroke = stroke(SearchFrame, Theme.Line, 1, 0.1)
    make("TextLabel", {
        Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1,
        Text = "🔍", Font = FONT, TextSize = 11, TextColor3 = Theme.Dim,
    }, SearchFrame)
    local SearchBox = make("TextBox", {
        Size = UDim2.new(1, -32, 1, 0), Position = UDim2.new(0, 28, 0, 0), BackgroundTransparency = 1,
        Text = "", PlaceholderText = "Search", PlaceholderColor3 = Theme.Dim, TextColor3 = Theme.Text,
        Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 4,
    }, SearchFrame)
    SearchBox.Focused:Connect(function()
        TweenService:Create(searchStroke, TweenInfo.new(0.15), {Color = Theme.Accent}):Play()
    end)
    SearchBox.FocusLost:Connect(function()
        TweenService:Create(searchStroke, TweenInfo.new(0.15), {Color = Theme.Line}):Play()
    end)

    line(MainFrame, {
        Size = UDim2.new(0, 1, 1, -(TOP_H + FOOT_H + 16)), Position = UDim2.new(0, SIDE_W, 0, TOP_H + 8),
        BackgroundColor3 = Theme.Line, ZIndex = 2,
    }, "center", 90)

    local Content = make("Frame", {
        Position = UDim2.new(0, SIDE_W + 1, 0, TOP_H), Size = UDim2.new(1, -(SIDE_W + 1), 1, -(TOP_H + FOOT_H)),
        BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.85, BorderSizePixel = 0,
        ClipsDescendants = true, ZIndex = 1,
    }, MainFrame)local panels = {}
local searchIndex = {}
local function NewPanel(name)
    local p = make("ScrollingFrame", {
        Name = name, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.AccentDim, ScrollBarImageTransparency = 0.3,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, Content)
    make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, p)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14),
        PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 18),
    }, p)
    panels[name] = p
    return p
end

local function Section(parent, text)
    local f = make("Frame", {
        Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = nextOrder(parent),
    }, parent)
    make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = text, Font = FONT_TITLE,
        TextSize = 18, TextColor3 = Theme.Accent, TextXAlignment = Enum.TextXAlignment.Left,
    }, f)
    line(f, {
        Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = Theme.AccentDim,
    }, "left")
    return f
end

local function Row(parent, h)
    local r = make("Frame", {
        Size = UDim2.new(1, 0, 0, h or 42), BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, LayoutOrder = nextOrder(parent),
    }, parent)
    corner(r, 4)
    stroke(r, Theme.Line, 1, 0.3)
    return r
end

local function RowLabel(row, text, reserve, y)
    return make("TextLabel", {
        Size = UDim2.new(1, -(reserve or 84), 0, 20), Position = UDim2.new(0, 14, y and 0 or 0.5, y or -10),
        BackgroundTransparency = 1, Text = text, Font = FONT, TextSize = 12, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
end

local function Toggle(parent, title, default, onChange)
    local row = Row(parent, 42)
    searchIndex[#searchIndex + 1] = {title = title, tab = parent.Name}
    RowLabel(row, title)
    local pill = make("TextButton", {
        Size = UDim2.new(0, 42, 0, 22), Position = UDim2.new(1, -56, 0.5, -11),
        BackgroundColor3 = Theme.Off, Text = "", AutoButtonColor = false,
    }, row)
    corner(pill, 11)
    local pillStroke = stroke(pill, Theme.Line, 1, 0.1)
    local knob = make("Frame", {
        Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3 = Theme.Dim, BorderSizePixel = 0,
    }, pill)
    corner(knob, 8)
    local state = false
    local function render(animate)
        local info = TweenInfo.new(animate and 0.2 or 0, Enum.EasingStyle.Quad)
        TweenService:Create(pill, info, {BackgroundColor3 = state and Theme.AccentDim or Theme.Off}):Play()
        TweenService:Create(pillStroke, info, {Color = state and Theme.Accent or Theme.Line}):Play()
        TweenService:Create(knob, info, {
            Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
            BackgroundColor3 = state and Theme.Text or Theme.Dim,
        }):Play()
    end
    pill.MouseButton1Click:Connect(function()
        state = not state
        render(true)
        if onChange then onChange(state) end
    end)
    state = default and true or false
    render(false)
end

local function bindDrag(hit, bar, cb)
    local dragging = false
    local function update(input)
        local a = math.clamp((input.Position.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        cb(a)
    end
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function Slider(parent, title, minV, maxV, defaultV, callback)
    local row = Row(parent, 56)
    searchIndex[#searchIndex + 1] = {title = title, tab = parent.Name}
    RowLabel(row, title, 90, 8)
    local valueLabel = make("TextLabel", {
        Size = UDim2.new(0, 60, 0, 20), Position = UDim2.new(1, -74, 0, 8), BackgroundTransparency = 1,
        Text = tostring(defaultV), Font = FONT_BOLD, TextSize = 12, TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)
    local bar = make("Frame", {
        Size = UDim2.new(1, -28, 0, 4), Position = UDim2.new(0, 14, 0, 38),
        BackgroundColor3 = Theme.Off, BorderSizePixel = 0,
    }, row)
    corner(bar, 2)
    local fill = make("Frame", {
        Size = UDim2.new((defaultV - minV) / (maxV - minV), 0, 1, 0),
        BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
    }, bar)
    corner(fill, 2)
    local knob = make("Frame", {
        Size = UDim2.new(0, 12, 0, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        BackgroundColor3 = Theme.Text, BorderSizePixel = 0, ZIndex = 3,
    }, fill)
    corner(knob, 6)
    stroke(knob, Theme.Accent, 1, 0)
    local hit = make("TextButton", {
        Size = UDim2.new(1, 0, 1, -24), Position = UDim2.new(0, 0, 0, 24),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
    }, row)
    bindDrag(hit, bar, function(alpha)
        local val = minV + (maxV - minV) * alpha
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        valueLabel.Text = tostring(math.floor(val * 10 + 0.5) / 10)
        if callback then callback(val) end
    end)
end

local function Dropdown(parent, title, options, default, callback)
    local row = Row(parent, 42)
    searchIndex[#searchIndex + 1] = {title = title, tab = parent.Name}
    row.ZIndex = 5
    RowLabel(row, title, 170)
    local btn = make("TextButton", {
        Size = UDim2.new(0, 130, 0, 26), Position = UDim2.new(1, -144, 0.5, -13),
        BackgroundColor3 = Theme.Off, Text = tostring(default or options[1]), TextColor3 = Theme.Accent,
        TextSize = 11, Font = FONT_BOLD, AutoButtonColor = false, ZIndex = 6,
    }, row)
    corner(btn, 4)
    stroke(btn, Theme.Line, 1, 0.1)
    local list = make("Frame", {
        Size = UDim2.new(0, 150, 0, #options * 26 + 8), AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 1, 4), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
        Visible = false, ZIndex = 20,
    }, row)
    corner(list, 4)
    stroke(list, Theme.Accent, 1, 0.4)
    make("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)}, list)
    make("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, list)
    for i, opt in ipairs(options) do
        local o = make("TextButton", {
            Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "  " .. tostring(opt),
            TextColor3 = Theme.Dim, TextSize = 11, Font = FONT, TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false, LayoutOrder = i, ZIndex = 21,
        }, list)
        o.MouseEnter:Connect(function()
            o.TextColor3 = Theme.Accent; o.BackgroundTransparency = 0.9; o.BackgroundColor3 = Theme.Accent
        end)
        o.MouseLeave:Connect(function()
            o.TextColor3 = Theme.Dim; o.BackgroundTransparency = 1
        end)
        o.MouseButton1Click:Connect(function()
            list.Visible = false
            btn.Text = tostring(opt)
            if callback then callback(opt) end
        end)
    end
    btn.MouseButton1Click:Connect(function() list.Visible = not list.Visible end)
end

local function ColorPicker(parent, title, defaultColor, callback)
    local row = Row(parent, 98)
    searchIndex[#searchIndex + 1] = {title = title, tab = parent.Name}
    RowLabel(row, title, 70, 8)
    local R, G, B = defaultColor.R, defaultColor.G, defaultColor.B
    local preview = make("Frame", {
        Size = UDim2.new(0, 32, 0, 20), Position = UDim2.new(1, -46, 0, 8),
        BackgroundColor3 = defaultColor, BorderSizePixel = 0,
    }, row)
    corner(preview, 4)
    stroke(preview, Theme.Text, 1, 0.6)
    local function fire()
        local c = Color3.new(R, G, B)
        preview.BackgroundColor3 = c
        if callback then callback(c) end
    end
    local function channel(y, label, tint, initial, setter)
        make("TextLabel", {
            Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 14, 0, y), BackgroundTransparency = 1,
            Text = label, Font = FONT_BOLD, TextSize = 10, TextColor3 = Theme.Dim,
        }, row)
        local bar = make("Frame", {
            Size = UDim2.new(1, -62, 0, 4), Position = UDim2.new(0, 34, 0, y + 5),
            BackgroundColor3 = Theme.Off, BorderSizePixel = 0,
        }, row)
        corner(bar, 2)
        local fill = make("Frame", {Size = UDim2.new(initial, 0, 1, 0), BackgroundColor3 = tint, BorderSizePixel = 0}, bar)
        corner(fill, 2)
        local knob = make("Frame", {
            Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            BackgroundColor3 = Theme.Text, BorderSizePixel = 0, ZIndex = 3,
        }, fill)
        corner(knob, 5)
        local hit = make("TextButton", {
            Size = UDim2.new(1, -48, 0, 16), Position = UDim2.new(0, 30, 0, y - 1),
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
        }, row)
        bindDrag(hit, bar, function(alpha)
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            setter(alpha); fire()
        end)
    end
    channel(36, "R", Color3.fromRGB(190, 85, 85), R, function(a) R = a end)
    channel(54, "G", Color3.fromRGB(95, 170, 105), G, function(a) G = a end)
    channel(72, "B", Color3.fromRGB(95, 135, 205), B, function(a) B = a end)
end-- HOME (simplificado)
local Home = NewPanel("HOME")
Section(Home, "PERFIL")
local card = make("Frame", {
    Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.3,
    BorderSizePixel = 0, LayoutOrder = nextOrder(Home),
}, Home)
corner(card, 4); stroke(card, Theme.Line, 1, 0.2)
local avatar = make("Frame", {
    Size = UDim2.new(0, 72, 0, 72), Position = UDim2.new(0, 16, 0, 14),
    BackgroundColor3 = Theme.Bg, BorderSizePixel = 0,
}, card)
corner(avatar, 4); stroke(avatar, Theme.Accent, 1.5, 0.1)
make("ImageLabel", {
    Size = UDim2.new(1, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3), BackgroundTransparency = 1,
    Image = IMAGE_ID, ScaleType = Enum.ScaleType.Crop,
}, avatar)
corner(avatar:FindFirstChildOfClass("ImageLabel"), 3)
make("TextLabel", {
    Size = UDim2.new(1, -110, 0, 22), Position = UDim2.new(0, 100, 0, 14),
    BackgroundTransparency = 1, Text = Player.DisplayName .. "  @" .. Player.Name,
    Font = FONT_TITLE, TextSize = 18, TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, card)
make("TextLabel", {
    Size = UDim2.new(1, -110, 0, 16), Position = UDim2.new(0, 100, 0, 40),
    BackgroundTransparency = 1, Text = "ID: " .. tostring(Player.UserId),
    Font = FONT, TextSize = 12, TextColor3 = Theme.Dim,
    TextXAlignment = Enum.TextXAlignment.Left,
}, card)
make("TextLabel", {
    Size = UDim2.new(1, -110, 0, 16), Position = UDim2.new(0, 100, 0, 60),
    BackgroundTransparency = 1, Text = "PXZD HUB DUELS · ONLINE",
    Font = FONT_BOLD, TextSize = 11, TextColor3 = Theme.Green,
    TextXAlignment = Enum.TextXAlignment.Left,
}, card)

Section(Home, "DISCORD")
local discordRow = Row(Home, 50)
make("TextLabel", {
    Size = UDim2.new(1, -140, 1, 0), Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1, Text = DISCORD_URL, Font = FONT, TextSize = 11,
    TextColor3 = Theme.Link, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, discordRow)
local copyBtn = make("TextButton", {
    Size = UDim2.new(0, 100, 0, 28), Position = UDim2.new(1, -114, 0.5, -14),
    BackgroundColor3 = Theme.Off, Text = "COPIAR", Font = FONT_BOLD, TextSize = 11,
    TextColor3 = Theme.Accent, AutoButtonColor = false,
}, discordRow)
corner(copyBtn, 4); stroke(copyBtn, Theme.AccentDim, 1, 0.1)
copyBtn.MouseButton1Click:Connect(function()
    pcall(function() setclipboard(DISCORD_URL) end)
    copyBtn.Text = "COPIADO!"
    task.wait(1.5)
    copyBtn.Text = "COPIAR"
end)

-- VARIABLES DE ESTADO
local autoShootEnabled, autoShootAgresivoEnabled = false, false
local autoShootTargetPart = "Cabeza"
local silentAimManualEnabled, silentAimFovEnabled = false, false
local silentAimTargetPart = "Cabeza"
local fovVisiblePreference = false
local fovRadius = 120
local equipGunEnabled = false
local espEnabled = false
local espColor = Color3.fromRGB(138, 43, 226)
local espGlow = true
getgenv().RoxHubTargetPart = nil

local function refreshMonitor()
    if autoShootEnabled or autoShootAgresivoEnabled or silentAimManualEnabled
        or silentAimFovEnabled or equipGunEnabled or espEnabled then
        startTargetMonitor()
    else
        stopTargetMonitor()
    end
end

-- AIMBOT
local Aim = NewPanel("AIMBOT")
Section(Aim, "AUTO SHOOT")
Toggle(Aim, "AUTO SHOOT NORMAL", false, function(v) autoShootEnabled = v; refreshMonitor() end)
Toggle(Aim, "AUTO SHOOT AGRESIVO", false, function(v) autoShootAgresivoEnabled = v; refreshMonitor() end)
local partMap = {["CABEZA"] = "Cabeza", ["TORSO"] = "Torso", ["CUERPO COMPLETO"] = "Cuerpo"}
Dropdown(Aim, "PARTE DEL CUERPO", {"CABEZA", "TORSO", "CUERPO COMPLETO"}, "CABEZA", function(v)
    autoShootTargetPart = partMap[v] or "Cabeza"
    silentAimTargetPart = autoShootTargetPart
end)

local equipWorkerRunning = false
local function startEquipWorker()
    if equipWorkerRunning or not equipGunEnabled then return end
    equipWorkerRunning = true
    task.spawn(function()
        while equipGunEnabled do
            task.wait(0.5)
            if not equipGunEnabled then break end
            if not IsInMatchStrict() then continue end
            local char = Player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not char or not hum or hum.Health <= 0 then continue end
            local pistola = obtenerPistola()
            if not pistola then continue end
            if pistola.Parent ~= char then pcall(function() hum:EquipTool(pistola) end) end
            task.wait(2)
            char = Player.Character
            hum = char and char:FindFirstChildOfClass("Humanoid")
            if char and hum then pcall(function() hum:UnequipTools() end) end
        end
        equipWorkerRunning = false
    end)
end
Toggle(Aim, "EQUIPAR ARMA AUTO", false, function(v)
    equipGunEnabled = v; refreshMonitor()
    if v then startEquipWorker() end
end)

Section(Aim, "SILENT AIM")
Toggle(Aim, "SILENT AIM", false, function(v) silentAimManualEnabled = v; refreshMonitor() end)
Toggle(Aim, "SILENT AIM (FOV)", false, function(v) silentAimFovEnabled = v; refreshMonitor() end)
Toggle(Aim, "MOSTRAR FOV", false, function(v) fovVisiblePreference = v end)
Slider(Aim, "TAMAÑO FOV", 10, 200, 120, function(v) fovRadius = v end)

-- VISUALS
local Vis = NewPanel("VISUALS")
local espFolder = Instance.new("Folder")
espFolder.Name = "PxzdHubESP"
espFolder.Parent = ScreenGui
Section(Vis, "ESP")
Toggle(Vis, "ESP HIGHLIGHT", false, function(v) espEnabled = v; refreshMonitor() end)
ColorPicker(Vis, "COLOR ESP", Color3.fromRGB(138, 43, 226), function(c) espColor = c end)

local activeESPs = {}
task.spawn(function()
    while task.wait(0.25) do
        if espEnabled and IsInMatchStrict() then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= Player and isEnemy(p) and p.Character then
                    local hl = activeESPs[p]
                    if not hl or hl.Adornee ~= p.Character then
                        if hl then hl:Destroy() end
                        hl = Instance.new("Highlight")
                        hl.FillTransparency = 0.5
                        hl.OutlineTransparency = 0
                        hl.OutlineColor = espColor
                        hl.FillColor = espColor
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Adornee = p.Character
                        hl.Parent = espFolder
                        activeESPs[p] = hl
                    end
                    hl.Enabled = espGlow
                elseif activeESPs[p] then
                    activeESPs[p]:Destroy()
                    activeESPs[p] = nil
                end
            end
        else
            for p, hl in pairs(activeESPs) do hl:Destroy(); activeESPs[p] = nil end
        end
    end
end)

-- MOVEMENT
local Move = NewPanel("MOVEMENT")
local PlatformActive = false
local platformSpawned = false
local activePlatforms = {}
local function StartPlatforms()
    if platformSpawned then return end
    platformSpawned = true
    task.spawn(function()
        while PlatformActive do
            task.wait(0.05)
            local char = Player.Character
            if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
                local hum = char.Humanoid
                if hum.MoveDirection.Magnitude > 0 or char.HumanoidRootPart.AssemblyLinearVelocity.Y ~= 0 then
                    local platform = Instance.new("Part")
                    platform.Size = Vector3.new(6, 0.6, 6)
                    platform.Anchored = true; platform.CanCollide = true
                    platform.Color = Color3.fromRGB(138, 43, 226)
                    platform.Material = Enum.Material.Neon
                    platform.CFrame = char.HumanoidRootPart.CFrame * CFrame.new(0, -3.3, 0)
                    platform.Parent = workspace
                    table.insert(activePlatforms, platform)
                    if #activePlatforms > 3 then
                        local oldPlatform = table.remove(activePlatforms, 1)
                        if oldPlatform then oldPlatform:Destroy() end
                    end
                end
            end
        end
    end)
end
local function StopPlatforms()
    PlatformActive = false; platformSpawned = false
    for _, plat in ipairs(activePlatforms) do if plat then plat:Destroy() end end
    activePlatforms = {}
end
Section(Move, "MOVIMIENTO")
Toggle(Move, "FIXED PLATFORM", false, function(v)
    PlatformActive = v
    if v then StartPlatforms() else StopPlatforms() end
end)
Slider(Move, "WALKSPEED", 16, 200, 16, function(v)
    local char = Player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = v end
end)
Slider(Move, "JUMPPOWER", 50, 300, 50, function(v)
    local char = Player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.JumpPower = v; hum.UseJumpPower = true end
end)

-- ANIMATIONS
local Anim = NewPanel("ANIMATIONS")
local animSelected = {}
local function ApplyAnims(ids)
    local char = Player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local Animate = char:FindFirstChild("Animate")
    if not Animate or not hum then return end
    local function setAnimId(pName, cName, newId)
        local pObj = Animate:FindFirstChild(pName)
        if pObj then
            local aObj = pObj:FindFirstChild(cName)
            if aObj and aObj:IsA("Animation") then aObj.AnimationId = newId or "rbxassetid://0" end
        end
    end
    setAnimId("idle", "Animation1", ids.idle1)
    setAnimId("idle", "Animation2", ids.idle2)
    setAnimId("walk", "WalkAnim", ids.walk)
    setAnimId("run", "RunAnim", ids.run)
    setAnimId("jump", "JumpAnim", ids.jump)
    setAnimId("fall", "FallAnim", ids.fall)
    Animate.Enabled = false; task.wait(0.03); Animate.Enabled = true
    if hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Landed) end
end
local animData = {
    {"Astronaut", 891621366, 891633237, 891667138, 891636393, 891627522, 891617961},
    {"Bubbly", 910004836, 910009958, 910034870, 910025107, 910016857, 910001910},
    {"Cartoony", 742637544, 742638445, 742640026, 742638842, 742637942, 742637151},
    {"Ninja", 656117400, 656118341, 656121766, 656118852, 656117878, 656115606},
    {"Zombie", 616158929, 616160636, 616168032, 616163682, 616161997, 616157476},
    {"Vampire", 1083445855, 1083450166, 1083473930, 1083462077, 1083455352, 1083443587},
    {"None", 0, 0, 0, 0, 0, 0},
}
local function asset(id) return "http://www.roblox.com/asset/?id=" .. id end
Section(Anim, "ANIMACIONES")
for i, a in ipairs(animData) do
    local ids = {
        idle1 = asset(a[2]), idle2 = asset(a[3]), walk = asset(a[4]),
        run = asset(a[5]), jump = asset(a[6]), fall = asset(a[7]),
    }
    local btn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.3,
        Text = a[1], Font = FONT, TextSize = 12, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, LayoutOrder = nextOrder(Anim),
    }, Anim)
    corner(btn, 4); stroke(btn, Theme.Line, 1, 0.3)
    make("UIPadding", {PaddingLeft = UDim.new(0, 14)}, btn)
    btn.MouseButton1Click:Connect(function()
        animSelected = ids
        ApplyAnims(ids)
    end)
end    -- HIGH FARM
    local Farm = NewPanel("HIGH FARM")
    Section(Farm, "EVENTO")
    Toggle(Farm, "AUTO FARM HALLOWEEN", false, function(v)
        getgenv().RoxHubAutoEventFarm = v
    end)

    -- HIGH KILLS
    local Kills = NewPanel("HIGH KILLS")
    Section(Kills, "KILL ALL")
    Toggle(Kills, "KILL ALL (PXZD HUB)", false, function(on)
        if on then RoxKillAllInstance:Start() else RoxKillAllInstance:Stop() end
    end)
    Slider(Kills, "VIBRACIÓN", 0.0, 3.0, 0.8, function(v) KILLALL_JITTER_AMPLITUDE = v end)
    Slider(Kills, "RADIO ACTIVACIÓN", 2.75, 9.0, 6.0, function(v) KILLALL_TRIGGER_RADIUS = v end)

    -- SETTINGS
    local Settings = NewPanel("SETTINGS")
    Section(Settings, "AJUSTES")
    local noteRow = Row(Settings, 42)
    RowLabel(noteRow, "Sin ajustes disponibles por ahora.", 28)

    -- CREDITS
    local Credits = NewPanel("CREDITS")
    Section(Credits, "CREDITOS")
    local creditCard = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 0.3, BorderSizePixel = 0, LayoutOrder = nextOrder(Credits),
    }, Credits)
    corner(creditCard, 4); stroke(creditCard, Theme.Line, 1, 0.2)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16),
        PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
    }, creditCard)
    make("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, creditCard)
    local accentHex = "#" .. Theme.Accent:ToHex()
    local function creditLine(order, text)
        return make("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
            Text = text, RichText = true, TextWrapped = true, Font = FONT, TextSize = 13,
            TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order,
        }, creditCard)
    end
    creditLine(1, "Pxzd Hub Duels")
    creditLine(2, '<font color="' .. accentHex .. '"><b>Source Pxzd Hub</b></font> -- Creador del script principal.')
    creditLine(3, '<font color="' .. accentHex .. '"><b>Powered by Nexy</b></font> -- Ayudante del script.')
    creditLine(4, '<font color="' .. accentHex .. '"><b>Taken by ChemxHub</b></font> -- Edición y soporte.')

    -- NAVEGACIÓN
    local navs = {}
    local current
    local function Select(name)
        current = name
        for n, d in pairs(navs) do
            local on = (n == name)
            TweenService:Create(d.btn, TweenInfo.new(0.15), {
                TextColor3 = on and Theme.Text or Theme.Dim,
            }):Play()
            d.deco.Visible = on
        end
        for n, p in pairs(panels) do p.Visible = (n == name) end
    end

    local function NavItem(text, order)
        local item = make("Frame", {
            Size = UDim2.new(1, -16, 0, 28), BackgroundTransparency = 1, LayoutOrder = order,
        }, Side)
        local deco = make("Frame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false,
        }, item)
        local glow = make("Frame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
        }, deco)
        make("UIGradient", {Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.86),
            NumberSequenceKeypoint.new(1, 1),
        })}, glow)
        line(deco, {Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Accent}, "center")
        local btn = make("TextButton", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = text,
            Font = FONT_TITLE, TextSize = 16, TextColor3 = Theme.Dim, AutoButtonColor = false,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, item)
        make("UIPadding", {PaddingLeft = UDim.new(0, 16)}, btn)
        navs[text] = {btn = btn, deco = deco, item = item}
        btn.MouseButton1Click:Connect(function()
            if SearchBox.Text ~= "" then SearchBox.Text = "" end
            Select(text)
        end)
    end

    local tabOrder = {"HOME", "AIMBOT", "VISUALS", "MOVEMENT", "ANIMATIONS", "HIGH FARM", "HIGH KILLS", "SETTINGS", "CREDITS"}
    for i, name in ipairs(tabOrder) do NavItem(name, i) end
    Select("HOME")

    -- SEARCH
    local SearchPanel = NewPanel("SEARCH")
    Section(SearchPanel, "RESULTADOS")
    local resultRows = {}
    local function runSearch()
        local q = string.lower(string.match(SearchBox.Text, "^%s*(.-)%s*$"))
        for name, d in pairs(navs) do
            d.item.Visible = (q == "") or (string.find(string.lower(name), q, 1, true) ~= nil)
        end
        for _, r in ipairs(resultRows) do r:Destroy() end
        resultRows = {}
        if q == "" then
            for n, p in pairs(panels) do p.Visible = (n == current) end
            return
        end
        for n, p in pairs(panels) do p.Visible = (n == "SEARCH") end
        for _, e in ipairs(searchIndex) do
            if string.find(string.lower(e.title), q, 1, true) then
                local b = make("TextButton", {
                    Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.3,
                    Text = "  " .. e.title .. "  →  " .. e.tab, Font = FONT, TextSize = 12,
                    TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
                    AutoButtonColor = false, LayoutOrder = nextOrder(SearchPanel),
                }, SearchPanel)
                corner(b, 4); stroke(b, Theme.Line, 1, 0.3)
                b.MouseButton1Click:Connect(function()
                    SearchBox.Text = ""; Select(e.tab)
                end)
                resultRows[#resultRows + 1] = b
            end
        end
    end
    SearchBox:GetPropertyChangedSignal("Text"):Connect(runSearch)

    -- RESIZE GRIP
    local MIN_W, MIN_H = 480, 320
    local MAX_W, MAX_H = 900, 620
    local Grip = make("TextButton", {
        Size = UDim2.new(0, 20, 0, 20), AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1,
        Text = "◢", Font = FONT_BOLD, TextSize = 14, TextColor3 = Theme.Dim, AutoButtonColor = false,
    }, MainFrame)
    local resizing = false
    local rStartInput, rStartW, rStartH
    Grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            rStartInput = Vector2.new(input.Position.X, input.Position.Y)
            rStartW, rStartH = MainFrame.Size.X.Offset, MainFrame.Size.Y.Offset
            Grip.TextColor3 = Theme.Accent
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local s = uiScale.Scale
            local d = (Vector2.new(input.Position.X, input.Position.Y) - rStartInput) / s
            local w = math.clamp(rStartW + d.X, MIN_W, MAX_W)
            local h = math.clamp(rStartH + d.Y, MIN_H, MAX_H)
            MainFrame.Size = UDim2.new(0, w, 0, h)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            resizing = false
            Grip.TextColor3 = Theme.Dim
        end
    end)

    -- MINIMIZAR / CERRAR / ABRIR
    local minimized = false
    MinimizeBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            Content.Visible = false
            MainFrame.Size = UDim2.new(0, 600, 0, 60)
            MinimizeBtn.Text = "+"
        else
            Content.Visible = true
            MainFrame.Size = UDim2.new(0, 600, 0, 410)
            MinimizeBtn.Text = "—"
        end
    end)
    CloseBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = false
        MainButton.Visible = true
    end)
    MainButton.MouseButton1Click:Connect(function()
        MainButton.Visible = false
        MainFrame.Visible = true
        uiScale.Scale = baseScale * 0.94
        TweenService:Create(uiScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Scale = baseScale,
        }):Play()
    end)

    Player.CharacterAdded:Connect(function(char)
        local animate = char:WaitForChild("Animate", 5)
        if animate and animSelected and animSelected.idle1 then
            task.wait(0.2)
            ApplyAnims(animSelected)
        end
    end)

    -- HOOK SILENT AIM (Raycast redirect)
    if hookmetamethod and getnamecallmethod and checkcaller then
        local oldNC = hookmetamethod(game, "__namecall", function(self, ...)
            if not checkcaller() and getgenv().RoxHubTargetPart then
                if getnamecallmethod() == "Raycast" and self == workspace then
                    local target = getgenv().RoxHubTargetPart
                    if target and target.Parent then
                        local origin, direction, p3 = ...
                        if typeof(direction) == "Vector3" and direction.Magnitude > 20 then
                            return oldNC(self, origin, (target.Position - origin).Unit * 5000, p3)
                        end
                    else
                        getgenv().RoxHubTargetPart = nil
                    end
                end
            end
            return oldNC(self, ...)
        end)
    end

    -- LOOP AUTO SHOOT
    task.spawn(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        while task.wait(0.1) do
            if (autoShootEnabled or autoShootAgresivoEnabled) then
                if estaEnLobby() then getgenv().RoxHubTargetPart = nil; continue end
                local char = Player.Character
                if not char or not char:FindFirstChild("HumanoidRootPart") then getgenv().RoxHubTargetPart = nil; continue end
                local arma = char:FindFirstChildOfClass("Tool")
                if not arma or not esPistola(arma) then getgenv().RoxHubTargetPart = nil; continue end
                local bestPart, bestDist = nil, math.huge
                local myPos = char.HumanoidRootPart.Position
                local headPos = char:FindFirstChild("Head") and char.Head.Position or myPos
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Player and isEnemy(p) and p.Character then
                        local ec = p.Character
                        local eHum = ec:FindFirstChildOfClass("Humanoid")
                        if eHum and eHum.Health > 0 then
                            params.FilterDescendantsInstances = {char, ec}
                            local function try(part)
                                if not part or not part:IsA("BasePart") then return end
                                local d = (part.Position - myPos).Magnitude
                                if d < bestDist and not workspace:Raycast(headPos, part.Position - headPos, params) then
                                    bestDist = d; bestPart = part
                                end
                            end
                            if autoShootAgresivoEnabled then
                                for _, part in ipairs(ec:GetChildren()) do
                                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then try(part) end
                                end
                            elseif autoShootTargetPart == "Cabeza" then
                                try(ec:FindFirstChild("Head"))
                            elseif autoShootTargetPart == "Torso" then
                                try(ec:FindFirstChild("UpperTorso"))
                                try(ec:FindFirstChild("Torso"))
                            else
                                for _, part in ipairs(ec:GetChildren()) do
                                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then try(part) end
                                end
                            end
                        end
                    end
                end
                if bestPart then
                    getgenv().RoxHubTargetPart = bestPart
                    pcall(function()
                        arma:Activate()
                        task.delay(0.05, function() if arma.Parent == char then arma:Deactivate() end end)
                    end)
                    task.wait(0.15)
                else
                    getgenv().RoxHubTargetPart = nil
                end
            end
        end
    end)

    -- LOOP SILENT AIM
    task.spawn(function()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        while task.wait(0.1) do
            if (silentAimManualEnabled or silentAimFovEnabled) then
                if estaEnLobby() then
                    if not autoShootEnabled and not autoShootAgresivoEnabled then getgenv().RoxHubTargetPart = nil end
                    continue
                end
                local char = Player.Character
                if not char or not char:FindFirstChild("HumanoidRootPart") then continue end
                local bestPart, bestDistCenter, bestDistFis = nil, math.huge, math.huge
                local myPos = char.HumanoidRootPart.Position
                local headPos = char:FindFirstChild("Head") and char.Head.Position or myPos
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Player and isEnemy(p) and p.Character then
                        local ec = p.Character
                        local eHum = ec:FindFirstChildOfClass("Humanoid")
                        if eHum and eHum.Health > 0 then
                            local parts = {}
                            if silentAimTargetPart == "Cabeza" then
                                local h = ec:FindFirstChild("Head")
                                if h then table.insert(parts, h) end
                            elseif silentAimTargetPart == "Torso" then
                                for _, n in ipairs({"UpperTorso","Torso"}) do
                                    local pp = ec:FindFirstChild(n)
                                    if pp then table.insert(parts, pp) end
                                end
                            else
                                for _, part in ipairs(ec:GetChildren()) do
                                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then table.insert(parts, part) end
                                end
                            end
                            params.FilterDescendantsInstances = {char, ec}
                            for _, part in ipairs(parts) do
                                local distFis = (part.Position - myPos).Magnitude
                                local pos2D, onScreen = workspace.CurrentCamera:WorldToViewportPoint(part.Position)
                                local distCenter = (Vector2.new(pos2D.X, pos2D.Y) - Vector2.new(
                                    workspace.CurrentCamera.ViewportSize.X/2,
                                    workspace.CurrentCamera.ViewportSize.Y/2)).Magnitude
                                local pass = false
                                if silentAimFovEnabled and onScreen and distCenter <= fovRadius and distCenter < bestDistCenter then
                                    pass = true
                                elseif silentAimManualEnabled and distFis < bestDistFis then
                                    pass = true
                                end
                                if pass and not workspace:Raycast(headPos, part.Position - headPos, params) then
                                    if silentAimFovEnabled then bestDistCenter = distCenter else bestDistFis = distFis end
                                    bestPart = part
                                end
                            end
                        end
                    end
                end
                if bestPart then getgenv().RoxHubTargetPart = bestPart
                elseif not autoShootEnabled and not autoShootAgresivoEnabled then
                    getgenv().RoxHubTargetPart = nil
                end
            end
        end
    end)

    -- FOV CIRCLE
    local FOVCircle = nil
    if Drawing then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Thickness = 1
        FOVCircle.Filled = false
        FOVCircle.Color = Color3.fromRGB(138, 43, 226)
        FOVCircle.Visible = false
    end
    RunService.RenderStepped:Connect(function()
        if fovVisiblePreference and FOVCircle then
            FOVCircle.Position = Vector2.new(workspace.CurrentCamera.ViewportSize.X/2, workspace.CurrentCamera.ViewportSize.Y/2)
            FOVCircle.Radius = fovRadius
            FOVCircle.Visible = true
            FOVCircle.Color = (silentAimFovEnabled and getgenv().RoxHubTargetPart)
                and Color3.fromRGB(0, 255, 128) or Color3.fromRGB(138, 43, 226)
        elseif FOVCircle then
            FOVCircle.Visible = false
        end
    end)
end

LoadHub()
