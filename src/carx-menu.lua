-- CARXAC - Carx Anti-Cheat
-- Licensed under the GNU Affero General Public License v3.0

local isAdmin = false
local pendingAdminMenuOpen = false
local playerLocations = { coords = nil, heading = nil }

local cam = nil
local InSpectatorMode = false
local TargetSpectate = nil
local targetPed = nil
local currentVoiceChannel = nil
local health, maxhealth, armor = nil, nil, nil
local radius = -1
local polarAngleDeg, azimuthAngleDeg = 0, 0

local adminModes = {
    godmode = false,
    invisible = false,
    night = false,
    thermal = false,
    spectate = false,
    weaponKit = false,
}

local function hasPersistentAdminMode()
    for _, enabled in pairs(adminModes) do
        if enabled then return true end
    end
    return false
end

local function grantAdminGrace(duration)
    if not isAdmin then return false end
    duration = math.max(1000, math.min(tonumber(duration) or 15000, 600000))
    TriggerServerEvent("CARXAC:adminState", true, duration)
    TriggerEvent("CARXAC:clientGrace", duration)
    return true
end

local function refreshPersistentAdminState()
    if not isAdmin then return false end
    if hasPersistentAdminMode() then
        TriggerServerEvent("CARXAC:adminState", true, 90000)
        TriggerEvent("CARXAC:clientGrace", 90000)
    else
        TriggerServerEvent("CARXAC:adminState", false, 0)
        TriggerEvent("CARXAC:clientGrace", 5000)
    end
    return true
end

CreateThread(function()
    while true do
        Wait(30000)
        if isAdmin and hasPersistentAdminMode() then
            refreshPersistentAdminState()
        end
    end
end)

local function carxacNotify(msg)
    msg = tostring(msg or "")
    BeginTextCommandThefeedDisplay("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedDisplay(0, true)
    print(("[CARXAC] %s"):format(msg))
end

RegisterNetEvent("CARXAC:allowToOpen")
AddEventHandler("CARXAC:allowToOpen", function(allowed)
    local wasPending = pendingAdminMenuOpen
    isAdmin = allowed == true

    if isAdmin then
        if wasPending then
            pendingAdminMenuOpen = false
            CreateThread(function()
                Wait(50)
                if not IsPauseMenuActive() then
                    openAdminMenu()
                end
            end)
        end
        return
    end

    -- Not admin
    if wasPending then
        pendingAdminMenuOpen = false
        carxacNotify("~r~CARXAC:~s~ No admin access. Open txAdmin menu once, or add yourself to group.admin.")
    end

    if InSpectatorMode then exitSpectate() end
    for mode in pairs(adminModes) do adminModes[mode] = false end
    SetEntityInvincible(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    SetNightvision(false)
    SetSeethrough(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "forceClose" })
end)

RegisterNetEvent("CARXAC:sendAllPlayerData")
AddEventHandler("CARXAC:sendAllPlayerData", function(playerList)
    if not isAdmin then return end
    updatePlayerList(playerList)
end)

RegisterNetEvent("CARXAC:openPlayerData")
AddEventHandler("CARXAC:openPlayerData", function(data)
    if not isAdmin then return end
    openPlayerAction(data)
end)

RegisterNetEvent("CARXAC:spectatePlayer")
AddEventHandler("CARXAC:spectatePlayer", function(target, coords)
    if not isAdmin then return end
    if target and coords then
        spectatePlayer(target, coords)
    end
end)

RegisterNetEvent("CARXAC:updateBanListData")
AddEventHandler("CARXAC:updateBanListData", function(banList, meta)
    if not isAdmin then return end
    updateBanListData(banList, meta)
end)

RegisterNetEvent("CARXAC:updateAdminData")
AddEventHandler("CARXAC:updateAdminData", function(adminList, meta)
    if not isAdmin then return end
    updateAdminData(adminList, meta)
end)

RegisterNetEvent("CARXAC:updateUnbanAccess")
AddEventHandler("CARXAC:updateUnbanAccess", function(unbanList, meta)
    if not isAdmin then return end
    updateUnbanAccess(unbanList, meta)
end)

RegisterNetEvent("CARXAC:updateWhiteList")
AddEventHandler("CARXAC:updateWhiteList", function(whiteList, meta)
    if not isAdmin then return end
    updateWhiteList(whiteList, meta)
end)

RegisterNetEvent("CARXAC:updateAccessOnlinePlayers")
AddEventHandler("CARXAC:updateAccessOnlinePlayers", function(scope, players)
    if not isAdmin then return end
    SendNUIMessage({
        action = "updateAccessPlayers",
        scope = scope,
        players = players or {}
    })
end)

RegisterNetEvent("CARXAC:updateDashboardStats")
AddEventHandler("CARXAC:updateDashboardStats", function(stats)
    if not isAdmin then return end
    SendNUIMessage({
        action = "updateDashboardStats",
        stats = stats or {}
    })
end)

local function requestAdminMenuOpen()
    if not CARXAC or not CARXAC.AdminMenu or CARXAC.AdminMenu.Enable ~= true then
        carxacNotify("~r~CARXAC:~s~ Admin menu is disabled in config.")
        return
    end
    if IsPauseMenuActive() then return end

    -- Already focused on our NUI → close instead of blocking
    if IsNuiFocused() and isAdmin then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "forceClose" })
        return
    end

    if isAdmin then
        openAdminMenu()
        return
    end

    -- Ask server; open when allowToOpen arrives
    pendingAdminMenuOpen = true
    TriggerServerEvent("CARXAC:checkIsAdmin")

    -- Keep pending longer (txAdmin/auth or DB can be slow)
    SetTimeout(5000, function()
        if pendingAdminMenuOpen then
            pendingAdminMenuOpen = false
            carxacNotify("~r~CARXAC:~s~ Admin check timed out. Open txAdmin menu (F10) once, then try again.")
        end
    end)
end

RegisterCommand("+carxac_admin_menu", function()
    requestAdminMenuOpen()
end, false)

RegisterCommand("-carxac_admin_menu", function() end, false)

RegisterCommand("carxacmenu", function()
    requestAdminMenuOpen()
end, false)

RegisterCommand("carxac", function()
    requestAdminMenuOpen()
end, false)

-- Alias some servers expect
RegisterCommand("carx", function()
    requestAdminMenuOpen()
end, false)

RegisterKeyMapping("+carxac_admin_menu", "CARXAC - Open admin menu", "keyboard", tostring((CARXAC.AdminMenu and CARXAC.AdminMenu.Key) or "F9"))

-- Proactive admin status on join so first F9 is faster
CreateThread(function()
    Wait(3000)
    TriggerServerEvent("CARXAC:checkIsAdmin")
    Wait(10000)
    TriggerServerEvent("CARXAC:checkIsAdmin")
end)

local function requireAdmin(cb)
    if isAdmin then return true end
    if cb then cb("forbidden") end
    return false
end

RegisterNUICallback("onCloseMenu", function(data, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("getAdminStatus", function(data, cb)
    if not requireAdmin(cb) then return end
    updateAdminStatus()
    cb("ok")
end)

RegisterNUICallback("godmode", function(data, cb)
    if not requireAdmin(cb) then return end
    local playerPed = PlayerPedId()
    adminModes.godmode = not GetPlayerInvincible(PlayerId())
    SetEntityInvincible(playerPed, adminModes.godmode)
    refreshPersistentAdminState()
    cb("ok")
end)

RegisterNUICallback("invisible", function(data, cb)
    if not requireAdmin(cb) then return end
    local playerPed = PlayerPedId()
    adminModes.invisible = IsEntityVisible(playerPed)
    SetEntityVisible(playerPed, not adminModes.invisible, false)
    refreshPersistentAdminState()
    cb("ok")
end)

RegisterNUICallback("suicide", function(data, cb)
    if not grantAdminGrace(15000) then cb("forbidden") return end
    SetEntityHealth(PlayerPedId(), 0)
    cb("ok")
end)

RegisterNUICallback("heal", function(data, cb)
    if not grantAdminGrace(10000) then cb("forbidden") return end
    local playerPed = PlayerPedId()
    SetEntityHealth(playerPed, GetPedMaxHealth(playerPed))
    SetPedArmour(playerPed, math.min(GetPedArmour(playerPed), tonumber(CARXAC.MaxArmor) or 100))
    cb("ok")
end)

RegisterNUICallback("giveAllWeapon", function(data, cb)
    local weapons = { 'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_KNUCKLE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER',
        'WEAPON_BAT',
        'WEAPON_GOLFCLUB', 'WEAPON_CROWBAR', 'WEAPON_BOTTLE', 'WEAPON_DAGGER', 'WEAPON_HATCHET', 'WEAPON_MACHETE',
        'WEAPON_FLASHLIGHT', 'WEAPON_SWITCHBLADE', 'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL',
        'WEAPON_APPISTOL', 'WEAPON_PISTOL50', 'WEAPON_SNSPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL',
        'WEAPON_STUNGUN', 'WEAPON_FLAREGUN', 'WEAPON_MARKSMANPISTOL', 'WEAPON_REVOLVER', 'WEAPON_MICROSMG', 'WEAPON_SMG',
        'WEAPON_MINISMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSMG', 'WEAPON_MG', 'WEAPON_COMBATMG', 'WEAPON_COMBATMG_MK2',
        'WEAPON_COMBATPDW', 'WEAPON_GUSENBERG', 'WEAPON_RAYPISTOL', 'WEAPON_MACHINEPISTOL', 'WEAPON_ASSAULTRIFLE',
        'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2', 'WEAPON_ADVANCEDRIFLE',
        'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_PUMPSHOTGUN',
        'WEAPON_SAWNOFFSHOTGUN',
        'WEAPON_BULLPUPSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_MUSKET', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN',
        'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2', 'WEAPON_MARKSMANRIFLE',
        'WEAPON_GRENADELAUNCHER', 'WEAPON_GRENADELAUNCHER_SMOKE', 'WEAPON_RPG', 'WEAPON_STINGER', 'WEAPON_FIREWORK',
        'WEAPON_HOMINGLAUNCHER', 'WEAPON_GRENADE', 'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE', 'WEAPON_MINIGUN',
        'WEAPON_RAILGUN', 'WEAPON_POOLCUE', 'WEAPON_BZGAS', 'WEAPON_SMOKEGRENADE', 'WEAPON_MOLOTOV',
        'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN', 'WEAPON_SNOWBALL', 'WEAPON_FLARE', 'WEAPON_BALL' }
    if not requireAdmin(cb) then return end
    for _, weapon in ipairs(weapons) do
        GiveWeaponToPed(PlayerPedId(), GetHashKey(weapon), 3000, false, false)
    end
    adminModes.weaponKit = true
    refreshPersistentAdminState()
    cb("ok")
end)

RegisterNUICallback("removeAllWeapon", function(data, cb)
    if not requireAdmin(cb) then return end
    RemoveAllPedWeapons(PlayerPedId(), true)
    adminModes.weaponKit = false
    refreshPersistentAdminState()
    cb("ok")
end)

RegisterNUICallback("getPlayerCoords", function(data, cb)
    if not requireAdmin(cb) then return end
    local playerCoord = GetEntityCoords(PlayerPedId())
    local headingCoord = GetEntityHeading(PlayerPedId())

    playerLocations.coords = playerCoord
    playerLocations.heading = headingCoord

    updatePlayerCoords()

    cb("ok")
end)

RegisterNUICallback("getDashboardStats", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getDashboardStats")
    cb("ok")
end)

RegisterNUICallback("getAllPlayersData", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getAllPlayerData")
    cb("ok")
end)

RegisterNUICallback("getPlayerData", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getPlayerData", tonumber(data and data.playerId))
    cb("ok")
end)

RegisterNUICallback("spectate", function(data, cb)
    if not requireAdmin(cb) then return end
    if InSpectatorMode then
        exitSpectate()
    else
        adminModes.spectate = true
        refreshPersistentAdminState()
        TriggerServerEvent('CARXAC:requestSpectate', tonumber(data and data.playerId))
    end
    cb("ok")
end)

RegisterNUICallback("ban", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:banPlayerByAdmin", tonumber(data and data.playerId), tostring(data and data.reason or "Banned by CARXAC admin menu"))
    cb("ok")
end)

RegisterNUICallback("gotoPlayer", function(data, cb)
    if not grantAdminGrace(90000) then cb("forbidden") return end
    TriggerServerEvent("CARXAC:TeleportToPlayer", tonumber(data and data.playerId))
    cb("ok")
end)

RegisterNUICallback("bringPlayer", function(data, cb)
    if not grantAdminGrace(120000) then cb("forbidden") return end
    TriggerServerEvent("CARXAC:BringPlayerToAdmin", tonumber(data and data.playerId))
    cb("ok")
end)

RegisterNUICallback("kickPlayer", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:KickPlayerByAdmin", tonumber(data and data.playerId), tostring(data and data.reason or "Kicked by admin menu"))
    cb("ok")
end)

RegisterNUICallback("addToAdmin", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:addPlayerAsAdmin", tonumber(data and data.playerId))
    cb("ok")
end)

RegisterNUICallback("addToWhiteList", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:addPlayerAsWhiteList", tonumber(data and data.playerId))
    cb("ok")
end)

RegisterNUICallback("addToUnban", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:addPlayerUnbanAccess", tonumber(data and data.playerId))
    cb("ok")
end)

RegisterNUICallback("delete_vehicles", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:deleteEntitys", "vehicles")
    cb("ok")
end)

RegisterNUICallback("delete_objects", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:deleteEntitys", "props")
    cb("ok")
end)

RegisterNUICallback("delete_peds", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:deleteEntitys", "peds")
    cb("ok")
end)

RegisterNUICallback("delete_all_entity", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:deleteEntitys", "vehicles")
    TriggerServerEvent("CARXAC:deleteEntitys", "props")
    TriggerServerEvent("CARXAC:deleteEntitys", "peds")
    cb("ok")
end)

RegisterNUICallback("teleportToWaypoint", function(data, cb)
    if not grantAdminGrace(15000) then cb("forbidden") return end
    local waypoint = GetFirstBlipInfoId(8)
    if DoesBlipExist(waypoint) then
        local coords = GetBlipInfoIdCoord(waypoint)
        SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
    end
    cb("ok")
end)

RegisterNUICallback("teleportToCoords", function(data, cb)
    if not grantAdminGrace(15000) then cb("forbidden") return end
    local x, y, z = tonumber(data and data.x), tonumber(data and data.y), tonumber(data and data.z)
    if x and y and z and math.abs(x) < 20000 and math.abs(y) < 20000 and math.abs(z) < 5000 then
        SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)
    end
    cb("ok")
end)

RegisterNUICallback("night", function(data, cb)
    if not requireAdmin(cb) then return end
    adminModes.night = not GetUsingnightvision()
    SetNightvision(adminModes.night)
    refreshPersistentAdminState()
    cb("ok")
end)

RegisterNUICallback("thermal", function(data, cb)
    if not requireAdmin(cb) then return end
    adminModes.thermal = not GetUsingseethrough()
    SetSeethrough(adminModes.thermal)
    refreshPersistentAdminState()
    cb("ok")
end)

RegisterNUICallback("spawnVehicleForSelf", function(data, cb)
    if not grantAdminGrace(45000) then cb("forbidden") return end
    TriggerServerEvent("CARXAC:spawnVehicle", data)
    cb("ok")
end)

RegisterNUICallback("spawnVehicleOthers", function(data, cb)
    if not grantAdminGrace(45000) then cb("forbidden") return end
    TriggerServerEvent("CARXAC:spawnVehicle", data)
    cb("ok")
end)

RegisterNUICallback("repairVehicle", function(data, cb)
    if not grantAdminGrace(30000) then cb("forbidden") return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleDirtLevel(vehicle, 0.0)
    end
    cb("ok")
end)

RegisterNUICallback("cleanVehicle", function(data, cb)
    if not grantAdminGrace(30000) then cb("forbidden") return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then SetVehicleDirtLevel(vehicle, 0.0) end
    cb("ok")
end)

RegisterNUICallback("deleteCurrentVehicle", function(data, cb)
    if not grantAdminGrace(30000) then cb("forbidden") return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
    end
    cb("ok")
end)

RegisterNUICallback("setVehicleColor", function(data, cb)
    if not grantAdminGrace(30000) then cb("forbidden") return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        local r = math.max(0, math.min(255, tonumber(data and data.r) or 255))
        local g = math.max(0, math.min(255, tonumber(data and data.g) or 120))
        local b = math.max(0, math.min(255, tonumber(data and data.b) or 24))
        SetVehicleCustomPrimaryColour(vehicle, r, g, b)
        SetVehicleCustomSecondaryColour(vehicle, r, g, b)
    end
    cb("ok")
end)

RegisterNUICallback("maxVehicleMods", function(data, cb)
    if not grantAdminGrace(45000) then cb("forbidden") return end
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetVehicleModKit(vehicle, 0)
        for modType = 0, 49 do
            local count = GetNumVehicleMods(vehicle, modType)
            if count and count > 0 then
                SetVehicleMod(vehicle, modType, count - 1, false)
            end
        end
        ToggleVehicleMod(vehicle, 18, true)
        SetVehicleFixed(vehicle)
        SetVehicleDirtLevel(vehicle, 0.0)
    end
    cb("ok")
end)

RegisterNUICallback("getBanListData", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getBanListData", data or {})
    cb("ok")
end)

RegisterNUICallback("unbanSelectedPlayer", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:unbanSelectedPlayer", tonumber(data and data.banID))
    cb("ok")
end)

RegisterNUICallback("getAdminListData", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getAdminListData", data or {})
    cb("ok")
end)

RegisterNUICallback("removeSelectedAdmin", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:removeSelectedAdmin", tonumber(data and data.id))
    cb("ok")
end)

RegisterNUICallback("getUnbanAccessData", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getUnbanAccessData", data or {})
    cb("ok")
end)

RegisterNUICallback("removeUnbanAccess", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:removeUnbanAccess", tonumber(data and data.id))
    cb("ok")
end)

RegisterNUICallback("getWhitelistData", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:getWhitelistData", data or {})
    cb("ok")
end)

RegisterNUICallback("getAccessOnlinePlayers", function(data, cb)
    if not requireAdmin(cb) then return end
    local scope = tostring(data and data.scope or "")
    if scope == "admins" or scope == "whitelist" then
        TriggerServerEvent("CARXAC:getAccessOnlinePlayers", scope)
    end
    cb("ok")
end)

RegisterNUICallback("removeWhitelistUser", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:removeWhitelistUser", tonumber(data and data.id))
    cb("ok")
end)

function openAdminMenu()
    if not isAdmin then
        carxacNotify("~r~CARXAC:~s~ Not authorized.")
        return
    end
    -- Do NOT re-check admin here (avoids race that force-closes the UI)
    SendNUIMessage({
        action = "openUI",
        version = tostring(CARXAC.Version or "1.0.0"),
    })
    SetNuiFocus(true, true)
    -- Prefetch Control Center data
    TriggerServerEvent("CARXAC:cc:getDashboard")
    TriggerServerEvent("CARXAC:cc:getConfig")
end

function openPlayerAction(data)
    SendNUIMessage({
        action = "openPlayerActionMenu",
        data = data
    })
end

function updateAdminStatus()
    local vision = "Normal"
    if GetUsingseethrough() then
        vision = "Thermal"
    elseif GetUsingnightvision() then
        vision = "Night"
    end
    SendNUIMessage({
        action = "updateAdminStatus",
        godmode = GetPlayerInvincible(PlayerId()),
        visible = IsEntityVisible(PlayerPedId()),
        vision = vision,
        spectate = InSpectatorMode == true
    })
end

function updatePlayerCoords()
    SendNUIMessage({
        action = "updatePlayerCoords",
        location = vector4(playerLocations.coords.x, playerLocations.coords.y, playerLocations.coords.z,
            playerLocations.heading),
    })
end

function updatePlayerList(playerList)
    SendNUIMessage({
        action = "updatePlayerList",
        playerList = playerList,
    })
end

function updateBanListData(banList, meta)
    SendNUIMessage({
        action = "updateBanList",
        banList = banList,
        meta = meta or {}
    })
end

function updateAdminData(adminList, meta)
    SendNUIMessage({
        action = "updateAdminData",
        adminList = adminList,
        meta = meta or {}
    })
end

function updateUnbanAccess(unbanList, meta)
    SendNUIMessage({
        action = "updateUnbanAccess",
        unbanList = unbanList,
        meta = meta or {}
    })
end

function updateWhiteList(whiteList, meta)
    SendNUIMessage({
        action = "updateWhiteList",
        whiteList = whiteList,
        meta = meta or {}
    })
end

function spectatePlayer(target, coords)
    if not isAdmin or type(coords) ~= "vector3" and type(coords) ~= "table" then return end
    local player = GetPlayerFromServerId(tonumber(target) or -1)
    if player == -1 then
        adminModes.spectate = false
        refreshPersistentAdminState()
        return
    end
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then
        adminModes.spectate = false
        refreshPersistentAdminState()
        return
    end

    cam = cam or CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    Wait(250)

    adminModes.spectate = true
    refreshPersistentAdminState()
    NetworkSetInSpectatorMode(true, ped)
    InSpectatorMode = true
    TargetSpectate = target
    handelSpectate(player, ped)
end

function updateTargetChecks()
    Citizen.CreateThread(function()
        while InSpectatorMode do
            Citizen.Wait(1000)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                health, maxhealth, armor = GetEntityHealth(targetPed), GetEntityMaxHealth(targetPed), GetPedArmour(targetPed)
                handleVoiceChannel(TargetSpectate)
            end
        end
    end)
end

function handleVoiceChannel(target)
    local channel = tonumber(MumbleGetVoiceChannelFromServerId(target))
    if not channel or channel < 0 or currentVoiceChannel == channel then return end
    if currentVoiceChannel then MumbleRemoveVoiceChannelListen(currentVoiceChannel) end
    currentVoiceChannel = channel
    MumbleAddVoiceChannelListen(channel)
end

function handelSpectate(player, ped)
    Citizen.CreateThread(function()
        targetPed = GetPlayerPed(player)
        updateTargetChecks()

        while InSpectatorMode do
            Citizen.Wait(5)
            local currentPlayer = GetPlayerFromServerId(TargetSpectate or -1)
            if currentPlayer == -1 then
                exitSpectate()
                break
            end
            targetPed = GetPlayerPed(currentPlayer)
            if targetPed == 0 or not DoesEntityExist(targetPed) then
                exitSpectate()
                break
            end
            local coords = GetEntityCoords(targetPed)

            DisableControlAction(2, 37, true)

            if IsControlPressed(2, 241) then
                radius = radius + 2.0
            end

            if IsControlPressed(2, 242) then
                radius = radius - 2.0
            end

            radius = math.max(radius, -1)

            local xMagnitude, yMagnitude = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
            polarAngleDeg, azimuthAngleDeg = polarAngleDeg + xMagnitude * 10, azimuthAngleDeg + yMagnitude * 10

            polarAngleDeg = (polarAngleDeg >= 360) and 0 or polarAngleDeg
            azimuthAngleDeg = (azimuthAngleDeg >= 360) and 0 or azimuthAngleDeg

            local nextCamLocation = polar3DToWorld3D(coords, radius, polarAngleDeg, azimuthAngleDeg)

            SetCamCoord(cam, nextCamLocation.x, nextCamLocation.y, nextCamLocation.z)
            PointCamAtEntity(cam, targetPed)

            if health and maxhealth and armor then
                Draw({
                    'Health' .. ': ~g~' .. health .. '/' .. maxhealth,
                    'Armor' .. ': ~b~' .. armor,
                    "To ~r~ exit ~s~ press spectate button again"
                })
            end
        end
    end)
end

function polar3DToWorld3D(entityPosition, radius, polarAngleDeg, azimuthAngleDeg)
    local polarAngleRad, azimuthAngleRad = polarAngleDeg * math.pi / 180.0, azimuthAngleDeg * math.pi / 180.0

    local pos = {
        x = entityPosition.x + radius * (math.sin(azimuthAngleRad) * math.cos(polarAngleRad)),
        y = entityPosition.y - radius * (math.sin(azimuthAngleRad) * math.sin(polarAngleRad)),
        z = entityPosition.z - radius * math.cos(azimuthAngleRad)
    }

    return pos
end

function Draw(text)
    for i, theText in pairs(text) do
        SetTextFont(0)
        SetTextProportional(1)
        SetTextScale(0.0, 0.30)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(1, 0, 0, 0, 255)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        AddTextComponentString(theText)
        EndTextCommandDisplayText(0.3, 0.7 + (i / 30))
    end
end

function exitSpectate()
    if not InSpectatorMode then return end
    InSpectatorMode, TargetSpectate, targetPed = false, nil, nil
    adminModes.spectate = false
    NetworkSetInSpectatorMode(false, PlayerPedId())
    RenderScriptCams(false, false, 0, true, true)
    if cam and DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
        cam = nil
    end
    if currentVoiceChannel then
        MumbleRemoveVoiceChannelListen(currentVoiceChannel)
        currentVoiceChannel = nil
    end
    refreshPersistentAdminState()
end

Citizen.CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    TriggerServerEvent("CARXAC:checkIsAdmin")
end)

AddEventHandler("onClientResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if InSpectatorMode then exitSpectate() end
    SetEntityInvincible(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    SetNightvision(false)
    SetSeethrough(false)
    SetNuiFocus(false, false)
end)


-- ============================================================
-- CARXAC Control Center — client bridge (NUI ↔ server)
-- ============================================================

RegisterNetEvent("CARXAC:cc:dashboard")
AddEventHandler("CARXAC:cc:dashboard", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:dashboard", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:config")
AddEventHandler("CARXAC:cc:config", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:config", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:detections")
AddEventHandler("CARXAC:cc:detections", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:detections", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:players")
AddEventHandler("CARXAC:cc:players", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:players", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:health")
AddEventHandler("CARXAC:cc:health", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:health", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:configLog")
AddEventHandler("CARXAC:cc:configLog", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:configLog", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:blacklists")
AddEventHandler("CARXAC:cc:blacklists", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:blacklists", data = data or {} })
end)

RegisterNetEvent("CARXAC:cc:toast")
AddEventHandler("CARXAC:cc:toast", function(data)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:toast", data = data or {} })
end)

RegisterNetEvent("CARXAC:liveDetection")
AddEventHandler("CARXAC:liveDetection", function(entry)
    if not isAdmin then return end
    SendNUIMessage({ action = "cc:liveDetection", data = entry or {} })
end)

RegisterNUICallback("cc:getDashboard", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getDashboard")
    cb({ ok = true })
end)

RegisterNUICallback("cc:getConfig", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getConfig")
    cb({ ok = true })
end)

RegisterNUICallback("cc:saveConfig", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:saveConfig", data and data.changes or {})
    cb({ ok = true })
end)

RegisterNUICallback("cc:resetConfig", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:resetConfig")
    cb({ ok = true })
end)

RegisterNUICallback("cc:getDetections", function(data, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getDetections", data or {})
    cb({ ok = true })
end)

RegisterNUICallback("cc:getPlayers", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getPlayers")
    cb({ ok = true })
end)

RegisterNUICallback("cc:getHealth", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getHealth")
    cb({ ok = true })
end)

RegisterNUICallback("cc:getConfigLog", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getConfigLog")
    cb({ ok = true })
end)

RegisterNUICallback("cc:getBlacklists", function(_, cb)
    if not requireAdmin(cb) then return end
    TriggerServerEvent("CARXAC:cc:getBlacklists")
    cb({ ok = true })
end)
