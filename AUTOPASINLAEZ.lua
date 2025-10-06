-- AutoJoiner direct (WebSocket/HTTP fallback)
-- By EMPIREUHQ

repeat task.wait() until game:IsLoaded()

local WebSocketURL = "ws://127.0.0.1:51948"
local PollURL      = "http://127.0.0.1:51948/poll"

local function prints(str)
    print("[AutoJoiner]: " .. tostring(str))
end

-- rejoindre directement avec placeId + jobId
local function joinJob(msg)
    local s = tostring(msg)

    local placeId = s:match("[&?]placeID=(%d+)")
    local jobId   = s:match("[&?]gameInstanceId=([%w%-]+)")

    -- si on reçoit juste un jobId, utiliser ton placeId par défaut
    if (not placeId or not jobId) and s:match("^%w[%w%-]+$") then
        placeId = "109983668079237" -- ton jeu par défaut
        jobId   = s
    end

    if not placeId or not jobId then
        prints("Impossible d'extraire placeId / jobId depuis: " .. s)
        return
    end

    prints("Teleporting to place " .. placeId .. " with jobId " .. jobId)

    local TeleportService = game:GetService("TeleportService")
    local Players = game:GetService("Players")

    TeleportService:TeleportToPlaceInstance(placeId, jobId, Players.LocalPlayer)
end

-- exécution directe d’un script reçu
local function justJoin(script)
    local func, err = loadstring(script)
    if func then
        local ok, result = pcall(func)
        if not ok then
            prints("Error while executing script: " .. tostring(result))
        end
    else
        prints("Some unexpected error: " .. tostring(err))
    end
end

-- helper HTTP GET
local function httpGet(url)
    if syn and syn.request then
        local ok, res = pcall(syn.request, {Url = url, Method = "GET"})
        if ok and res and res.Body then return res.Body end
    end
    if typeof(http) == "table" and http.request then
        local ok, res = pcall(http.request, {Url = url, Method = "GET"})
        if ok and res and res.Body then return res.Body end
    end
    if type(http_request) == "function" then
        local ok, res = pcall(http_request, {Url = url, Method = "GET"})
        if ok and res and res.Body then return res.Body end
    end
    if type(request) == "function" then
        local ok, res = pcall(request, {Url = url, Method = "GET"})
        if ok and res and res.Body then return res.Body end
    end
    return nil
end

-- tentative WebSocket multi-API
local function tryWebSocketConnect(url)
    local connectFnCandidates = {
        function() if syn and syn.websocket and syn.websocket.connect then return syn.websocket.connect end end,
        function() if WebSocket and WebSocket.connect then return WebSocket.connect end end,
        function() if xeno and xeno.websocket and xeno.websocket.connect then return xeno.websocket.connect end end,
        function() if websocket and websocket.connect then return websocket.connect end end,
    }

    for _, cand in ipairs(connectFnCandidates) do
        local ok, connectFn = pcall(cand)
        if ok and type(connectFn) == "function" then
            local suc, socket = pcall(connectFn, url)
            if suc and socket then
                prints("WebSocket connected via detected API")
                return socket
            end
        end
    end
    return nil
end

-- main connect
local function connect()
    prints("Starting connect procedure...")

    local ws = tryWebSocketConnect(WebSocketURL)
    if ws then
        if ws.OnMessage and type(ws.OnMessage.Connect) == "function" then
            ws.OnMessage:Connect(function(msg)
                local data = tostring(msg)
                if data:find("TeleportService") or data:find("function") or data:find("game:") then
                    prints("Received script payload -> executing")
                    justJoin(data)
                else
                    prints("Received join URL/ID -> joining job")
                    joinJob(data)
                end
            end)
        else
            task.spawn(function()
                while true do
                    local ok, data = pcall(function() return ws:Receive() end)
                    if ok and data then
                        local s = tostring(data)
                        if s:find("TeleportService") or s:find("function") or s:find("game:") then
                            prints("Received script payload -> executing")
                            justJoin(s)
                        else
                            prints("Received join URL/ID -> joining job")
                            joinJob(s)
                        end
                    else
                        task.wait(0.5)
                    end
                end
            end)
        end

        if ws.OnClose and type(ws.OnClose.Connect) == "function" then
            ws.OnClose:Connect(function()
                prints("WebSocket closed, reconnecting...")
                task.wait(1)
                connect()
            end)
        end

        prints("Connected to WebSocket")
        return
    end

    -- HTTP fallback
    prints("WebSocket unavailable — trying HTTP polling fallback.")
    local test = httpGet(PollURL)
    if not test then
        prints("Aucun mécanisme WebSocket/HTTP disponible dans ton executor.")
        return
    end

    prints("HTTP fallback actif — polling " .. PollURL)
    while true do
        local body = httpGet(PollURL)
        if body and body ~= "" then
            local s = tostring(body)
            if s:find("TeleportService") or s:find("function") or s:find("game:") then
                prints("Received script payload (via HTTP) -> executing")
                justJoin(s)
            else
                prints("Received join URL/ID (via HTTP) -> joining job")
                joinJob(s)
            end
        end
        task.wait(1)
    end
end

-- start
connect()
