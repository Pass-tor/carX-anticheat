# CARXAC — Carx Anti-Cheat

**Version:** 1.0.0  
**Type:** FiveM server anti-cheat + admin Control Center  
**Stack:** FXServer · OneSync · oxmysql · Lua 5.4  
**License:** GNU Affero General Public License v3.0  

CARXAC is a production anti-cheat with:

- Client + server detection modules
- Configurable punishments (`WARN` / `KICK` / `BAN`)
- Database bans, admins, whitelist, unban access
- **Control Center NUI** (primary management interface)
- Runtime configuration (NUI → server → `data/runtime.json`)
- Detection history + live feed
- Discord webhooks (optional)
- ESX / QBCore / standalone client ready hooks

The NUI is a management surface only. **All security decisions are server-side.**

---

## Table of contents

1. [Features](#1-features)
2. [Resource structure](#2-resource-structure)
3. [Installation](#3-installation)
4. [Configuration](#4-configuration)
5. [Control Center](#5-control-center)
6. [Detection modules](#6-detection-modules)
7. [Punishment system](#7-punishment-system)
8. [Bypass / admin / whitelist](#8-bypass--admin--whitelist)
9. [Database](#9-database)
10. [Commands](#10-commands)
11. [Exports](#11-exports)
12. [Events (internal)](#12-events-internal)
13. [Webhooks](#13-webhooks)
14. [Security model](#14-security-model)
15. [Performance notes](#15-performance-notes)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. Features

### 1.1 Client protection

| Module | Config key | Default punishment key |
|--------|------------|------------------------|
| Health hack | `AntiHealthHack` + `MaxHealth` | `HealthPunishment` |
| Armor hack | `AntiArmorHack` + `MaxArmor` | `ArmorPunishment` |
| Godmode | `AntiGodMode` | `GodPunishment` |
| Invisible | `AntiInvisible` | `InvisiblePunishment` |
| Noclip | `AntiNoclip` | `NoclipPunishment` |
| Super jump | `AntiSuperJump` | `JumpPunishment` |
| Teleport | `AntiTeleport` + distance limits | `TeleportPunishment` |
| Speed anomaly | `AntiChangeSpeed` | `SpeedPunishment` |
| Free camera | `AntiFreeCam` | `CamPunishment` |
| Spectate abuse | `AntiSpectate` | `SpectatePunishment` |
| Night / thermal vision | `AntiNightVision` / `AntiThermalVision` | `VisionPunishment` |
| Ped changer | `AntiPedChanger` | `PedChangePunishment` |
| Tiny ped | `AntiTinyPed` | `PedFlagPunishment` |
| Infinite stamina | `AntiInfiniteStamina` | `InfinitePunishment` |
| Suicide exploit | `AntiSuicide` | `SuicidePunishment` |
| Infinite ammo | `AntiInfinityAmmo` | (weapon path) |
| Blacklisted weapons | `AntiBlackListWeapon` | `WeaponPunishment` |
| Weapon add/remove | `AntiAddWeapon` / `AntiRemoveWeapon` | `WeaponPunishment` |
| Blacklisted tasks | `AntiBlacklistTasks` | `TasksPunishment` |
| Blacklisted anims | `AntiBlacklistAnims` | `AnimsPunishment` |
| Rainbow vehicle | `AntiRainbowVehicle` | `RainbowPunishment` |
| Plate changer / blacklist | `AntiPlateChanger` / `AntiBlackListPlate` | `PlatePunishment` |
| Pickup collect | `AntiPickupCollect` | `PickupPunishment` |

### 1.2 Server protection

| Module | Config key | Notes |
|--------|------------|--------|
| Chat spam | `AntiSpamChat` + `MaxMessage` + `CoolDownSec` | |
| Blacklisted words | `AntiBlackListWord` | Table: `Words` |
| Blacklisted commands | `AntiBlackListCommands` | Table: `Commands` |
| Weapon damage changer | `AntiWeaponDamageChanger` | Table: `DAMAGE` |
| Blacklisted / spam triggers | `AntiBlackListTrigger` / `AntiSpamTrigger` | Table: `Events` |
| ClearPedTasks spam | `AntiClearPedTasks` | |
| Taze spam | `AntiTazePlayers` | |
| Bring-all | `AntiBringAll` | |
| Inject / unexpected resource | `AntiInject` | Layered; often off by default |
| Explosion spam | `AntiExplosionSpam` + `MaxExplosion` | Table: `Explosion` |
| Blacklisted entities | Object / Ped / Building / Vehicle | Tables: `Objects`, `Peds`, `Vehicle` |
| Entity spawn spam | Vehicle / Ped / Object caps | `MaxVehicle`, `MaxPed`, `MaxObject` |
| Sound spam | `AntiPlaySound` | |
| Permission change | `AntiChangePerm` | |

### 1.3 Connection protection

- Blacklisted names (`Names` table + `Connection.AntiBlackListName`)
- Optional Anti-VPN (`Connection.AntiVPN`)
- Hide IP in logs (`Connection.HideIP`)
- Deferral / Adaptive Card connect UI (`Connection.*`)
- Ban-list check on connect (fail-open if DB errors)

### 1.4 Detection engine (false-positive reduction)

Under `CARXAC.Detection`:

- Spawn / framework / respawn / ped-change / camera grace windows
- Evidence threshold + time window
- Godmode sample count
- Client report cooldown
- Server report rate limit

### 1.5 Control Center NUI

See [§5](#5-control-center).

### 1.6 Admin tools (authorized only)

- Godmode / invisible / heal / night / thermal (self)
- Spectate, goto, bring, kick, ban
- Add admin / whitelist / unban access
- Entity cleanup (vehicles, props, peds)
- Waypoint / coordinate teleport (with action grace)
- Vehicle spawn / repair / color / max mods (admin events, server-checked)

---

## 2. Resource structure

```
CARXAC/
├── fxmanifest.lua
├── database.sql
├── README.md
├── LICENSE
├── configs/
│   ├── carx-config.lua      # Baseline configuration
│   └── carx-webhook.lua     # Discord webhook URLs
├── data/
│   └── runtime.json         # NUI/runtime overrides (persisted)
├── shared/
│   └── carx-schema.lua      # Editable config schema (NUI whitelist)
├── src/
│   ├── carx-client.lua      # Client detections
│   ├── carx-menu.lua        # Admin UI client + NUI bridge
│   ├── carx-server.lua      # Core server AC + bans + admin
│   └── carx-control.lua     # Control Center APIs (config, history, health)
├── tables/
│   ├── carx-weapon.lua      # Weapon blacklist
│   ├── carx-vehicle.lua
│   ├── carx-peds.lua
│   ├── carx-object.lua
│   ├── carx-explosions.lua
│   ├── carx-event.lua
│   ├── carx-words.lua
│   ├── carx-cmd.lua
│   ├── carx-name.lua
│   ├── carx-plate.lua
│   ├── carx-damage.lua
│   ├── carx-anim.lua
│   ├── carx-task.lua
│   └── carx-emoji.lua
└── ui/
    ├── index.html
    ├── css/style.css
    ├── js/script.js
    └── assists/             # Optional images
```

**Dependency:** `oxmysql` (must start before CARXAC).

---

## 3. Installation

1. Copy the folder to `resources/CARXAC`.
2. Import `database.sql` into your MySQL database.
3. Edit:
   - `configs/carx-config.lua` — server name, toggles, punishments
   - `configs/carx-webhook.lua` — Discord URLs (optional)
4. `server.cfg`:

```cfg
ensure oxmysql
ensure CARXAC
```

5. Grant admin access (pick one or combine):

**Database admin** (table `carxac_admin` — identifier such as `license:`):

```sql
INSERT INTO carxac_admin (identifier, player_name) VALUES ('license:YOURLICENSE', 'AdminName');
```

**ACE** (optional — enable `CARXAC.ACE.Enable = true`):

```cfg
add_ace group.admin CARXAC.Admin allow
add_ace group.admin CARXAC.Whitelist allow
add_ace group.admin CARXAC.Unban allow
add_principal identifier.license:YOURLICENSE group.admin
```

6. Restart the server (or `ensure CARXAC`).
7. In-game: press **F9** or run `/carxac` / `/carxacmenu`.

### Startup banner

```
========================================
          CARXAC ANTI-CHEAT
           Carx Anti-Cheat
            Version 1.0.0
========================================
  Protection: ACTIVE
  Detection Engine: ACTIVE
  ...
========================================
```

---

## 4. Configuration

### 4.1 Baseline file

`configs/carx-config.lua` is the baseline. It loads on resource start.

### 4.2 Runtime overrides (Control Center)

Changes saved from the NUI are validated against `shared/carx-schema.lua` and written to:

```
data/runtime.json
```

- Applied automatically on resource start
- Survive resource restart
- **Reset Overrides** clears the file; restart CARXAC to fully restore baseline values from `carx-config.lua`

### 4.3 Punishment values

Used across modules:

| Value | Behaviour |
|-------|-----------|
| `WARN` | Log + warn (no drop) |
| `KICK` | Drop player |
| `BAN` | Insert ban row + drop |
| `LOG` | In schema/UI; stored as `WARN` for the action path |

### 4.4 Safe defaults guidance

- Prefer `WARN` / `KICK` for weak client signals until tuned
- Keep evidence thresholds and grace windows as configured under `CARXAC.Detection`
- Leave high false-positive modules off until tested (`AntiNoclip`, `AntiFreeCam`, `AntiInject`, etc.)

### 4.5 Tables (blacklists)

Edit Lua tables under `tables/` — Control Center **Blacklist** page is read-only display.

| File | Global | Use |
|------|--------|-----|
| `carx-weapon.lua` | `Weapon` | Weapon blacklist |
| `carx-vehicle.lua` | `Vehicle` | Vehicle blacklist |
| `carx-peds.lua` | `Peds` | Ped blacklist |
| `carx-object.lua` | `Objects` | Object blacklist |
| `carx-explosions.lua` | `Explosion` | Per-type log/punish |
| `carx-event.lua` | `Events` | Trigger blacklist / rate |
| `carx-words.lua` | `Words` | Chat words |
| `carx-cmd.lua` | `Commands` | Command blacklist |
| `carx-name.lua` | `Names` | Connect name blacklist |
| `carx-plate.lua` | `Plate` | Plate blacklist |
| `carx-damage.lua` | `DAMAGE` | Expected weapon damage |
| `carx-anim.lua` | `Anims` | Anim blacklist |
| `carx-task.lua` | `Tasks` | Task blacklist |

---

## 5. Control Center

**Open:** F9 (configurable) · `/carxac` · `/carxacmenu`  
**Requires:** admin permission (DB admin and/or ACE)

### Layout

- Top bar: brand, server online, protection active, player count, version
- Sidebar navigation
- Main content panels
- Toasts + confirm modals (no browser `alert`)

### Pages

| Page | Data source | Actions |
|------|-------------|---------|
| **Dashboard** | Session counters + protection flags + live feed | Refresh |
| **Players** | Online players (id, name, ping, admin, detection count) | Kick / Ban |
| **Live Detections** | Session feed from `CARXAC_ACTION` | — |
| **Detection History** | Same buffer + filters (search, severity, action) | Pagination |
| **Protection** | Live `CARXAC.*` boolean flags | — |
| **Bans** | `carxac_banlist` | Unban |
| **Whitelist** | `carxac_whitelist` | Remove entry |
| **Blacklist** | Table globals (read-only) | Filter chips |
| **Logs** | Config change log (memory) | Refresh |
| **System Health** | oxmysql started, webhook URL set, core flags | Refresh |
| **Configuration** | Schema + current values | Edit, Save, Reset overrides |
| **Admin Tools** | Legacy self tools | Godmode, invisible, heal, NV, entity delete, waypoint TP |

### Configuration UI

- Categories: General, Player, Weapon, Vehicle, Entity, Explosion, Event/Chat, Detection Engine, Connection
- Controls: toggle, number, punishment dropdown, string
- **Unsaved changes** badge
- Save → server validate → `runtime.json` → toast
- Config change log: admin, key, old → new, time

### Live detection feed

On every punish path, admins receive:

- Time, severity (`LOW` / `MEDIUM` / `HIGH` / `CRITICAL`)
- Player name + server ID
- Detection reason
- Action

Severity is derived from action: BAN→CRITICAL, KICK→HIGH, WARN→MEDIUM, else LOW.

---

## 6. Detection modules

### Layered client reports

Client signals go through server acceptance (`acceptClientReport`):

- Trusted / admin skip
- Cooldowns and report limits
- Optional near-admin exceptions (e.g. teleport)
- Then `CARXAC_ACTION`

### Entity / explosion

- `entityCreated` inspection for blacklists + spam counters
- Explosion rate limiting when enabled

### Framework readiness

Client waits for spawn / ESX / QBCore load events when `CARXAC.Detection.RequireFrameworkLoaded` is true, reducing join false positives.

---

## 7. Punishment system

Central function: **`CARXAC_ACTION(src, action, reason, details)`**

1. Normalize action (`WARN` / `KICK` / `BAN`)
2. Skip if trusted / spam-listed duplicate
3. Optional screenshot (`discord-screenshot` + webhook)
4. Log detection (`CARXAC_LogDetection`)
5. Discord / console log
6. Chat message to staff (if enabled)
7. WARN → return; KICK → drop; BAN → DB ban + drop

Ban storage includes license, discord, steam, live, xbl, IP (respect `HideIP`), tokens, reason, ban id.

---

## 8. Bypass / admin / whitelist

| Mechanism | Purpose |
|-----------|---------|
| `carxac_admin` | Full admin / Control Center |
| `carxac_whitelist` | Detection bypass (trusted) |
| `carxac_unban` | Allowed to run unban commands |
| Temp whitelist | Short grace after admin TP / tools |
| ACE | Optional parallel permission (`CARXAC.ACE`) |

Unauthorized use of admin events/commands is punished with `AdminMenu.MenuPunishment`.

---

## 9. Database

```sql
carxac_admin       -- admin identifiers
carxac_banlist     -- bans (multi-identifier + tokens + reason)
carxac_unban       -- unban permission identifiers
carxac_whitelist   -- trusted players
carxac_detections  -- optional persistent detection log
```

Import: `database.sql`.

---

## 10. Commands

| Command | Who | Description |
|---------|-----|-------------|
| `/carxac` | Admin | Open Control Center |
| `/carxacmenu` | Admin | Open Control Center |
| F9 (default) | Admin | Keybind (`CARXAC.AdminMenu.Key`) |
| `/carxacban [id] [reason]` | Admin | Ban online player |
| `/carxacunban [ban_id]` | Admin / unban access | Remove ban by BANID |
| `/addadmin [id]` | Console / authorized | Add DB admin |
| `/addwhitelist [id]` | Authorized | Add whitelist |
| `/addunban [id]` | Authorized | Grant unban access |
| `/unban` / `/funban` | Authorized | Legacy unban helpers |

---

## 11. Exports

### Server

| Export | Description |
|--------|-------------|
| `CARXAC_ACTION(src, action, reason, details)` | Central punish |
| `CARXAC_BAN_PLAYER` / `BanPlayer` | Ban API |
| `CARXAC_UNBAN_PLAYER` / `UnbanPlayer` | Unban API |
| `CARXAC_CHANGE_TEMP_WHITELIST` | Temp bypass |
| `CARXAC_CHECK_TEMP_WHITELIST` | Query temp bypass |
| `CARXAC_CHANGE_TEMP_WHHITELIST` | Alias (legacy typo kept) |

Example:

```lua
exports['CARXAC']:CARXAC_ACTION(source, 'KICK', 'Custom reason', 'details')
```

---

## 12. Events (internal)

Do not trigger these from untrusted clients as “admin actions” — server re-validates.

### Client → server (examples)

- `CARXAC:clientReady`
- `CARXAC:reportDetection` / `CARXAC:BanFromClient`
- `CARXAC:checkIsAdmin`
- `CARXAC:cc:getDashboard` / `getConfig` / `saveConfig` / `getDetections` / …

### Server → client (examples)

- `CARXAC:allowToOpen`
- `CARXAC:cc:dashboard` / `cc:config` / `cc:toast` / `liveDetection`
- `CARXAC:updateBanListData` / whitelist / admin lists

---

## 13. Webhooks

`configs/carx-webhook.lua`:

```lua
CARXAC.Webhooks = {
    Ban = "",
    Error = "",
    Connect = "",
    Disconnect = "",
    Explosion = "",
    ScreenShot = "",
}
```

Leave empty to disable. Screenshot path needs resource `discord-screenshot` when enabled.

---

## 14. Security model

```
CARXAC NUI
    → NUI callback
    → client bridge
    → server event
    → CARXAC_GETADMINS / ACE
    → schema + type/range validation
    → apply config or admin action
```

- NUI never trusted for permissions or config authority
- Client detection reports rate-limited and validated
- Money/items/jobs are **not** granted by CARXAC — use your framework
- Unauthorized admin menu / events → configured punishment

---

## 15. Performance notes

- Prefer event-driven server paths over continuous heavy loops
- Detection grace windows reduce join-time cost and false positives
- Control Center uses request/response (no aggressive polling)
- Entity enumeration for dashboard entity counts is intentionally light
- Avoid enabling every module at `BAN` on a busy production box without testing

---

## 16. Troubleshooting

| Issue | Check |
|-------|--------|
| Menu does not open | Not in txAdmin Admin Manager / not in `group.admin`; `AdminMenu.Enable`; key conflict |
| Config save fails | File permissions on `data/`; server console for reject reason |
| Overrides not applying | Confirm `data/runtime.json`; restart resource |
| DB errors | oxmysql connection; tables imported; charset |
| False positives | Raise grace / evidence threshold; switch module to WARN; whitelist staff |
| VPN always blocks | `Connection.AntiVPN = false` or fix lookup |
| Ban not sticking | oxmysql errors on insert; identifier availability |

---

## Version

```
CARXAC.Version = "1.0.0"
```

Displayed in Control Center top bar and sidebar.

---

## License

GNU Affero General Public License v3.0 — see `LICENSE`.


## Admin & bans (txAdmin)

CARXAC does **not** use custom CARXAC ACE permissions. Admin access and bans are integrated with **txAdmin** and your **admin group**.

**Who is admin** (checked in this order)
1. **txAdmin staff** — authenticated in-game via the txAdmin menu (`txAdmin:events:adminAuth`)
2. **Admin group** — players in `group.admin` / `group.god` / `admin` (server.cfg principals)
3. Optional: `carxac_admin` MySQL table only if `AdminAccess.UseDatabase = true`

**server.cfg example**
```cfg
add_principal identifier.license:YOUR_LICENSE group.admin
add_ace group.admin command allow
```

Also add the same people in **txAdmin → Admin Manager** so they authenticate in-game.

**Bans**
- Default: `BanSystem.Provider = "txadmin"` → runs `txaBan <id> permanent [CARXAC] reason`
- Bans appear under **txAdmin → Players → Bans**
- Options: `"txadmin"` (recommended) | `"internal"` | `"both"`
- Detection bans and admin-menu bans both go through this path

