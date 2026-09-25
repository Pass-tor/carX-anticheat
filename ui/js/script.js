/* CARXAC Control Center */
const RES = typeof GetParentResourceName === "function" ? GetParentResourceName() : "CARXAC";

const state = {
  open: false,
  page: "dashboard",
  version: "1.0.0",
  dashboard: null,
  configSchema: null,
  configValues: {},
  pendingChanges: {},
  players: [],
  history: { rows: [], total: 0, page: 1, pageSize: 25 },
  blacklists: {},
  blTab: "weapons",
  health: null,
  configLog: [],
  live: [],
};

function post(name, data) {
  return fetch(`https://${RES}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(data || {}),
  }).catch(() => null);
}

function $(sel) { return document.querySelector(sel); }
function $all(sel) { return Array.from(document.querySelectorAll(sel)); }

function toast(type, title, message) {
  const el = document.createElement("div");
  el.className = `toast ${type || ""}`;
  el.innerHTML = `<strong>${esc(title || "CARXAC")}</strong><span>${esc(message || "")}</span>`;
  $("#toasts").appendChild(el);
  setTimeout(() => el.remove(), 4200);
}

function esc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function openUI(version) {
  state.open = true;
  if (version) state.version = version;
  $("#app").style.display = "flex";
  $("#top-version").textContent = "v" + state.version;
  $("#side-version").textContent = "Version " + state.version;
  navigate("dashboard");
  refreshDashboard();
  loadConfig();
}

function closeUI() {
  state.open = false;
  $("#app").style.display = "none";
  post("onCloseMenu", {});
}

function navigate(page) {
  state.page = page;
  $all(".nav-item").forEach((b) => b.classList.toggle("active", b.dataset.page === page));
  $all(".page").forEach((p) => p.classList.toggle("active", p.id === "page-" + page));
  if (page === "players") loadPlayers();
  if (page === "history") loadHistory();
  if (page === "bans") loadBans();
  if (page === "whitelist") loadWhitelist();
  if (page === "blacklist") loadBlacklists();
  if (page === "logs") loadConfigLog();
  if (page === "health") loadHealth();
  if (page === "configuration") loadConfig();
  if (page === "protection") renderProtectionFull();
  if (page === "detections") renderLiveFull();
}

function refreshDashboard() {
  post("cc:getDashboard", {});
}

function loadConfig() {
  post("cc:getConfig", {});
}

function loadPlayers() {
  post("cc:getPlayers", {});
}

function loadHistory() {
  post("cc:getDetections", {
    search: ($("#hist-search") && $("#hist-search").value) || "",
    severity: ($("#hist-severity") && $("#hist-severity").value) || "ALL",
    action: ($("#hist-action") && $("#hist-action").value) || "ALL",
    page: state.history.page,
    pageSize: state.history.pageSize,
  });
}

function loadHealth() {
  post("cc:getHealth", {});
}

function loadConfigLog() {
  post("cc:getConfigLog", {});
}

function loadBlacklists() {
  post("cc:getBlacklists", {});
}

function loadBans() {
  post("getBanListData", { page: 1, pageSize: 50, search: ($("#ban-search") && $("#ban-search").value) || "" });
}

function loadWhitelist() {
  post("getWhitelistData", { page: 1, pageSize: 50, search: "" });
}

function tool(name) {
  post(name, {});
}

/* ---------- render helpers ---------- */

function renderDashboard(data) {
  if (!data) return;
  state.dashboard = data;
  $("#stat-players").textContent = data.players ?? 0;
  $("#stat-detections").textContent = data.detections ?? 0;
  $("#stat-kicks").textContent = data.kicks ?? 0;
  $("#stat-bans").textContent = data.bans ?? 0;
  $("#top-players").textContent = data.players ?? 0;
  if (data.version) {
    state.version = data.version;
    $("#top-version").textContent = "v" + state.version;
    $("#side-version").textContent = "Version " + state.version;
  }
  renderProtection(data.protection || {});
  if (Array.isArray(data.live)) {
    state.live = data.live;
    renderLive(state.live);
    renderLiveFull();
  }
}

function renderProtection(prot) {
  const labels = {
    godmode: "Godmode", invisible: "Invisible", noclip: "Noclip", superjump: "Super Jump",
    teleport: "Teleport", speed: "Speed", freecam: "Freecam", spectate: "Spectate",
    weapon: "Weapons", damage: "Damage", vehicle: "Vehicles", entity: "Entities",
    explosion: "Explosions", event: "Events", chat: "Chat", inject: "Inject",
  };
  const html = Object.keys(labels).map((k) => {
    const on = !!prot[k];
    return `<div class="prot-item"><b>${labels[k]}</b><span class="tag ${on ? "on" : "off"}">${on ? "ACTIVE" : "OFF"}</span></div>`;
  }).join("");
  const grid = $("#prot-grid");
  if (grid) grid.innerHTML = html || '<div class="empty">No data</div>';
  const full = $("#prot-grid-full");
  if (full) full.innerHTML = html || '<div class="empty">No data</div>';
}

function renderProtectionFull() {
  if (state.dashboard && state.dashboard.protection) renderProtection(state.dashboard.protection);
  else refreshDashboard();
}

function renderLive(items) {
  const feed = $("#live-feed");
  if (!feed) return;
  if (!items || !items.length) {
    feed.innerHTML = '<div class="empty">No detections this session</div>';
    return;
  }
  feed.innerHTML = items.slice(0, 12).map(feedItemHtml).join("");
}

function renderLiveFull() {
  const feed = $("#live-feed-full");
  if (!feed) return;
  const items = state.live || [];
  if (!items.length) {
    feed.innerHTML = '<div class="empty">Waiting for detections…</div>';
    return;
  }
  feed.innerHTML = items.map(feedItemHtml).join("");
}

function feedItemHtml(e) {
  const t = (e.time || "").split(" ").pop() || e.time || "";
  return `<div class="feed-item">
    <span class="time">${esc(t)}</span>
    <span class="tag sev-${esc(e.severity || "MEDIUM")}">${esc(e.severity || "MEDIUM")}</span>
    <span><span class="who">ID ${esc(e.serverId)} · ${esc(e.player)}</span><br><span class="det">${esc(e.detection)}</span></span>
    <span class="tag">${esc(e.action)}</span>
  </div>`;
}

function renderPlayers(list) {
  state.players = list || [];
  const q = (($("#player-search") && $("#player-search").value) || "").toLowerCase();
  const rows = state.players.filter((p) => {
    if (!q) return true;
    return String(p.id).includes(q) || (p.name || "").toLowerCase().includes(q);
  });
  const body = $("#players-body");
  if (!body) return;
  if (!rows.length) {
    body.innerHTML = '<tr><td colspan="6" class="empty">No players</td></tr>';
    return;
  }
  body.innerHTML = rows.map((p) => `<tr>
    <td>${esc(p.id)}</td>
    <td>${esc(p.name)}</td>
    <td>${esc(p.ping)} ms</td>
    <td>${p.isAdmin ? '<span class="tag on">ADMIN</span>' : '<span class="tag off">PLAYER</span>'}</td>
    <td>${esc(p.detections || 0)}</td>
    <td><button class="btn secondary" onclick="playerAction(${Number(p.id)},'kick')">Kick</button>
        <button class="btn danger" onclick="playerAction(${Number(p.id)},'ban')">Ban</button></td>
  </tr>`).join("");
}

function playerAction(id, action) {
  if (action === "kick") post("kickPlayer", { id });
  if (action === "ban") post("ban", { id, reason: "Banned via CARXAC Control Center" });
}

function renderHistory(data) {
  data = data || {};
  state.history.rows = data.rows || [];
  state.history.total = data.total || 0;
  state.history.page = data.page || 1;
  const body = $("#history-body");
  if (!body) return;
  if (!state.history.rows.length) {
    body.innerHTML = '<tr><td colspan="7" class="empty">No detections match filters</td></tr>';
  } else {
    body.innerHTML = state.history.rows.map((e) => `<tr>
      <td>${esc(e.time)}</td>
      <td>${esc(e.player)}</td>
      <td>${esc(e.serverId)}</td>
      <td>${esc(e.detection)}</td>
      <td><span class="tag sev-${esc(e.severity)}">${esc(e.severity)}</span></td>
      <td>${esc(e.action)}</td>
      <td>${esc(e.status)}</td>
    </tr>`).join("");
  }
  const pages = Math.max(1, Math.ceil(state.history.total / state.history.pageSize));
  const pager = $("#history-pager");
  if (pager) {
    pager.innerHTML = `<button ${state.history.page <= 1 ? "disabled" : ""} onclick="histPage(-1)">Prev</button>
      <span style="color:var(--muted);font-size:12px;padding:6px;">${state.history.page} / ${pages} (${state.history.total})</span>
      <button ${state.history.page >= pages ? "disabled" : ""} onclick="histPage(1)">Next</button>`;
  }
}

function histPage(delta) {
  state.history.page = Math.max(1, state.history.page + delta);
  loadHistory();
}

function renderHealth(h) {
  state.health = h || {};
  const items = [
    ["CARXAC Core", h.core],
    ["Client Monitoring", h.clientMonitoring],
    ["Server Monitoring", h.serverMonitoring],
    ["Event Protection", h.eventProtection],
    ["Database (oxmysql)", h.database],
    ["Webhook Configured", h.webhook],
    ["NUI", h.nui],
  ];
  $("#health-grid").innerHTML = items.map(([label, ok]) => `
    <div class="health-card">
      <span>${esc(label)}</span>
      <strong class="${ok ? "" : ""}" style="color:${ok ? "var(--ok)" : "var(--danger)"}">${ok ? "● ONLINE" : "● OFFLINE"}</strong>
    </div>`).join("") + `
    <div class="health-card"><span>Version</span><strong>${esc(h.version || state.version)}</strong></div>
    <div class="health-card"><span>Online Players</span><strong>${esc(h.players || 0)}</strong></div>`;
}

function renderConfigLog(rows) {
  state.configLog = rows || [];
  const el = $("#config-log");
  if (!el) return;
  if (!state.configLog.length) {
    el.innerHTML = '<div class="empty">No configuration changes yet</div>';
    return;
  }
  el.innerHTML = state.configLog.map((e) => `
    <div class="feed-item" style="grid-template-columns:90px 1fr">
      <span class="time">${esc(e.time)}</span>
      <span><span class="who">${esc(e.admin)}</span> changed <b>${esc(e.key)}</b><br>
      <span class="det">${esc(e.oldValue)} → ${esc(e.newValue)}</span></span>
    </div>`).join("");
}

function renderBlacklists(data) {
  state.blacklists = data || {};
  showBlTab(state.blTab);
}

function showBlTab(tab) {
  state.blTab = tab;
  $all("#bl-tabs .tab").forEach((t) => t.classList.toggle("active", t.dataset.bl === tab));
  const raw = state.blacklists[tab] || [];
  let items = [];
  if (Array.isArray(raw)) items = raw;
  else if (typeof raw === "object") items = Object.keys(raw).map((k) => (raw[k] && raw[k].NAME) ? `${k}: ${raw[k].NAME}` : String(raw[k] ?? k));
  const q = (($("#bl-search") && $("#bl-search").value) || "").toLowerCase();
  if (q) items = items.filter((x) => String(x).toLowerCase().includes(q));
  const list = $("#bl-list");
  if (!list) return;
  if (!items.length) {
    list.innerHTML = '<div class="empty">Empty list</div>';
    return;
  }
  list.innerHTML = items.slice(0, 500).map((x) => `<span class="chip">${esc(x)}</span>`).join("");
}

/* ---------- configuration UI ---------- */

function renderConfig() {
  if (!state.configSchema) return;
  const cats = state.configSchema.categories || [];
  const catEl = $("#cfg-cats");
  const activeCat = state.cfgCat || (cats[0] && cats[0].id) || "general";
  state.cfgCat = activeCat;
  catEl.innerHTML = cats.map((c) =>
    `<button class="cfg-cat ${c.id === activeCat ? "active" : ""}" data-cat="${esc(c.id)}">${esc(c.label)}</button>`
  ).join("");
  catEl.querySelectorAll(".cfg-cat").forEach((btn) => {
    btn.onclick = () => { state.cfgCat = btn.dataset.cat; renderConfig(); };
  });

  const q = (($("#cfg-search") && $("#cfg-search").value) || "").toLowerCase();
  const body = $("#cfg-body");
  const sections = cats.filter((c) => !state.cfgCat || c.id === state.cfgCat || q);

  body.innerHTML = sections.map((cat) => {
    let settings = cat.settings || [];
    if (q) {
      settings = settings.filter((s) =>
        (s.label || "").toLowerCase().includes(q) ||
        (s.key || "").toLowerCase().includes(q) ||
        (s.description || "").toLowerCase().includes(q)
      );
    }
    if (!settings.length) return "";
    return `<div class="cfg-section">
      <h3>${esc(cat.label)}</h3>
      <p>${esc(cat.description || "")}</p>
      ${settings.map((s) => cfgRowHtml(s)).join("")}
    </div>`;
  }).join("") || '<div class="empty">No settings match search</div>';

  updateUnsaved();
}

function currentValue(key) {
  if (Object.prototype.hasOwnProperty.call(state.pendingChanges, key)) return state.pendingChanges[key];
  return state.configValues[key];
}

function cfgRowHtml(s) {
  const val = currentValue(s.key);
  const dirty = Object.prototype.hasOwnProperty.call(state.pendingChanges, s.key);
  let control = "";
  if (s.type === "bool") {
    const on = val === true;
    control = `<button type="button" class="toggle ${on ? "on" : ""}" data-key="${esc(s.key)}" data-type="bool"><i></i></button>`;
  } else if (s.type === "punishment") {
    const opts = (state.configSchema.punishments || ["WARN", "KICK", "BAN"]).map((p) =>
      `<option value="${p}" ${String(val).toUpperCase() === p ? "selected" : ""}>${p}</option>`
    ).join("");
    control = `<select data-key="${esc(s.key)}" data-type="punishment">${opts}</select>`;
  } else if (s.type === "number") {
    control = `<input type="number" data-key="${esc(s.key)}" data-type="number" value="${esc(val ?? "")}" min="${s.min ?? 0}" max="${s.max ?? 999999}">`;
  } else {
    control = `<input type="text" data-key="${esc(s.key)}" data-type="string" value="${esc(val ?? "")}">`;
  }
  return `<div class="cfg-row ${dirty ? "dirty" : ""}">
    <div><label>${esc(s.label)}</label>${s.description ? `<small>${esc(s.description)}</small>` : ""}</div>
    <div class="cfg-control">${control}</div>
  </div>`;
}

function setPending(key, value) {
  const original = state.configValues[key];
  if (value === original || (typeof original === "boolean" && value === original)) {
    delete state.pendingChanges[key];
  } else {
    state.pendingChanges[key] = value;
  }
  updateUnsaved();
  renderConfig();
}

function updateUnsaved() {
  const n = Object.keys(state.pendingChanges).length;
  const badge = $("#unsaved-badge");
  if (badge) badge.style.display = n ? "inline" : "none";
  if (badge && n) badge.textContent = `● ${n} unsaved change${n > 1 ? "s" : ""}`;
}

function saveConfig() {
  const changes = state.pendingChanges;
  if (!Object.keys(changes).length) {
    toast("warn", "Nothing to save", "No configuration changes pending");
    return;
  }
  post("cc:saveConfig", { changes });
}

function resetConfig() {
  showModal("Reset overrides?", "This clears runtime overrides. Restart CARXAC to fully restore defaults from the config file.", () => {
    post("cc:resetConfig", {});
    state.pendingChanges = {};
    updateUnsaved();
  });
}

function showModal(title, body, onConfirm) {
  $("#modal-title").textContent = title;
  $("#modal-body").textContent = body;
  $("#modal").style.display = "flex";
  const conf = $("#modal-confirm");
  const cancel = $("#modal-cancel");
  const close = () => { $("#modal").style.display = "none"; };
  cancel.onclick = close;
  conf.onclick = () => { close(); if (onConfirm) onConfirm(); };
}

/* ---------- ban/whitelist list rendering (legacy payload) ---------- */

function renderBanList(rows) {
  const el = $("#ban-records");
  if (!el) return;
  rows = rows || [];
  if (!rows.length) {
    el.innerHTML = '<div class="empty">No bans</div>';
    return;
  }
  el.innerHTML = rows.map((r) => {
    const name = r.PLAYER_NAME || r.player_name || "Unknown";
    const id = r.BANID || r.id || "?";
    const reason = r.REASON || r.reason || "";
    return `<div class="record-row" onclick="unban(${Number(id)})">
      <div class="main"><b>${esc(name)} · Ban #${esc(id)}</b><small>${esc(reason)}</small></div>
      <button class="btn secondary">Unban</button>
    </div>`;
  }).join("");
}

function unban(banId) {
  if (!banId) return;
  showModal("Unban player?", `Remove ban ID ${banId}?`, () => post("unbanSelectedPlayer", { banID: banId }));
}

function renderWhitelist(rows) {
  const el = $("#whitelist-records");
  if (!el) return;
  rows = rows || [];
  if (!rows.length) {
    el.innerHTML = '<div class="empty">No whitelist entries</div>';
    return;
  }
  el.innerHTML = rows.map((r) => {
    const name = r.player_name || r.name || "Unknown";
    const ident = r.identifier || "";
    const id = r.id;
    return `<div class="record-row" onclick="removeWhitelist(${Number(id)})">
      <div class="main"><b>${esc(name)}</b><small>${esc(ident)}</small></div>
      <button class="btn secondary">Remove</button>
    </div>`;
  }).join("");
}

function removeWhitelist(id) {
  if (!id) return;
  showModal("Remove whitelist?", `Remove whitelist record #${id}?`, () => post("removeWhitelistUser", { id }));
}

/* ---------- events ---------- */

document.addEventListener("DOMContentLoaded", () => {
  $all(".nav-item").forEach((btn) => {
    btn.addEventListener("click", () => navigate(btn.dataset.page));
  });
  $("#btn-close").addEventListener("click", closeUI);
  $("#cfg-search") && $("#cfg-search").addEventListener("input", () => renderConfig());
  $("#player-search") && $("#player-search").addEventListener("input", () => renderPlayers(state.players));
  $("#bl-search") && $("#bl-search").addEventListener("input", () => showBlTab(state.blTab));
  $("#bl-tabs") && $("#bl-tabs").addEventListener("click", (e) => {
    const t = e.target.closest(".tab");
    if (t) showBlTab(t.dataset.bl);
  });
  $("#cfg-body") && $("#cfg-body").addEventListener("click", (e) => {
    const tog = e.target.closest(".toggle");
    if (tog) {
      const key = tog.dataset.key;
      const next = !tog.classList.contains("on");
      setPending(key, next);
    }
  });
  $("#cfg-body") && $("#cfg-body").addEventListener("change", (e) => {
    const el = e.target;
    if (!el.dataset || !el.dataset.key) return;
    const key = el.dataset.key;
    const type = el.dataset.type;
    let val = el.value;
    if (type === "number") val = Number(val);
    if (type === "punishment") val = String(val).toUpperCase();
    setPending(key, val);
  });
});

window.addEventListener("message", (event) => {
  const msg = event.data || {};
  const action = msg.action;
  if (action === "openUI") {
    openUI(msg.version);
  } else if (action === "forceClose") {
    state.open = false;
    $("#app").style.display = "none";
  } else if (action === "cc:dashboard") {
    renderDashboard(msg.data);
  } else if (action === "cc:config") {
    const d = msg.data || {};
    state.configSchema = d.schema;
    state.configValues = d.values || {};
    state.pendingChanges = {};
    renderConfig();
  } else if (action === "cc:detections") {
    renderHistory(msg.data);
  } else if (action === "cc:players") {
    renderPlayers(msg.data);
  } else if (action === "cc:health") {
    renderHealth(msg.data);
  } else if (action === "cc:configLog") {
    renderConfigLog(msg.data);
  } else if (action === "cc:blacklists") {
    renderBlacklists(msg.data);
  } else if (action === "cc:toast") {
    const d = msg.data || {};
    toast(d.type || "success", d.title, d.message);
    if (d.type === "success") {
      state.pendingChanges = {};
      loadConfig();
      if (state.page === "bans") loadBans();
      if (state.page === "whitelist") loadWhitelist();
    }
  } else if (action === "cc:liveDetection") {
    if (msg.data) {
      state.live = [msg.data].concat(state.live || []).slice(0, 100);
      renderLive(state.live);
      renderLiveFull();
      if (state.dashboard) {
        state.dashboard.detections = (state.dashboard.detections || 0) + 1;
        $("#stat-detections").textContent = state.dashboard.detections;
      }
    }
  } else if (action === "updateBanList") {
    renderBanList(msg.banList || msg.data || []);
  } else if (action === "updateWhiteList") {
    renderWhitelist(msg.whiteList || msg.data || []);
  }
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && state.open) closeUI();
});

// expose for inline handlers
window.navigate = navigate;
window.refreshDashboard = refreshDashboard;
window.loadPlayers = loadPlayers;
window.loadHistory = loadHistory;
window.loadBans = loadBans;
window.loadWhitelist = loadWhitelist;
window.loadBlacklists = loadBlacklists;
window.loadConfigLog = loadConfigLog;
window.loadHealth = loadHealth;
window.loadConfig = loadConfig;
window.saveConfig = saveConfig;
window.resetConfig = resetConfig;
window.tool = tool;
window.playerAction = playerAction;
window.histPage = histPage;
window.unban = unban;
window.removeWhitelist = removeWhitelist;
