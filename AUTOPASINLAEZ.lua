-- AutoJoiner direct (WebSocket Only)
-- By EMPIREUHQ

-- Configuration
local WebSocketURL = "ws://127.0.0.1:51948"
local DefaultPlaceId = 109983668079237 -- ID de place en tant que NOMBRE

-- Services
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- --- Fonctions Utilitaires ---

local function prints(str)
	print("[AutoJoiner]: " .. tostring(str))
end

-- Tente de joindre la partie avec l'ID du serveur (jobId)
local function joinJob(jobId)
	if not jobId or jobId == "" then
		prints("JobID manquant ou invalide.")
		return
	end

	prints("Teleporting to place " .. DefaultPlaceId .. " with jobId " .. jobId)
	
	-- Utilisation de la syntaxe la plus simple
	TeleportService:TeleportToPlaceInstance(DefaultPlaceId, jobId)
end

-- Tente de trouver et connecter une API WebSocket disponible
local function tryWebSocketConnect(url)
	local connectFnCandidates = {
		function() return syn and syn.websocket and syn.websocket.connect end,
		function() return WebSocket and WebSocket.connect end,
		function() return websocket and websocket.connect end,
	}

	for _, getFn in ipairs(connectFnCandidates) do
		local success, connectFn = pcall(getFn)
		if success and type(connectFn) == "function" then
			local suc, socket = pcall(connectFn, url)
			if suc and socket then
				prints("WebSocket connected via detected API")
				return socket
			end
		end
	end
	return nil
end

-- Handler de message principal
local function messageHandler(data)
	local msg = tostring(data)
	
	-- Retire le préfixe "connect:"
	if msg:match("^connect:") then
		local jobId = msg:sub(msg:find(":") + 1)
		
		if jobId:match("^[%w%-]+$") then
			joinJob(jobId)
			return
		end
	end

	-- Exécution de script (si ce n'est pas une commande de connexion)
	if msg:find("TeleportService") or msg:find("function") or msg:find("game:") then
		prints("Received raw script payload -> executing (NOT RECOMMENDED)")
		local func, err = loadstring(msg)
		if func then
			local ok, result = pcall(func)
			if not ok then
				prints("Error while executing script: " .. tostring(result))
			end
		end
	else
		prints("Received UNKNOWN message: " .. msg)
	end
end

-- --- Démarrage principal ---

local function connectMain()
	prints("Starting connect procedure...")
	repeat task.wait() until game:IsLoaded()

	local ws = tryWebSocketConnect(WebSocketURL)
	
	if not ws then
		prints("FATAL: WebSocket API not found or connection failed. Check executor support.")
		return
	end

	-- Gestion des messages entrants (méthode événementielle)
	if ws.OnMessage and type(ws.OnMessage.Connect) == "function" then
		ws.OnMessage:Connect(messageHandler)
		prints("Connected to WebSocket (Event-based)")

	-- Gestion des messages entrants (méthode de boucle manuelle)
	else
		task.spawn(function()
			prints("Connected to WebSocket (Manual loop)")
			while true do
				local ok, data = pcall(function() return ws:Receive() end)
				if ok and data then
					messageHandler(data)
				end
				task.wait(0.1)
			end
		end)
	end

	-- Gestion de la déconnexion
	if ws.OnClose and type(ws.OnClose.Connect) == "function" then
		ws.OnClose:Connect(function()
			prints("WebSocket closed, restarting...")
			task.wait(3)
			connectMain()
		end)
	end
end

-- Point d'entrée pour la robustesse
local success, errorMessage = pcall(connectMain)
if not success then
	prints("CRITICAL ERROR during execution: " .. tostring(errorMessage))
end
