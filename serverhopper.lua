-- Xeno-friendly Persistent Server Hopper
-- Auto-ON on execute, 15s countdown, persistent retry (tries many HTTP APIs commonly exposed by executors)
-- Paste into Xeno executor (Local client script)

local Players     = game:GetService("Players")
local TeleportSvc = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- CONFIG
local COUNTDOWN_TIME    = 15      -- seconds
local POLL_DELAY         = 0.8    -- wait between full scans/retries
local SERVER_PAGE_LIMIT  = 100

-- UI (compact modern)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "XenoServerHopper"
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
title.Text = "Server Hopper (Xeno)"

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
local enabled = true          -- auto-enabled on execute
local attemptCount = 0

-- Normalize responses (helpers)
local function normalizeResponse(resp)
    if not resp then return nil end
    if type(resp) == "string" then return resp end
    if type(resp) == "table" then
        -- many executors return a table with Body / body
        if resp.Body and type(resp.Body) == "string" then return resp.Body end
        if resp.body and type(resp.body) == "string" then return resp.body end
        -- some return {Success=true, Body=...}
        for k,v in pairs(resp) do
            if type(v) == "string" and #v > 0 then
                return v
            end
        end
    end
    return nil
end

-- Flexible HTTP GET that tries many common executor APIs (including Xeno variants).
local function httpGet(url)
    local tries = {
        -- synapse-style
        function() if syn and syn.request then return syn.request({Url = url, Method = "GET"}) end end,
        -- generic request
        function() if request then return request({Url = url, Method = "GET"}) end end,
        -- http.request
        function() if http and http.request then return http.request({Url = url, Method = "GET"}) end end,
        -- some executors expose http_request
        function() if http_request then return http_request({Url = url, Method = "GET"}) end end,
        -- some expose a http_get shortcut
        function() if http_get then return http_get(url) end end,
        -- xeno-specific attempts (common patterns)
        function() if xeno and type(xeno) == "table" and xeno.request then return xeno.request({Url = url, Method = "GET"}) end end,
        function() if Xeno and type(Xeno) == "table" and Xeno.request then return Xeno.request({Url = url, Method = "GET"}) end end,
        function() if Xeno and type(Xeno) == "table" and Xeno.HttpGet then return Xeno.HttpGet(url) end end,
        function() if xeno and type(xeno) == "table" and xeno.HttpGet then return xeno.HttpGet(url) end end,
        -- some wrappers store request under `.http` or `.http_request`
        function() if _G and _G.http_request then return _G.http_request({Url = url, Method = "GET"}) end end,
        -- fallback to Roblox HttpService:GetAsync (may fail depending on environment/permissions)
        function() return HttpService:GetAsync(url) end
    }

    for _,fn in ipairs(tries) do
        local ok, res = pcall(fn)
        if ok and res then
            local norm = normalizeResponse(res)
            if norm then
                return norm
            end
        end
    end

    error("No HTTP request method available in this execution environment.")
end

-- Core: persistent server hop loop (will attempt teleport to ANY instance id found, ignoring "full"/restricted)
local function serverHopLoop()
    local placeId = tostring(game.PlaceId)
    local myJobId = tostring(game.JobId)
    local baseUrl = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=" .. tostring(SERVER_PAGE_LIMIT)

    while enabled do
        local cursor = nil
        repeat
            if not enabled then return end
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
                if not enabled then return end
                -- server.id is typical. Some endpoints have different keys; attempt several.
                local serverId = tostring(server.id or server.playbackCloudId or server.idValue or "")
                if serverId ~= "" and serverId ~= myJobId then
                    attemptCount = attemptCount + 1
                    attemptsLabel.Text = "Attempts: " .. tostring(attemptCount)

                    -- attempt teleport and ignore errors (we deliberately keep trying)
                    pcall(function()
                        TeleportSvc:TeleportToPlaceInstance(tonumber(placeId), serverId, LocalPlayer)
                    end)

                    wait(0.12)
                end
            end

            cursor = data.nextPageCursor
            wait(0.05)
        until not cursor or not enabled

        if enabled then
            wait(POLL_DELAY)
        end
    end
end

-- Countdown + start
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
    if not ok and enabled then
        countdownLabel.Text = "ERROR"
        warn("Server hop loop error:", err)
        wait(1)
        if enabled then countdownLabel.Text = "READY" else countdownLabel.Text = "OFF" end
    end
end

-- Toggle UI handler
toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    if enabled then
        toggleBtn.Text = "ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(54,170,120)
        attemptCount = 0
        attemptsLabel.Text = "Attempts: 0"
        countdownLabel.Text = tostring(COUNTDOWN_TIME) .. "s"
        spawn(startCountdownAndHop)
    else
        toggleBtn.Text = "OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(36,36,42)
        countdownLabel.Text = "OFF"
    end
end)

-- Auto-start on execute
enabled = true
toggleBtn.Text = "ON"
toggleBtn.BackgroundColor3 = Color3.fromRGB(54,170,120)
attemptCount = 0
attemptsLabel.Text = "Attempts: 0"
countdownLabel.Text = tostring(COUNTDOWN_TIME) .. "s"
spawn(startCountdownAndHop)
