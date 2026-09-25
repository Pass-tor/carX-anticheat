-- CARXAC Configuration
-- Carx Anti-Cheat v1.0.0
-- Licensed under the GNU Affero General Public License v3.0


CARXAC              = {}

CARXAC.Version      = "1.0.0"

CARXAC.ServerConfig = {
    Name  = "YOUR SERVER NAME",

    Port  = "30120",

    Linux = false
}

-- Admin access: txAdmin staff + admin group (NO custom CARXAC ACE permissions)
CARXAC.AdminAccess = {
    -- 1) txAdmin authenticated staff (in-game menu / adminAuth event)
    UseTxAdmin = true,

    -- 2) Players in these admin groups (server.cfg principals)
    -- server.cfg example (recommended):
    --   add_principal identifier.license:XXXX group.admin
    --   add_ace group.admin command allow
    --   add_ace group.admin carxac.admin allow
    -- Also add the same people in txAdmin → Admin Manager, then open
    -- the txAdmin in-game menu once so adminAuth fires.
    UseAdminGroup = true,
    Groups = {
        "group.admin",
        "group.god",
        "admin",
    },

    -- 3) Optional carxac_admin / whitelist / unban MySQL tables (off by default)
    UseDatabase = false,
}

-- Ban provider — default is txAdmin so bans appear in txAdmin → Players → Bans
CARXAC.BanSystem = {
    -- "txadmin" = ban via txaBan (recommended)
    -- "internal" = carxac_banlist MySQL only
    -- "both"     = txAdmin + internal DB
    Provider = "txadmin",

    -- Duration passed to txaBan: permanent | 1h | 24h | 7d | 30d
    DefaultDuration = "permanent",

    -- Prefix on ban reason for staff visibility in txAdmin
    ReasonPrefix = "[CARXAC] ",
}

-- Legacy ACE block — permanently disabled (use AdminAccess above)
CARXAC.ACE = {
    Enable = false,
    Admin = "group.admin",
    Whitelist = "group.admin",
    Unban = "group.admin"
}

CARXAC.ChatSettings             = {
    Enable      = true,
    PrivateWarn = true
}

CARXAC.ScreenShot               = {
    Enable  = true,
    Format  = "PNG",
    Quality = 1
}

CARXAC.Connection               = {
    AntiBlackListName = true,
    AntiVPN           = false,
    HideIP            = true,

    -- CLOSED = reject join if ban DB fails (recommended for anti-cheat)
    -- OPEN   = allow join and log warning if ban DB fails
    BanCheckFailMode  = "CLOSED",

    UseDeferrals      = true,
    DeferralMode      = "card",
    DeferralDelayMs   = 1200,
    DeferralStepMs    = 120,
    AdaptiveCard      = true,

    ShowConnectUI     = true,
    ShowProblemCard   = true,
    ProblemOnlyMode   = false,

    PresentCardOnce   = false,
    PresentCardHoldMs = 900,
    CardTitle         = "CARXAC - Carx Anti-Cheat",
    VisualStepMs      = 320,
    ConnectHoldMs     = 1200
}

-- Allowed freemode / job peds. Unauthorized models are reported to server.
-- Trusted resources should call: exports['CARXAC']:AuthorizePedChange(src, model, durationMs)
CARXAC.AllowedPlayerModels = {
    [`mp_m_freemode_01`] = true,
    [`mp_f_freemode_01`] = true,
}

CARXAC.ServerRuntime            = {
    EntityCreatedMonitor = false,
    EntityCreatedDelayMs = 750
}

CARXAC.Detection = {
    RequirePlayerSpawned = true,
    RequireFrameworkLoaded = true,
    ReadyMaxWaitMs = 120000,
    MinimumClientReadyMs = 12000,
    ResourceRestartAssumeSpawnedMs = 8000,
    ReadyReentryCooldownMs = 30000,

    SpawnGraceMs = 20000,
    PostSpawnSettleMs = 18000,
    PostReadyGraceMs = 20000,
    FrameworkLoadGraceMs = 12000,
    RespawnGraceMs = 15000,
    RespawnCooldownMs = 8000,
    PedChangeGraceMs = 12000,
    CameraGraceMs = 3500,
    GodmodeAfterReadyMs = 12000,

    EvidenceThreshold = 3,
    EvidenceWindowMs = 15000,
    GodmodeSamples = 6,
    ClientReportCooldownMs = 10000,
    ServerReportWindowMs = 10000,
    ServerReportLimit = 6,
    -- Client-only signals need this many accumulated violations before BAN is honored
    ClientBanEvidenceThreshold = 2,
}

CARXAC.Message                  = {
    Kick = "⚡️ You've been kicked from the server protection by CARXAC® Carx Anti-Cheat. Avoid cheating on this server.",
    Ban  = "⛔️ You've been banned from the server. Please create a support ticket for assistance.",
}

CARXAC.AdminMenu                = {
    Enable         = true,
    Key            = "F9",
    MenuPunishment = "BAN"
}

CARXAC.AntiHealthHack           = true
CARXAC.MaxHealth                = 200
CARXAC.HealthPunishment         = "BAN"

CARXAC.AntiArmorHack            = true
CARXAC.MaxArmor                 = 100
CARXAC.ArmorPunishment          = "BAN"

CARXAC.AntiBlacklistTasks       = false
CARXAC.TasksPunishment          = "BAN"

CARXAC.AntiBlacklistAnims       = true
CARXAC.AnimsPunishment          = "BAN"

CARXAC.AntiInfinityAmmo         = true

CARXAC.AntiSpectate             = true
CARXAC.SpactatePunishment       = "BAN"
CARXAC.SpectatePunishment       = CARXAC.SpactatePunishment

CARXAC.AntiBlackListWeapon      = true
CARXAC.AntiAddWeapon            = false
CARXAC.AntiRemoveWeapon         = false
CARXAC.WeaponPunishment         = "BAN"

CARXAC.AntiGodMode              = true
CARXAC.GodPunishment            = "BAN"

CARXAC.AntiInvisible            = true
CARXAC.InvisiblePunishment      = "KICK"

CARXAC.AntiChangeSpeed          = true
CARXAC.SpeedPunishment          = "KICK"

CARXAC.AntiFreeCam              = false
CARXAC.CamPunishment            = "BAN"

CARXAC.AntiRainbowVehicle       = true
CARXAC.RainbowPunishment        = "BAN"

CARXAC.AntiPlateChanger         = true
CARXAC.AntiBlackListPlate       = true
CARXAC.PlatePunishment          = "BAN"

CARXAC.AntiNightVision          = true
CARXAC.AntiThermalVision        = true
CARXAC.VisionPunishment         = "BAN"

CARXAC.AntiSuperJump            = true
CARXAC.JumpPunishment           = "BAN"

CARXAC.AntiTeleport             = true
CARXAC.MaxFootDistance          = 200
CARXAC.MaxVehicleDistance       = 600
CARXAC.TeleportPunishment       = "BAN"

CARXAC.AntiNoclip               = false
CARXAC.NoclipPunishment         = "KICK"

CARXAC.AntiPedChanger           = true
CARXAC.PedChangePunishment      = "BAN"

CARXAC.AntiInfiniteStamina      = false
CARXAC.InfinitePunishment       = "WARN"


CARXAC.AntiTinyPed              = true
CARXAC.PedFlagPunishment        = "BAN"

CARXAC.AntiSuicide              = false
CARXAC.SuicidePunishment        = "WARN"

CARXAC.AntiPickupCollect        = false
CARXAC.PickupPunishment         = "BAN"

CARXAC.AntiSpamChat             = true
CARXAC.MaxMessage               = 10
CARXAC.CoolDownSec              = 3
CARXAC.ChatPunishment           = "BAN"

CARXAC.AntiBlackListCommands    = true
CARXAC.CMDPunishment            = "BAN"

CARXAC.AntiWeaponDamageChanger  = true
CARXAC.DamagePunishment         = "BAN"

CARXAC.AntiBlackListWord        = true
CARXAC.WordPunishment           = "KICK"

CARXAC.AntiBringAll             = false
CARXAC.BringAllPunishment       = "BAN"

CARXAC.AntiBlackListTrigger     = false
CARXAC.AntiSpamTrigger          = true
CARXAC.TriggerPunishment        = "BAN"

CARXAC.AntiClearPedTasks        = false
CARXAC.MaxClearPedTasks         = 5
CARXAC.CPTPunishment            = "BAN"

CARXAC.AntiTazePlayers          = true
CARXAC.MaxTazeSpam              = 3
CARXAC.TazePunishment           = "KICK"

CARXAC.AntiInject               = false
CARXAC.InjectPunishment         = "BAN"

CARXAC.AntiExplosionSpam        = true
CARXAC.MaxExplosion             = 10
CARXAC.ExplosionSpamPunishment  = "BAN"

CARXAC.AntiBlackListObject      = true
CARXAC.AntiBlackListPed         = true
CARXAC.AntiBlackListBuilding    = true
CARXAC.AntiBlackListVehicle     = true
CARXAC.EntityPunishment         = "BAN"


CARXAC.AntiSpamVehicle          = true
CARXAC.MaxVehicle               = 10

CARXAC.AntiSpamPed              = true
CARXAC.MaxPed                   = 4

CARXAC.AntiSpamObject           = true
CARXAC.MaxObject                = 15

CARXAC.SpamPunishment           = "KICK"

CARXAC.AntiChangePerm           = false
CARXAC.PermPunishment           = "BAN"

CARXAC.AntiPlaySound            = true
CARXAC.SoundPunishment          = "KICK"
