-- CARXAC Control Center — editable configuration schema
-- Only keys listed here can be changed via NUI (server validates against this)

CARXAC_SCHEMA = {
    version = "1.0.0",
    categories = {
        {
            id = "general",
            label = "General",
            description = "Core CARXAC behaviour",
            settings = {
                { key = "AdminMenu.Enable", type = "bool", label = "Admin Menu", description = "Allow authorized admins to open the Control Center", path = { "AdminMenu", "Enable" } },
                { key = "AdminMenu.Key", type = "string", label = "Menu Keybind", description = "Default key mapping for the admin menu", path = { "AdminMenu", "Key" } },
                { key = "AdminMenu.MenuPunishment", type = "punishment", label = "Unauthorized Menu Use", description = "Action when a non-admin triggers admin events", path = { "AdminMenu", "MenuPunishment" } },
                { key = "ChatSettings.Enable", type = "bool", label = "Chat Alerts", description = "Broadcast detection messages to staff chat", path = { "ChatSettings", "Enable" } },
                { key = "ChatSettings.PrivateWarn", type = "bool", label = "Private Warn Messages", description = "Send private warn messages to the player", path = { "ChatSettings", "PrivateWarn" } },
                { key = "ScreenShot.Enable", type = "bool", label = "Screenshots", description = "Request screenshots on punish (requires discord-screenshot)", path = { "ScreenShot", "Enable" } },
            }
        },
        {
            id = "player",
            label = "Player Protection",
            description = "Client-side player exploit detection",
            settings = {
                { key = "AntiGodMode", type = "bool", label = "Godmode", description = "Detect abnormal invulnerability", path = { "AntiGodMode" } },
                { key = "GodPunishment", type = "punishment", label = "Godmode Action", path = { "GodPunishment" } },
                { key = "AntiHealthHack", type = "bool", label = "Health Hack", path = { "AntiHealthHack" } },
                { key = "MaxHealth", type = "number", label = "Max Health", min = 100, max = 500, path = { "MaxHealth" } },
                { key = "HealthPunishment", type = "punishment", label = "Health Action", path = { "HealthPunishment" } },
                { key = "AntiArmorHack", type = "bool", label = "Armor Hack", path = { "AntiArmorHack" } },
                { key = "MaxArmor", type = "number", label = "Max Armor", min = 0, max = 100, path = { "MaxArmor" } },
                { key = "ArmorPunishment", type = "punishment", label = "Armor Action", path = { "ArmorPunishment" } },
                { key = "AntiInvisible", type = "bool", label = "Invisible", path = { "AntiInvisible" } },
                { key = "InvisiblePunishment", type = "punishment", label = "Invisible Action", path = { "InvisiblePunishment" } },
                { key = "AntiNoclip", type = "bool", label = "Noclip", path = { "AntiNoclip" } },
                { key = "NoclipPunishment", type = "punishment", label = "Noclip Action", path = { "NoclipPunishment" } },
                { key = "AntiSuperJump", type = "bool", label = "Super Jump", path = { "AntiSuperJump" } },
                { key = "JumpPunishment", type = "punishment", label = "Jump Action", path = { "JumpPunishment" } },
                { key = "AntiTeleport", type = "bool", label = "Teleport", path = { "AntiTeleport" } },
                { key = "MaxFootDistance", type = "number", label = "Max Foot Distance", min = 50, max = 1000, path = { "MaxFootDistance" } },
                { key = "MaxVehicleDistance", type = "number", label = "Max Vehicle Distance", min = 100, max = 2000, path = { "MaxVehicleDistance" } },
                { key = "TeleportPunishment", type = "punishment", label = "Teleport Action", path = { "TeleportPunishment" } },
                { key = "AntiChangeSpeed", type = "bool", label = "Speed Anomaly", path = { "AntiChangeSpeed" } },
                { key = "SpeedPunishment", type = "punishment", label = "Speed Action", path = { "SpeedPunishment" } },
                { key = "AntiFreeCam", type = "bool", label = "Free Camera", path = { "AntiFreeCam" } },
                { key = "CamPunishment", type = "punishment", label = "FreeCam Action", path = { "CamPunishment" } },
                { key = "AntiSpectate", type = "bool", label = "Spectate Abuse", path = { "AntiSpectate" } },
                { key = "SpectatePunishment", type = "punishment", label = "Spectate Action", path = { "SpectatePunishment" } },
                { key = "AntiNightVision", type = "bool", label = "Night Vision", path = { "AntiNightVision" } },
                { key = "AntiThermalVision", type = "bool", label = "Thermal Vision", path = { "AntiThermalVision" } },
                { key = "VisionPunishment", type = "punishment", label = "Vision Action", path = { "VisionPunishment" } },
                { key = "AntiPedChanger", type = "bool", label = "Ped Changer", path = { "AntiPedChanger" } },
                { key = "PedChangePunishment", type = "punishment", label = "Ped Change Action", path = { "PedChangePunishment" } },
                { key = "AntiTinyPed", type = "bool", label = "Tiny Ped", path = { "AntiTinyPed" } },
                { key = "PedFlagPunishment", type = "punishment", label = "Tiny Ped Action", path = { "PedFlagPunishment" } },
                { key = "AntiInfiniteStamina", type = "bool", label = "Infinite Stamina", path = { "AntiInfiniteStamina" } },
                { key = "InfinitePunishment", type = "punishment", label = "Stamina Action", path = { "InfinitePunishment" } },
                { key = "AntiSuicide", type = "bool", label = "Suicide Exploit", path = { "AntiSuicide" } },
                { key = "SuicidePunishment", type = "punishment", label = "Suicide Action", path = { "SuicidePunishment" } },
            }
        },
        {
            id = "weapon",
            label = "Weapon Protection",
            description = "Weapon and damage checks",
            settings = {
                { key = "AntiBlackListWeapon", type = "bool", label = "Blacklisted Weapons", path = { "AntiBlackListWeapon" } },
                { key = "AntiAddWeapon", type = "bool", label = "Unauthorized Weapon Add", path = { "AntiAddWeapon" } },
                { key = "AntiRemoveWeapon", type = "bool", label = "Unauthorized Weapon Remove", path = { "AntiRemoveWeapon" } },
                { key = "AntiInfinityAmmo", type = "bool", label = "Infinite Ammo", path = { "AntiInfinityAmmo" } },
                { key = "AntiWeaponDamageChanger", type = "bool", label = "Damage Changer", path = { "AntiWeaponDamageChanger" } },
                { key = "WeaponPunishment", type = "punishment", label = "Weapon Action", path = { "WeaponPunishment" } },
                { key = "DamagePunishment", type = "punishment", label = "Damage Action", path = { "DamagePunishment" } },
            }
        },
        {
            id = "vehicle",
            label = "Vehicle Protection",
            description = "Vehicle model and behaviour checks",
            settings = {
                { key = "AntiBlackListVehicle", type = "bool", label = "Blacklisted Vehicles", path = { "AntiBlackListVehicle" } },
                { key = "AntiRainbowVehicle", type = "bool", label = "Rainbow Vehicle", path = { "AntiRainbowVehicle" } },
                { key = "RainbowPunishment", type = "punishment", label = "Rainbow Action", path = { "RainbowPunishment" } },
                { key = "AntiPlateChanger", type = "bool", label = "Plate Changer", path = { "AntiPlateChanger" } },
                { key = "AntiBlackListPlate", type = "bool", label = "Blacklisted Plates", path = { "AntiBlackListPlate" } },
                { key = "PlatePunishment", type = "punishment", label = "Plate Action", path = { "PlatePunishment" } },
                { key = "AntiSpamVehicle", type = "bool", label = "Vehicle Spawn Spam", path = { "AntiSpamVehicle" } },
                { key = "MaxVehicle", type = "number", label = "Max Vehicles / Window", min = 1, max = 50, path = { "MaxVehicle" } },
            }
        },
        {
            id = "entity",
            label = "Entity Protection",
            description = "Ped / object / spam limits",
            settings = {
                { key = "AntiBlackListObject", type = "bool", label = "Blacklisted Objects", path = { "AntiBlackListObject" } },
                { key = "AntiBlackListPed", type = "bool", label = "Blacklisted Peds", path = { "AntiBlackListPed" } },
                { key = "AntiBlackListBuilding", type = "bool", label = "Blacklisted Buildings", path = { "AntiBlackListBuilding" } },
                { key = "EntityPunishment", type = "punishment", label = "Entity Action", path = { "EntityPunishment" } },
                { key = "AntiSpamPed", type = "bool", label = "Ped Spawn Spam", path = { "AntiSpamPed" } },
                { key = "MaxPed", type = "number", label = "Max Peds / Window", min = 1, max = 30, path = { "MaxPed" } },
                { key = "AntiSpamObject", type = "bool", label = "Object Spawn Spam", path = { "AntiSpamObject" } },
                { key = "MaxObject", type = "number", label = "Max Objects / Window", min = 1, max = 50, path = { "MaxObject" } },
                { key = "SpamPunishment", type = "punishment", label = "Spam Action", path = { "SpamPunishment" } },
                { key = "AntiPickupCollect", type = "bool", label = "Pickup Collect", path = { "AntiPickupCollect" } },
                { key = "PickupPunishment", type = "punishment", label = "Pickup Action", path = { "PickupPunishment" } },
            }
        },
        {
            id = "explosion",
            label = "Explosion Protection",
            description = "Explosion rate limits",
            settings = {
                { key = "AntiExplosionSpam", type = "bool", label = "Explosion Spam", path = { "AntiExplosionSpam" } },
                { key = "MaxExplosion", type = "number", label = "Max Explosions / Window", min = 1, max = 50, path = { "MaxExplosion" } },
                { key = "ExplosionSpamPunishment", type = "punishment", label = "Explosion Action", path = { "ExplosionSpamPunishment" } },
            }
        },
        {
            id = "event",
            label = "Event & Chat Protection",
            description = "Triggers, chat, commands",
            settings = {
                { key = "AntiBlackListTrigger", type = "bool", label = "Blacklisted Triggers", path = { "AntiBlackListTrigger" } },
                { key = "AntiSpamTrigger", type = "bool", label = "Trigger Spam", path = { "AntiSpamTrigger" } },
                { key = "TriggerPunishment", type = "punishment", label = "Trigger Action", path = { "TriggerPunishment" } },
                { key = "AntiSpamChat", type = "bool", label = "Chat Spam", path = { "AntiSpamChat" } },
                { key = "MaxMessage", type = "number", label = "Max Messages", min = 1, max = 50, path = { "MaxMessage" } },
                { key = "CoolDownSec", type = "number", label = "Chat Cooldown (sec)", min = 1, max = 30, path = { "CoolDownSec" } },
                { key = "ChatPunishment", type = "punishment", label = "Chat Action", path = { "ChatPunishment" } },
                { key = "AntiBlackListWord", type = "bool", label = "Blacklisted Words", path = { "AntiBlackListWord" } },
                { key = "WordPunishment", type = "punishment", label = "Word Action", path = { "WordPunishment" } },
                { key = "AntiBlackListCommands", type = "bool", label = "Blacklisted Commands", path = { "AntiBlackListCommands" } },
                { key = "CMDPunishment", type = "punishment", label = "Command Action", path = { "CMDPunishment" } },
                { key = "AntiInject", type = "bool", label = "Inject Detection", path = { "AntiInject" } },
                { key = "InjectPunishment", type = "punishment", label = "Inject Action", path = { "InjectPunishment" } },
                { key = "AntiPlaySound", type = "bool", label = "Sound Spam", path = { "AntiPlaySound" } },
                { key = "SoundPunishment", type = "punishment", label = "Sound Action", path = { "SoundPunishment" } },
                { key = "AntiClearPedTasks", type = "bool", label = "Clear Ped Tasks Spam", path = { "AntiClearPedTasks" } },
                { key = "MaxClearPedTasks", type = "number", label = "Max ClearPedTasks", min = 1, max = 20, path = { "MaxClearPedTasks" } },
                { key = "CPTPunishment", type = "punishment", label = "ClearPedTasks Action", path = { "CPTPunishment" } },
                { key = "AntiTazePlayers", type = "bool", label = "Taze Spam", path = { "AntiTazePlayers" } },
                { key = "MaxTazeSpam", type = "number", label = "Max Taze Spam", min = 1, max = 20, path = { "MaxTazeSpam" } },
                { key = "TazePunishment", type = "punishment", label = "Taze Action", path = { "TazePunishment" } },
                { key = "AntiBringAll", type = "bool", label = "Bring All", path = { "AntiBringAll" } },
                { key = "BringAllPunishment", type = "punishment", label = "Bring All Action", path = { "BringAllPunishment" } },
                { key = "AntiChangePerm", type = "bool", label = "Permission Change", path = { "AntiChangePerm" } },
                { key = "PermPunishment", type = "punishment", label = "Perm Action", path = { "PermPunishment" } },
            }
        },
        {
            id = "detection_engine",
            label = "Detection Engine",
            description = "Thresholds and grace periods (reduces false positives)",
            settings = {
                { key = "Detection.EvidenceThreshold", type = "number", label = "Evidence Threshold", min = 1, max = 20, path = { "Detection", "EvidenceThreshold" } },
                { key = "Detection.EvidenceWindowMs", type = "number", label = "Evidence Window (ms)", min = 1000, max = 60000, path = { "Detection", "EvidenceWindowMs" } },
                { key = "Detection.GodmodeSamples", type = "number", label = "Godmode Samples", min = 2, max = 20, path = { "Detection", "GodmodeSamples" } },
                { key = "Detection.ClientReportCooldownMs", type = "number", label = "Client Report Cooldown (ms)", min = 1000, max = 60000, path = { "Detection", "ClientReportCooldownMs" } },
                { key = "Detection.ServerReportLimit", type = "number", label = "Server Report Limit", min = 1, max = 30, path = { "Detection", "ServerReportLimit" } },
                { key = "Detection.SpawnGraceMs", type = "number", label = "Spawn Grace (ms)", min = 0, max = 60000, path = { "Detection", "SpawnGraceMs" } },
                { key = "Detection.PostReadyGraceMs", type = "number", label = "Post-Ready Grace (ms)", min = 0, max = 60000, path = { "Detection", "PostReadyGraceMs" } },
            }
        },
        {
            id = "connection",
            label = "Connection",
            description = "Join / name / VPN checks",
            settings = {
                { key = "Connection.AntiBlackListName", type = "bool", label = "Blacklisted Names", path = { "Connection", "AntiBlackListName" } },
                { key = "Connection.AntiVPN", type = "bool", label = "Anti VPN", path = { "Connection", "AntiVPN" } },
                { key = "Connection.HideIP", type = "bool", label = "Hide IP in Logs", path = { "Connection", "HideIP" } },
                { key = "Connection.CardTitle", type = "string", label = "Connect Card Title", path = { "Connection", "CardTitle" } },
            }
        },
    },
    punishments = { "LOG", "WARN", "KICK", "BAN" },
}

function CARXAC_SchemaGet(path)
    local cur = CARXAC
    if type(path) ~= "table" then return nil end
    for _, key in ipairs(path) do
        if type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

function CARXAC_SchemaSet(path, value)
    if type(path) ~= "table" or #path == 0 then return false end
    local cur = CARXAC
    for i = 1, #path - 1 do
        local key = path[i]
        if type(cur[key]) ~= "table" then
            cur[key] = {}
        end
        cur = cur[key]
    end
    cur[path[#path]] = value
    return true
end

function CARXAC_SchemaFind(key)
    for _, cat in ipairs(CARXAC_SCHEMA.categories) do
        for _, setting in ipairs(cat.settings) do
            if setting.key == key then
                return setting, cat
            end
        end
    end
    return nil
end

function CARXAC_SchemaSnapshot()
    local out = {}
    for _, cat in ipairs(CARXAC_SCHEMA.categories) do
        for _, setting in ipairs(cat.settings) do
            out[setting.key] = CARXAC_SchemaGet(setting.path)
        end
    end
    return out
end
