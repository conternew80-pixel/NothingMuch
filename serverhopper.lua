-- serverhopper.lua (CORE patched)
-- Host this file as a PUBLIC raw file (Pastebin raw, public GitHub raw, Hastebin)
-- Do NOT include a ?token=... in the URL when using the loader.

if getgenv().SERVER_HOPPER_RUNNING then
    return
end
getgenv().SERVER_HOPPER_RUNNING = true

-- == Config ==
local COUNTDOWN_TIME = 15
local POLL_DELAY = 0.8
local SERVER_PAGE_LIMIT = 100
local TELEPORT_FAIL_COOLDOWN = 3 -- seconds

-- Services
local Players     = game:GetService("Players")
local TeleportSvc = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- UI creation (compact modern)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PersistentServerHopperCore"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local holder = Instance.new("Frame", screenGui)
holder.Name = "Holder"
holder.Size = UDim2.new(0, 260, 0, 120)
holder.Position = UDim2.new(0.5, -130, 0.08, 0)
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.BackgroundColor3 = Color3.fromRGB(18,18,22)
holder.BorderSizePixel = 0
local UICorner = Instance.new("UICorner", holder); UICorner.CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel", holder)
title.Size = UDim2.new(1, -20, 0, 28)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamSemibold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(230,230,230)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Server Hopper"

local countdownLabel = Instance.new("TextLabel", holder)
countdownLabel.Size = UDim2.new(1, -20, 0, 36)
countdownLabel.Position = UDim2.new(0, 10, 0, 36)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Font = Enum.Font.Gotham
countdownLabel.TextSize = 20
countdownLabel.TextColor3 = Color3.fromRGB(200,200,200)
countdownLabel.TextXAlignment = Enum.TextXAlignment.Center
countdownLabel.Text = "OFF"

local attemptsLabel = Instance.new("TextLabel", holder)
attemptsLabel.Size = UDim2.new(1, -20, 0, 16)
attemptsLabel.Position = UDim2.new(0, 10, 0, 76)
attemptsLabel.BackgroundTransparency = 1
attemptsLabel.Font = Enum.Font.Gotham
attemptsLabel.TextSize = 12
attemptsLabel.TextColor3 = Color3.fromRGB(170,170,170)
attemptsLabel.TextXAlignment = Enum.TextXAlignment.Left
attemptsLabel.Text = "Attempts: 0"

local toggleBtn = Instance.new("TextButton", holder)
toggleBtn.Size = UDim2.new(0, 68, 0, 30)
toggleBtn.Position = UDim2.new(1, -80, 0, 10)
toggleBtn.BackgroundColor3 = Color3.fromRGB(54,170,120)
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.GothamSemibold
toggleBtn.TextSize = 14
toggleBtn.Text = "ON"
toggleBtn.TextColor3 = Color3.fromRGB(240,240,240)
local btnCorner = Instance.new("UICorner", toggleBtn); btnCorner.CornerRadius = UDim.new(0,10)
toggleBtn.Parent = holder

-- State
local enabled = true       -- auto-enabled on execute
local attemptCount = 0
local teleporting = false
local teleportCooldown = false

-- Xeno/executor-friendly HTTP GET
local function normalizeResponse(resp)
    if not resp then return nil end
    if type(resp) == "string" then return resp end
    if type(resp) == "table" then
        if resp.Body and type(resp.Body) == "string" then return resp.Body end
        if resp.body and type(resp.body) == "string" then return resp.body end
        for k,v in pairs(resp) do
            if type(v) == "string" and #v > 0 then return v end
        end
    end
    return nil
end

local function httpGet(url)
    local tries = {
        function() if syn and syn.request then return syn.request({Url = url, Method = "GET"}) end end,
        function() if request then return request({Url = url, Method = "GET"}) end end,
        function() if http and http.request then return http.request({Url = url, Method = "GET"}) end end,
        function() if http_request then return http_request({Url = url, Method = "GET"}) end end,
        function() if http_get then return http_get(url) end end,
        function() if xeno and type(xeno) == "table" and xeno.request then return xeno.request({Url = url, Method = "GET"}) end end,
        function() if Xeno and type(Xeno) == "table" and Xeno.request then return Xeno.request({Url = url, Method = "GET"}) end end,
        function() if Xeno and type(Xeno) == "table" and Xeno.HttpGet then return Xeno.HttpGet(url) end end,
        function() if xeno and type(xeno) == "table" and xeno.HttpGet then return xeno.HttpGet(url) end end,
        function() if _G and _G.http_request then return _G.http_request({Url = url, Method = "GET"}) end end,
        function() return HttpService:GetAsync(url) end
    }

    for _,fn in ipairs(tries) do
        local ok, res = pcall(fn)
        if ok and res then
            local norm = normalizeResponse(res)
            if norm then return norm end
        end
    end

    error("No HTTP request method available in this execution environment.")
end

-- Attempt teleport safely
local function tryTeleportToServer(placeId, serverId)
    if teleporting or teleportCooldown then return end
    teleporting = true
    enabled = false
    pcall(function()
        TeleportSvc:TeleportToPlaceInstance(tonumber(placeId), serverId, LocalPlayer)
    end)
end

-- Handle teleport failure
pcall(function()
    if TeleportSvc and TeleportSvc.TeleportInitFailed then
        TeleportSvc.TeleportInitFailed:Connect(function()
            if teleportCooldown then return end
            teleporting = false
            teleportCooldown = true
            task.delay(TELEPORT_FAIL_COOLDOWN, function()
                teleportCooldown = false
                enabled = true
            end)
        end)
    end
end)

-- Persistent server hop loop
local function serverHopLoop()
    local placeId = tostring(game.PlaceId)
    local myJobId = tostring(game.JobId)
    local baseUrl = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=" .. tostring(SERVER_PAGE_LIMIT)

    while enabled do
        if teleporting or teleportCooldown then break end
        local cursor = nil

        repeat
            if not enabled or teleporting or teleportCooldown then return end

            local url = baseUrl
            if cursor and #cursor > 0 then
                url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
            end

            local ok, body = pcall(function() return httpGet(url) end)
            if not ok or not body then
                attemptCount = attemptCount + 1
                attemptsLabel.Text = "Attempts: " .. tostring(attemptCount)
                wait(0.3)
                break
            end

            local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not ok2 or type(data) ~= "table" or type(data.data) ~= "table" then
                attemptCount = attemptCount + 1
                attemptsLabel.Text = "Attempts: " .. tostring(attemptCount)
                wait(0.25)
                break
            end

            for _, server in ipairs(data.data) do
                if not enabled or teleporting or teleportCooldown then return end
                local serverId = tostring(server.id or server.playbackCloudId or server.idValue or "")
                if serverId ~= "" and serverId ~= myJobId then
                    attemptCount = attemptCount + 1
                    attemptsLabel.Text = "Attempts: " .. tostring(attemptCount)
                    tryTeleportToServer(placeId, serverId)
                    wait(0.12)
                end
            end

            cursor = data.nextPageCursor
            wait(0.05)
        until not cursor or not enabled

        if enabled and not teleporting and not teleportCooldown then
            wait(POLL_DELAY)
        end
    end
end

-- Countdown routine
local function startCountdownAndHop()
    local remaining = COUNTDOWN_TIME
    countdownLabel.Text = tostring(math.ceil(remaining)) .. "s"
    while remaining > 0 do
        if not enabled then
            countdownLabel.Text = "OFF"
            return
        end
        wait(0.1)
        remaining = remaining - 0.1
        countdownLabel.Text = tostring(math.ceil(math.max(0, remaining))) .. "s"
    end

    countdownLabel.Text = "HOPPING..."
    local ok, err = pcall(serverHopLoop)
    if not ok then
        countdownLabel.Text = "ERROR"
        warn("Server hop loop error:", err)
        wait(1)
        if enabled then countdownLabel.Text = "READY" else countdownLabel.Text = "OFF" end
    end
end

-- Toggle handler
toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    if enabled then
        toggleBtn.Text = "ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(54,170,120)
        attemptCount = 0
        attemptsLabel.Text = "Attempts: 0"
        spawn(startCountdownAndHop)
    else
        toggleBtn.Text = "OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(36,36,42)
        countdownLabel.Text = "OFF"
    end
end)

-- Auto-start
countdownLabel.Text = tostring(COUNTDOWN_TIME) .. "s"
attemptsLabel.Text = "Attempts: 0"
spawn(startCountdownAndHop)
