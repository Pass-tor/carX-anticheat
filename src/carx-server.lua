-- CARXAC - Carx Anti-Cheat
-- Licensed under the GNU Affero General Public License v3.0

local COLORS = math.random(1, 9)
local SPAWNED = {}
local SPAMLIST = {}
local TEMP_WHITELIST = {}
local PLAYER_STATE = {}
local PERMISSION_CACHE = {}
local TRUSTED_ADMINS = {}
local RATE_BUCKETS = {} -- [src][bucket] = { count, windowStart }
local PED_AUTHORIZATIONS = {} -- [src] = { [modelHash] = expiresAt }
local invalidatePermissionCache

local function cfg(name, fallback)
    if CARXAC.Detection and CARXAC.Detection[name] ~= nil then
        return CARXAC.Detection[name]
    end
    return fallback
end

local function connectionCfg(name, fallback)
    if CARXAC.Connection and CARXAC.Connection[name] ~= nil then
        return CARXAC.Connection[name]
    end
    return fallback
end

local function runtimeCfg(name, fallback)
    if CARXAC.ServerRuntime and CARXAC.ServerRuntime[name] ~= nil then
        return CARXAC.ServerRuntime[name]
    end
    return fallback
end

local function monotonicMs()
    return GetGameTimer()
end

--- Server-authoritative player state machine
--- States: connecting → loading → ready → spawn_grace → monitoring → disconnecting
local function playerState(src)
    src = tonumber(src)
    if not src then return nil end
    if not PLAYER_STATE[src] then
        PLAYER_STATE[src] = {
            connectedAt = monotonicMs(),
            readyAt = 0,
            graceUntil = 0,
            spawnSerial = 0,
            spawnState = "connecting",
            lastSpawnAt = 0,
            lastReadyAt = 0,
            handshakeNonce = nil,
            handshakeUsed = false,
            handshakeIssuedAt = 0,
            detectionEnabled = false,
            violationCount = 0,
            suspicionScore = 0,
            reportWindowAt = 0,
            reportCount = 0,
            lastReasonAt = {},
            spawnNotifyCount = 0,
            spawnNotifyWindowAt = 0,
        }
    end
    return PLAYER_STATE[src]
end

--- Rate limit: returns true if ALLOWED, false if over limit
local function RateLimit(src, bucket, limit, windowMs)
    src = tonumber(src)
    if not src or type(bucket) ~= "string" then return false end
    limit = tonumber(limit) or 5
    windowMs = tonumber(windowMs) or 10000
    local t = monotonicMs()
    RATE_BUCKETS[src] = RATE_BUCKETS[src] or {}
    local b = RATE_BUCKETS[src][bucket]
    if not b or (t - b.windowStart) > windowMs then
        RATE_BUCKETS[src][bucket] = { count = 1, windowStart = t }
        return true
    end
    b.count = b.count + 1
    if b.count > limit then
        return false
    end
    return true
end

--- Centralized grace check — server state only
function IsDetectionGraceActive(src)
    src = tonumber(src)
    if not src then return true end
    local st = PLAYER_STATE[src]
    if not st then return true end -- not tracked yet → treat as grace
    if st.detectionEnabled ~= true then return true end
    if st.readyAt == 0 then return true end
    local t = monotonicMs()
    if t < (st.graceUntil or 0) then return true end
    return false
end

local function setSpawnGrace(src, durationMs, reason)
    local st = playerState(src)
    if not st then return false end
    durationMs = math.max(1000, math.min(tonumber(durationMs) or cfg("RespawnGraceMs", 15000), 120000))
    local untilTs = monotonicMs() + durationMs
    st.graceUntil = math.max(st.graceUntil or 0, untilTs)
    st.spawnState = "spawn_grace"
    st.detectionEnabled = false
    -- Schedule return to monitoring
    local serial = st.spawnSerial
    SetTimeout(durationMs + 50, function()
        local s = PLAYER_STATE[src]
        if not s or s.spawnSerial ~= serial then return end
        if monotonicMs() >= (s.graceUntil or 0) then
            s.spawnState = "monitoring"
            s.detectionEnabled = true
        end
    end)
    return true
end

local function issueHandshake(src)
    local st = playerState(src)
    if not st then return nil end
    -- Cryptographically weak but server-generated; not client-controlled
    local nonce = ("%s-%s-%s"):format(src, monotonicMs(), math.random(100000, 999999))
    st.handshakeNonce = nonce
    st.handshakeUsed = false
    st.handshakeIssuedAt = monotonicMs()
    st.spawnState = "loading"
    return nonce
end

local function resetPlayerState(src)
    src = tonumber(src)
    if not src then return end
    PLAYER_STATE[src] = nil
    RATE_BUCKETS[src] = nil
    PED_AUTHORIZATIONS[src] = nil
    SPAWNED[src] = nil
    TEMP_WHITELIST[src] = nil
    PERMISSION_CACHE[src] = nil
    TRUSTED_ADMINS[src] = nil
    SPAMLIST[src] = nil
end

AddEventHandler('playerConnecting', function()
    local st = playerState(source)
    if st then
        st.spawnState = "connecting"
        st.detectionEnabled = false
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    resetPlayerState(src)
end)

-- Issue handshake after player joins so client can complete ready flow
AddEventHandler('playerJoining', function()
    local src = tonumber(source)
    if not src then return end
    SetTimeout(1500, function()
        if not GetPlayerName(src) then return end
        local nonce = issueHandshake(src)
        if nonce then
            TriggerClientEvent("CARXAC:handshakeChallenge", src, nonce)
        end
    end)
end)

--- Secure ped-change authorization (server/resource only — NOT a client event)
exports("AuthorizePedChange", function(target, model, durationMs)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end
    local hash = type(model) == "number" and model or GetHashKey(tostring(model or ""))
    if not hash or hash == 0 then return false end
    durationMs = math.max(1000, math.min(tonumber(durationMs) or 30000, 300000))
    PED_AUTHORIZATIONS[target] = PED_AUTHORIZATIONS[target] or {}
    PED_AUTHORIZATIONS[target][hash] = monotonicMs() + durationMs
    setSpawnGrace(target, math.min(durationMs, cfg("PedChangeGraceMs", 12000)), "authorizedPedChange")
    TriggerClientEvent("CARXAC:clientGrace", target, math.min(durationMs, 60000))
    return true
end)

local function isPedChangeAuthorized(src, modelHash)
    src = tonumber(src)
    modelHash = tonumber(modelHash)
    if not src or not modelHash then return false end
    local auth = PED_AUTHORIZATIONS[src]
    if not auth then return false end
    local exp = auth[modelHash]
    if not exp then return false end
    if monotonicMs() > exp then
        auth[modelHash] = nil
        return false
    end
    return true
end

local function isAllowedPlayerModel(modelHash)
    modelHash = tonumber(modelHash)
    if not modelHash then return false end
    local list = CARXAC.AllowedPlayerModels
    if type(list) ~= "table" then
        -- Default freemode only when not configured
        return modelHash == GetHashKey("mp_m_freemode_01") or modelHash == GetHashKey("mp_f_freemode_01")
    end
    if list[modelHash] == true then return true end
    for k, v in pairs(list) do
        if v == true then
            local h = type(k) == "number" and k or GetHashKey(tostring(k))
            if h == modelHash then return true end
        end
    end
    return false
end

local function carxacNormalizeName(name)
    return tostring(name or ""):lower():gsub("[%s,%-%_]", "")
end

local DB_COLUMN_READY = {}
local function carxacDbName(value)
    local name = tostring(value or "Unknown")
    name = name:gsub("[%c]", " "):gsub("%s+", " "):sub(1, 96)
    if name == "" then name = "Unknown" end
    return name
end

local function carxacEnsureColumn(tableName, columnName, definition)
    tableName, columnName = tostring(tableName or ""), tostring(columnName or "")
    if tableName == "" or columnName == "" then return false end
    local key = tableName .. "." .. columnName
    if DB_COLUMN_READY[key] ~= nil then return DB_COLUMN_READY[key] end

    local p = promise.new()
    MySQL.Async.fetchAll(("SHOW COLUMNS FROM `%s` LIKE @column"):format(tableName), {
        ["@column"] = columnName
    }, function(rows)
        if rows and rows[1] then
            DB_COLUMN_READY[key] = true
            p:resolve(true)
            return
        end
        MySQL.Async.execute(("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(tableName, columnName, definition), {}, function(rowsChanged)
            DB_COLUMN_READY[key] = true
            p:resolve(true)
        end)
    end)
    return Citizen.Await(p)
end

local function carxacGrantActionGrace(target, durationMs, reason)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end
    durationMs = math.max(5000, math.min(tonumber(durationMs) or 30000, 600000))
    CARXAC_CHANGE_TEMP_WHHITELIST(target, true, durationMs)
    TriggerClientEvent("CARXAC:clientGrace", target, durationMs)
    local st = playerState(target)
    if st then st.graceUntil = math.max(st.graceUntil or 0, monotonicMs() + durationMs) end
    return true
end

local function CARXAC_PostConnectValidation(src, playerName)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end

    local okBan, banData = pcall(CARXAC_INBANLIST, src)
    if okBan and banData and banData[1] then
        local reason = tostring(banData[1].REASON or "Unknown")
        local banId = tostring(banData[1].BANID or "N/A")
        print(("^%sCARXAC^0: ^1Blocked banned player ^3%s^0 | Ban ID: %s"):format(COLORS, playerName or GetPlayerName(src) or src, banId))
        DropPlayer(src, ("\n[CARXAC]\nYou are banned from this server.\nReason: %s\nBan ID: #%s"):format(reason, banId))
        return
    elseif not okBan then
        local failMode = tostring(connectionCfg("BanCheckFailMode", "CLOSED")):upper()
        print(("^1[CARXAC]^0 Ban-list lookup failed post-connect (mode=%s)."):format(failMode))
        if failMode ~= "OPEN" then
            DropPlayer(src, "\n[CARXAC]\nConnection rejected: ban database temporarily unavailable.")
            return
        end
    end

    if CARXAC.Connection and CARXAC.Connection.AntiBlackListName and type(Names) == "table" then
        local normalizedName = carxacNormalizeName(playerName or GetPlayerName(src))
        for _, blocked in ipairs(Names) do
            local needle = carxacNormalizeName(blocked)
            if needle ~= "" and normalizedName:find(needle, 1, true) then
                DropPlayer(src, ("\n[CARXAC]\nYour player name contains a blocked term: %s"):format(tostring(blocked)))
                return
            end
        end
    end
end

AddEventHandler('playerJoining', function()
    local src = tonumber(source)
    if not src then return end
    SetTimeout(2500, function()
        CARXAC_PostConnectValidation(src, GetPlayerName(src))
    end)
end)

CreateThread(function()
    Wait(0)
    StartAntiCheat()
end)

local ALLOWED_REPORT_REASONS = {
    ["Anti Health Hack"] = function() return CARXAC.HealthPunishment end,
    ["Anti Armor Hack"] = function() return CARXAC.ArmorPunishment end,
    ["Anti Spectate"] = function() return CARXAC.SpectatePunishment or CARXAC.SpactatePunishment end,
    ["Anti Godmode"] = function() return CARXAC.GodPunishment end,
    ["Anti Invisible"] = function() return CARXAC.InvisiblePunishment end,
    ["Anti Tiny Ped"] = function() return CARXAC.PedFlagPunishment end,
    ["Anti Ped Changer"] = function() return CARXAC.PedChangePunishment end,
    ["Anti Free Cam"] = function() return CARXAC.CamPunishment end,
    ["Anti Teleport"] = function() return CARXAC.TeleportPunishment end,
    ["Anti Noclip"] = function() return CARXAC.NoclipPunishment end,
    ["Anti Black List Weapon"] = function() return CARXAC.WeaponPunishment end,
    ["Anti Weapon Damage Changer"] = function() return CARXAC.DamagePunishment or CARXAC.WeaponPunishment end,
    ["Anti Infinite Stamina"] = function() return CARXAC.InfinitePunishment end,
    ["Anti Night Vision"] = function() return CARXAC.VisionPunishment end,
    ["Anti Thermal Vision"] = function() return CARXAC.VisionPunishment end,
    ["Anti Black List Tasks"] = function() return CARXAC.TasksPunishment end,
    ["Anti Black List Animation"] = function() return CARXAC.AnimsPunishment end,
    ["Anti Plate Changer"] = function() return CARXAC.PlatePunishment end,
    ["Anti Black List Plate"] = function() return CARXAC.PlatePunishment end,
    ["Anti Rainbow"] = function() return CARXAC.RainbowPunishment end,
    ["Anti Speed Changer"] = function() return CARXAC.SpeedPunishment end,
    ["Anti Collected Pickup"] = function() return CARXAC.PickupPunishment end,
    ["Anti Suicide"] = function() return CARXAC.SuicidePunishment end,
}

local function acceptClientReport(src, requestedAction, reason, details)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return end
    if CARXAC_IS_TRUSTED and CARXAC_IS_TRUSTED(src) then return end
    if type(reason) ~= "string" then return end
    details = type(details) == "string" and details or tostring(details or "")
    if #reason > 80 or #details > 800 then return end

    -- Client reports are untrusted signals only — reason must be allowlisted
    local resolver = ALLOWED_REPORT_REASONS[reason]
    if not resolver then
        if not RateLimit(src, "bad_report", 3, 30000) then
            print(("^3[CARXAC]^0 Dropped invalid detection reason from %s: %s"):format(src, reason:sub(1, 40)))
        end
        return
    end

    if not RateLimit(src, "report", cfg("ServerReportLimit", 6), cfg("ServerReportWindowMs", 10000)) then
        return
    end

    -- Server grace is authoritative — never punish during grace
    if IsDetectionGraceActive(src) then return end

    local st = playerState(src)
    local t = monotonicMs()
    if not st or st.readyAt == 0 then return end

    local window = cfg("ServerReportWindowMs", 10000)
    local last = st.lastReasonAt[reason] or 0
    if t - last < window then return end
    st.lastReasonAt[reason] = t

    -- Suspicion accumulation (client signal alone is not enough for BAN on first hit)
    st.suspicionScore = (st.suspicionScore or 0) + 1
    st.violationCount = (st.violationCount or 0) + 1

    local action = tostring(resolver() or requestedAction or "WARN"):upper()
    if action ~= "WARN" and action ~= "KICK" and action ~= "BAN" then action = "WARN" end

    -- Require repeated evidence before BAN from client-only signals
    local banThreshold = tonumber(cfg("ClientBanEvidenceThreshold", 2)) or 2
    if action == "BAN" and (st.violationCount or 0) < banThreshold then
        action = "KICK"
    end

    if reason == "Anti Teleport" and CARXAC_ISNEARADMIN(src) then return end
    CARXAC_ACTION(src, action, reason, details)
end

--- SECURE clientReady: nonce handshake required. Client cannot reset grace by replaying.
RegisterNetEvent("CARXAC:clientReady", function(nonce, reason)
    local src = tonumber(source)
    local st = playerState(src)
    if not st then return end

    if not RateLimit(src, "clientReady", 3, 15000) then
        print(("^3[CARXAC]^0 Rate-limited clientReady from %s"):format(src))
        return
    end

    reason = tostring(reason or "unknown"):sub(1, 48)
    local connectedFor = monotonicMs() - (st.connectedAt or monotonicMs())
    local minimumMs = tonumber(cfg("MinimumClientReadyMs", 12000)) or 12000
    if connectedFor < minimumMs then
        return
    end

    -- Validate handshake nonce (server-issued only)
    local provided = tostring(nonce or "")
    if st.handshakeNonce == nil or st.handshakeUsed == true then
        -- Issue a new challenge; do not grant ready on bare calls
        local fresh = issueHandshake(src)
        if fresh then TriggerClientEvent("CARXAC:handshakeChallenge", src, fresh) end
        return
    end
    if provided == "" or provided ~= st.handshakeNonce then
        print(("^3[CARXAC]^0 Invalid ready nonce from %s"):format(src))
        return
    end
    -- Nonce max age 3 minutes
    if (monotonicMs() - (st.handshakeIssuedAt or 0)) > 180000 then
        local fresh = issueHandshake(src)
        if fresh then TriggerClientEvent("CARXAC:handshakeChallenge", src, fresh) end
        return
    end

    -- Prevent repeated ready resets once already monitoring
    if st.spawnState == "monitoring" and st.readyAt > 0 then
        local sinceReady = monotonicMs() - (st.lastReadyAt or st.readyAt)
        if sinceReady < (tonumber(cfg("ReadyReentryCooldownMs", 30000)) or 30000) then
            return
        end
    end

    st.handshakeUsed = true
    st.handshakeNonce = nil -- single use
    st.readyAt = monotonicMs()
    st.lastReadyAt = st.readyAt
    st.spawnSerial = (st.spawnSerial or 0) + 1 -- server owns serial
    SPAWNED[src] = true
    st.readyReason = reason
    st.spawnState = "spawn_grace"
    st.detectionEnabled = false
    -- Server decides grace duration — never client
    setSpawnGrace(src, cfg("PostReadyGraceMs", cfg("SpawnGraceMs", 20000)), "clientReady")
    TriggerClientEvent("CARXAC:clientGrace", src, cfg("PostReadyGraceMs", cfg("SpawnGraceMs", 20000)))
end)

--- Spawn notification: client may inform server it respawned, but server validates + rate-limits
RegisterNetEvent("CARXAC:spawnNotify", function(clientSerial)
    local src = tonumber(source)
    local st = playerState(src)
    if not st or st.readyAt == 0 then return end

    if not RateLimit(src, "spawn", 3, 12000) then
        return
    end

    local t = monotonicMs()
    local cooldown = tonumber(cfg("RespawnCooldownMs", 8000)) or 8000
    if st.lastSpawnAt > 0 and (t - st.lastSpawnAt) < cooldown then
        return -- ignore rapid respawn spam
    end

    -- Ignore stale / replayed client serials (client serial is informational only)
    clientSerial = tonumber(clientSerial) or 0
    if clientSerial > 0 and clientSerial < (st.spawnSerial or 0) then
        return
    end

    st.lastSpawnAt = t
    st.spawnSerial = (st.spawnSerial or 0) + 1
    SPAWNED[src] = true
    setSpawnGrace(src, cfg("RespawnGraceMs", 15000), "spawnNotify")
    TriggerClientEvent("CARXAC:clientGrace", src, cfg("RespawnGraceMs", 15000))
end)

-- Legacy event name kept but hardened (no longer grants unlimited grace)
RegisterNetEvent("CARXAC:AddToSpawnList", function()
    local src = tonumber(source)
    local st = playerState(src)
    if not st or st.readyAt == 0 then return end
    if not RateLimit(src, "spawn", 3, 12000) then return end
    local t = monotonicMs()
    local cooldown = tonumber(cfg("RespawnCooldownMs", 8000)) or 8000
    if st.lastSpawnAt > 0 and (t - st.lastSpawnAt) < cooldown then return end
    st.lastSpawnAt = t
    st.spawnSerial = (st.spawnSerial or 0) + 1
    SPAWNED[src] = true
    setSpawnGrace(src, cfg("RespawnGraceMs", 15000), "legacySpawnList")
end)

RegisterNetEvent("CARXAC:reportDetection", function(action, reason, details)
    acceptClientReport(source, action, reason, details)
end)

RegisterNetEvent("CARXAC:BanFromClient", function(action, reason, details)
    acceptClientReport(source, action, reason, tostring(details or "legacy report"))
end)

-- Client reports unauthorized ped model; server validates against allowlist + authorizations
RegisterNetEvent("CARXAC:reportPedChange", function(modelHash)
    local src = tonumber(source)
    if not src or not GetPlayerName(src) then return end
    if IsDetectionGraceActive(src) then return end
    if CARXAC_IS_TRUSTED and CARXAC_IS_TRUSTED(src) then return end
    if not RateLimit(src, "ped_report", 4, 20000) then return end

    modelHash = tonumber(modelHash)
    if not modelHash then return end

    if isPedChangeAuthorized(src, modelHash) then return end
    if isAllowedPlayerModel(modelHash) then return end

    -- Blacklist table still applies as high severity
    local blocked = false
    if type(Peds) == "table" then
        for _, name in ipairs(Peds) do
            if modelHash == GetHashKey(name) then blocked = true break end
        end
    end

    local action = tostring(CARXAC.PedChangePunishment or "WARN"):upper()
    if blocked then
        CARXAC_ACTION(src, action == "BAN" and "BAN" or action, "Anti Ped Changer",
            ("Blocked/blacklisted model: %s"):format(modelHash))
    else
        -- Unexpected non-allowlisted model — warn/kick path with evidence threshold
        acceptClientReport(src, action, "Anti Ped Changer", ("Unauthorized model: %s"):format(modelHash))
    end
end)

local function verifyInjectionReport(src, resource, info)
    src = tonumber(src)
    if not src or not CARXAC.AntiInject or type(resource) ~= "string" or type(info) ~= "string" then return end
    if CARXAC_IS_TRUSTED(src) then return end
    resource = resource:sub(1, 100)
    info = info:sub(1, 300)
    if resource ~= "" and GetResourceState(resource) == "missing" then
        CARXAC_ACTION(src, CARXAC.InjectPunishment, "Anti Inject",
            ("Unknown client resource `%s`: %s"):format(resource, info))
    end
end

RegisterNetEvent("CARXAC:BanForInject", function(_, details, resource)
    verifyInjectionReport(source, resource, tostring(details or "legacy report"))
end)

RegisterNetEvent("CARXAC:AntiInject", function(resource, info)
    verifyInjectionReport(source, resource, info)
end)

local function carxacHandleAdminCheck(src)
    src = tonumber(src)
    if not src then return end
    local menuOn = CARXAC.AdminMenu and CARXAC.AdminMenu.Enable == true
    local isAdmin = CARXAC_GETADMINS(src) == true
    local allowed = menuOn and isAdmin

    if not allowed then
        local name = GetPlayerName(src) or ("id:" .. tostring(src))
        local why = not menuOn and "AdminMenu.Enable=false"
            or "not txAdmin staff and not in admin group"
        print(("^3[CARXAC]^0 Admin check DENIED for %s (%s) — %s"):format(name, src, why))
        print("^3[CARXAC]^0 Fix: open txAdmin in-game menu once, OR in server.cfg:")
        print("^3[CARXAC]^0   add_principal identifier.license:YOUR_LICENSE group.admin")
        print("^3[CARXAC]^0   add_ace group.admin carxac.admin allow")
    else
        local name = GetPlayerName(src) or ("id:" .. tostring(src))
        print(("^2[CARXAC]^0 Admin check OK for %s (%s)"):format(name, src))
    end

    TriggerClientEvent("CARXAC:allowToOpen", src, allowed == true)
end

RegisterNetEvent("CARXAC:checkIsAdmin")
AddEventHandler("CARXAC:checkIsAdmin", function()
    carxacHandleAdminCheck(source)
end)

RegisterNetEvent("CARXAC:CheckIsAdmin")
AddEventHandler("CARXAC:CheckIsAdmin", function()
    carxacHandleAdminCheck(source)
end)

local function carxacCountPlayers()
    local count = 0
    for _, _ in ipairs(GetPlayers()) do
        count = count + 1
    end
    return count
end

local function carxacSafeListCount(fn, filter)
    if type(fn) ~= "function" then return 0 end

    local ok, list = pcall(fn)
    if not ok or type(list) ~= "table" then return 0 end
    if type(filter) ~= "function" then return #list end

    local count = 0
    for _, entity in ipairs(list) do
        local okFilter, result = pcall(filter, entity)
        if okFilter and result then count = count + 1 end
    end
    return count
end

local function carxacSendDashboardStats(src, databaseStats, recentAdmins, recentBans)
    if not src or not GetPlayerName(src) then return end
    local stats = {
        players = carxacCountPlayers(),
        vehicles = carxacSafeListCount(GetAllVehicles),
        props = carxacSafeListCount(GetAllObjects),
        peds = carxacSafeListCount(GetAllPeds, function(ped)
            return DoesEntityExist(ped) and not IsPedAPlayer(ped)
        end),
        bans = 0,
        admins = 0,
        whitelist = 0,
        unban = 0,
        recentAdmins = type(recentAdmins) == "table" and recentAdmins or {},
        recentBans = type(recentBans) == "table" and recentBans or {},
    }

    if type(databaseStats) == "table" then
        stats.bans = tonumber(databaseStats.bans) or 0
        stats.admins = tonumber(databaseStats.admins) or 0
        stats.whitelist = tonumber(databaseStats.whitelist) or 0
        stats.unban = tonumber(databaseStats.unban) or 0
    end

    TriggerClientEvent("CARXAC:updateDashboardStats", src, stats)
end

RegisterNetEvent("CARXAC:getDashboardStats")
AddEventHandler("CARXAC:getDashboardStats", function()
    local src = tonumber(source)
    if not src then return end

    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to get CARXAC dashboard stats.")
        return
    end

    MySQL.Async.fetchAll([[
        SELECT
            (SELECT COUNT(*) FROM carxac_banlist) AS bans,
            (SELECT COUNT(*) FROM carxac_admin) AS admins,
            (SELECT COUNT(*) FROM carxac_whitelist) AS whitelist,
            (SELECT COUNT(*) FROM carxac_unban) AS unban
    ]], {}, function(rows)
        local row = rows and rows[1] or {}
        MySQL.Async.fetchAll('SELECT * FROM carxac_admin ORDER BY id DESC LIMIT 5', {}, function(adminRows)
            MySQL.Async.fetchAll('SELECT * FROM carxac_banlist ORDER BY id DESC LIMIT 5', {}, function(banRows)
                carxacSendDashboardStats(src, row, adminRows or {}, banRows or {})
            end)
        end)
    end)
end)

RegisterNetEvent("CARXAC:getAllPlayerData")
AddEventHandler("CARXAC:getAllPlayerData", function()
    local source = source

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Try For Open Admin Menu (Not Admin)")
    else
        local PlayerList = {}
        for _, value in pairs(GetPlayers()) do
            local pid = tonumber(value)
            table.insert(PlayerList, {
                name = GetPlayerName(value),
                id   = value,
                identifier = carxacPlayerLicense(pid) or "no license yet",
                isAdmin = CARXAC_GETADMINS(pid) == true,
                isWhitelist = CARXAC_WHITELIST(pid) == true,
            })
        end
        TriggerClientEvent("CARXAC:sendAllPlayerData", source, PlayerList)
    end
end)

RegisterNetEvent("CARXAC:getPlayerData")
AddEventHandler("CARXAC:getPlayerData", function(playerId)
    local source = source
    playerId = tonumber(playerId)

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Try for get a player data")
    else
        if GetPlayerName(playerId) then
            local data = {
                id     = playerId,
                name   = GetPlayerName(playerId),
                health = GetEntityHealth(GetPlayerPed(playerId)),
                armour = GetPedArmour(GetPlayerPed(playerId)),
                identifier = carxacPlayerLicense(playerId) or "no license yet",
                isAdmin = CARXAC_GETADMINS(playerId) == true,
                isWhitelist = CARXAC_WHITELIST(playerId) == true,
            }
            TriggerClientEvent("CARXAC:openPlayerData", source, data)
        end
    end
end)

RegisterNetEvent("CARXAC:addPlayerAsAdmin")
AddEventHandler("CARXAC:addPlayerAsAdmin", function(playerId)
    local source = source
    playerId = tonumber(playerId)

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Try to set player as admin")
    else
        if GetPlayerName(playerId) then
            if not CARXAC_GETADMINS(playerId) then
                local added = CARXAC:ADDADMIN(playerId)
                if added then
                    TRUSTED_ADMINS[playerId] = true
                    invalidatePermissionCache(playerId)
                    CARXAC_CHANGE_TEMP_WHHITELIST(playerId, true, 120000)
                    TriggerClientEvent("CARXAC:clientGrace", playerId, 120000)
                    TriggerClientEvent("CARXAC:allowToOpen", playerId, true)
                end
            end
        end
    end
end)

RegisterNetEvent("CARXAC:addPlayerAsWhiteList")
AddEventHandler("CARXAC:addPlayerAsWhiteList", function(playerId)
    local source = source
    playerId = tonumber(playerId)

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Try to set player as admin")
    else
        if GetPlayerName(playerId) then
            if not CARXAC_WHITELIST(playerId) then
                local added = CARXAC:ADDWHITELIST(playerId)
                if added then
                    invalidatePermissionCache(playerId)
                    CARXAC_CHANGE_TEMP_WHHITELIST(playerId, true, 120000)
                    TriggerClientEvent("CARXAC:clientGrace", playerId, 120000)
                end
            end
        end
    end
end)

RegisterNetEvent("CARXAC:addPlayerUnbanAccess")
AddEventHandler("CARXAC:addPlayerUnbanAccess", function(playerId)
    local source = source
    playerId = tonumber(playerId)

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Try to add player unban access")
    else
        if GetPlayerName(playerId) then
            if not CARXAC_UNBANACCESS(playerId) then
                CARXAC:ADDUNBAN(playerId)
                invalidatePermissionCache(playerId)
            end
        end
    end
end)

function carxacPlayerLicense(src)
    src = tonumber(src)
    if not src then return nil end
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if type(identifier) == "string" and identifier:sub(1, 8) == "license:" then
            return identifier
        end
    end
    return nil
end

RegisterNetEvent("CARXAC:getAccessOnlinePlayers")
AddEventHandler("CARXAC:getAccessOnlinePlayers", function(scope)
    local src = tonumber(source)
    scope = tostring(scope or "")
    if not src or not CARXAC_GETADMINS(src) then
        if src then
            CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
                "Attempt to get online access picker data")
        end
        return
    end

    if scope ~= "admins" and scope ~= "whitelist" then return end

    local players = {}
    for _, value in ipairs(GetPlayers()) do
        local playerId = tonumber(value)
        if playerId and GetPlayerName(playerId) then
            table.insert(players, {
                id = playerId,
                name = GetPlayerName(playerId),
                identifier = carxacPlayerLicense(playerId) or "no license yet",
                isAdmin = CARXAC_GETADMINS(playerId) == true,
                isWhitelist = CARXAC_WHITELIST(playerId) == true
            })
        end
    end

    TriggerClientEvent("CARXAC:updateAccessOnlinePlayers", src, scope, players)
end)

local function spawnAdminVehicle(requester, data)
    local src = tonumber(requester)
    if not src or not CARXAC_GETADMINS(src) then
        if src then
            CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Spawn Vehicle",
                "Unauthorized admin vehicle spawn event")
        end
        return false
    end

    if type(data) ~= "table" or type(data.vehicleName) ~= "string" then return false end
    local vehicleName = data.vehicleName:lower():match("^[%w_%-]+$")
    if not vehicleName or #vehicleName > 64 then return false end

    local target = tonumber(data.targetId) or src
    if not target or not GetPlayerName(target) then return false end
    local ped = GetPlayerPed(target)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    carxacGrantActionGrace(src, 45000, "adminVehicleSpawn")
    carxacGrantActionGrace(target, 45000, "adminVehicleSpawn")

    local model = GetHashKey(vehicleName)
    if model == 0 then return false end
    local pos = GetEntityCoords(ped)
    local vehicle = CreateVehicle(model, pos.x, pos.y, pos.z, GetEntityHeading(ped), true, false)
    if not vehicle or vehicle == 0 then return false end

    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(vehicle) then return false end

    SetPedIntoVehicle(ped, vehicle, -1)
    return true
end

RegisterNetEvent("CARXAC:spawnVehicle")
AddEventHandler("CARXAC:spawnVehicle", function(data)
    spawnAdminVehicle(source, data)
end)

local CARXAC_LIST_TABLES = {
    admins = {
        tableName = "carxac_admin",
        orderBy = "id",
        columns = "`id`, `identifier`, `player_name`",
        searchable = {"identifier", "player_name", "id"},
    },
    unban = {
        tableName = "carxac_unban",
        orderBy = "id",
        columns = "`id`, `identifier`, `player_name`",
        searchable = {"identifier", "player_name", "id"},
    },
    whitelist = {
        tableName = "carxac_whitelist",
        orderBy = "id",
        columns = "`id`, `identifier`, `player_name`",
        searchable = {"identifier", "player_name", "id"},
    },
    bans = {
        tableName = "carxac_banlist",
        orderBy = "id",
        columns = "*",
        searchable = {"PLAYER_NAME", "LICENSE", "DISCORD", "STEAM", "BANID", "REASON", "IP"},
    }
}

local function carxacListRequest(data)
    data = type(data) == "table" and data or {}
    local page = math.max(1, tonumber(data.page) or 1)
    local pageSize = math.max(5, math.min(100, tonumber(data.pageSize) or 25))
    local search = tostring(data.search or ""):gsub("[%c]", " "):sub(1, 96)
    return page, pageSize, search
end

local function carxacFetchPagedList(scope, request, cb)
    local cfgList = CARXAC_LIST_TABLES[scope]
    if not cfgList then cb({}, { page = 1, pageSize = 25, total = 0, search = "" }) return end

    if scope == "admins" or scope == "unban" or scope == "whitelist" then
        carxacEnsureColumn(cfgList.tableName, "player_name", "varchar(128) NULL DEFAULT NULL AFTER `identifier`")
    elseif scope == "bans" then
        carxacEnsureColumn(cfgList.tableName, "PLAYER_NAME", "varchar(128) NULL DEFAULT NULL AFTER `id`")
    end

    local page, pageSize, search = carxacListRequest(request)
    local offset = (page - 1) * pageSize
    local params = { ["@limit"] = pageSize, ["@offset"] = offset }
    local where = ""

    if search ~= "" then
        local pieces = {}
        for index, column in ipairs(cfgList.searchable or {}) do
            local key = "@q" .. tostring(index)
            params[key] = "%" .. search .. "%"
            pieces[#pieces + 1] = ("CAST(`%s` AS CHAR) LIKE %s"):format(column, key)
        end
        if #pieces > 0 then
            where = " WHERE " .. table.concat(pieces, " OR ")
        end
    end

    local countSql = ("SELECT COUNT(*) AS total FROM `%s`%s"):format(cfgList.tableName, where)
    MySQL.Async.fetchAll(countSql, params, function(countRows)
        local total = tonumber(countRows and countRows[1] and countRows[1].total) or 0
        local maxPage = math.max(1, math.ceil(total / pageSize))
        if page > maxPage then
            page = maxPage
            offset = (page - 1) * pageSize
            params["@offset"] = offset
        end

        local sql = ("SELECT %s FROM `%s`%s ORDER BY `%s` DESC LIMIT %d OFFSET %d"):format(
            cfgList.columns, cfgList.tableName, where, cfgList.orderBy, pageSize, offset
        )

        MySQL.Async.fetchAll(sql, params, function(rows)
            cb(rows or {}, {
                page = page,
                pageSize = pageSize,
                total = total,
                search = search
            })
        end)
    end)
end

RegisterNetEvent('CARXAC:getAdminListData')
AddEventHandler('CARXAC:getAdminListData', function(request)
    local source = source
    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to get admins data by admin menu event.")
        return
    end

    carxacFetchPagedList("admins", request, function(rows, meta)
        TriggerClientEvent("CARXAC:updateAdminData", source, rows, meta)
    end)
end)

RegisterNetEvent('CARXAC:removeSelectedAdmin')
AddEventHandler('CARXAC:removeSelectedAdmin', function(id)
    local source = source

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to remove admins data by admin menu event.")
    else
        MySQL.Async.execute('DELETE FROM carxac_admin WHERE id=@id', {
            ['@id'] = tonumber(id) or -1
        }, function()
            TRUSTED_ADMINS = {}
            invalidatePermissionCache()
        end)
    end
end)

RegisterNetEvent('CARXAC:getUnbanAccessData')
AddEventHandler('CARXAC:getUnbanAccessData', function(request)
    local source = source
    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to get unban data by admin menu event.")
        return
    end

    carxacFetchPagedList("unban", request, function(rows, meta)
        TriggerClientEvent("CARXAC:updateUnbanAccess", source, rows, meta)
    end)
end)

RegisterNetEvent('CARXAC:removeUnbanAccess')
AddEventHandler('CARXAC:removeUnbanAccess', function(id)
    local source = source

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to remove player from unban access list.")
    else
        MySQL.Async.execute('DELETE FROM carxac_unban WHERE id=@id', {
            ['@id'] = tonumber(id) or -1
        }, function() invalidatePermissionCache() end)
    end
end)

RegisterNetEvent('CARXAC:removeWhitelistUser')
AddEventHandler('CARXAC:removeWhitelistUser', function(id)
    local source = source

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to remove user from whitelist by admin menu event.")
    else
        MySQL.Async.execute('DELETE FROM carxac_whitelist WHERE id=@id', {
            ['@id'] = tonumber(id) or -1
        }, function() invalidatePermissionCache() end)
    end
end)

RegisterNetEvent('CARXAC:getWhitelistData')
AddEventHandler('CARXAC:getWhitelistData', function(request)
    local source = source
    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to get whitelist data by admin menu event.")
        return
    end

    carxacFetchPagedList("whitelist", request, function(rows, meta)
        TriggerClientEvent("CARXAC:updateWhiteList", source, rows, meta)
    end)
end)

RegisterNetEvent('CARXAC:getBanListData')
AddEventHandler('CARXAC:getBanListData', function(request)
    local source = source
    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to get banlist data by admin menu event.")
        return
    end

    carxacFetchPagedList("bans", request, function(rows, meta)
        TriggerClientEvent("CARXAC:updateBanListData", source, rows, meta)
    end)
end)

RegisterNetEvent('CARXAC:unbanSelectedPlayer')
AddEventHandler('CARXAC:unbanSelectedPlayer', function(banID)
    local source = source

    if not CARXAC_GETADMINS(source) then
        CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Attempt to remove player from banlist by admin menu event.")
    else
        MySQL.Async.execute('DELETE FROM carxac_banlist WHERE BANID=@banid', {
            ['@banid'] = tonumber(banID) or -1
        })
    end
end)

RegisterNetEvent("CARXAC:deleteEntitys")
AddEventHandler("CARXAC:deleteEntitys", function(entityType)
    local source = source

    if entityType ~= nil then
        if CARXAC_GETADMINS(source) then
            if entityType == "vehicles" then
                for index, vehicles in ipairs(GetAllVehicles()) do
                    if DoesEntityExist(vehicles) then
                        DeleteEntity(vehicles)
                    end
                end
            elseif entityType == "peds" then
                for _, ped in ipairs(GetAllPeds()) do
                    if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                        DeleteEntity(ped)
                    end
                end
            elseif entityType == "props" then
                for index, objects in ipairs(GetAllObjects()) do
                    if DoesEntityExist(objects) then
                        DeleteEntity(objects)
                    end
                end
            end
        else
            CARXAC_ACTION(source, CARXAC.AdminMenu.MenuPunishment, "Anti Delete Entity", "Try For Delete Entitys")
        end
    end
end)

RegisterNetEvent("CARXAC:TeleportToPlayer", function(targetId)
    local src = tonumber(source)
    local target = tonumber(targetId)
    if not src or not target or not GetPlayerName(target) then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Teleport", "Unauthorized admin teleport event")
        return
    end
    local sourcePed, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    if sourcePed == 0 or targetPed == 0 then return end
    carxacGrantActionGrace(src, 90000, "adminGoto")
    carxacGrantActionGrace(target, 90000, "adminGotoTargetNear")
    local coords = GetEntityCoords(targetPed)
    SetEntityCoords(sourcePed, coords.x, coords.y, coords.z, false, false, false, false)
end)

RegisterNetEvent("CARXAC:BringPlayerToAdmin", function(targetId)
    local src = tonumber(source)
    local target = tonumber(targetId)
    if not src or not target or not GetPlayerName(target) or target == src then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Teleport", "Unauthorized admin bring event")
        return
    end
    local sourcePed, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    if sourcePed == 0 or targetPed == 0 then return end
    carxacGrantActionGrace(src, 90000, "adminBring")
    carxacGrantActionGrace(target, 120000, "adminBringTarget")
    local coords = GetEntityCoords(sourcePed)
    SetEntityCoords(targetPed, coords.x + 1.0, coords.y + 1.0, coords.z, false, false, false, false)
end)

RegisterNetEvent("CARXAC:KickPlayerByAdmin", function(targetId, reason)
    local src = tonumber(source)
    local target = tonumber(targetId)
    if not src or not target or not GetPlayerName(target) or target == src then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Kick Players", "Unauthorized admin kick event")
        return
    end
    reason = tostring(reason or "Kicked by admin menu"):gsub("[%c]", " "):sub(1, 160)
    DropPlayer(target, ("\n[CARXAC]\nYou have been kicked by an administrator.\nReason: %s"):format(reason))
end)

RegisterNetEvent("CARXAC:GiveVehicleToPlayer", function(vehicleName, targetId)
    spawnAdminVehicle(source, { vehicleName = vehicleName, targetId = tonumber(targetId) })
end)

RegisterNetEvent("CARXAC:GetScreenShot", function(playerId)
    local src, target = tonumber(source), tonumber(playerId)
    if not src or not target or not GetPlayerName(target) then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Get ScreenShot", "Unauthorized screenshot request")
        return
    end
    if GetResourceState("discord-screenshot") ~= "started" then return end
    local webhook = CARXAC.Webhooks and CARXAC.Webhooks.ScreenShot or ""
    if type(webhook) ~= "string" or not webhook:match("^https?://") then return end
    CARXAC_SCREENSHOT(target, "By Admin Menu", "Requested by " .. (GetPlayerName(src) or tostring(src)), "WARN")
end)

RegisterNetEvent("CARXAC:banPlayerByAdmin", function(targetId, reason)
    local src, target = tonumber(source), tonumber(targetId)
    if not src or not target or not GetPlayerName(target) then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Ban Players", "Unauthorized admin ban event")
        return
    end
    if target == src then return end

    local adminName = GetPlayerName(src) or ("ID " .. tostring(src))
    CARXAC_BAN_PLAYER(target, reason or "Banned by CARXAC admin menu", "Admin " .. adminName .. " (" .. tostring(src) .. ")")
end)

RegisterNetEvent("CARXAC:requestSpectate", function(targetId)
    local src, target = tonumber(source), tonumber(targetId)
    if not src or not target or not GetPlayerName(target) or target == src then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Spectate Players", "Unauthorized spectate event")
        return
    end
    local targetPed = GetPlayerPed(target)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then return end
    carxacGrantActionGrace(src, 90000, "adminSpectate")
    TriggerClientEvent("CARXAC:spectatePlayer", src, target, GetEntityCoords(targetPed))
end)

RegisterNetEvent("CARXAC:CheckJumping", function()
    local src = tonumber(source)
    if not src or not GetPlayerName(src) then return end
    local st = playerState(src)
    if not st or st.readyAt == 0 or monotonicMs() < st.graceUntil then return end
    if CARXAC_IS_TRUSTED(src) then return end
    if IsPlayerUsingSuperJump(src) then
        CARXAC_ACTION(src, CARXAC.JumpPunishment, "Anti Superjump", "Server native confirmed super jump")
    end
end)

RegisterNetEvent("CARXAC:ScreenShotFromClient", function()
    return
end)

AddEventHandler("playerDropped", function(reason)
    local src = tonumber(source)
    local name = GetPlayerName(src) or ("ID " .. tostring(src))
    reason = tostring(reason or "Unknown")
    print(("^%s[CARXAC]^0 ^1Player ^3%s ^1disconnected | ^0%s"):format(COLORS, name, reason))
    if GetPlayerName(src) then
        CARXAC_SENDLOG(src, CARXAC.Webhooks and CARXAC.Webhooks.Disconnect or "", "DISCONNECT", reason)
    end
end)

AddEventHandler("giveWeaponEvent", function(SRC, DATA)
    if CARXAC.AntiAddWeapon then
        if tonumber(SRC) ~= nil and GetPlayerName(SRC) ~= nil then
            if not CARXAC_IS_TRUSTED(SRC) then
                CancelEvent()
                CARXAC_ACTION(SRC, CARXAC.WeaponPunishment, "Anti Add Weapon", "Try for add weapon for player")
            end
        else
            CARXAC_ERROR(CARXAC.ServerConfig.Name, "giveWeaponEvent : SRC (Not Found)")
        end
    end
end)

AddEventHandler("RemoveWeaponEvent", function(SRC, DATA)
    if CARXAC.AntiRemoveWeapon then
        if tonumber(SRC) ~= nil and GetPlayerName(SRC) ~= nil then
            if not CARXAC_IS_TRUSTED(SRC) then
                CancelEvent()
                CARXAC_ACTION(SRC, CARXAC.WeaponPunishment, "Anti Remove Weapon", "Try for remove weapon for player")
            end
        else
            CARXAC_ERROR(CARXAC.ServerConfig.Name, "giveWeaponEvent : SRC (Not Found)")
        end
    end
end)

AddEventHandler("RemoveAllWeaponsEvent", function(SRC, DATA)
    if CARXAC.AntiRemoveWeapon then
        if tonumber(SRC) ~= nil and GetPlayerName(SRC) ~= nil then
            if not CARXAC_IS_TRUSTED(SRC) then
                CancelEvent()
                CARXAC_ACTION(SRC, CARXAC.WeaponPunishment, "Anti Remove All Weapon",
                    "Try for remove all weapon for player")
            end
        else
            CARXAC_ERROR(CARXAC.ServerConfig.Name, "giveWeaponEvent : SRC (Not Found)")
        end
    end
end)

-- CARXAC:AddToSpawnList is registered earlier (hardened). Do not re-register here.

local EVENTS = {}
if CARXAC.AntiSpamTrigger then
    for i = 1, #SpamCheck do
        local eventName = SpamCheck[i].EVENT
        local maxCount = tonumber(SpamCheck[i].MAX_TIME) or 10
        RegisterNetEvent(eventName)
        AddEventHandler(eventName, function()
            local src = tonumber(source)
            if not src or src <= 0 then return end
            local now = os.time()
            EVENTS[src] = EVENTS[src] or {}
            local state = EVENTS[src][eventName]
            if not state or now - state.startedAt >= 10 then
                state = { count = 0, startedAt = now }
                EVENTS[src][eventName] = state
            end
            state.count = state.count + 1
            if state.count > maxCount then
                CARXAC_ACTION(src, CARXAC.TriggerPunishment, "Anti Spam Trigger",
                    ("Event `%s` fired %s times within 10 seconds"):format(eventName, state.count))
                CancelEvent()
            end
        end)
    end
end

local SERVER_CMDS = {}
if type(Commands) == "table" then
    for _, blockedCommand in ipairs(Commands) do
        local commandName = tostring(blockedCommand)
        if commandName ~= "" then
            RegisterCommand(commandName, function(src)
                src = tonumber(src)
                if CARXAC.AntiBlackListCommands and src and src > 0 then
                    CARXAC_ACTION(src, CARXAC.CMDPunishment, "Anti Black List Commands",
                        "Attempted blocked command: " .. commandName)
                end
            end, false)
        end
    end
end

local MESSAGE = {}
AddEventHandler("chatMessage", function(src, _, word)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return end
    if CARXAC_IS_TRUSTED(src) then return end

    local text = tostring(word or "")
    local lower = text:lower()
    if CARXAC.AntiBlackListWord and type(Words) == "table" then
        for _, blocked in ipairs(Words) do
            local needle = tostring(blocked):lower()
            if needle ~= "" and lower:find(needle, 1, true) then
                CARXAC_ACTION(src, CARXAC.WordPunishment, "Anti Bad Word", "Blocked chat term detected")
                CancelEvent()
                return
            end
        end
    end

    if not CARXAC.AntiSpamChat then return end
    local now = os.time()
    local state = MESSAGE[src]
    if not state or now - state.startedAt >= (tonumber(CARXAC.CoolDownSec) or 3) then
        state = { count = 0, startedAt = now, acted = false }
        MESSAGE[src] = state
    end
    state.count = state.count + 1
    local maximum = tonumber(CARXAC.MaxMessage) or 10
    if state.count >= maximum and not state.acted then
        state.acted = true
        CancelEvent()
        CARXAC_ACTION(src, CARXAC.ChatPunishment, "Anti Spam Chat",
            ("Sent %s messages in %s seconds"):format(state.count, tonumber(CARXAC.CoolDownSec) or 3))
    end
end)

if CARXAC.AntiBlackListTrigger and type(Events) == "table" then
    for _, blockedEvent in ipairs(Events) do
        local eventName = tostring(blockedEvent)
        RegisterNetEvent(eventName)
        AddEventHandler(eventName, function()
            local src = tonumber(source)
            if not src or CARXAC_IS_TRUSTED(src) then return end
            CancelEvent()
            CARXAC_ACTION(src, CARXAC.TriggerPunishment, "Anti Black List Trigger",
                "Attempted blocked event: " .. eventName)
        end)
    end
end

AddEventHandler("db:updateUser", function(data)
    local src = tonumber(source)
    if not CARXAC.AntiChangePerm or not src or CARXAC_IS_TRUSTED(src) then return end
    if type(data) ~= "table" or not data.playerName or not data.dateofbirth then
        CancelEvent()
        CARXAC_ACTION(src, CARXAC.PermPunishment, "Anti Change Perm", "Malformed db:updateUser payload")
    end
end)

local EXPLOSION = {}
AddEventHandler("explosionEvent", function(src, data)
    src = tonumber(src)
    if not src or src <= 0 or type(data) ~= "table" then
        CancelEvent()
        return
    end
    if CARXAC_IS_TRUSTED(src) then return end

    local definition = type(Explosion) == "table" and Explosion[tonumber(data.explosionType)] or nil
    if definition then
        local name = tostring(definition.NAME or data.explosionType or "Unknown")
        if definition.Log then
            CARXAC_SENDLOG(src, CARXAC.Webhooks and CARXAC.Webhooks.Exoplosion or "", "EXPLOSION", name)
        end
        local punishment = type(definition.Punishment) == "string" and definition.Punishment:upper() or nil
        if punishment == "WARN" or punishment == "KICK" or punishment == "BAN" then
            CancelEvent()
            CARXAC_ACTION(src, punishment, "Anti Explosion", "Blocked explosion type: " .. name)
            return
        end
    end

    if not CARXAC.AntiExplosionSpam then return end
    local key = GetPlayerToken(src, 0) or tostring(src)
    local now = os.time()
    local state = EXPLOSION[key]
    if not state or now - state.startedAt >= 10 then
        state = { count = 0, startedAt = now, acted = false }
        EXPLOSION[key] = state
    end
    state.count = state.count + 1
    if state.count >= (tonumber(CARXAC.MaxExplosion) or 10) and not state.acted then
        state.acted = true
        CancelEvent()
        CARXAC_ACTION(src, CARXAC.ExplosionSpamPunishment, "Anti Spam Explosion",
            ("Created %s explosions within 10 seconds"):format(state.count))
    end
end)

if GetResourceState("interact-sound") == "started" then
    local blockedSounds = {
        ["10000:handcuff"] = true, ["1000:Cuff"] = true, ["103232:lock"] = true,
        ["10:szajbusek"] = true, ["5:alarm"] = true, ["13232:pasysound"] = true,
        ["5000:demo"] = true,
    }
    AddEventHandler("InteractSound_SV:PlayWithinDistance", function(maxDistance, soundFile)
        local src = tonumber(source)
        if not CARXAC.AntiPlaySound or not src or CARXAC_IS_TRUSTED(src) then return end
        local key = tostring(tonumber(maxDistance) or maxDistance) .. ":" .. tostring(soundFile)
        if blockedSounds[key] then
            CancelEvent()
            CARXAC_ACTION(src, CARXAC.SoundPunishment, "Anti Play Sound", "Blocked sound payload: " .. key)
        end
    end)
end

local TAZE, FREEZE = {}, {}
AddEventHandler("weaponDamageEvent", function(src, data)
    src = tonumber(src)
    if not CARXAC.AntiTazePlayers or not src or type(data) ~= "table" or data.weaponType ~= 911657153 then return end
    if CARXAC_IS_TRUSTED(src) then return end
    local key = GetPlayerToken(src, 0) or tostring(src)
    local now = os.time()
    local state = TAZE[key]
    if not state or now - state.startedAt >= 10 then
        state = { count = 0, startedAt = now, acted = false }
        TAZE[key] = state
    end
    state.count = state.count + 1
    if state.count >= (tonumber(CARXAC.MaxTazeSpam) or 8) and not state.acted then
        state.acted = true
        CancelEvent()
        CARXAC_ACTION(src, CARXAC.TazePunishment, "Anti Spam Tazer",
            ("Tazer damage repeated %s times within 10 seconds"):format(state.count))
    end
end)

AddEventHandler("clearPedTasksEvent", function(src)
    src = tonumber(src)
    if not CARXAC.AntiClearPedTasks or not src then return end
    if CARXAC_IS_TRUSTED(src) then return end
    local key = GetPlayerToken(src, 0) or tostring(src)
    local now = os.time()
    local state = FREEZE[key]
    if not state or now - state.startedAt >= 10 then
        state = { count = 0, startedAt = now, acted = false }
        FREEZE[key] = state
    end
    state.count = state.count + 1
    if state.count >= (tonumber(CARXAC.MaxClearPedTasks) or 8) and not state.acted then
        state.acted = true
        CancelEvent()
        CARXAC_ACTION(src, CARXAC.CPTPunishment, "Anti Clear Ped Tasks",
            ("clearPedTasksEvent repeated %s times within 10 seconds"):format(state.count))
    end
end)

RegisterNetEvent("esx_ambulancejob:syncDeadBody")
AddEventHandler("esx_ambulancejob:syncDeadBody", function(ped, target)
    local src = tonumber(source)
    if not CARXAC.AntiBringAll or not src or CARXAC_IS_TRUSTED(src) then return end
    local targetId = tonumber(target)
    if targetId == -1 or (targetId and targetId ~= src and not GetPlayerName(targetId)) then
        CancelEvent()
        CARXAC_ACTION(src, CARXAC.BringAllPunishment, "Anti Bring All Players", "Invalid ambulance sync target")
    end
end)

AddEventHandler("onResourceStarting", function(RES)
    CARXAC_REFRESHCMD()
end)

AddEventHandler("onResourceStop", function(RES)
    CARXAC_REFRESHCMD()
end)

local function carxacConnectionConfig(name, fallback)
    if CARXAC and CARXAC.Connection and CARXAC.Connection[name] ~= nil then
        return CARXAC.Connection[name]
    end
    return fallback
end

local function carxacDeferralMode()
    local mode = tostring(carxacConnectionConfig("DeferralMode", "legacy") or "legacy"):lower()
    if mode == "legacy" then mode = "update" end
    if mode ~= "card" and mode ~= "update" and mode ~= "silent" then
        mode = "update"
    end
    if mode == "card" and not carxacConnectionConfig("AdaptiveCard", false) then
        mode = "update"
    end
    return mode
end

local function carxacConnectionUiEnabled()
    return carxacConnectionConfig("ShowConnectUI", true) ~= false
end

local function carxacProblemOnlyMode()
    return carxacConnectionConfig("ProblemOnlyMode", false) == true
end

local function carxacShouldShowConnectionStep(isProblem)
    if carxacConnectionUiEnabled() then
        return true
    end
    return isProblem == true and carxacConnectionConfig("ShowProblemCard", true) == true
end

local function carxacDeferralWait(multiplier)
    local ms = tonumber(carxacConnectionConfig("DeferralStepMs", 150)) or 150
    if ms < 0 then ms = 0 end
    if ms > 1000 then ms = 1000 end
    Wait(math.floor(ms * (tonumber(multiplier) or 1)))
end

local function carxacText(value, fallback, maxLen)
    local out = tostring(value or fallback or "")
    out = out:gsub("[%c]", "")
    maxLen = tonumber(maxLen) or 180
    if #out > maxLen then
        out = out:sub(1, maxLen - 3) .. "..."
    end
    return out
end

local function carxacDeferralUpdate(deferrals, message)
    if carxacDeferralMode() == "silent" then
        carxacDeferralWait()
        return true
    end
    if not deferrals or not deferrals.update then return false end
    local ok = pcall(function()
        deferrals.update(carxacText(message, "CARXAC security validation is running...", 240))
    end)
    carxacDeferralWait()
    return ok
end

local function carxacVisualDelay(multiplier)
    local ms = tonumber(carxacConnectionConfig("VisualStepMs", 420)) or 420
    if ms < 0 then ms = 0 end
    if ms > 1500 then ms = 1500 end
    Wait(math.floor(ms * (tonumber(multiplier) or 1)))
end

local function carxacProgress(step, total)
    step = tonumber(step) or 1
    total = tonumber(total) or 4
    if step < 1 then step = 1 end
    if step > total then step = total end
    local slots = 10
    local filled = math.floor((step / total) * slots + 0.5)
    if filled < 1 then filled = 1 end
    if filled > slots then filled = slots end
    return "[" .. string.rep("#", filled) .. string.rep("-", slots - filled) .. "]"
end

local function carxacConnectBrand()
    return carxacText(carxacConnectionConfig("CardTitle", "CARXAC SECURITY"), "CARXAC SECURITY", 32):upper()
end

local function carxacStatus(deferrals, step, total, title, detail, delayMultiplier)
    if not deferrals or not deferrals.update then return false end
    local brand = carxacConnectBrand()
    local msg = string.format("[%s] %s %s", brand, carxacProgress(step, total), carxacText(title, "Checking connection", 80))
    if detail and tostring(detail) ~= "" then
        msg = msg .. " | " .. carxacText(detail, "", 80)
    end
    local ok = pcall(function()
        deferrals.update(carxacText(msg, "[CARXAC] Checking connection...", 220))
    end)
    carxacVisualDelay(delayMultiplier or 1)
    return ok
end

local function carxacAdaptivePercent(step, total)
    step = tonumber(step) or 1
    total = tonumber(total) or 4
    if step < 1 then step = 1 end
    if step > total then step = total end
    local value = math.floor((step / total) * 100 + 0.5)
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    return value
end

local CARXAC_CONNECT_STEP_LABELS = {
    [1] = "Gateway initialization",
    [2] = "Identity verification",
    [3] = "Security validation",
    [4] = "Connection result"
}

local function carxacBuildConnectCard(step, total, title, detail, accent)
    local brand = carxacConnectBrand()
    local percent = carxacAdaptivePercent(step, total)
    local safeTitle = carxacText(title, "Checking connection", 70)
    local safeDetail = carxacText(detail, "Please wait", 120)
    local color = carxacText(accent, "Accent", 16)

    local body = {
        {
            type = "Container",
            style = "emphasis",
            items = {
                {
                    type = "TextBlock",
                    text = brand,
                    weight = "Bolder",
                    size = "Large",
                    color = "Attention",
                    horizontalAlignment = "Center",
                    wrap = true
                },
                {
                    type = "TextBlock",
                    text = "Protected connection screening",
                    isSubtle = true,
                    spacing = "None",
                    horizontalAlignment = "Center",
                    wrap = true
                }
            }
        },
        {
            type = "TextBlock",
            text = safeTitle,
            weight = "Bolder",
            size = "Medium",
            color = color,
            horizontalAlignment = "Center",
            wrap = true,
            spacing = "Medium"
        },
        {
            type = "TextBlock",
            text = safeDetail,
            isSubtle = true,
            horizontalAlignment = "Center",
            wrap = true,
            spacing = "Small"
        },
        {
            type = "TextBlock",
            text = "Progress " .. tostring(percent) .. "%  " .. carxacProgress(step, total),
            weight = "Bolder",
            horizontalAlignment = "Center",
            wrap = true,
            spacing = "Medium"
        },
        {
            type = "TextBlock",
            text = "Security pipeline",
            weight = "Bolder",
            color = "Accent",
            spacing = "Medium",
            wrap = true
        }
    }

    for index = 1, total do
        local prefix = index < step and "DONE" or (index == step and "LIVE" or "WAIT")
        local rowColor = index < step and "Good" or (index == step and color or "Default")
        body[#body + 1] = {
            type = "TextBlock",
            text = string.format("[%s] %s", prefix, carxacText(CARXAC_CONNECT_STEP_LABELS[index] or ("Step " .. tostring(index)), "Step", 48)),
            color = rowColor,
            wrap = true,
            spacing = index == 1 and "Small" or "None"
        }
    end

    body[#body + 1] = {
        type = "TextBlock",
        text = "Please keep this screen open while the connection is being validated.",
        isSubtle = true,
        wrap = true,
        spacing = "Medium"
    }

    return {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json",
        type = "AdaptiveCard",
        version = "1.0",
        body = body
    }
end

local function carxacPresentCard(deferrals, step, total, title, detail, accent)
    if carxacDeferralMode() ~= "card" then
        return carxacStatus(deferrals, step, total, title, detail, 1)
    end
    if not deferrals or not deferrals.presentCard then
        return carxacStatus(deferrals, step, total, title, detail, 1)
    end

    carxacDeferralWait()

    local card = carxacBuildConnectCard(step, total, title, detail, accent)
    local encoded = nil
    local okJson = pcall(function()
        encoded = json.encode(card)
    end)
    if not okJson or not encoded or encoded == "" then
        return carxacStatus(deferrals, step, total, title, detail, 1)
    end

    local ok = pcall(function()
        deferrals.presentCard(encoded)
    end)

    carxacDeferralWait()
    if not ok then
        print("^3[CARXAC]^0 presentCard failed at Lua level; falling back to deferrals.update.")
        return carxacStatus(deferrals, step, total, title, detail, 1)
    end

    local hold = tonumber(carxacConnectionConfig("PresentCardHoldMs", 1600)) or 1600
    if hold < 0 then hold = 0 end
    if hold > 5000 then hold = 5000 end
    if hold > 0 then Wait(math.floor(hold)) end
    return true
end

AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    local src = tonumber(source)
    if not src then return end
    playerState(src)

    if connectionCfg("UseDeferrals", true) ~= true then
        return
    end

    local name = carxacText(playerName or GetPlayerName(src) or ("ID " .. tostring(src)), "Player", 64)
    print(("^%sCARXAC^0: ^2Player ^3%s ^2Connecting ...^0"):format(COLORS, name))

    local hasDeferral = deferrals and deferrals.defer and deferrals.update and deferrals.done
    if not hasDeferral then
        return
    end

    deferrals.defer()
    Wait(0)

    local function showStatus(step, total, title, detail, delayMultiplier, accent, isProblem)
        if not carxacShouldShowConnectionStep(isProblem == true) then
            carxacDeferralWait(delayMultiplier or 1)
            return true
        end

        if carxacDeferralMode() == "card" then
            return carxacPresentCard(deferrals, step, total, title, detail, accent or "Attention")
        end

        return carxacStatus(deferrals, step, total, title, detail, delayMultiplier or 1)
    end

    local startDelay = tonumber(carxacConnectionConfig("DeferralDelayMs", 0)) or 0
    if startDelay < 0 then startDelay = 0 end
    if startDelay > 10000 then startDelay = 10000 end
    if startDelay > 0 then Wait(math.floor(startDelay)) end

    showStatus(1, 4, "Initializing secure gateway", "Protected by CARXAC", 1, "Attention")
    showStatus(2, 4, "Verifying player identity", name, 1, "Accent")

    local function finish(message)
        if message and message ~= "" then
            pcall(function() deferrals.done(message) end)
        else
            pcall(function() deferrals.done() end)
        end
    end

    showStatus(3, 4, "Checking ban database", "Please wait", 0.8, "Accent")
    local okBan, banData = pcall(CARXAC_INBANLIST, src)
    if okBan and banData and banData[1] then
        local reason = carxacText(banData[1].REASON, "Unknown", 160)
        local banId = carxacText(banData[1].BANID, "N/A", 48)
        print(("^%sCARXAC^0: ^1Blocked banned player ^3%s^0 | Ban ID: %s"):format(COLORS, name, banId))
        pcall(CARXAC_SENDLOG, src, CARXAC.Webhooks and CARXAC.Webhooks.Connect or "", "TFJ", banId, reason)
        showStatus(4, 4, "Connection blocked", "Ban ID #" .. banId, 1, "Attention", true)
        Wait(600)
        finish(("\n[CARXAC]\nYou are banned from this server.\nReason: %s\nBan ID: #%s"):format(reason, banId))
        return
    elseif not okBan then
        local failMode = tostring(connectionCfg("BanCheckFailMode", "CLOSED")):upper()
        print(("^1[CARXAC]^0 Ban-list lookup FAILED during connection (mode=%s)."):format(failMode))
        if failMode ~= "OPEN" then
            showStatus(4, 4, "Connection blocked", "Security database unavailable", 1, "Attention", true)
            Wait(600)
            finish("\n[CARXAC]\nConnection rejected: ban database temporarily unavailable.\nPlease try again in a moment.")
            return
        end
        print("^3[CARXAC]^0 BanCheckFailMode=OPEN — allowing player despite DB failure.")
    end

    if CARXAC.Connection and CARXAC.Connection.AntiBlackListName and type(Names) == "table" then
        local normalizedName = carxacNormalizeName(playerName or name)
        for _, blocked in ipairs(Names) do
            local needle = carxacNormalizeName(blocked)
            if needle ~= "" and normalizedName:find(needle, 1, true) then
                print(("^%sCARXAC^0: ^1Player ^3%s ^3Try For Join ^0| ^3Black List Word in name: ^3%s^0"):format(COLORS, name, tostring(blocked)))
                pcall(CARXAC_SENDLOG, src, CARXAC.Webhooks and CARXAC.Webhooks.Connect or "", "BLN", "Black List Name", "Found " .. tostring(blocked) .. " in player name")
                showStatus(4, 4, "Connection blocked", "Invalid player name", 1, "Attention", true)
                Wait(600)
                finish(("\n[CARXAC]\nYour player name contains a blocked term: %s"):format(tostring(blocked)))
                return
            end
        end
    end

    local endpoint = tostring(GetPlayerEndpoint(src) or "")
    local localEndpoint = endpoint == "" or endpoint == "127.0.0.1" or endpoint:find("192.168.", 1, true) == 1 or endpoint:find("10.", 1, true) == 1 or endpoint:find("172.16.", 1, true) == 1
    local function allow(statusDetail)
        if not carxacProblemOnlyMode() then
            showStatus(4, 4, "Connection accepted", statusDetail or "Welcome to the server", 1, "Good")
        else
            carxacDeferralWait(0.5)
        end
        pcall(CARXAC_SENDLOG, src, CARXAC.Webhooks and CARXAC.Webhooks.Connect or "", "CONNECT")
        local hold = tonumber(carxacConnectionConfig("ConnectHoldMs", 1800)) or 1800
        if hold < 0 then hold = 0 end
        if hold > 5000 then hold = 5000 end
        if hold > 0 then Wait(math.floor(hold)) end
        finish()
    end

    if CARXAC.Connection and CARXAC.Connection.AntiVPN and not localEndpoint then
        showStatus(3, 4, "Checking network reputation", "VPN/proxy scan", 1, "Accent")
        local finished = false
        -- HTTPS only; timeout handled by finished flag + deferral wait below
        PerformHttpRequest("https://ip-api.com/json/" .. endpoint .. "?fields=status,message,proxy,hosting,isp,country,city", function(statusCode, body)
            if finished then return end
            finished = true
            if statusCode ~= 200 or not body or body == "" then
                print("^3[CARXAC]^0 VPN lookup unavailable; allowing player fail-open.")
                allow("VPN lookup unavailable")
                return
            end
            local ok, data = pcall(json.decode, body)
            if not ok or type(data) ~= "table" or data.status == "fail" then
                print("^3[CARXAC]^0 Invalid VPN lookup response; allowing player fail-open.")
                allow("VPN lookup invalid")
                return
            end
            if data.proxy == true or data.hosting == true then
                local isp = carxacText(data.isp, "Unknown", 80)
                local country = carxacText(data.country, "Unknown", 60)
                local city = carxacText(data.city, "Unknown", 60)
                print(("^%sCARXAC^0: ^1Player ^3%s ^3Try For Join ^0| ^3VPN/Hosting ^3 ISP: %s / Country: %s / City: %s^0"):format(COLORS, name, isp, country, city))
                pcall(CARXAC_SENDLOG, src, CARXAC.Webhooks and CARXAC.Webhooks.Connect or "", "VPN")
                showStatus(4, 4, "Connection blocked", "VPN/proxy is not allowed", 1, "Attention", true)
                Wait(600)
                finish(("\n[CARXAC]\nVPN/hosting connections are not allowed.\nISP: %s\nCountry: %s\nCity: %s"):format(isp, country, city))
                return
            end
            allow("Network reputation passed")
        end, "GET")

        CreateThread(function()
            Wait(8000)
            if not finished then
                finished = true
                print("^3[CARXAC]^0 VPN lookup timed out; allowing player fail-open.")
                allow("VPN lookup timed out")
            end
        end)
        return
    end

    allow("Security checks passed")
end)

local SV_VEHICLES, SV_PEDS, SV_OBJECT = {}, {}, {}
local ENTITY_LISTS = { [1] = Peds, [2] = Vehicle, [3] = Objects }
local ENTITY_NAMES = { [1] = "Ped", [2] = "Vehicle", [3] = "Object" }
local ENTITY_BLACKLIST_FLAGS = {
    [1] = function() return CARXAC.AntiBlackListPed end,
    [2] = function() return CARXAC.AntiBlackListVehicle end,
    [3] = function() return CARXAC.AntiBlackListObject or CARXAC.AntiBlackListBuilding end,
}
local ENTITY_SPAM_FLAGS = {
    [1] = function() return CARXAC.AntiSpamPed end,
    [2] = function() return CARXAC.AntiSpamVehicle end,
    [3] = function() return CARXAC.AntiSpamObject end,
}
local ENTITY_SPAM_TABLES = { [1] = SV_PEDS, [2] = SV_VEHICLES, [3] = SV_OBJECT }

local function modelInList(model, list)
    if type(list) ~= "table" then return false end
    for _, value in ipairs(list) do
        if model == GetHashKey(value) then return true end
    end
    return false
end

local function getEntitiesByType(entityType)
    if entityType == 1 then return GetAllPeds() end
    if entityType == 2 then return GetAllVehicles() end
    if entityType == 3 then return GetAllObjects() end
    return {}
end

local function CARXAC_InspectCreatedEntity(entity)
    if not runtimeCfg("EntityCreatedMonitor", false) then return end
    if not entity or entity == 0 then return end

    local delay = tonumber(runtimeCfg("EntityCreatedDelayMs", 750)) or 750
    if delay < 0 then delay = 0 end
    if delay > 5000 then delay = 5000 end

    SetTimeout(delay, function()
        if not runtimeCfg("EntityCreatedMonitor", false) then return end
        if not DoesEntityExist(entity) then return end

        local owner = tonumber(NetworkGetFirstEntityOwner(entity))
        if not owner or owner <= 0 or not GetPlayerName(owner) then return end

        local entityType = GetEntityType(entity)
        if not ENTITY_NAMES[entityType] then return end

        local population = GetEntityPopulationType(entity)
        if population ~= 0 then return end
        if CARXAC_IS_TRUSTED(owner) then return end

        local model = GetEntityModel(entity)
        local kind = ENTITY_NAMES[entityType]
        if ENTITY_BLACKLIST_FLAGS[entityType]() and modelInList(model, ENTITY_LISTS[entityType]) then
            if DoesEntityExist(entity) then DeleteEntity(entity) end
            CARXAC_ACTION(owner, CARXAC.EntityPunishment, "Anti Spawn " .. kind,
                ("Blocked %s model: %s"):format(kind:lower(), tostring(model)))
            return
        end

        if not ENTITY_SPAM_FLAGS[entityType]() then return end
        local key = GetPlayerToken(owner, 0) or tostring(owner)
        local bucket = ENTITY_SPAM_TABLES[entityType]
        local now = os.time()
        local state = bucket[key]
        if not state or now - state.startedAt >= 10 then
            state = { count = 0, startedAt = now, acted = false }
            bucket[key] = state
        end
        state.count = state.count + 1

        local maximum = tonumber(CARXAC["Max" .. kind]) or 10
        if state.count < maximum or state.acted then return end
        state.acted = true

        if DoesEntityExist(entity) then DeleteEntity(entity) end
        CARXAC_ACTION(owner, CARXAC.SpamPunishment, "Anti Spam " .. kind,
            ("Created %s entities within 10 seconds"):format(state.count))
    end)
end

AddEventHandler("entityCreated", function(entity)
    CARXAC_InspectCreatedEntity(entity)
end)

function StartAntiCheat()
    local resources = {
        "configs/carx-config.lua", "tables/carx-event.lua", "tables/carx-explosions.lua",
        "tables/carx-name.lua", "tables/carx-object.lua", "tables/carx-peds.lua",
        "tables/carx-plate.lua", "tables/carx-vehicle.lua", "tables/carx-weapon.lua",
        "tables/carx-words.lua", "tables/carx-task.lua", "tables/carx-anim.lua",
        "tables/carx-emoji.lua"
    }

    local missing = {}
    for _, resource in ipairs(resources) do
        if LoadResourceFile(GetCurrentResourceName(), resource) then
            print("^" .. COLORS .. "[CARXAC]^0: ^2" .. resource .. " LOADED !^0")
        else
            missing[#missing + 1] = resource
        end
    end

    if #missing > 0 then
        print("^" .. COLORS .. "[CARXAC]^0: ^1 Some Files Of CARXAC Not Found! Please Replace or Repair Them^0")
        print("^1[CARXAC]^0 Missing required files: " .. table.concat(missing, ", "))
        return false
    end

    local configuredPort = tostring(CARXAC.ServerConfig.Port or "auto")
    local actualPort = GetConvar("netPort", configuredPort)
    local artifact = GetConvar("version", "unknown build")

    print("^" .. COLORS .. "========================================")
    print("^" .. COLORS .. "          CARXAC ANTI-CHEAT")
    print("^" .. COLORS .. "           Carx Anti-Cheat")
    print("^" .. COLORS .. "            Version " .. tostring(CARXAC.Version))
    print("^" .. COLORS .. "========================================")
    print("^" .. COLORS .. "  Protection: ACTIVE")
    print("^" .. COLORS .. "  Detection Engine: ACTIVE")
    print("^" .. COLORS .. "  Server Build: " .. tostring(artifact))
    print("^" .. COLORS .. "  Port: " .. tostring(actualPort))
    print("^" .. COLORS .. "========================================^0")

    local webhook = CARXAC.Webhooks and CARXAC.Webhooks.Ban or ""
    if type(webhook) == "string" and webhook:match("^https?://") then
        PerformHttpRequest(webhook, function() end, "POST", json.encode({
            username = "CARXAC",
            embeds = {{
                title = "CARXAC started",
                description = ("Version: %s\nServer: %s\nPort: %s\nBuild: %s"):format(
                    tostring(CARXAC.Version), tostring(CARXAC.ServerConfig.Name), tostring(actualPort), tostring(artifact)),
                color = 16733440
            }}
        }), { ["Content-Type"] = "application/json" })
    end

    return true
end

function CARXAC_ISNEARADMIN(SRC)
    local src = tonumber(SRC)
    if not src then return false end
    local myPed = GetPlayerPed(src)
    if not myPed or myPed == 0 or not DoesEntityExist(myPed) then return false end
    local myPos = GetEntityCoords(myPed)
    for _, value in ipairs(GetPlayers()) do
        local other = tonumber(value)
        if other and other ~= src and CARXAC_GETADMINS(other) then
            local adminPed = GetPlayerPed(other)
            if adminPed and adminPed ~= 0 and DoesEntityExist(adminPed) then
                local adminPos = GetEntityCoords(adminPed)
                if #(myPos - adminPos) < 30.0 then return true end
            end
        end
    end
    return false
end

local PERMISSION_TABLES = {
    whitelist = "carxac_whitelist",
    admin = "carxac_admin",
    unban = "carxac_unban"
}

local function permissionIdentifiers(src)
    local result, seen = {}, {}
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier and identifier ~= "" and not seen[identifier] then
            seen[identifier] = true
            result[#result + 1] = identifier
        end
        if identifier and identifier:sub(1, 8) == "discord:" then
            local legacy = identifier:sub(9)
            if legacy ~= "" and not seen[legacy] then
                seen[legacy] = true
                result[#result + 1] = legacy
            end
        end
    end
    return result
end


-- ========== txAdmin + admin group integration (no custom ACE permissions) ==========
local TXADMIN_ADMINS = {} -- [src] = true when authenticated by txAdmin in-game menu

AddEventHandler("txAdmin:events:adminAuth", function(data)
    if type(data) ~= "table" then return end
    local netId = tonumber(data.netid or data.id or data.source)
    if netId == -1 then
        -- Forced reauth: clear all
        TXADMIN_ADMINS = {}
        if invalidatePermissionCache then invalidatePermissionCache() end
        return
    end
    if not netId or netId <= 0 then return end
    if data.isAdmin == true then
        TXADMIN_ADMINS[netId] = true
    else
        TXADMIN_ADMINS[netId] = nil
    end
    if invalidatePermissionCache then invalidatePermissionCache(netId) end
end)

-- When txAdmin admin list changes, drop cache so next check re-evaluates
AddEventHandler("txAdmin:events:adminsUpdated", function(onlineNetIds)
    if type(onlineNetIds) == "table" then
        local keep = {}
        for _, id in ipairs(onlineNetIds) do
            local n = tonumber(id)
            if n and TXADMIN_ADMINS[n] then keep[n] = true end
        end
        -- Preserve known admins that are still listed; clear others
        for src in pairs(TXADMIN_ADMINS) do
            if not keep[src] then TXADMIN_ADMINS[src] = nil end
        end
    end
    if invalidatePermissionCache then invalidatePermissionCache() end
end)

AddEventHandler("playerDropped", function()
    local src = source
    TXADMIN_ADMINS[src] = nil
end)

local function isTxAdminStaff(src)
    src = tonumber(src)
    if not src then return false end
    return TXADMIN_ADMINS[src] == true
end

local function isAdminGroup(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    local access = CARXAC.AdminAccess or {}
    local groups = access.Groups or { "group.admin", "group.god", "admin" }

    -- Dedicated ACE object (recommended in server.cfg):
    --   add_ace group.admin carxac.admin allow
    if IsPlayerAceAllowed(tostring(src), "carxac.admin") then
        return true
    end

    for _, g in ipairs(groups) do
        if type(g) == "string" and g ~= "" then
            -- Principal/group object checks used by many servers
            if IsPlayerAceAllowed(tostring(src), g) then
                return true
            end
            -- Also try without "group." prefix (some cfgs use principal "admin")
            local short = g:gsub("^group%.", "")
            if short ~= g and IsPlayerAceAllowed(tostring(src), short) then
                return true
            end
        end
    end

    -- Framework group fallbacks (optional, non-fatal)
    local okEsx, esxObj = pcall(function()
        return ESX or (exports["es_extended"] and exports["es_extended"]:getSharedObject())
    end)
    if okEsx and esxObj and esxObj.GetPlayerFromId then
        local xPlayer = esxObj.GetPlayerFromId(src)
        if xPlayer and xPlayer.getGroup then
            local grp = tostring(xPlayer.getGroup() or ""):lower()
            if grp == "admin" or grp == "superadmin" or grp == "god" then
                return true
            end
        end
    end

    local okQb, qbObj = pcall(function()
        return QBCore or (exports["qb-core"] and exports["qb-core"]:GetCoreObject())
    end)
    if okQb and qbObj and qbObj.Functions and qbObj.Functions.GetPlayer then
        local Player = qbObj.Functions.GetPlayer(src)
        if Player and Player.PlayerData then
            local job = Player.PlayerData.job
            local name = job and tostring(job.name or ""):lower() or ""
            if name == "admin" or name == "god" then return true end
            -- QB permission bit
            if Player.PlayerData.permission then
                local perm = tostring(Player.PlayerData.permission):lower()
                if perm == "admin" or perm == "god" or perm == "mod" then return true end
            end
        end
    end
    return false
end

local function carxacBanViaTxAdmin(target, reason, duration)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end
    local banCfg = CARXAC.BanSystem or {}
    local dur = tostring(duration or banCfg.DefaultDuration or "permanent")
    local prefix = tostring(banCfg.ReasonPrefix or "[CARXAC] ")
    local clean = tostring(reason or "Cheating"):gsub('"', "'"):gsub("[%c]", " "):sub(1, 180)
    local fullReason = prefix .. clean
    -- txaBan is provided by the monitor/txAdmin resource
    local cmd = ("txaBan %s %s %s"):format(target, dur, fullReason)
    local ok = pcall(function()
        ExecuteCommand(cmd)
    end)
    if ok then
        print(("^1[CARXAC]^0 txAdmin ban issued: %s"):format(cmd))
        return true
    end
    print("^3[CARXAC]^0 txaBan ExecuteCommand failed — is monitor/txAdmin running?")
    return false
end

local function databasePermission(src, kind)
    src = tonumber(src)
    local tableName = PERMISSION_TABLES[kind]
    if not src or not tableName or not GetPlayerName(src) then return false end

    PERMISSION_CACHE[src] = PERMISSION_CACHE[src] or {}
    local cached = PERMISSION_CACHE[src][kind]
    local t = monotonicMs()
    if cached and cached.expiresAt > t then return cached.value end

    local identifiers = permissionIdentifiers(src)
    if #identifiers == 0 then return false end

    local placeholders, params = {}, {}
    for index, identifier in ipairs(identifiers) do
        local key = "@id" .. index
        placeholders[#placeholders + 1] = key
        params[key] = identifier
    end

    local p = promise.new()
    MySQL.Async.fetchAll(("SELECT id FROM %s WHERE identifier IN (%s) LIMIT 1"):format(tableName, table.concat(placeholders, ",")), params,
        function(rows)
            local value = rows ~= nil and rows[1] ~= nil
            PERMISSION_CACHE[src][kind] = { value = value, expiresAt = monotonicMs() + 15000 }
            p:resolve(value)
        end)
    return Citizen.Await(p)
end

local function acePermission(src, permission)
    if not permission or permission == "" then return false end
    return IsPlayerAceAllowed(tostring(src), permission) == true
end

function CARXAC_WHITELIST(SRC)
    local src = tonumber(SRC)
    if not src then return false end
    -- Admins are always treated as whitelisted for detection bypass
    if CARXAC_GETADMINS(src) then return true end
    local access = CARXAC.AdminAccess or {}
    if access.UseDatabase == true then
        return databasePermission(src, "whitelist")
    end
    return false
end

function CARXAC_GETADMINS(SRC)
    local src = tonumber(SRC)
    if not src then return false end

    local access = CARXAC.AdminAccess or {}

    -- 1) txAdmin authenticated staff (primary)
    if access.UseTxAdmin ~= false and isTxAdminStaff(src) then
        return true
    end

    -- 2) Admin groups: group.admin / group.god / admin (server.cfg principals)
    if access.UseAdminGroup ~= false and isAdminGroup(src) then
        return true
    end

    -- 3) Optional carxac_admin table (off by default)
    if access.UseDatabase == true then
        return databasePermission(src, "admin")
    end

    -- Legacy CARXAC.ACE path is disabled (Enable = false). Do not use custom ACE.
    return false
end

function CARXAC_UNBANACCESS(SRC)
    local src = tonumber(SRC)
    if not src then return false end
    -- Same staff that can open Control Center can unban
    if CARXAC_GETADMINS(src) then return true end
    local access = CARXAC.AdminAccess or {}
    if access.UseDatabase == true then
        return databasePermission(src, "unban")
    end
    return false
end

function CARXAC_IS_TRUSTED(SRC)
    local src = tonumber(SRC)
    if not src then return false end
    if TRUSTED_ADMINS[src] == true then return true end
    if CARXAC_CHECK_TEMP_WHITELIST(src) then return true end
    if CARXAC_GETADMINS(src) then return true end
    if CARXAC_WHITELIST(src) then return true end
    return false
end

invalidatePermissionCache = function(src)
    if src then
        PERMISSION_CACHE[tonumber(src)] = nil
    else
        PERMISSION_CACHE = {}
    end
end

function CARXAC_ERROR(SERVER_NAME, ERROR_MESSAGE)
    local message = tostring(ERROR_MESSAGE or "Unknown CARXAC error")
    print(("^1[CARXAC ERROR]^0 %s"):format(message))

    local webhook = CARXAC.Webhooks and CARXAC.Webhooks.Error or ""
    if type(webhook) ~= "string" or not webhook:match("^https?://") then return end

    PerformHttpRequest(webhook, function() end, "POST", json.encode({
        username = "CARXAC",
        embeds = {{
            title = "CARXAC warning",
            description = ("Server: %s\nError: `%s`"):format(tostring(SERVER_NAME or "Unknown"), message:sub(1, 1500)),
            color = 16753920
        }}
    }), { ["Content-Type"] = "application/json" })
end

function CARXAC_BAN(SRC, REASON)
    local src = tonumber(SRC)
    local reason = type(REASON) == "string" and REASON:sub(1, 1000) or nil
    if not src or not reason or not GetPlayerName(src) then
        CARXAC_ERROR(CARXAC.ServerConfig.Name, "CARXAC_BAN received an invalid source or reason")
        return false
    end

    local identifiers = {
        steam = "__NONE__", discord = "__NONE__", license = "__NONE__",
        live = "__NONE__", xbl = "__NONE__"
    }
    for _, value in ipairs(GetPlayerIdentifiers(src)) do
        local kind, identifier = value:match("^([^:]+):(.+)$")
        if kind == "discord" then identifiers.discord = identifier
        elseif kind and identifiers[kind] then identifiers[kind] = value end
    end

    local tokens = {}
    local tokenCount = tonumber(GetNumPlayerTokens(src)) or 0
    for index = 0, tokenCount - 1 do
        local token = GetPlayerToken(src, index)
        if type(token) == "string" and token ~= "" then tokens[#tokens + 1] = token end
    end

    local banId = os.time() * 1000 + math.random(0, 999)
    local playerName = carxacDbName(GetPlayerName(src))
    local hasNameColumn = carxacEnsureColumn("carxac_banlist", "PLAYER_NAME", "varchar(128) NULL DEFAULT NULL AFTER `id`")
    local p = promise.new()

    local params = {
        ["@steam"] = identifiers.steam, ["@discord"] = identifiers.discord,
        ["@license"] = identifiers.license, ["@live"] = identifiers.live,
        ["@xbl"] = identifiers.xbl, ["@ip"] = GetPlayerEndpoint(src) or "__NONE__",
        ["@tokens"] = json.encode(tokens), ["@banid"] = banId, ["@reason"] = reason,
        ["@player_name"] = playerName
    }

    if hasNameColumn then
        MySQL.Async.execute([[INSERT INTO carxac_banlist
            (PLAYER_NAME, STEAM, DISCORD, LICENSE, LIVE, XBL, IP, TOKENS, BANID, REASON)
            VALUES (@player_name, @steam, @discord, @license, @live, @xbl, @ip, @tokens, @banid, @reason)]], params, function(rowsChanged)
            p:resolve((tonumber(rowsChanged) or 0) > 0)
        end)
    else
        MySQL.Async.execute([[INSERT INTO carxac_banlist
            (STEAM, DISCORD, LICENSE, LIVE, XBL, IP, TOKENS, BANID, REASON)
            VALUES (@steam, @discord, @license, @live, @xbl, @ip, @tokens, @banid, @reason)]], params, function(rowsChanged)
            p:resolve((tonumber(rowsChanged) or 0) > 0)
        end)
    end

    local inserted = Citizen.Await(p)
    return inserted and banId or false
end

local function carxacCleanBanReason(value, fallback)
    local text = tostring(value or fallback or "Banned by CARXAC")
    text = text:gsub("[%c]", " "):gsub("%s+", " "):sub(1, 240)
    if text == "" then text = fallback or "Banned by CARXAC" end
    return text
end

function CARXAC_BAN_PLAYER(targetId, reason, issuer)
    local target = tonumber(targetId)
    if not target or target <= 0 or not GetPlayerName(target) then
        return false, "invalid_player"
    end

    local finalReason = carxacCleanBanReason(reason, "Banned by CARXAC")
    local finalIssuer = carxacCleanBanReason(issuer or GetInvokingResource() or "server", "server")
    local playerName = GetPlayerName(target) or ("ID " .. tostring(target))
    local details = "Issued by " .. finalIssuer

    if CARXAC.ScreenShot and CARXAC.ScreenShot.Enable
        and GetResourceState("discord-screenshot") == "started"
        and CARXAC.Webhooks and type(CARXAC.Webhooks.ScreenShot) == "string"
        and CARXAC.Webhooks.ScreenShot:match("^https?://") then
        CARXAC_SCREENSHOT(target, finalReason, details, "BAN")
    end

    CARXAC_SENDLOG(target, CARXAC.Webhooks and CARXAC.Webhooks.Ban or "", "BAN", finalReason, details)
    CARXAC_MESSAGE(target, "BAN", playerName, finalReason)

    local provider = tostring((CARXAC.BanSystem and CARXAC.BanSystem.Provider) or "txadmin"):lower()
    local brandEmoji = Emoji and Emoji.Brand or "🛡️"
    local txOk, internalId = false, false

    if provider == "txadmin" or provider == "both" then
        txOk = carxacBanViaTxAdmin(target, finalReason)
    end
    if provider == "internal" or provider == "both" then
        internalId = CARXAC_BAN(target, finalReason)
    end

    if txOk or internalId then
        local ref = internalId and tostring(internalId) or "txAdmin"
        print(("^1[CARXAC]^0 Banned ^3%s^0 | %s | By: %s | Provider: %s | Ref: %s"):format(
            playerName, finalReason, finalIssuer, provider, ref))
        if GetPlayerName(target) then
            DropPlayer(target, ("\n[%s CARXAC %s]\n%s\nReason: %s"):format(brandEmoji, brandEmoji,
                CARXAC.Message and CARXAC.Message.Ban or "You have been banned.", finalReason))
        end
        return true, ref
    end

    CARXAC_ERROR(CARXAC.ServerConfig.Name, "External/admin ban could not be persisted; player was kicked instead")
    DropPlayer(target, ("\n[%s CARXAC %s]\n%s\nReason: %s"):format(brandEmoji, brandEmoji,
        CARXAC.Message and CARXAC.Message.Kick or "You have been kicked.", finalReason))
    return false, "ban_failed"
end

function BanPlayer(targetId, reason, issuer)
    return CARXAC_BAN_PLAYER(targetId, reason, issuer)
end

RegisterCommand("carxacban", function(src, args)
    args = args or {}
    local executor = tonumber(src) or 0
    if executor > 0 and not CARXAC_GETADMINS(executor) then
        CARXAC_ACTION(executor, CARXAC.AdminMenu.MenuPunishment, "Anti Ban Players", "Unauthorized carxacban command")
        return
    end

    local target = tonumber(args and args[1])
    if not target or not GetPlayerName(target) then
        print("^1[CARXAC]^0 Usage: carxacban [server_id] [reason]")
        return
    end

    table.remove(args, 1)
    local reason = table.concat(args or {}, " ")
    if reason == "" then reason = "Banned by CARXAC command" end

    local issuer = executor > 0 and ("Admin " .. (GetPlayerName(executor) or tostring(executor)) .. " (" .. tostring(executor) .. ")") or "server console"
    CARXAC_BAN_PLAYER(target, reason, issuer)
end, false)

RegisterCommand("carxacunban", function(src, args)
    args = args or {}
    local executor = tonumber(src) or 0
    if executor > 0 and not CARXAC_GETADMINS(executor) then
        CARXAC_ACTION(executor, CARXAC.AdminMenu.MenuPunishment, "Anti Unban", "Unauthorized carxacunban command")
        return
    end

    local banId = tonumber(args and args[1])
    if not banId then
        print("^1[CARXAC]^0 Usage: carxacunban [ban_id]")
        return
    end

    local issuer = executor > 0 and ("Admin " .. (GetPlayerName(executor) or tostring(executor)) .. " (" .. tostring(executor) .. ")") or "server console"
    local ok, result = CARXAC_UNBAN_PLAYER(banId, issuer)
    if not ok then
        print(("^1[CARXAC]^0 Unban failed for Ban ID %s | %s"):format(tostring(banId), tostring(result)))
    end
end, false)

function CARXAC:UNBAN(BanID)
    local p = promise.new()
    if tonumber(BanID) then
        MySQL.Async.execute('DELETE FROM carxac_banlist WHERE BANID=@BANID', {
            ['@BANID'] = tonumber(BanID)
        }, function(rowsChanged)
            if rowsChanged > 0 then
                p:resolve(true)
            else
                p:resolve(false)
            end
        end)
    else
        p:resolve(false)
    end
    return Citizen.Await(p)
end

function CARXAC_UNBAN_PLAYER(banId, issuer)
    local id = tonumber(banId)
    if not id then
        return false, "invalid_ban_id"
    end

    local ok = CARXAC:UNBAN(id)
    if ok then
        local who = tostring(issuer or GetInvokingResource() or "server"):gsub("[%c]", " "):sub(1, 120)
        print(("^2[CARXAC]^0 Unbanned Ban ID ^3%s^0 | By: %s"):format(tostring(id), who))
        return true, id
    end

    return false, "not_found"
end

function UnbanPlayer(banId, issuer)
    return CARXAC_UNBAN_PLAYER(banId, issuer)
end

local ACCESS_TABLE_ALLOWLIST = {
    carxac_admin = true,
    carxac_whitelist = true,
    carxac_unban = true
}

local function addAccessIdentifier(playerId, tableName)
    local p = promise.new()
    playerId = tonumber(playerId)
    if not playerId or not ACCESS_TABLE_ALLOWLIST[tableName] or not GetPlayerName(playerId) then
        p:resolve(false)
        return Citizen.Await(p)
    end

    local license
    for _, identifier in ipairs(GetPlayerIdentifiers(playerId)) do
        if identifier:sub(1, 8) == "license:" then
            license = identifier
            break
        end
    end
    if not license then
        p:resolve(false)
        return Citizen.Await(p)
    end

    local playerName = carxacDbName(GetPlayerName(playerId))
    local hasNameColumn = carxacEnsureColumn(tableName, "player_name", "varchar(128) NULL DEFAULT NULL AFTER `identifier`")

    MySQL.Async.fetchScalar(("SELECT id FROM `%s` WHERE identifier=@identifier LIMIT 1"):format(tableName), {
        ["@identifier"] = license
    }, function(existing)
        if existing then
            if hasNameColumn then
                MySQL.Async.execute(("UPDATE `%s` SET player_name=@player_name WHERE identifier=@identifier"):format(tableName), {
                    ["@identifier"] = license,
                    ["@player_name"] = playerName
                }, function()
                    invalidatePermissionCache(playerId)
                    p:resolve(true)
                end)
            else
                invalidatePermissionCache(playerId)
                p:resolve(true)
            end
            return
        end

        if hasNameColumn then
            MySQL.Async.execute(("INSERT INTO `%s` (`identifier`, `player_name`) VALUES (@identifier, @player_name)"):format(tableName), {
                ["@identifier"] = license,
                ["@player_name"] = playerName
            }, function(rowsChanged)
                invalidatePermissionCache(playerId)
                p:resolve((tonumber(rowsChanged) or 0) > 0)
            end)
        else
            MySQL.Async.execute(("INSERT INTO `%s` (`identifier`) VALUES (@identifier)"):format(tableName), {
                ["@identifier"] = license
            }, function(rowsChanged)
                invalidatePermissionCache(playerId)
                p:resolve((tonumber(rowsChanged) or 0) > 0)
            end)
        end
    end)
    return Citizen.Await(p)
end

function CARXAC:ADDADMIN(Player_ID)
    return addAccessIdentifier(Player_ID, "carxac_admin")
end

function CARXAC:ADDWHITELIST(Player_ID)
    return addAccessIdentifier(Player_ID, "carxac_whitelist")
end

function CARXAC:ADDUNBAN(Player_ID)
    return addAccessIdentifier(Player_ID, "carxac_unban")
end

function CARXAC_INBANLIST(SRC)
    local p = promise.new()
    local src = tonumber(SRC)
    if not src then
        p:resolve(false)
        return Citizen.Await(p)
    end

    local identifiers = {
        steam = "__NO_STEAM__", discord = "__NO_DISCORD__", license = "__NO_LICENSE__",
        live = "__NO_LIVE__", xbl = "__NO_XBL__"
    }
    for _, value in ipairs(GetPlayerIdentifiers(src)) do
        local kind, identifier = value:match("^([^:]+):(.+)$")
        if kind == "discord" then
            identifiers.discord = identifier
        elseif kind and identifiers[kind] then
            identifiers[kind] = value
        end
    end

    local token = GetPlayerToken(src, 0)
    local tokenPattern = type(token) == "string" and token ~= "" and ("%%" .. token .. "%%") or "%__NO_TOKEN__%"
    MySQL.Async.fetchAll([[SELECT * FROM carxac_banlist
        WHERE STEAM = @steam OR DISCORD = @discord OR LICENSE = @license
           OR LIVE = @live OR XBL = @xbl OR IP = @ip OR TOKENS LIKE @token
        ORDER BY id DESC LIMIT 1]], {
        ["@steam"] = identifiers.steam,
        ["@discord"] = identifiers.discord,
        ["@license"] = identifiers.license,
        ["@live"] = identifiers.live,
        ["@xbl"] = identifiers.xbl,
        ["@ip"] = GetPlayerEndpoint(src) or "__NO_IP__",
        ["@token"] = tokenPattern,
    }, function(result)
        p:resolve(result and #result > 0 and result or false)
    end)

    return Citizen.Await(p)
end

function CARXAC_ACTION(SRC, ACTION, REASON, DETAILS)
    local src = tonumber(SRC)
    local action = tostring(ACTION or "WARN"):upper()
    local reason = tostring(REASON or "Unknown detection")
    local details = tostring(DETAILS or "No details")

    if not src or src <= 0 or not GetPlayerName(src) then return false end
    if action ~= "WARN" and action ~= "KICK" and action ~= "BAN" then action = "WARN" end
    if CARXAC_IS_TRUSTED(src) then return false end
    if CARXAC_IS_SPAMLIST(src, action, reason, details) then return false end
    CARXAC_ADD_SPAMLIST(src, action, reason, details)

    if CARXAC.ScreenShot and CARXAC.ScreenShot.Enable
        and GetResourceState("discord-screenshot") == "started"
        and CARXAC.Webhooks and type(CARXAC.Webhooks.ScreenShot) == "string"
        and CARXAC.Webhooks.ScreenShot:match("^https?://") then
        CARXAC_SCREENSHOT(src, reason, details, action)
    end

    local playerName = GetPlayerName(src) or ("ID " .. src)
    if type(CARXAC_LogDetection) == "function" then
        pcall(CARXAC_LogDetection, src, action, reason, details)
    end
    CARXAC_SENDLOG(src, CARXAC.Webhooks and CARXAC.Webhooks.Ban or "", action, reason, details)
    CARXAC_MESSAGE(src, action, playerName, reason)

    if action == "WARN" then
        print(("^3[CARXAC]^0 Warning for ^3%s^0 | %s"):format(playerName, reason))
        return true
    end

    local brandEmoji = Emoji and Emoji.Brand or "🛡️"
    if action == "BAN" then
        local provider = tostring((CARXAC.BanSystem and CARXAC.BanSystem.Provider) or "txadmin"):lower()
        local txOk, internalId = false, false

        if provider == "txadmin" or provider == "both" then
            txOk = carxacBanViaTxAdmin(src, reason)
        end
        if provider == "internal" or provider == "both" then
            internalId = CARXAC_BAN(src, reason)
        end

        if txOk or internalId then
            local idLabel = internalId and tostring(internalId) or "txAdmin"
            print(("^1[CARXAC]^0 Banned ^3%s^0 | %s | Provider: %s | Ref: %s"):format(playerName, reason, provider, idLabel))
            if GetPlayerName(src) then
                DropPlayer(src, ("\n[%s CARXAC %s]\n%s\nReason: %s"):format(brandEmoji, brandEmoji,
                    CARXAC.Message and CARXAC.Message.Ban or "You have been banned.", reason))
            end
        else
            CARXAC_ERROR(CARXAC.ServerConfig.Name, "Ban failed (txAdmin/internal); player was kicked instead")
            DropPlayer(src, ("\n[%s CARXAC %s]\n%s\nReason: %s"):format(brandEmoji, brandEmoji,
                CARXAC.Message and CARXAC.Message.Kick or "You have been kicked.", reason))
        end
        return true
    end

    print(("^1[CARXAC]^0 Kicked ^3%s^0 | %s"):format(playerName, reason))
    DropPlayer(src, ("\n[%s CARXAC %s]\n%s\nReason: %s"):format(brandEmoji, brandEmoji,
        CARXAC.Message and CARXAC.Message.Kick or "You have been kicked.", reason))
    return true
end

function CARXAC_MESSAGE(SRC, TYPE, NAME, REASON)
    local settings = CARXAC.ChatSettings or {}
    if not settings.Enable then return end
    local src = tonumber(SRC)
    local kind = tostring(TYPE or "WARN"):upper()
    local name = tostring(NAME or "Unknown"):gsub("[%c]", ""):sub(1, 80)
    local reason = tostring(REASON or "Unknown"):gsub("[%c]", " "):sub(1, 240)
    local icon = kind == "BAN" and (Emoji and Emoji.Ban or "⛔")
        or kind == "KICK" and (Emoji and Emoji.Kick or "👢")
        or (Emoji and Emoji.Warn or "⚠️")
    local payload = {
        color = kind == "WARN" and {255, 170, 0} or {255, 70, 70},
        multiline = true,
        args = { "CARXAC", ("%s %s | %s (%s): %s"):format(icon, kind, name, tostring(src or "?"), reason) }
    }

    if kind == "WARN" and settings.PrivateWarn then
        for _, playerId in ipairs(GetPlayers()) do
            if CARXAC_GETADMINS(playerId) then TriggerClientEvent("chat:addMessage", playerId, payload) end
        end
    else
        TriggerClientEvent("chat:addMessage", -1, payload)
    end
end

local function validWebhook(url)
    return type(url) == "string" and url:match("^https?://") ~= nil and not url:find("YOUR_WEBHOOK", 1, true)
end

local function limited(value, length)
    value = tostring(value or "Not Found")
    if #value > length then return value:sub(1, length - 3) .. "..." end
    return value
end

local function getIdentitySummary(src)
    local ids = { steam = "Not Found", discord = "Not Found", license = "Not Found", live = "Not Found", xbl = "Not Found" }
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        local kind = identifier:match("^([^:]+):")
        if kind == "steam" then ids.steam = identifier
        elseif kind == "discord" then ids.discord = "<@" .. identifier:sub(9) .. ">"
        elseif kind == "license" then ids.license = identifier
        elseif kind == "live" then ids.live = identifier
        elseif kind == "xbl" then ids.xbl = identifier end
    end
    return ids
end

function CARXAC_SENDLOG(SRC, URL, TYPE, REASON, DETAILS)
    local src = tonumber(SRC)
    if not src or not GetPlayerName(src) or not validWebhook(URL) then return false end

    local kind = tostring(TYPE or "INFO"):upper()
    local colors = { BAN = 16711680, KICK = 16744192, WARN = 16763904, CONNECT = 5763719, DISCONNECT = 9807270, EXPLOSION = 16724787 }
    local ids = getIdentitySummary(src)
    local ped = GetPlayerPed(src)
    local coordsText = "Unavailable"
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local c = GetEntityCoords(ped)
        coordsText = ("%.2f, %.2f, %.2f"):format(c.x, c.y, c.z)
    end
    local endpoint = GetPlayerEndpoint(src) or "Not Found"
    if CARXAC.Connection and CARXAC.Connection.HideIP then endpoint = "Hidden by owner" end

    local description = table.concat({
        ("**Player:** %s (`%s`)"):format(limited(GetPlayerName(src), 120), src),
        ("**Type:** %s"):format(limited(kind, 40)),
        ("**Reason:** %s"):format(limited(REASON, 700)),
        ("**Details:** %s"):format(limited(DETAILS, 1200)),
        ("**License:** `%s`"):format(limited(ids.license, 150)),
        ("**Discord:** %s"):format(limited(ids.discord, 150)),
        ("**Steam:** `%s`"):format(limited(ids.steam, 150)),
        ("**Endpoint:** `%s`"):format(limited(endpoint, 100)),
        ("**Coords:** `%s`"):format(coordsText),
        ("**Ping:** `%sms`"):format(GetPlayerPing(src) or 0),
    }, "\n")

    PerformHttpRequest(URL, function(status)
        if status and status >= 400 then
            print(("^3[CARXAC]^0 Discord webhook returned HTTP %s"):format(status))
        end
    end, "POST", json.encode({
        username = "CARXAC Security",
        embeds = {{
            title = "CARXAC • " .. limited(kind, 60),
            description = description,
            color = colors[kind] or 16744448,
            footer = { text = ("CARXAC %s • %s"):format(tostring(CARXAC.Version), os.date("!%Y-%m-%d %H:%M:%S UTC")) }
        }}
    }), { ["Content-Type"] = "application/json" })
    return true
end

function CARXAC_REFRESHCMD()
    SERVER_CMDS = {}
    for _, command in ipairs(GetRegisteredCommands() or {}) do
        if type(command) == "table" and type(command.name) == "string" then
            SERVER_CMDS[command.name] = true
        end
    end
    return SERVER_CMDS
end

function CARXAC_ISPLAYERLOAD(source)
    local SRC = tonumber(source)
    local PED = GetPlayerPed(SRC)
    local STATUS = false
    if SRC ~= nil then
        if DoesEntityExist(PED) then
            if SPAWNED[SRC] ~= nil then
                STATUS = true
            else
                STATUS = false
            end
        else
            STATUS = false
        end
    else
        STATUS = false
    end
    return STATUS
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000)
        for index in pairs(SPAMLIST) do
            SPAMLIST[index] = nil
        end
        Citizen.Wait(0)
    end
end)

function CARXAC_ADD_SPAMLIST(SRC, ACTION, REASON, DETAILS)
    local src = tonumber(SRC)
    if not src then return end
    SPAMLIST[src] = SPAMLIST[src] or {}
    local key = table.concat({ tostring(ACTION), tostring(REASON), tostring(DETAILS) }, "|")
    SPAMLIST[src][key] = monotonicMs() + 10000
end

function CARXAC_IS_SPAMLIST(SRC, ACTION, REASON, DETAILS)
    local src = tonumber(SRC)
    if not src or not SPAMLIST[src] then return false end
    local key = table.concat({ tostring(ACTION), tostring(REASON), tostring(DETAILS) }, "|")
    local expires = SPAMLIST[src][key]
    if not expires then return false end
    if monotonicMs() >= expires then
        SPAMLIST[src][key] = nil
        return false
    end
    return true
end

function CARXAC_SCREENSHOT(SRC, REASON, DETAILS, ACTION)
    local src = tonumber(SRC)
    local webhook = CARXAC.Webhooks and CARXAC.Webhooks.ScreenShot or ""
    if not src or not GetPlayerName(src) or not validWebhook(webhook) then return false end
    if GetResourceState("discord-screenshot") ~= "started" then return false end

    local colors = { WARN = 16763904, KICK = 16744192, BAN = 16711680 }
    local ids = getIdentitySummary(src)
    local options = {
        encoding = (CARXAC.ScreenShot and CARXAC.ScreenShot.Format) or "jpg",
        quality = math.max(0.1, math.min(tonumber(CARXAC.ScreenShot and CARXAC.ScreenShot.Quality) or 0.75, 1.0))
    }
    local payload = {
        username = "CARXAC Security",
        embeds = {{
            title = "CARXAC • Screenshot",
            color = colors[tostring(ACTION or "WARN"):upper()] or colors.WARN,
            description = table.concat({
                ("**Player:** %s (`%s`)"):format(limited(GetPlayerName(src), 120), src),
                ("**Reason:** %s"):format(limited(REASON, 700)),
                ("**Details:** %s"):format(limited(DETAILS, 1200)),
                ("**License:** `%s`"):format(limited(ids.license, 150)),
                ("**Discord:** %s"):format(limited(ids.discord, 150))
            }, "\n"),
            footer = { text = ("CARXAC %s • %s"):format(tostring(CARXAC.Version), os.date("!%Y-%m-%d %H:%M:%S UTC")) }
        }}
    }

    local ok, err = pcall(function()
        exports["discord-screenshot"]:requestCustomClientScreenshotUploadToDiscord(src, webhook, options, payload)
    end)
    if not ok then
        print(("^3[CARXAC]^0 Screenshot request failed: %s"):format(tostring(err)))
        return false
    end
    return true
end

function CARXAC_CHANGE_TEMP_WHHITELIST(SRC, STATUS, DURATION_MS)
    local src = tonumber(SRC)
    if not src then return false end
    if STATUS == true then
        local duration = math.max(1000, math.min(tonumber(DURATION_MS) or 15000, 600000))
        TEMP_WHITELIST[src] = monotonicMs() + duration
        return true
    end
    TEMP_WHITELIST[src] = nil
    return true
end

function CARXAC_CHANGE_TEMP_WHITELIST(SRC, STATUS, DURATION_MS)
    return CARXAC_CHANGE_TEMP_WHHITELIST(SRC, STATUS, DURATION_MS)
end

function CARXAC_CHECK_TEMP_WHITELIST(SRC)
    local src = tonumber(SRC)
    if not src then return false end
    local expires = TEMP_WHITELIST[src]
    if not expires then return false end
    if monotonicMs() >= expires then
        TEMP_WHITELIST[src] = nil
        return false
    end
    return true
end

RegisterNetEvent("CARXAC:adminState", function(enabled, durationMs)
    local src = tonumber(source)
    if not src then return end
    if not RateLimit(src, "adminState", 8, 30000) then return end
    if not CARXAC_GETADMINS(src) then
        CARXAC_ACTION(src, CARXAC.AdminMenu.MenuPunishment, "Anti Open Admin Menu",
            "Unauthorized admin exemption request")
        return
    end
    -- Server clamps duration — client cannot request arbitrary long grace
    local dur = math.max(1000, math.min(tonumber(durationMs) or 30000, 120000))
    if enabled == true then
        carxacGrantActionGrace(src, dur, "adminMode")
    else
        CARXAC_CHANGE_TEMP_WHHITELIST(src, false, 0)
    end
end)

RegisterCommand('funban', function(source, args)
    local BAN_ID = args[1]

    if source == 0 then
        local unbaned = CARXAC:UNBAN(BAN_ID)

        if unbaned then
            print("^" .. COLORS .. "[CARXAC]^0: You unbanned ^2" .. tostring(BAN_ID) .. "^0 !")
        else
            print("^" .. COLORS .. "[CARXAC]^0: ^1 unban failed !^0")
        end
    else
        if CARXAC_UNBANACCESS(source) then
            local unbaned = CARXAC:UNBAN(BAN_ID)

            if unbaned then
                TriggerClientEvent("chatMessage", source, "[CARXAC]", { 255, 0, 0 }, "You unbanned ^2" .. tostring(BAN_ID) ..
                    "^0 !")
            else
                TriggerClientEvent("chatMessage", source, "[CARXAC]", { 255, 0, 0 }, "Your unbanned failed !")
            end
        else
            TriggerClientEvent("chatMessage", source, "[CARXAC]", { 255, 0, 0 },
                "You don't have access for unban players !")
        end
    end
end)

RegisterCommand('unban', function(source, args)
    local BAN_ID = args[1]
    if source == 0 then
        local unbaned = CARXAC:UNBAN(BAN_ID)
        if unbaned then
            print("^" .. COLORS .. "[CARXAC]^0: You unbanned ^2" .. tostring(BAN_ID) .. "^0 !")
        else
            print("^" .. COLORS .. "[CARXAC]^0: ^1 unban failed !^0")
        end
    elseif CARXAC_UNBANACCESS(source) then
        local unbaned = CARXAC:UNBAN(BAN_ID)
        if unbaned then
            TriggerClientEvent("chatMessage", source, "[CARXAC]", { 255, 0, 0 }, "You unbanned ^2" .. tostring(BAN_ID) .. "^0 !")
        else
            TriggerClientEvent("chatMessage", source, "[CARXAC]", { 255, 0, 0 }, "Your unban failed !")
        end
    else
        TriggerClientEvent("chatMessage", source, "[CARXAC]", { 255, 0, 0 }, "You don't have access for unban players !")
    end
end)

RegisterCommand('addadmin', function(source, args)
    local PLAYER_ID = tonumber(args[1])

    if source == 0 then
        if PLAYER_ID and GetPlayerName(PLAYER_ID) then
            local addedAdmin = CARXAC:ADDADMIN(PLAYER_ID)

            if addedAdmin then
                TRUSTED_ADMINS[PLAYER_ID] = true
                invalidatePermissionCache(PLAYER_ID)
                CARXAC_CHANGE_TEMP_WHHITELIST(PLAYER_ID, true, 120000)
                print("^" ..
                    COLORS ..
                    "[CARXAC]^0: You added ^2" .. GetPlayerName(PLAYER_ID) .. "(" .. PLAYER_ID .. ")^0 to admin list^0 !")
                TriggerClientEvent("CARXAC:clientGrace", PLAYER_ID, 120000)
                TriggerClientEvent("CARXAC:allowToOpen", PLAYER_ID, true)
            else
                print("^" .. COLORS .. "[CARXAC]^0: ^1 add admin failed !^0")
            end
        else
            print("^" .. COLORS .. "[CARXAC]^0: ^1 This player isn't online !^0")
        end
    end
end)

RegisterCommand('addwhitelist', function(source, args)
    local PLAYER_ID = tonumber(args[1])

    if source == 0 then
        if PLAYER_ID and GetPlayerName(PLAYER_ID) then
            local addedAdmin = CARXAC:ADDWHITELIST(PLAYER_ID)

            if addedAdmin then
                invalidatePermissionCache(PLAYER_ID)
                CARXAC_CHANGE_TEMP_WHHITELIST(PLAYER_ID, true, 120000)
                TriggerClientEvent("CARXAC:clientGrace", PLAYER_ID, 120000)
                print("^" ..
                    COLORS ..
                    "[CARXAC]^0: You added ^2" .. GetPlayerName(PLAYER_ID) .. "(" .. PLAYER_ID .. ")^0 to whitelist^0 !")
            else
                print("^" .. COLORS .. "[CARXAC]^0: ^1 failed to add access !^0")
            end
        else
            print("^" .. COLORS .. "[CARXAC]^0: ^1 This player isn't online !^0")
        end
    end
end)

RegisterCommand('addunban', function(source, args)
    local PLAYER_ID = tonumber(args[1])

    if source == 0 then
        if PLAYER_ID and GetPlayerName(PLAYER_ID) then
            local addedAdmin = CARXAC:ADDUNBAN(PLAYER_ID)

            if addedAdmin then
                print("^" ..
                    COLORS ..
                    "[CARXAC]^0: You added ^2" ..
                    GetPlayerName(PLAYER_ID) .. "(" .. PLAYER_ID .. ")^0 to unban access^0 !")
            else
                print("^" .. COLORS .. "[CARXAC]^0: ^1 failed to add access !^0")
            end
        else
            print("^" .. COLORS .. "[CARXAC]^0: ^1 This player isn't online !^0")
        end
    end
end)
