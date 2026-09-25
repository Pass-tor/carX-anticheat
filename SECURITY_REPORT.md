# CARXAC Security Hardening Report

**Date:** 2026-09-25  
**Scope:** Full security audit & production hardening of the existing CARXAC resource  
**Method:** In-place patches — architecture, NUI, detections, and Control Center preserved

---

## Fixed

| ID | Vulnerability | Fix |
|----|---------------|-----|
| F1 | **AddToSpawnList grace abuse** — client could repeatedly extend `graceUntil` | Server rate-limits spawn notifications; cooldown (`RespawnCooldownMs`); server owns duration; legacy event kept but hardened |
| F2 | **clientReady replay/grace reset** — client could reset ready/grace freely | Server-issued one-time **nonce handshake**; nonce invalidated after use; age limit; rate limit; server increments `spawnSerial` |
| F3 | **Client-controlled grace duration** | All grace durations taken from `CARXAC.Detection.*` only |
| F4 | **Fail-open ban DB** | `Connection.BanCheckFailMode = "CLOSED"` (default) rejects join on DB failure |
| F5 | **Ped baseline bypass** — any non-blacklisted model became new baseline | `AllowedPlayerModels` allowlist; unauthorized models reported; baseline not updated; `exports.AuthorizePedChange` for trusted resources |
| F6 | **adminState duration abuse** | Duration clamped server-side (max 120s); rate-limited |
| F7 | **Client detection as sole BAN signal** | Suspicion score + `ClientBanEvidenceThreshold`; first client-only BAN signals downgraded |
| F8 | **Runtime config reset incomplete** | `CARXAC_ResetRuntimeConfig()` restores baseline snapshot in-memory + clears `runtime.json` + pushes NUI values |
| F9 | **HTTP VPN lookup** | Switched to **HTTPS** `ip-api.com`; feature still opt-in (`AntiVPN = false`) |
| F10 | **Missing centralized grace API** | `IsDetectionGraceActive(source)` — server state only |
| F11 | **Event spam** | Reusable `RateLimit(src, bucket, limit, windowMs)` with per-event buckets |
| F12 | **Invalid client report reasons** | Allowlist enforced; length limits; rate limit on bad reports |

---

## Remaining risks (FiveM inherent)

- Client-side observations (godmode samples, freecam distance, local health) can always be spoofed or suppressed by a fully modified client. Mitigation: treat as signals + evidence thresholds + server entity events where available.
- OneSync entity ownership races can produce false entity-create signals — keep entity monitors optional.
- txAdmin `adminAuth` requires the admin to open the txAdmin menu at least once per session.
- External VPN APIs can fail or rate-limit; with `AntiVPN = false` this path is inactive.

---

## Modified files

- `src/carx-server.lua` — state machine, handshake, rate limits, spawn/ready hardening, ban fail mode, ped auth, adminState clamp, HTTPS VPN
- `src/carx-client.lua` — handshake consumer, spawnNotify, ped allowlist (no silent baseline adopt)
- `src/carx-control.lua` — baseline snapshot + `CARXAC_ResetRuntimeConfig()`
- `configs/carx-config.lua` — `BanCheckFailMode`, `AllowedPlayerModels`, detection thresholds
- `fxmanifest.lua` — exports `AuthorizePedChange`, `IsDetectionGraceActive`
- `SECURITY_REPORT.md` — this document

---

## New network events

| Event | Direction | Purpose |
|-------|-----------|---------|
| `CARXAC:handshakeChallenge` | S→C | Delivers one-time ready nonce |
| `CARXAC:spawnNotify` | C→S | Informational spawn notice (rate-limited; server grants grace) |
| `CARXAC:reportPedChange` | C→S | Untrusted ped-model signal for server validation |

## Changed events

| Event | Change |
|-------|--------|
| `CARXAC:clientReady` | Args are now `(nonce, reason)` — requires valid server nonce |
| `CARXAC:AddToSpawnList` | No longer unlimited grace; cooldown + rate limit |

## Removed / not removed

- No detections removed.
- No NUI pages removed.
- Legacy `AddToSpawnList` retained as compatibility wrapper (hardened).

---

## Configuration changes

```lua
CARXAC.Connection.BanCheckFailMode = "CLOSED"  -- or "OPEN"

CARXAC.AllowedPlayerModels = {
    [`mp_m_freemode_01`] = true,
    [`mp_f_freemode_01`] = true,
}

CARXAC.Detection.RespawnCooldownMs = 8000
CARXAC.Detection.ReadyReentryCooldownMs = 30000
CARXAC.Detection.ClientBanEvidenceThreshold = 2
```

**Trusted ped changes from other resources:**

```lua
exports['CARXAC']:AuthorizePedChange(source, `mp_m_freemode_01`, 15000)
-- or model name string
```

---

## Database

- No schema migration required for this pass.
- Existing parameterized queries retained; ban fail mode is connection-policy only.

---

## Compatibility notes

1. **clientReady signature changed** — only CARXAC client should call it; external scripts must not trigger it.
2. **Ped changer** — servers using custom job peds must add hashes to `AllowedPlayerModels` or call `AuthorizePedChange`.
3. **BanCheckFailMode=CLOSED** — if oxmysql is down, players cannot join. Set `"OPEN"` only if you accept that risk.
4. Admin menu, bans via txAdmin, Control Center, webhooks unchanged in behavior.

---

## Security test checklist

| Test | Expected |
|------|----------|
| Spam `CARXAC:AddToSpawnList` | Rate-limited; grace does not grow unbounded |
| Spam `CARXAC:clientReady` without nonce | Rejected; new challenge may be issued |
| Replay old nonce | Rejected (`handshakeUsed` / mismatch) |
| Rapid respawn events | Cooldown blocks extra grace |
| Trigger admin ban event as non-admin | Rejected + punishment path |
| Ban DB failure + CLOSED | Connection rejected |
| Ban DB failure + OPEN | Connection allowed + warning log |
| Unauthorized ped model | Report; baseline not updated |
| `AuthorizePedChange` then change model | Allowed during window |
| NUI `cc:saveConfig` as non-admin | Unauthorized punishment |
| Config reset from Control Center | Values restore immediately in NUI |

---

## Sensitive API audit

| API | Use | Safe? |
|-----|-----|-------|
| `LoadResourceFile` | Startup file presence + runtime.json read | Yes — local resource only |
| `SaveResourceFile` | runtime.json write (admin-gated) | Yes |
| `PerformHttpRequest` | Discord webhooks, HTTPS VPN | Yes — no remote code exec |
| `ExecuteCommand` | `txaBan` only | Yes — fixed command template |
| `loadstring` / `load` / `dofile` / `os.execute` | **Not present** | N/A |

No remote Lua loader. No client-side secrets required for security.

---

## Deploy steps

1. Replace resource with updated `CARXAC` folder / zip.
2. Ensure `oxmysql` is running before go-live if `BanCheckFailMode = "CLOSED"`.
3. Add custom job peds to `AllowedPlayerModels` if needed.
4. `ensure CARXAC` (or server restart).
5. Staff: open txAdmin menu once, then F9 for Control Center.
}
