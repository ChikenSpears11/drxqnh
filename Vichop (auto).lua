if not game:IsLoaded() then
    game.Loaded:Wait()
end
local preloadPlayer = game:GetService("Players").LocalPlayer or game:GetService("Players").PlayerAdded:Wait()
preloadPlayer:WaitForChild("PlayerGui")
workspace:WaitForChild("FlowerZones")
workspace:WaitForChild("Particles")
workspace:WaitForChild("Monsters")
workspace:WaitForChild("Honeycombs")
local viciousStarted = os.clock()

-- Vicious bee caller.
-- Alts idle until workspace.Particles.WTs.WaitingThorn exists, then publish that server.
-- The account whose name matches Main Username joins, claims a hive, walks onto the thorn, then circles the field.
-- Room code is the shared channel. Other people using this script only meet you if they type the same code.

if typeof(_G.ViciousCleanup) == "function" then
    pcall(_G.ViciousCleanup)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local alive = true
local connections = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local UPSTASH_REST_URL = "https://grateful-boar-219745.upstash.io"
local UPSTASH_REST_TOKEN = "gQAAAAAAA1phAAIgcDE0ZTQ5NjYyNGI0YTY0ZTA3YjA4NWMyOTVkMDU5YTEyYQ"

local settings = {
    mainUsername = "DefNotAHaxerLO15",
    roomCode = "drxqnh"
}

local function settingsPath()
    return "ViciousHive/settings.json"
end

local function readSaved()
    if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(settingsPath()) then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(settingsPath()))
        end)
        if ok and type(decoded) == "table" then
            settings.mainUsername = tostring(decoded.mainUsername or "")
            settings.roomCode = tostring(decoded.roomCode or "")
        end
    end
end

local function writeSaved()
    if typeof(writefile) ~= "function" then
        return
    end
    if typeof(makefolder) == "function" then
        pcall(makefolder, "ViciousHive")
    end
    pcall(writefile, settingsPath(), HttpService:JSONEncode(settings))
end

readSaved()

local travelTween = nil
local phase = "idle"
local thornGoal = nil
local fieldName = nil
local circleIndex = 1
local lastPublish = 0
local lastPoll = 0
local lastTeleport = 0
local claimArrived = 0
local claimSent = 0
local statusText = "Starting"
local joinedJob = nil
local teleportStartedAt = nil
local centerWaitUntil = nil
local pendingHuntHop = false
local pendingHuntHopAt = 0
local serverHopInProgress = false
local teleportPurpose = nil
local presenceBusy = false
local lastPresenceUpdate = 0
local lastPostHuntHopAttempt = 0
local lastAltHopAttempt = 0
local rejectedCalls = {}
local lastVerifiedJob = nil
local lastVerifiedWasTest = nil
local hasPublishedCall = false
local lastPublishedWasTest = false
local lastCallPublishedAt = 0
local testCallHoldUntil = 0
local lastCallClearAttempt = 0
local callClearBusy = false
local ALT_NAMES = {
    "DefNotAHaxerLO19",
    "DefNotAHaxerLO23",
    "DefNotAHaxerLO14",
    "DefNotAHaxerLO22",
    "DefNotAHaxerLO20"
}
local ALT_RANK = {}
for index, name in ipairs(ALT_NAMES) do
    ALT_RANK[string.lower(name)] = index
end
local SERVER_CAPACITY = 6
local ALT_HOP_TARGET_MAX = 3
local PRESENCE_TTL_SECONDS = 420
local PRESENCE_INTERVAL = 180
local CALL_TTL_SECONDS = 240
local CALL_REFRESH_INTERVAL = 120
local MAIN_POLL_INTERVAL = 10
local CALL_FRESHNESS_SECONDS = 180
local POST_HUNT_QUEUE_GRACE = 8
local VICHOP_MODE = true
local ALT_HOP_RETRY_INTERVAL = 5

local function setStatus(text)
    if text == statusText then
        return
    end
    statusText = text
    warn("[Vicious] " .. text)
end

local function flat(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function fieldPart(zone)
    if not zone then
        return nil
    end
    if zone:IsA("BasePart") then
        return zone
    end
    local best, bestArea = nil, 0
    for _, descendant in ipairs(zone:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local area = descendant.Size.X * descendant.Size.Z
            if area > bestArea then
                best = descendant
                bestArea = area
            end
        end
    end
    return best
end

local function insidePart(part, position)
    if not part or not position then
        return false
    end
    local localPos = part.CFrame:PointToObjectSpace(position)
    local half = part.Size * 0.5
    return math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z
end

local function fieldOf(position)
    local zones = workspace:FindFirstChild("FlowerZones")
    if not zones or not position then
        return nil
    end
    local nearest, nearestDist = nil, math.huge
    for _, zone in ipairs(zones:GetChildren()) do
        local part = fieldPart(zone)
        if part and insidePart(part, position) then
            return zone
        end
        if part then
            local dist = flat(part.Position, position)
            if dist < nearestDist then
                nearest = zone
                nearestDist = dist
            end
        end
    end
    return nearest
end

local function findThorn()
    local particles = workspace:FindFirstChild("Particles")
    local wts = particles and particles:FindFirstChild("WTs")
    local thorn = wts and wts:FindFirstChild("WaitingThorn")
    if not thorn then
        return nil
    end
    if thorn:IsA("BasePart") then
        return thorn.Position, thorn
    end
    local part = thorn:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.Position, part
    end
    if thorn.GetPivot then
        return thorn:GetPivot().Position, thorn
    end
    return nil
end

local function findViciousBee()
    local monsters = workspace:FindFirstChild("Monsters")
    if not monsters then
        return nil
    end
    for _, child in ipairs(monsters:GetChildren()) do
        if string.find(string.lower(child.Name), "vicious bee", 1, true) then
            local root = child:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                return root.Position, child
            end
            if child:IsA("Model") and child.PrimaryPart then
                return child.PrimaryPart.Position, child
            end
            if child.GetPivot then
                return child:GetPivot().Position, child
            end
        end
    end
    return nil
end

local function findTarget()
    local beePos = findViciousBee()
    if beePos then
        return beePos, "bee"
    end
    local thornPos = findThorn()
    if thornPos then
        return thornPos, "thorn"
    end
    return nil
end

local function isMain()
    return settings.mainUsername ~= "" and string.lower(player.Name) == string.lower(settings.mainUsername)
end

local function roomKey()
    local code = string.gsub(settings.roomCode, "[^%w_%-]", "")
    if code == "" then
        return nil
    end
    return "vhive_" .. code
end

local function relayCallKey(name)
    local base = roomKey()
    if not base then
        return nil
    end
    return base .. "_call_" .. string.lower(name)
end

local httpCall, redisUrl

local function clearOwnCall()
    local key = relayCallKey(player.Name)
    if not key then
        return false, "no room code"
    end
    local result = httpCall("GET", redisUrl("del", key))
    if not result.ok then
        return false, result.detail
    end
    local ok, envelope = pcall(function()
        return HttpService:JSONDecode(result.body)
    end)
    if not ok or type(envelope) ~= "table" or envelope.error then
        return false, "malformed Upstash DEL response"
    end
    hasPublishedCall = false
    lastPublishedWasTest = false
    lastCallPublishedAt = 0
    testCallHoldUntil = 0
    lastPublish = 0
    lastVerifiedJob = nil
    lastVerifiedWasTest = nil
    return true
end

local callsFromStored

httpCall = function(method, url, body)
    local requester = request or http_request or (syn and syn.request) or (httpApi and httpApi.request)
    if typeof(requester) ~= "function" then
        return { ok = false, kind = "request", detail = "request error: no HTTP request function" }
    end
    local requestData = {
        Url = url,
        Method = method,
        Headers = { ["Authorization"] = "Bearer " .. UPSTASH_REST_TOKEN }
    }
    if body ~= nil then
        requestData.Body = body
    end
    local ok, result = pcall(requester, requestData)
    if not ok then
        return { ok = false, kind = "request", detail = "request error: " .. tostring(result) }
    end
    if type(result) ~= "table" then
        return { ok = false, kind = "request", detail = "request error: response was not a table" }
    end
    local code = tonumber(result.StatusCode or result.status_code or result.Status)
    local responseBody = result.Body or result.body or ""
    if code == nil then
        return { ok = false, kind = "http", body = responseBody, detail = "HTTP status missing" }
    end
    if code < 200 or code >= 300 then
        return { ok = false, kind = "http", status = code, body = responseBody, detail = "HTTP " .. tostring(code) }
    end
    return { ok = true, kind = "ok", status = code, body = responseBody, detail = "HTTP " .. tostring(code) }
end
local function urlEncode(text)
    local encoded = string.gsub(text, "([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return encoded
end

local function urlDecode(text)
    text = string.gsub(text, "%+", " ")
    text = string.gsub(text, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return text
end

redisUrl = function(command, key)
    return UPSTASH_REST_URL .. "/" .. command .. "/" .. urlEncode(key)
end
local function readCall(body)
    if typeof(body) ~= "string" then
        return nil, "malformed response"
    end
    body = string.gsub(body, "^%s+", "")
    body = string.gsub(body, "%s+$", "")
    for _ = 1, 4 do
        if body == "" or body == "null" then
            return { v = 1, calls = {} }
        end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if ok then
            if type(data) == "table" then
                return data
            elseif type(data) == "string" then
                body = string.gsub(data, "^%s+", "")
                body = string.gsub(body, "%s+$", "")
            elseif data == nil then
                return { v = 1, calls = {} }
            else
                return nil, "malformed response"
            end
        else
            local decoded = urlDecode(body)
            if decoded == body then
                return nil, "malformed response"
            end
            body = decoded
        end
    end
    return nil, "malformed response"
end

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function validateCall(data)
    if type(data) ~= "table" then
        return nil, "malformed call"
    end
    if typeof(data.job) ~= "string" or data.job == "" then
        return nil, "invalid server id"
    end
    local place = tonumber(data.place)
    if not place or place <= 0 or place % 1 ~= 0 then
        return nil, "invalid place id"
    end
    if place ~= game.PlaceId then
        return nil, "call is for another place"
    end
    local at = tonumber(data.at)
    if not at then
        return nil, "invalid call time"
    end
    local age = os.time() - at
    if age < -2 then
        return nil, string.format("future call (%ds ahead)", math.floor(-age))
    end
    if age > CALL_FRESHNESS_SECONDS then
        return nil, string.format("stale call (%ds old)", math.floor(age))
    end
    local x = finiteNumber(data.x)
    local z = finiteNumber(data.z)
    if not x or not z then
        return nil, "invalid coordinates"
    end
    local y = nil
    if data.y ~= nil then
        y = finiteNumber(data.y)
        if not y then
            return nil, "invalid coordinates"
        end
    end
    data.place = place
    data.at = at
    data.x = x
    data.z = z
    data.y = y or 0
    return data
end

callsFromStored = function(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data.calls) == "table" then
        return data.calls
    end
    if data.job ~= nil then
        return { data }
    end
    return {}
end

local function poll()
    local base = roomKey()
    if not base then
        return nil, "no room code"
    end
    local keys = {}
    for _, name in ipairs(ALT_NAMES) do
        table.insert(keys, relayCallKey(name))
    end
    local encoded = {}
    for _, key in ipairs(keys) do
        if not key then
            return nil, "invalid relay key"
        end
        table.insert(encoded, urlEncode(key))
    end
    local result = httpCall("GET", UPSTASH_REST_URL .. "/mget/" .. table.concat(encoded, "/"))
    if result.kind == "request" then
        return nil, result.detail
    end
    if not result.ok then
        local body = result.body or ""
        if #body > 160 then body = string.sub(body, 1, 160) end
        if body == "" then return nil, result.detail .. "; empty response" end
        return nil, result.detail .. "; body: " .. body
    end
    local ok, envelope = pcall(function()
        return HttpService:JSONDecode(result.body)
    end)
    if not ok or type(envelope) ~= "table" then
        return nil, "malformed Upstash MGET response"
    end
    if envelope.error then
        return nil, "Upstash MGET error: " .. tostring(envelope.error)
    end
    if type(envelope.result) ~= "table" then
        return nil, "malformed Upstash MGET value"
    end
    local calls = {}
    for index = 1, #keys do
        local value = envelope.result[index]
        if typeof(value) == "string" then
            local data, why = readCall(value)
            if not data then
                return nil, "malformed stored call at key " .. tostring(index) .. ": " .. tostring(why)
            end
            for _, call in ipairs(callsFromStored(data)) do
                table.insert(calls, call)
            end
        end
    end
    return { v = 1, calls = calls }
end
local function publish(payload)
    if not ALT_RANK[string.lower(player.Name)] then
        return false, "this account is not in the configured alt list"
    end
    local key = relayCallKey(player.Name)
    if not key then
        return false, "no room code"
    end
    local call, invalid = validateCall({
        who = payload.who,
        job = payload.job,
        place = payload.place,
        field = payload.field,
        x = payload.x,
        y = payload.y,
        z = payload.z,
        at = payload.at,
        test = payload.test == true
    })
    if not call then
        return false, invalid
    end
    local storedValue = HttpService:JSONEncode(call)
    if #storedValue > 900 then
        return false, "call payload exceeds safe relay value size"
    end
    local posted = httpCall("POST", redisUrl("set", key) .. "?EX=" .. tostring(CALL_TTL_SECONDS), storedValue)
    if posted.kind == "request" then
        return false, posted.detail
    end
    if not posted.ok then
        local body = posted.body or ""
        if #body > 160 then body = string.sub(body, 1, 160) end
        if body == "" then return false, posted.detail .. "; empty response" end
        return false, posted.detail .. "; body: " .. body
    end
    local ackOk, acknowledgement = pcall(function()
        return HttpService:JSONDecode(posted.body)
    end)
    if not ackOk or type(acknowledgement) ~= "table" or acknowledgement.result ~= "OK" then
        return false, "Upstash SET did not confirm success"
    end
    hasPublishedCall = true
    lastPublishedWasTest = call.test
    lastCallPublishedAt = os.clock()
    if call.test then
        testCallHoldUntil = lastCallPublishedAt + 30
    end
    if lastVerifiedJob == call.job and lastVerifiedWasTest == call.test then
        return true, "Upstash confirmed this refresh with SET OK; read-back was already confirmed for this account/server call."
    end
    local readback = httpCall("GET", redisUrl("get", key))
    if not readback.ok then
        return false, "Upstash read-back failed: " .. tostring(readback.detail)
    end
    local readOk, readEnvelope = pcall(function()
        return HttpService:JSONDecode(readback.body)
    end)
    if not readOk or type(readEnvelope) ~= "table" or readEnvelope.error or typeof(readEnvelope.result) ~= "string" then
        return false, "Upstash read-back was empty or malformed"
    end
    local storedCall, readWhy = readCall(readEnvelope.result)
    if not storedCall then
        return false, "Upstash read-back could not decode the call: " .. tostring(readWhy)
    end
    local found = false
    for _, item in ipairs(callsFromStored(storedCall)) do
        if item.job == call.job and tonumber(item.place) == call.place and tonumber(item.at) == call.at
            and tostring(item.who) == tostring(call.who) then
            found = true
            break
        end
    end
    if not found then
        return false, "Upstash read-back did not match this call"
    end
    lastVerifiedJob = call.job
    lastVerifiedWasTest = call.test
    return true, "Upstash accepted the write and read-back found this call. That does not confirm the main received it."
end
local function releaseTravel(root)
    if travelTween then
        pcall(function()
            travelTween:Cancel()
        end)
        travelTween = nil
    end
    if root then
        root.Anchored = false
    end
end

local function tweenTo(root, humanoid, pos)
    if not root or not pos then
        return
    end
    if typeof(travelTween) == "Instance" then
        root.Anchored = true
        return
    end
    local distance = (root.Position - pos).Magnitude
    if distance < 4 then
        return
    end
    root.Anchored = true
    local speed = 80
    travelTween = TweenService:Create(root, TweenInfo.new(distance / speed, Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos)
    })
    travelTween.Completed:Connect(function()
        travelTween = nil
        if root.Parent then
            root.Anchored = false
        end
    end)
    travelTween:Play()
end

local function ownsHive()
    local hives = workspace:FindFirstChild("Honeycombs")
    if not hives then
        return false
    end
    for _, child in ipairs(hives:GetChildren()) do
        local owner = child:FindFirstChild("Owner")
        local value = owner and owner.Value
        if value == player or tostring(value) == player.Name then
            return true
        end
    end
    return false
end

local function claimHive(humanoid, root)
    if ownsHive() then
        claimArrived = 0
        return true
    end
    local hives = workspace:FindFirstChild("Honeycombs")
    local deco = workspace:FindFirstChild("HiveDeco")
    local canvases = deco and deco:FindFirstChild("StickerCanvases")
    if not hives or not canvases then
        return false
    end
    local emptyNumber = nil
    local slots = {}
    for _, child in ipairs(hives:GetChildren()) do
        local number = tonumber(string.match(child.Name, "%d+"))
        if number then
            table.insert(slots, { number = number, owner = child:FindFirstChild("Owner") })
        end
    end
    table.sort(slots, function(a, b)
        return a.number < b.number
    end)
    for _, slot in ipairs(slots) do
        local value = slot.owner and slot.owner.Value
        if value == nil or value == false or value == "" then
            emptyNumber = slot.number
            break
        end
    end
    if not emptyNumber then
        return false
    end
    local canvas = canvases:FindFirstChild("StickerCanvas" .. tostring(emptyNumber))
    local surfaces = canvas and canvas:FindFirstChild("PlaceableSurfaces")
    local circle = surfaces and surfaces:FindFirstChild("NegateCircle")
    local pos = nil
    if circle and circle:IsA("BasePart") then
        pos = circle.Position + Vector3.new(0, 3, 0)
    elseif circle and circle.GetPivot then
        pos = circle:GetPivot().Position
    end
    if not pos then
        return false
    end
    tweenTo(root, humanoid, pos)
    if flat(root.Position, pos) <= 8 then
        if claimArrived == 0 then
            claimArrived = os.clock()
        end
        if os.clock() - claimArrived >= 0.25 and os.clock() - claimSent > 2 then
            local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
            local claim = events and events:FindFirstChild("ClaimHive")
            if claim then
                claim:FireServer(emptyNumber)
                claimSent = os.clock()
                claimArrived = 0
            end
        end
    else
        claimArrived = 0
    end
    return false
end

local function circlePoint(root)
    local zones = workspace:FindFirstChild("FlowerZones")
    local zone = fieldName and zones and zones:FindFirstChild(fieldName)
    local part = fieldPart(zone)
    if not part then
        return nil
    end
    local half = part.Size * 0.5
    local radius = math.min(24, half.X * 0.45, half.Z * 0.45)
    local angle = (circleIndex - 1) * (math.pi * 2 / 8)
    local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
    local world = part.CFrame:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Z))
    return Vector3.new(world.X, root.Position.Y, world.Z)
end

local function web(method, url, headers, body)
    local requester = request or http_request or (syn and syn.request) or (httpApi and httpApi.request)
    if typeof(requester) ~= "function" then
        return nil, "the executor cannot send web requests"
    end
    local ok, result = pcall(requester, {
        Url = url,
        Method = method,
        Headers = headers,
        Body = body
    })
    if not ok then
        return nil, "web request error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "web request returned a non-table response"
    end
    return result
end

local function presenceKey(name)
    local base = roomKey()
    if not base then
        return nil
    end
    return base .. "_presence_" .. string.lower(name)
end

local function writePresence()
    local key = presenceKey(player.Name)
    if not key then
        return false, "room code is empty"
    end
    local payload = HttpService:JSONEncode({
        name = player.Name,
        job = game.JobId,
        place = game.PlaceId,
        players = #Players:GetPlayers(),
        main = isMain(),
        at = os.time()
    })
    local result = httpCall("POST", redisUrl("set", key) .. "?EX=" .. tostring(PRESENCE_TTL_SECONDS), payload)
    if not result.ok then
        return false, result.detail .. (result.body and (": " .. string.sub(result.body, 1, 120)) or "")
    end
    local ok, envelope = pcall(function()
        return HttpService:JSONDecode(result.body)
    end)
    if not ok or type(envelope) ~= "table" or envelope.error or envelope.result ~= "OK" then
        return false, "Upstash did not confirm presence write"
    end
    return true
end

local function readPresenceRoster()
    local keys = {}
    table.insert(keys, presenceKey(settings.mainUsername))
    for _, name in ipairs(ALT_NAMES) do
        table.insert(keys, presenceKey(name))
    end
    for _, key in ipairs(keys) do
        if not key then
            return nil, "room code is empty"
        end
    end
    local encoded = {}
    for _, key in ipairs(keys) do
        table.insert(encoded, urlEncode(key))
    end
    local result = httpCall("GET", UPSTASH_REST_URL .. "/mget/" .. table.concat(encoded, "/"))
    if not result.ok then
        return nil, result.detail .. (result.body and (": " .. string.sub(result.body, 1, 120)) or "")
    end
    local ok, envelope = pcall(function()
        return HttpService:JSONDecode(result.body)
    end)
    if not ok or type(envelope) ~= "table" then
        return nil, "malformed Upstash presence response"
    end
    if envelope.error then
        return nil, "Upstash MGET error: " .. tostring(envelope.error)
    end
    if type(envelope.result) ~= "table" then
        return nil, "malformed Upstash presence response"
    end
    local roster = {}
    for index = 1, #keys do
        local raw = envelope.result[index]
        if type(raw) == "string" then
            local decodedOk, entry = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if decodedOk and type(entry) == "table" and type(entry.job) == "string"
                and tonumber(entry.at) and os.time() - tonumber(entry.at) <= PRESENCE_TTL_SECONDS then
                roster[string.lower(tostring(entry.name or ""))] = entry
            end
        end
    end
    return roster
end

local function reservePublicServer(serverId)
    local base = roomKey()
    if not base then
        return nil, "room code is empty"
    end
    local key = base .. "_reserve_" .. serverId
    local result = httpCall("GET", redisUrl("set", key) .. "/" .. urlEncode(player.Name) .. "/NX/EX/30")
    if not result.ok then
        return nil, "reservation " .. result.detail
    end
    local ok, envelope = pcall(function()
        return HttpService:JSONDecode(result.body)
    end)
    if not ok or type(envelope) ~= "table" or envelope.error then
        return nil, "malformed server reservation response"
    end
    return envelope.result == "OK"
end

local function findLowPopulationServer(roster)
    local occupied = {}
    for _, entry in pairs(roster or {}) do
        if type(entry.job) == "string" then
            occupied[entry.job] = true
        end
    end
    local candidates = {}
    local cursor = nil
    for _ = 1, 3 do
        local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
            .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor and cursor ~= "" then
            url = url .. "&cursor=" .. urlEncode(cursor)
        end
        local response, requestError = web("GET", url, { ["Content-Type"] = "application/json" })
        if not response then
            return nil, requestError or "server-list request failed"
        end
        local status = tonumber(response.StatusCode or response.status_code or response.Status)
        if not status or status < 200 or status >= 300 then
            return nil, "server-list HTTP " .. tostring(status or "status missing")
        end
        local decodeOk, page = pcall(function()
            return HttpService:JSONDecode(response.Body or response.body or "")
        end)
        if not decodeOk or type(page) ~= "table" or type(page.data) ~= "table" then
            return nil, "malformed public server list"
        end
        for _, server in ipairs(page.data) do
            local id = server.id
            local playing = tonumber(server.playing)
            local maxPlayers = tonumber(server.maxPlayers) or SERVER_CAPACITY
            if type(id) == "string" and id ~= "" and id ~= game.JobId
                and playing and playing <= ALT_HOP_TARGET_MAX and playing < maxPlayers
                and not occupied[id] then
                table.insert(candidates, id)
            end
        end
        cursor = page.nextPageCursor
        if not cursor or cursor == "" then
            break
        end
    end
    if #candidates == 0 then
        return nil, "no eligible public server with 3 or fewer players was found"
    end
    while #candidates > 0 do
        local index = math.random(1, #candidates)
        local candidate = table.remove(candidates, index)
        local reserved, reserveError = reservePublicServer(candidate)
        if reserved == nil then
            return nil, reserveError
        elseif reserved then
            return candidate
        end
    end
    return nil, "all low-population servers were reserved by another account; retrying"
end

local function shouldAltHop()
    if #Players:GetPlayers() >= SERVER_CAPACITY then
        return true, "this server is full"
    end
    local myRank = ALT_RANK[string.lower(player.Name)]
    if not myRank then
        return false
    end
    for _, other in ipairs(Players:GetPlayers()) do
        if string.lower(other.Name) == string.lower(settings.mainUsername) then
            return true, "the main joined this server"
        end
        local otherRank = ALT_RANK[string.lower(other.Name)]
        if other ~= player and otherRank and otherRank < myRank then
            return true, "a higher-priority alt is already in this server"
        end
    end
    return false
end

local function startServerHop(serverId, reason)
    if not serverId or serverHopInProgress then
        return false
    end
    phase = "joining"
    serverHopInProgress = true
    teleportPurpose = "server-hop"
    joinedJob = serverId
    teleportStartedAt = os.clock()
    lastTeleport = os.clock()
    task.spawn(function()
        if not alive or not serverHopInProgress or joinedJob ~= serverId then
            return
        end
        if not isMain() then
            local cleared, clearError = clearOwnCall()
            if not cleared then
                warn("[Vicious] Could not clear old alt call before hopping: " .. tostring(clearError))
            end
        end
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, player)
        end)
        if not alive or joinedJob ~= serverId then
            return
        end
        if ok then
            setStatus("Server hop initiated: " .. tostring(reason) .. ". Destination has 3 or fewer players.")
        else
            phase = "idle"
            serverHopInProgress = false
            teleportPurpose = nil
            teleportStartedAt = nil
            joinedJob = nil
            if isMain() and not VICHOP_MODE then
                pendingHuntHop = true
            end
            setStatus("Server-hop initiation failed: " .. tostring(err))
        end
    end)
    return true
end

local postHuntHopSearching = false
local tryJoin
local function startPostHuntHop()
    if postHuntHopSearching or serverHopInProgress or not pendingHuntHop
        or os.clock() - lastPostHuntHopAttempt < 15 then
        return
    end
    postHuntHopSearching = true
    lastPostHuntHopAttempt = os.clock()
    task.spawn(function()
        local roster, rosterError = readPresenceRoster()
        if not roster then
            setStatus("Post-hunt hop waiting: roster read failed: " .. tostring(rosterError))
            postHuntHopSearching = false
            return
        end
        local serverId, hopError = findLowPopulationServer(roster)
        if not serverId then
            setStatus("Post-hunt hop waiting: " .. tostring(hopError))
            postHuntHopSearching = false
            return
        end
        local latest, pollError = poll()
        if not latest then
            setStatus("Post-hunt hop postponed because the call queue could not be checked: " .. tostring(pollError))
            postHuntHopSearching = false
            return
        end
        if not pendingHuntHop or phase ~= "idle" then
            postHuntHopSearching = false
            return
        end
        local queued = nil
        for _, item in ipairs(callsFromStored(latest)) do
            local call = validateCall(item)
            if call and call.job ~= game.JobId and not rejectedCalls[call.job .. "|" .. tostring(call.at)]
                and (not queued or call.at > queued.at) then
                queued = call
            end
        end
        if queued and tryJoin and pendingHuntHop and phase == "idle" then
            setStatus("A fresh alt call arrived during server selection. Joining that server first.")
            tryJoin(queued)
            postHuntHopSearching = false
            return
        end
        pendingHuntHop = false
        if not startServerHop(serverId, "the vicious bee is gone") then
            pendingHuntHop = true
        end
        postHuntHopSearching = false
    end)
end

local function runPresenceCycle()
    if presenceBusy or not alive then
        return
    end
    local localIsMain = isMain()
    local myRank = ALT_RANK[string.lower(player.Name)]
    if not localIsMain and not myRank then
        return
    end
    presenceBusy = true
    if lastPresenceUpdate == 0 or os.clock() - lastPresenceUpdate >= PRESENCE_INTERVAL then
        lastPresenceUpdate = os.clock()
        local wrote, writeError = writePresence()
        if not wrote then
            setStatus("Presence update failed: " .. tostring(writeError))
        end
    end
    if localIsMain then
        presenceBusy = false
        return
    end
    local shouldHop, reason = shouldAltHop()
    if not shouldHop and VICHOP_MODE and not findTarget() then
        shouldHop, reason = true, "no vicious bee in this server"
    end
    local retryInterval = VICHOP_MODE and ALT_HOP_RETRY_INTERVAL or 30
    if not shouldHop or serverHopInProgress or os.clock() - lastAltHopAttempt < retryInterval
        or (phase == "joining" and teleportStartedAt and os.clock() - teleportStartedAt < 12) then
        presenceBusy = false
        return
    end
    local mainHasJoined = reason == "the main joined this server"
    if not mainHasJoined and os.clock() < testCallHoldUntil then
        presenceBusy = false
        return
    end
    if not mainHasJoined and reason ~= "this server is full" and reason ~= "no vicious bee in this server" and hasPublishedCall
        and os.clock() - lastCallPublishedAt < 25 then
        presenceBusy = false
        return
    end
    lastAltHopAttempt = os.clock()
    local roster, rosterError = readPresenceRoster()
    if not roster then
        setStatus("Server roster unavailable: " .. tostring(rosterError))
        presenceBusy = false
        return
    end
    setStatus("Finding a low-population server because " .. tostring(reason) .. ".")
    local serverId, hopError = findLowPopulationServer(roster)
    if not serverId then
        setStatus("Server hop waiting: " .. tostring(hopError) .. ". Will retry.")
        presenceBusy = false
        return
    end
    if reason ~= "the main joined this server" and os.clock() < testCallHoldUntil then
        presenceBusy = false
        return
    end
    if reason ~= "the main joined this server" and reason ~= "this server is full" and reason ~= "no vicious bee in this server"
        and hasPublishedCall and os.clock() - lastCallPublishedAt < 25 then
        presenceBusy = false
        return
    end
    startServerHop(serverId, reason)
    presenceBusy = false
end

task.spawn(function()
    while alive do
        runPresenceCycle()
        task.wait(5)
    end
end)

local function beginHunt(data)
    if phase == "joining" and teleportPurpose == "server-hop" then
        serverHopInProgress = false
        teleportPurpose = nil
        teleportStartedAt = nil
        joinedJob = nil
    end
    pendingHuntHop = false
    pendingHuntHopAt = 0
    centerWaitUntil = nil
    fieldName = data.field
    if typeof(data.x) == "number" and typeof(data.z) == "number" then
        thornGoal = Vector3.new(data.x, typeof(data.y) == "number" and data.y or 0, data.z)
    end
    phase = "claim"
    setStatus("In the server. Claiming a hive.")
end

tryJoin = function(data)
    local call, why = validateCall(data)
    if not call then
        phase = "idle"
        setStatus("Invalid call: " .. tostring(why))
        if type(data) == "table" and data.job and data.at then
            rejectedCalls[tostring(data.job) .. "|" .. tostring(data.at)] = why
        end
        return
    end
    if rejectedCalls[call.job .. "|" .. tostring(call.at)] then
        return
    end
    if call.job == game.JobId then
        if call.test then
            phase = "idle"
            teleportStartedAt = nil
            joinedJob = nil
            setStatus("Connection test passed: main is already in the alt server.")
            return
        end
        if phase == "idle" or phase == "joining" then
            beginHunt(call)
        elseif thornGoal == nil then
            thornGoal = Vector3.new(call.x, call.y, call.z)
            fieldName = call.field or fieldName
        end
        return
    end
    if phase == "joining" and teleportStartedAt and os.clock() - teleportStartedAt < 12 then
        return
    end
    if os.clock() - lastTeleport < 8 then
        return
    end
    lastTeleport = os.clock()
    teleportStartedAt = os.clock()
    teleportPurpose = "call"
    serverHopInProgress = false
    joinedJob = call.job
    phase = "joining"
    fieldName = call.field
    thornGoal = Vector3.new(call.x, call.y, call.z)
    setStatus("Call accepted from " .. tostring(call.who or "alt") .. " for " .. tostring(call.field or "a field") .. ". Server " .. call.job .. ".")
    task.spawn(function()
        if not alive or phase ~= "joining" or joinedJob ~= call.job then
            return
        end
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(call.place, call.job, player)
        end)
        if not alive or phase ~= "joining" or joinedJob ~= call.job then
            return
        end
        if not ok then
            phase = "idle"
            teleportStartedAt = nil
            joinedJob = nil
            teleportPurpose = nil
            setStatus("Teleport initiation failed: " .. tostring(err))
        else
            setStatus(call.test and "Test teleport initiated to the alt server." or ("Teleport initiated to " .. call.job .. "."))
        end
    end)
end

connect(TeleportService.TeleportInitFailed, function(failedPlayer, result, message)
    if failedPlayer ~= player then
        return
    end
    setStatus("Teleport failed after it started: " .. tostring(result) .. " " .. tostring(message))
    phase = "idle"
    teleportStartedAt = nil
    joinedJob = nil
    if teleportPurpose == "server-hop" and isMain() and not VICHOP_MODE then
        pendingHuntHop = true
    end
    serverHopInProgress = false
    teleportPurpose = nil
end)

connect(player.Idled, function()
    local virtualUser = game:GetService("VirtualUser")
    virtualUser:CaptureController()
    virtualUser:ClickButton2(Vector2.new())
end)

antiLagTouched = {}
antiLagWatched = {}
liveMarkModels = {}
local antiLagAt = 0
local antiLagOn = false
local renderReductionEnabled = string.lower(player.Name) ~= "defnotahaxerlo15"

local function applyRenderingPreference()
    local gui = player:FindFirstChild("PlayerGui")
    local screen = gui and gui:FindFirstChild("ScreenGui")
    if screen then
        screen.Enabled = not renderReductionEnabled
    end
    pcall(function()
        RunService:Set3dRenderingEnabled(not renderReductionEnabled)
    end)
end

local function antiLagRemember(inst, kind)
    if antiLagTouched[inst] then
        return
    end
    antiLagTouched[inst] = kind
end

local function antiLagConceal(root)
    if not root or antiLagTouched[root] then
        return
    end
    local list = root:GetDescendants()
    table.insert(list, root)
    for _, inst in ipairs(list) do
        if inst:IsA("BasePart") then
            inst.LocalTransparencyModifier = 1
            antiLagRemember(inst, "part")
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Light") then
            inst.Enabled = false
            antiLagRemember(inst, "emit")
        elseif inst:IsA("Highlight") then
            inst.Enabled = false
            antiLagRemember(inst, "emit")
        end
    end
    antiLagRemember(root, "root")
end

function antiLagRestore()
    for inst, kind in pairs(antiLagTouched) do
        pcall(function()
            if kind == "part" then
                inst.LocalTransparencyModifier = 0
            elseif kind == "emit" then
                inst.Enabled = true
            end
        end)
    end
    table.clear(antiLagTouched)
    pcall(function()
        RunService:Set3dRenderingEnabled(true)
    end)
    local gui = player:FindFirstChild("PlayerGui")
    local screen = gui and gui:FindFirstChild("ScreenGui")
    if screen then
        screen.Enabled = true
    end
end

local function antiLagWatch(parent)
    if not parent or antiLagWatched[parent] then
        return
    end
    antiLagWatched[parent] = true
    connect(parent.DescendantAdded, function(inst)
        if antiLagOn then
            antiLagConceal(inst)
        end
    end)
end

local function antiLagApply()
    local collectibles = workspace:FindFirstChild("Collectibles")
    antiLagWatch(collectibles)
    antiLagConceal(collectibles)
    local particles = workspace:FindFirstChild("Particles")
    if particles then
        for _, obj in ipairs(particles:GetChildren()) do
            if string.lower(obj.Name) == "crosshair" then
                antiLagConceal(obj)
            end
        end
    end
    local camera = workspace.CurrentCamera
    antiLagConceal(camera and camera:FindFirstChild("DupedTokens"))
    for _, model in pairs(liveMarkModels) do
        antiLagConceal(model)
    end
    local bees = workspace:FindFirstChild("Bees")
    antiLagWatch(bees)
    antiLagConceal(bees)
    local flowers = workspace:FindFirstChild("Flowers")
    local flowerZones = workspace:FindFirstChild("FlowerZones")
    antiLagWatch(flowers)
    antiLagWatch(flowerZones)
    antiLagConceal(flowers)
    if flowerZones then
        for _, zone in ipairs(flowerZones:GetChildren()) do
            for _, child in ipairs(zone:GetChildren()) do
                antiLagConceal(child)
            end
        end
    end
    local decorations = workspace:FindFirstChild("Decorations")
    antiLagWatch(decorations)
    antiLagConceal(decorations)
    local balloons = workspace:FindFirstChild("Balloons")
    if balloons then
        for _, child in ipairs(balloons:GetChildren()) do
            if child.Name ~= "HiveBalloons" then
                antiLagConceal(child)
            end
        end
    end
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            antiLagConceal(other.Character)
        end
    end
    applyRenderingPreference()
end

task.spawn(function()
    local events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
    local remote = events:WaitForChild("StationEvent")
    if remote:IsA("RemoteEvent") then
        connect(remote.OnClientEvent, function(action, data)
            if typeof(data) ~= "table" then
                return
            end
            local id = tostring(data.Id or data.ID or data.id or "")
            if action == "AnimDestroy" then
                liveMarkModels[id] = nil
            elseif action == "Spawn" and typeof(data.Model) == "Instance" then
                liveMarkModels[id] = data.Model
            end
        end)
    end
end)

connect(RunService.Heartbeat, function()
    if not alive then
        return
    end
    if not antiLagOn and os.clock() - viciousStarted >= 10 then
        antiLagOn = true
    end
    if antiLagOn and os.clock() - antiLagAt >= 0.5 then
        antiLagAt = os.clock()
        pcall(antiLagApply)
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if settings.mainUsername == "" or settings.roomCode == "" then
        setStatus("Set the main username and a room code.")
        return
    end
    if isMain() then
        local localPos = findViciousBee()
        if localPos then
            local zone = fieldOf(localPos)
            local moved = thornGoal and flat(thornGoal, localPos) > 12
            thornGoal = localPos
            fieldName = (zone and zone.Name) or fieldName
            if phase == "idle" or (phase == "joining" and teleportPurpose == "server-hop") or (phase == "circle" and moved) then
                beginHunt({
                    field = fieldName,
                    x = localPos.X,
                    y = localPos.Y,
                    z = localPos.Z
                })
                setStatus("Vicious bee in this server, in " .. tostring(fieldName) .. ".")
            end
        end
        if os.clock() - lastPoll >= MAIN_POLL_INTERVAL and phase ~= "claim" and phase ~= "field" and phase ~= "centerWait" and phase ~= "thorn" and phase ~= "circle" then
            lastPoll = os.clock()
            if phase == "joining" and teleportStartedAt and os.clock() - teleportStartedAt >= 12 and game.JobId ~= joinedJob then
                if teleportPurpose == "server-hop" and isMain() and not VICHOP_MODE then
                    pendingHuntHop = true
                end
                phase = "idle"
                teleportStartedAt = nil
                joinedJob = nil
                serverHopInProgress = false
                teleportPurpose = nil
                setStatus("Teleport was started but this server did not change. Retrying.")
            end
            local data, why = poll()
            if not data then
                if phase == "idle" then
                    setStatus("Main. " .. tostring(why) .. " on room " .. settings.roomCode .. ".")
                end
            else
                local picked, invalid = nil, nil
                for _, item in ipairs(callsFromStored(data)) do
                    local call, reason = validateCall(item)
                    if not call then
                        invalid = reason
                        if type(item) == "table" and item.job and item.at then
                            rejectedCalls[tostring(item.job) .. "|" .. tostring(item.at)] = reason
                        end
                    elseif not rejectedCalls[call.job .. "|" .. tostring(call.at)]
                        and (not pendingHuntHop or call.job ~= game.JobId) then
                        if not picked or call.at > picked.at then
                            picked = call
                        end
                    end
                end
                if picked then
                    tryJoin(picked)
                elseif pendingHuntHop and phase == "idle" and not VICHOP_MODE then
                    if os.clock() - pendingHuntHopAt >= POST_HUNT_QUEUE_GRACE then
                        startPostHuntHop()
                    else
                        setStatus("Vicious bee is gone. Checking for queued alt calls before hopping.")
                    end
                elseif phase == "idle" then
                    if VICHOP_MODE and not invalid then
                        setStatus("Main waiting for a fresh alt call.")
                    else
                        setStatus("Invalid call: " .. tostring(invalid or "no call stored"))
                    end
                end
            end
        end
        if not root or not humanoid then
            return
        end
        if phase == "claim" then
            if claimHive(humanoid, root) then
                phase = "field"
                releaseTravel(root)
                setStatus("Hive claimed. Tweening to " .. tostring(fieldName or "the field") .. ".")
            end
            return
        end
        if phase == "field" then
            local zones = workspace:FindFirstChild("FlowerZones")
            local zone = fieldName and zones and zones:FindFirstChild(fieldName)
            local part = fieldPart(zone)
            if not part then
                setStatus("Field " .. tostring(fieldName) .. " is not in this server.")
                return
            end
            local center = part.Position + Vector3.new(0, 5, 0)
            if (root.Position - center).Magnitude <= 6 then
                releaseTravel(root)
                phase = "centerWait"
                centerWaitUntil = os.clock() + 5
                setStatus("At the center of " .. tostring(fieldName or "the field") .. ". Waiting 5 seconds before walking to the vicious bee.")
            else
                setStatus("Tweening to the center of " .. tostring(fieldName or "the field") .. ".")
                tweenTo(root, humanoid, center)
            end
            return
        end
        if phase == "centerWait" then
            if not centerWaitUntil then
                centerWaitUntil = os.clock() + 5
            end
            if os.clock() >= centerWaitUntil then
                centerWaitUntil = nil
                phase = "thorn"
                setStatus("Center wait complete. Walking onto the vicious bee.")
            end
            return
        end
        if phase == "thorn" then
            local livePos = findViciousBee()
            if livePos then
                thornGoal = livePos
                local zone = fieldOf(livePos)
                fieldName = (zone and zone.Name) or fieldName
            end
            if not thornGoal then
                setStatus("Waiting for the vicious bee to load.")
                return
            end
            local spot = Vector3.new(thornGoal.X, root.Position.Y, thornGoal.Z)
            if flat(root.Position, spot) <= 4 then
                phase = "circle"
                circleIndex = 1
                setStatus("On the vicious bee. Circling " .. tostring(fieldName or "the field") .. ".")
            else
                humanoid.WalkSpeed = 70
                humanoid:MoveTo(spot)
            end
            return
        end
        if phase == "circle" then
            if not findViciousBee() then
                phase = "idle"
                thornGoal = nil
                centerWaitUntil = nil
                pendingHuntHop = false
                pendingHuntHopAt = os.clock()
                humanoid:MoveTo(root.Position)
                setStatus("Vicious bee is gone. Main is waiting for a fresh alt call.")
                return
            end
            local spot = circlePoint(root)
            if not spot then
                return
            end
            humanoid.WalkSpeed = 70
            humanoid:MoveTo(spot)
            if flat(root.Position, spot) <= 5 then
                circleIndex = (circleIndex % 8) + 1
            end
            return
        end
    else
        if serverHopInProgress then
            return
        end
        local pos = findTarget()
        if not pos then
            if hasPublishedCall and not lastPublishedWasTest then
                phase = "idle"
                lastPublish = 0
                if not callClearBusy and os.clock() - lastCallClearAttempt >= 10 then
                    callClearBusy = true
                    lastCallClearAttempt = os.clock()
                    task.spawn(function()
                        local cleared, clearError = clearOwnCall()
                        if not cleared then
                            warn("[Vicious] Could not clear expired target call: " .. tostring(clearError))
                        end
                        callClearBusy = false
                    end)
                end
                setStatus("The vicious target disappeared. Clearing its old call and waiting.")
            elseif lastPublishedWasTest then
                phase = "seen"
            else
                local wasSeen = phase == "seen"
                phase = "idle"
                if not wasSeen then
                    setStatus("Alt " .. player.Name .. ". Idling until a vicious bee spawns.")
                end
            end
            return
        end
        local zone = fieldOf(pos)
        fieldName = zone and zone.Name or "Unknown"
        phase = "seen"
        if lastPublish == 0 or os.clock() - lastPublish >= CALL_REFRESH_INTERVAL then
            lastPublish = os.clock()
            local sent, detail = publish({
                who = player.Name,
                job = game.JobId,
                place = game.PlaceId,
                field = fieldName,
                x = pos.X,
                y = pos.Y,
                z = pos.Z,
                at = os.time()
            })
            if sent then
                setStatus("Read back the " .. fieldName .. " call. " .. tostring(detail))
            else
                lastPublish = os.clock() - (CALL_REFRESH_INTERVAL - 10)
                setStatus("Call failed: " .. tostring(detail) .. ". Retrying in about 10 seconds.")
            end
        end
    end
end)

_G.ViciousCleanup = function()
    alive = false
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    releaseTravel(root)
    if typeof(antiLagRestore) == "function" then
        antiLagRestore()
    end
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Vichop",
    LoadingTitle = "Vichop",
    LoadingSubtitle = "alts hop without a vicious bee; main waits for calls",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "ViciousHive",
        FileName = "Settings"
    },
    ToggleUIKeybind = "J"
})

local Tab = Window:CreateTab("Home", 4483362458)
Tab:CreateSection("Room")
Tab:CreateInput({
    Name = "Main Username",
    PlaceholderText = "Your main account",
    CurrentValue = settings.mainUsername,
    Flag = "MainUsername",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        settings.mainUsername = Text or ""
        writeSaved()
    end
})
Tab:CreateInput({
    Name = "Room Code",
    PlaceholderText = "A code only your accounts know",
    CurrentValue = settings.roomCode,
    Flag = "RoomCode",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        settings.roomCode = Text or ""
        writeSaved()
    end
})
Tab:CreateButton({
    Name = "Bring Main (Test Teleport)",
    Callback = function()
        if isMain() then
            setStatus("Run this test from an alt account.")
            return
        end
        if serverHopInProgress then
            setStatus("Test unavailable: this alt is already server hopping.")
            return
        end
        local previousTestFlag = lastPublishedWasTest
        local previousHasCall = hasPublishedCall
        local previousLastPublish = lastPublish
        lastPublishedWasTest = true
        lastPublish = os.clock()
        phase = "seen"
        testCallHoldUntil = os.clock() + 30
        setStatus("Test button clicked. Sending a test call.")
        task.spawn(function()
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then
                testCallHoldUntil = 0
                lastPublishedWasTest = previousTestFlag
                hasPublishedCall = previousHasCall
                lastPublish = previousLastPublish
                setStatus("Test failed: your character is not loaded.")
                return
            end
            local zone = fieldOf(root.Position)
            local ok, sent, detail = pcall(publish, {
                who = player.Name,
                job = game.JobId,
                place = game.PlaceId,
                field = zone and zone.Name or "Connection Test",
                x = root.Position.X,
                y = root.Position.Y,
                z = root.Position.Z,
                at = os.time(),
                test = true
            })
            if not ok then
                testCallHoldUntil = 0
                lastPublishedWasTest = previousTestFlag
                hasPublishedCall = previousHasCall
                lastPublish = previousLastPublish
                setStatus("Test call error: " .. tostring(sent))
            elseif sent then
                lastPublish = os.clock()
                setStatus("Test call sent. Waiting for the main to join. " .. tostring(detail))
            else
                testCallHoldUntil = 0
                lastPublishedWasTest = previousTestFlag
                hasPublishedCall = previousHasCall
                lastPublish = previousLastPublish
                setStatus("Test call failed: " .. tostring(detail))
            end
        end)
    end
})
Tab:CreateSection("Performance")
Tab:CreateToggle({
    Name = "Disable ScreenGui and 3D rendering",
    CurrentValue = renderReductionEnabled,
    Flag = "RenderReduction_" .. string.lower(player.Name),
    Callback = function(Value)
        renderReductionEnabled = Value == true
        applyRenderingPreference()
    end
})
local readout = Tab:CreateParagraph({
    Title = "Status",
    Content = statusText
})

task.spawn(function()
    while alive do
        pcall(function()
            readout:Set({
                Title = "Status",
                Content = statusText .. "\nThis account: " .. player.Name .. (isMain() and " (main)" or " (alt)")
            })
        end)
        task.wait(0.5)
    end
end)

pcall(function()
    Rayfield:LoadConfiguration()
end)
applyRenderingPreference()
