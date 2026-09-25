-- CARXAC Control Center — runtime config, detection history, system health
-- Server is authoritative. NUI is never trusted.

local RESOURCE = GetCurrentResourceName()
local RUNTIME_FILE = "data/runtime.json"
local DETECTION_LIMIT = 250
local CONFIG_LOG_LIMIT = 100

local detectionHistory = {} -- newest first
local configChangeLog = {}
local sessionCounters = {
    detections = 0,
    kicks = 0,
    bans = 0,
    warns = 0,
    logs = 0,
}

local function isAdmin(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    if type(CARXAC_GETADMINS) == "function" then
        return CARXAC_GETADMINS(src) == true
    end
    return false
end

local function punishUnauthorized(src, detail)
    if type(CARXAC_ACTION) == "function" then
        local action = (CARXAC.AdminMenu and CARXAC.AdminMenu.MenuPunishment) or "BAN"
        CARXAC_ACTION(src, action, "Anti Open Admin Menu", detail or "Unauthorized control center request")
    end
end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local n = {}
    for k, v in pairs(t) do
        n[k] = deepCopy(v)
    end
    return n
end

local function loadRuntimeOverrides()
    local raw = LoadResourceFile(RESOURCE, RUNTIME_FILE)
    if not raw or raw == "" then return {} end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= "table" then
        print("^3[CARXAC]^0 runtime.json could not be parsed; ignoring overrides.")
        return {}
    end
    return data
end

local function saveRuntimeOverrides(overrides)
    local payload = json.encode(overrides or {})
    if not payload then return false end
    return SaveResourceFile(RESOURCE, RUNTIME_FILE, payload, -1) == true
end

local function applyOverrideValue(setting, value)
    if not setting then return false, "unknown_setting" end
    local t = setting.type

    if t == "bool" then
        if type(value) ~= "boolean" then
            if value == 1 or value == "1" or value == "true" then value = true
            elseif value == 0 or value == "0" or value == "false" then value = false
            else return false, "invalid_bool" end
        end
        CARXAC_SchemaSet(setting.path, value)
        return true
    end

    if t == "number" then
        local n = tonumber(value)
        if not n then return false, "invalid_number" end
        if setting.min and n < setting.min then n = setting.min end
        if setting.max and n > setting.max then n = setting.max end
        n = math.floor(n + 0.0)
        CARXAC_SchemaSet(setting.path, n)
        return true
    end

    if t == "punishment" then
        local a = tostring(value or ""):upper()
        local allowed = false
        for _, p in ipairs(CARXAC_SCHEMA.punishments or {}) do
            if p == a then allowed = true break end
        end
        if not allowed then return false, "invalid_punishment" end
        -- LOG is treated as WARN for runtime action path (CARXAC_ACTION accepts WARN/KICK/BAN)
        CARXAC_SchemaSet(setting.path, a == "LOG" and "WARN" or a)
        return true
    end

    if t == "string" then
        local s = tostring(value or "")
        if #s > 120 then s = s:sub(1, 120) end
        CARXAC_SchemaSet(setting.path, s)
        return true
    end

    return false, "unsupported_type"
end

local function applyAllOverrides(overrides)
    if type(overrides) ~= "table" then return 0 end
    local count = 0
    for key, value in pairs(overrides) do
        local setting = CARXAC_SchemaFind(key)
        if setting then
            local ok = applyOverrideValue(setting, value)
            if ok then count = count + 1 end
        end
    end
    return count
end

-- Snapshot of schema keys → values taken before any runtime overrides (for reset)
local BASELINE_SNAPSHOT = nil

local function captureBaseline()
    if type(CARXAC_SchemaSnapshot) ~= "function" then return end
    BASELINE_SNAPSHOT = CARXAC_SchemaSnapshot()
end

function CARXAC_LoadRuntimeConfig()
    if not BASELINE_SNAPSHOT then
        captureBaseline()
    end
    local overrides = loadRuntimeOverrides()
    local applied = applyAllOverrides(overrides)
    if applied > 0 then
        print(("^2[CARXAC]^0 Applied %s runtime configuration override(s)."):format(applied))
    end
    return applied
end

--- Clear runtime overrides and restore in-memory config to baseline immediately
function CARXAC_ResetRuntimeConfig()
    if not BASELINE_SNAPSHOT then
        captureBaseline()
    end
    saveRuntimeOverrides({})
    local restored = 0
    if type(BASELINE_SNAPSHOT) == "table" and type(CARXAC_SchemaFind) == "function" then
        for key, value in pairs(BASELINE_SNAPSHOT) do
            local setting = CARXAC_SchemaFind(key)
            if setting then
                local ok = applyOverrideValue(setting, value)
                if ok then restored = restored + 1 end
            end
        end
    end
    print(("^2[CARXAC]^0 Runtime config reset — restored %s baseline setting(s)."):format(restored))
    return restored
end

local function severityForAction(action)
    action = tostring(action or "WARN"):upper()
    if action == "BAN" then return "CRITICAL" end
    if action == "KICK" then return "HIGH" end
    if action == "WARN" then return "MEDIUM" end
    return "LOW"
end

function CARXAC_LogDetection(src, action, reason, details)
    local playerName = (src and GetPlayerName(src)) or "Unknown"
    local entry = {
        id = (#detectionHistory + 1) .. "-" .. (os.time()),
        player = playerName,
        serverId = tonumber(src) or 0,
        detection = tostring(reason or "Unknown"),
        details = tostring(details or ""),
        action = tostring(action or "WARN"):upper(),
        severity = severityForAction(action),
        time = os.date("%Y-%m-%d %H:%M:%S"),
        ts = os.time(),
        status = "COMPLETED",
    }

    table.insert(detectionHistory, 1, entry)
    while #detectionHistory > DETECTION_LIMIT do
        table.remove(detectionHistory)
    end

    sessionCounters.detections = sessionCounters.detections + 1
    local a = entry.action
    if a == "BAN" then sessionCounters.bans = sessionCounters.bans + 1
    elseif a == "KICK" then sessionCounters.kicks = sessionCounters.kicks + 1
    elseif a == "WARN" then sessionCounters.warns = sessionCounters.warns + 1
    else sessionCounters.logs = sessionCounters.logs + 1 end

    -- Push live feed to online admins
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id and isAdmin(id) then
            TriggerClientEvent("CARXAC:liveDetection", id, entry)
        end
    end

    -- Optional DB persist (fail-soft)
    if MySQL and MySQL.Async and MySQL.Async.execute then
        pcall(function()
            MySQL.Async.execute(
                "INSERT INTO carxac_detections (player_name, server_id, detection, details, action, severity, created_at) VALUES (@n, @sid, @d, @det, @a, @sev, NOW())",
                {
                    ["@n"] = entry.player,
                    ["@sid"] = entry.serverId,
                    ["@d"] = entry.detection,
                    ["@det"] = entry.details,
                    ["@a"] = entry.action,
                    ["@sev"] = entry.severity,
                }
            )
        end)
    end

    return entry
end

local function pushConfigLog(adminName, adminSrc, key, oldVal, newVal)
    local entry = {
        admin = adminName or "Unknown",
        adminId = tonumber(adminSrc) or 0,
        key = tostring(key),
        oldValue = tostring(oldVal),
        newValue = tostring(newVal),
        time = os.date("%Y-%m-%d %H:%M:%S"),
        ts = os.time(),
    }
    table.insert(configChangeLog, 1, entry)
    while #configChangeLog > CONFIG_LOG_LIMIT do
        table.remove(configChangeLog)
    end
end

local function protectionStatus()
    return {
        godmode = CARXAC.AntiGodMode == true,
        invisible = CARXAC.AntiInvisible == true,
        noclip = CARXAC.AntiNoclip == true,
        superjump = CARXAC.AntiSuperJump == true,
        teleport = CARXAC.AntiTeleport == true,
        speed = CARXAC.AntiChangeSpeed == true,
        freecam = CARXAC.AntiFreeCam == true,
        spectate = CARXAC.AntiSpectate == true,
        weapon = CARXAC.AntiBlackListWeapon == true,
        damage = CARXAC.AntiWeaponDamageChanger == true,
        vehicle = CARXAC.AntiBlackListVehicle == true,
        entity = CARXAC.AntiBlackListObject == true or CARXAC.AntiBlackListPed == true,
        explosion = CARXAC.AntiExplosionSpam == true,
        event = CARXAC.AntiSpamTrigger == true or CARXAC.AntiBlackListTrigger == true,
        chat = CARXAC.AntiSpamChat == true,
        inject = CARXAC.AntiInject == true,
    }
end

local function systemHealth()
    local webhookOk = false
    if CARXAC.Webhooks and type(CARXAC.Webhooks.Ban) == "string" and CARXAC.Webhooks.Ban:match("^https?://") then
        webhookOk = true
    end
    local dbOk = GetResourceState("oxmysql") == "started"
    return {
        core = true,
        clientMonitoring = true,
        serverMonitoring = true,
        eventProtection = CARXAC.AntiSpamTrigger == true or CARXAC.AntiBlackListTrigger == true,
        database = dbOk,
        webhook = webhookOk,
        nui = true,
        version = tostring(CARXAC.Version or "1.0.0"),
        resource = RESOURCE,
        players = #GetPlayers(),
    }
end

local function dashboardPayload()
    local players = #GetPlayers()
    local vehicles, peds, objects = 0, 0, 0
    -- Prefer counts already computed by main server if available via events; lightweight entity count is expensive — skip native enumeration.
    return {
        players = players,
        detections = sessionCounters.detections,
        kicks = sessionCounters.kicks,
        bans = sessionCounters.bans,
        warns = sessionCounters.warns,
        protection = protectionStatus(),
        health = systemHealth(),
        live = { table.unpack(detectionHistory, 1, math.min(15, #detectionHistory)) },
        version = tostring(CARXAC.Version or "1.0.0"),
    }
end

-- ========== Events ==========

RegisterNetEvent("CARXAC:cc:getDashboard", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getDashboard") return end
    TriggerClientEvent("CARXAC:cc:dashboard", src, dashboardPayload())
end)

RegisterNetEvent("CARXAC:cc:getConfig", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getConfig") return end
    TriggerClientEvent("CARXAC:cc:config", src, {
        schema = CARXAC_SCHEMA,
        values = CARXAC_SchemaSnapshot(),
        punishments = CARXAC_SCHEMA.punishments,
    })
end)

RegisterNetEvent("CARXAC:cc:saveConfig", function(changes)
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "saveConfig") return end
    if type(changes) ~= "table" then
        TriggerClientEvent("CARXAC:cc:toast", src, { type = "error", title = "Save failed", message = "Invalid payload" })
        return
    end

    local overrides = loadRuntimeOverrides()
    local applied = 0
    local adminName = GetPlayerName(src) or ("ID " .. src)

    for key, value in pairs(changes) do
        local setting = CARXAC_SchemaFind(key)
        if setting then
            local oldVal = CARXAC_SchemaGet(setting.path)
            local ok, err = applyOverrideValue(setting, value)
            if ok then
                overrides[key] = CARXAC_SchemaGet(setting.path)
                pushConfigLog(adminName, src, key, oldVal, overrides[key])
                applied = applied + 1
            else
                print(("^3[CARXAC]^0 Config reject %s: %s"):format(tostring(key), tostring(err)))
            end
        end
    end

    local saved = saveRuntimeOverrides(overrides)
    TriggerClientEvent("CARXAC:cc:toast", src, {
        type = saved and "success" or "error",
        title = saved and "Configuration saved" or "Save error",
        message = saved and (("%s setting(s) updated"):format(applied)) or "Could not write runtime.json",
    })
    TriggerClientEvent("CARXAC:cc:config", src, {
        schema = CARXAC_SCHEMA,
        values = CARXAC_SchemaSnapshot(),
        punishments = CARXAC_SCHEMA.punishments,
    })
    print(("^2[CARXAC]^0 %s saved %s config change(s)."):format(adminName, applied))
end)

RegisterNetEvent("CARXAC:cc:resetConfig", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "resetConfig") return end
    local restored = CARXAC_ResetRuntimeConfig()
    TriggerClientEvent("CARXAC:cc:toast", src, {
        type = "success",
        title = "Configuration reset",
        message = ("Restored %s baseline setting(s). Active now — no restart required."):format(restored),
    })
    TriggerClientEvent("CARXAC:cc:config", src, {
        schema = CARXAC_SCHEMA,
        values = CARXAC_SchemaSnapshot(),
        punishments = CARXAC_SCHEMA.punishments,
    })
    local adminName = GetPlayerName(src) or ("ID " .. src)
    pushConfigLog(adminName, src, "*", "runtime", "reset_to_baseline")
    print(("^2[CARXAC]^0 %s reset runtime config to baseline (%s keys)."):format(adminName, restored))
end)

RegisterNetEvent("CARXAC:cc:getDetections", function(request)
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getDetections") return end
    request = type(request) == "table" and request or {}
    local search = tostring(request.search or ""):lower()
    local severity = tostring(request.severity or ""):upper()
    local action = tostring(request.action or ""):upper()
    local page = math.max(1, tonumber(request.page) or 1)
    local pageSize = math.min(50, math.max(10, tonumber(request.pageSize) or 25))

    local filtered = {}
    for _, e in ipairs(detectionHistory) do
        local ok = true
        if search ~= "" then
            local hay = (e.player .. " " .. e.detection .. " " .. tostring(e.serverId)):lower()
            if not hay:find(search, 1, true) then ok = false end
        end
        if ok and severity ~= "" and severity ~= "ALL" and e.severity ~= severity then ok = false end
        if ok and action ~= "" and action ~= "ALL" and e.action ~= action then ok = false end
        if ok then filtered[#filtered + 1] = e end
    end

    local total = #filtered
    local startIdx = (page - 1) * pageSize + 1
    local slice = {}
    for i = startIdx, math.min(total, startIdx + pageSize - 1) do
        slice[#slice + 1] = filtered[i]
    end

    TriggerClientEvent("CARXAC:cc:detections", src, {
        rows = slice,
        total = total,
        page = page,
        pageSize = pageSize,
    })
end)

RegisterNetEvent("CARXAC:cc:getConfigLog", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getConfigLog") return end
    TriggerClientEvent("CARXAC:cc:configLog", src, configChangeLog)
end)

RegisterNetEvent("CARXAC:cc:getHealth", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getHealth") return end
    TriggerClientEvent("CARXAC:cc:health", src, systemHealth())
end)

RegisterNetEvent("CARXAC:cc:getPlayers", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getPlayers") return end
    local list = {}
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id then
            local detCount = 0
            for _, e in ipairs(detectionHistory) do
                if e.serverId == id then detCount = detCount + 1 end
            end
            list[#list + 1] = {
                id = id,
                name = GetPlayerName(id) or ("ID " .. id),
                ping = GetPlayerPing(id) or 0,
                isAdmin = isAdmin(id),
                detections = detCount,
            }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    TriggerClientEvent("CARXAC:cc:players", src, list)
end)

-- Blacklist tables (read-only from tables/*.lua for NUI display)
RegisterNetEvent("CARXAC:cc:getBlacklists", function()
    local src = source
    if not isAdmin(src) then punishUnauthorized(src, "getBlacklists") return end
    TriggerClientEvent("CARXAC:cc:blacklists", src, {
        weapons = Weapon or {},
        vehicles = Vehicle or {},
        peds = Peds or {},
        objects = Objects or {},
        events = Events or {},
        words = Words or {},
        commands = Commands or {},
        plates = Plate or {},
    })
end)

CreateThread(function()
    Wait(500)
    if type(CARXAC_SCHEMA) == "table" then
        CARXAC_LoadRuntimeConfig()
    else
        print("^1[CARXAC]^0 Schema missing; Control Center config disabled.")
    end
end)

print("^2[CARXAC]^0 Control Center server module loaded.")
