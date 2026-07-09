// Suniye Browser Control — MV3 service worker.
// Connects to the Suniye app's localhost WebSocket, authenticates with the paired
// token, and answers tool requests: perception (snapshot/read_text), navigation,
// and trusted CDP actuation (click/focus/type/press) on the perceived tab.
// Everything stays on 127.0.0.1; nothing is sent off the machine.
//
// Known v1 limitations (deliberate): top frame only (no cross-origin iframes),
// no shadow-DOM piercing, and the app drives requests serially (handlers assume
// no overlapping tool calls).

// Code-level version: Chrome caches unpacked SW scripts, and getManifest() can
// report a RELOADED manifest while stale script code still runs — so staleness
// detection must key off a constant baked into THIS file. Bump with every edit.
const CODE_VERSION = "0.0.6";

// Max actionable elements per snapshot. Controls are prioritized over links, but
// the cap must be high enough that important LINKS (e.g. a "My orders" item in an
// account dropdown) aren't all crowded out behind a page's nav links.
const SNAPSHOT_CAP = 120;

let ws = null;
let connecting = false;
let reconnectTimer = null;

// TEMP diagnostics: in-memory breadcrumbs (empty after an SW eviction+revival).
const DBG = [];
function dbg(s) { DBG.push((Date.now() % 100000) + ":" + s); if (DBG.length > 300) DBG.shift(); }
dbg("SW-START");

async function loadPairing() {
  // The app injects pairing.json {port, token} into this (copied-out) extension.
  try {
    const res = await fetch(chrome.runtime.getURL("pairing.json"));
    return await res.json();
  } catch (e) {
    console.warn("[suniye] no pairing.json yet:", e);
    return null;
  }
}

async function connect() {
  // Guard against overlapping connects (load-time call + alarm + reconnect all race).
  if (connecting || (ws && (ws.readyState === 0 || ws.readyState === 1))) return;
  connecting = true;
  const pairing = await loadPairing();
  if (!pairing || !pairing.port || !pairing.token) { connecting = false; return scheduleReconnect(); }

  let socket;
  try {
    socket = new WebSocket(`ws://127.0.0.1:${pairing.port}`);
  } catch (e) {
    connecting = false;
    return scheduleReconnect();
  }
  ws = socket; // capture locally in every handler so a later connect() can't hijack this one

  socket.onopen = () => {
    connecting = false;
    socket.send(JSON.stringify({ type: "hello", protocol: 1, extensionVersion: "0.0.1", token: pairing.token }));
    console.log("[suniye] connected to app");
  };
  socket.onmessage = async (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch { return; }
    if (msg.type === "welcome") { console.log("[suniye] paired"); return; }
    if (msg.type === "ping") { socket.send(JSON.stringify({ type: "pong", t: msg.t })); return; }
    if (!msg.id || !msg.tool) return;
    dbg("recv:" + msg.tool);
    // Watchdog: a tool that internally hangs (e.g. executeScript against a paused
    // or wedged page) must still ANSWER, or the app-side request only dies by timeout.
    const watchdog = new Promise((resolve) => setTimeout(() =>
      resolve({ ok: false, error: { code: "tool_hang", message: `${msg.tool} did not finish in time` } }), 8000));
    const response = await Promise.race([handleTool(msg.tool, msg.args || {}), watchdog]);
    dbg("done:" + msg.tool + ":" + (response && response.ok));
    try { socket.send(JSON.stringify({ id: msg.id, ...response })); } catch {}
  };
  socket.onclose = () => { connecting = false; if (ws === socket) ws = null; detachDebugger(); scheduleReconnect(); };
  socket.onerror = () => { connecting = false; try { socket.close(); } catch {} };
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 2000);
}

// ---- Tab targeting. Perception (snapshot/navigate/read_text) PINS the tab it
// acted on; actuation then targets that pinned tab, so a user switching tabs or
// windows mid-run can't make the agent click on an unrelated page.
let targetTabId = null;

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  return tab;
}

async function resolveTargetTab() {
  if (targetTabId != null) {
    try {
      return await chrome.tabs.get(targetTabId);
    } catch {
      targetTabId = null; // pinned tab was closed
    }
  }
  return activeTab();
}

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabId === targetTabId) targetTabId = null;
  if (tabId === attachedTabId) attachedTabId = null;
});

async function handleTool(tool, args) {
  try {
    if (tool === "read_text") return await readText(args);
    if (tool === "navigate") return await navigate(args);
    if (tool === "snapshot") return await snapshot(args);
    if (tool === "click") return await clickRef(args);
    if (tool === "focus") return await focusRef(args);
    if (tool === "type") return await typeRef(args);
    if (tool === "press") return await pressKeys(args);
    if (tool === "diag") { // pure JS, cannot hang — version + breadcrumbs for the harness
      return { ok: true, result: { v: CODE_VERSION, log: DBG.join(" | "), targetTabId: String(targetTabId), attached: String(attachedTabId) } };
    }
    if (tool === "close_tab") { // harness hygiene: close the pinned fixture tab
      if (targetTabId != null) { try { await chrome.tabs.remove(targetTabId); } catch {} targetTabId = null; }
      return { ok: true, result: { output: "closed" } };
    }
    if (tool === "reload") {
      // Dev/harness hook: Chrome caches unpacked service-worker code until an
      // explicit extension reload — this makes code syncs autonomous.
      setTimeout(() => chrome.runtime.reload(), 100);
      return { ok: true, result: { output: "reloading" } };
    }
    return { ok: false, error: { code: "unknown_tool", message: `unknown tool ${tool}` } };
  } catch (e) {
    return { ok: false, error: { code: "exception", message: String((e && e.message) || e) } };
  }
}

// ---- CDP (chrome.debugger) attach management: trusted input on the target tab.
// The "Suniye started debugging this browser" banner while attached is the
// intended, always-visible "automation is active" signal.
let attachedTabId = null;
// When the USER cancels the banner, that is a stop request — honor it instead of
// silently re-attaching on the next action.
let userDetachedAt = 0;
const USER_DETACH_COOLDOWN_MS = 15000;

async function ensureAttached(tabId) {
  if (Date.now() - userDetachedAt < USER_DETACH_COOLDOWN_MS) {
    throw Object.assign(new Error("browser automation was cancelled from the banner"), { code: "user_detached" });
  }
  if (attachedTabId === tabId) return;
  if (attachedTabId != null) { try { await chrome.debugger.detach({ tabId: attachedTabId }); } catch {} }
  await chrome.debugger.attach({ tabId }, "1.3");
  attachedTabId = tabId;
}

async function detachDebugger() {
  if (attachedTabId == null) return;
  try { await chrome.debugger.detach({ tabId: attachedTabId }); } catch {}
  attachedTabId = null;
}

chrome.debugger.onDetach.addListener((source, reason) => {
  if (source.tabId === attachedTabId) attachedTabId = null;
  if (reason === "canceled_by_user") userDetachedAt = Date.now();
});

function cdp(tabId, method, params) {
  return chrome.debugger.sendCommand({ tabId }, method, params || {});
}

// ---- Snapshot: DOM walk → e0/e1 refs (mirrors AXTreeReader's role/label set).
// Tags each actionable element with data-suniye-ref so click/type resolve later.
function snapshotFn(maxElements) {
  document.querySelectorAll("[data-suniye-ref]").forEach((el) => el.removeAttribute("data-suniye-ref"));
  const roleFor = (el) => {
    const tag = el.tagName.toLowerCase();
    const role = (el.getAttribute("role") || "").toLowerCase();
    const type = (el.getAttribute("type") || "").toLowerCase();
    if ((tag === "a" && el.href) || role === "link") return "link";
    if (tag === "button" || role === "button" || (tag === "input" && ["button", "submit", "reset", "image"].includes(type))) return "button";
    if (tag === "textarea") return "textarea";
    if (tag === "select" || role === "combobox" || role === "listbox") return "combobox";
    if ((tag === "input" && type === "search") || role === "searchbox") return "searchfield";
    if ((tag === "input" && ["text", "email", "tel", "url", "number", "password", "date", "datetime-local", "month", "week", "time", ""].includes(type)) || el.isContentEditable || role === "textbox") return "textfield";
    if ((tag === "input" && type === "checkbox") || role === "checkbox" || role === "switch") return "checkbox";
    if ((tag === "input" && type === "radio") || role === "radio") return "radiobutton";
    if (["menuitem", "menuitemcheckbox", "option"].includes(role)) return "menuitem";
    return null;
  };
  const labelFor = (el) => {
    const byId = (id) => { const l = id ? document.getElementById(id) : null; return l ? l.innerText : null; };
    const forLabel = () => { if (!el.id) return null; try { const l = document.querySelector(`label[for="${CSS.escape(el.id)}"]`); return l ? l.innerText : null; } catch { return null; } };
    const options = [el.getAttribute("aria-label"), byId(el.getAttribute("aria-labelledby")), forLabel(),
      el.getAttribute("placeholder"), el.getAttribute("title"), el.getAttribute("alt"),
      (el.innerText || "").trim(), el.value, el.getAttribute("name")];
    for (const opt of options) { if (opt && String(opt).trim()) return String(opt).trim().replace(/\s+/g, " "); }
    return "";
  };
  const visible = (el) => {
    const st = getComputedStyle(el);
    if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) === 0) return false;
    if (el.getAttribute("aria-hidden") === "true") return false;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    if (el.offsetParent === null && st.position !== "fixed") return false;
    return true;
  };
  const collected = [];
  const candidates = document.querySelectorAll('a, button, input, textarea, select, [role], [contenteditable="true"]');
  for (const el of candidates) {
    if (collected.length >= 300) break;
    const role = roleFor(el);
    if (!role) continue;
    if (el.disabled || el.getAttribute("aria-disabled") === "true" || !visible(el)) continue;
    let label = labelFor(el);
    if (label.length > 60) label = label.slice(0, 60) + "…";
    collected.push({ el, role, label });
  }
  // Prioritize interactive controls (buttons/fields) over the many nav links, so a
  // key button like "Add to cart" survives the cap on dense pages. Array.sort is
  // stable, so document order is preserved within a priority band.
  const priority = (role) => (role === "link" || role === "menuitem" ? 1 : 0);
  collected.sort((a, b) => priority(a.role) - priority(b.role));
  const rows = [];
  collected.slice(0, maxElements).forEach((item, index) => {
    const ref = "e" + index;
    item.el.setAttribute("data-suniye-ref", ref);
    rows.push({ ref, role: item.role, label: item.label });
  });
  return { rows, url: location.href, title: document.title, count: rows.length };
}

async function runSnapshot(tabId) {
  const [res] = await chrome.scripting.executeScript({ target: { tabId }, func: snapshotFn, args: [SNAPSHOT_CAP] });
  return (res && res.result) || { rows: [], url: "", title: "", count: 0 };
}

async function snapshot() {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  targetTabId = tab.id; // pin: actuation acts on what was perceived
  // SPA pages report "complete" before rendering content. Rather than sleeping a
  // fixed delay after navigation, retry the walk briefly until the page yields a
  // usable number of elements (bounded; plain/empty pages just take the last try).
  let data = { rows: [], url: "", title: "", count: 0 };
  for (let attempt = 0; attempt < 4; attempt++) {
    data = await runSnapshot(tab.id);
    if (data.rows.length >= 3) break;
    await new Promise((r) => setTimeout(r, 400));
  }
  return { ok: true, result: { rows: JSON.stringify(data.rows), url: data.url, title: data.title, count: data.count } };
}

// ---- Ref resolution with IDENTITY VERIFICATION. If a ref's tag vanished (SPA
// re-render), re-running the walk re-assigns e0..eN by current order — which can
// silently point the SAME ref at a DIFFERENT element. So on any re-tag, the ref
// is only trusted if its role+label still match what the model saw; otherwise we
// look for a unique element with that role+label and remap, else report stale.
async function resolveRef(tabId, ref, role, label) {
  const present = async () => {
    const [res] = await chrome.scripting.executeScript({
      target: { tabId },
      func: (r) => !!document.querySelector(`[data-suniye-ref="${r}"]`),
      args: [ref],
    });
    return !!(res && res.result === true);
  };
  if (await present()) return { ok: true, ref };

  const data = await runSnapshot(tabId);
  const stale = { ok: false, error: { code: "stale_ref", message: `no element ${ref} — call read_screen first` } };
  if (!role && !label) {
    // No identity to verify against — only accept an exact re-tag.
    return (await present()) ? { ok: true, ref } : stale;
  }
  const matches = data.rows.filter((row) => (!role || row.role === role) && (!label || row.label === label));
  if (matches.length === 1) return { ok: true, ref: matches[0].ref };
  const atRef = data.rows.find((row) => row.ref === ref);
  if (atRef && (!role || atRef.role === role) && (!label || atRef.label === label)) return { ok: true, ref };
  return stale;
}

// ---- Sensitive-target refusal (defense in depth; the app also gates risky
// actions behind a user confirmation). Best-effort heuristics — password inputs,
// card/CVC autocomplete, and name/placeholder patterns.
const SENSITIVE_JS = `(el) => {
    const t = ((el && el.type) || "").toLowerCase();
    if (t === "password") return true;
    const attr = (name) => ((el.getAttribute && el.getAttribute(name)) || "").toLowerCase();
    const ac = attr("autocomplete");
    if (/cc-|card|cvc|cvv|password/.test(ac)) return true;
    const hints = [attr("name"), attr("id"), attr("placeholder"), attr("aria-label")].join(" ");
    return /passw|cvv|cvc|card.?number|security.?code/.test(hints);
  }`;

function locateExpr(ref) {
  return `(() => {
    const isSensitive = ${SENSITIVE_JS};
    const el = document.querySelector('[data-suniye-ref=${JSON.stringify(ref)}]');
    if (!el) return { err: "stale" };
    if (isSensitive(el)) return { refused: 1 };
    el.scrollIntoView({ block: "center", inline: "center" });
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  })()`;
}

async function locate(tabId, ref) {
  const ev = await cdp(tabId, "Runtime.evaluate", { expression: locateExpr(ref), returnByValue: true });
  const v = ev && ev.result && ev.result.value;
  if (!v || v.err === "stale") return { error: { code: "stale_ref", message: `no element ${ref} — call read_screen first` } };
  if (v.refused) return { error: { code: "refused", message: "I can't complete login or payment steps" } };
  return { x: v.x, y: v.y };
}

async function clickRef(args) {
  const tab = await resolveTargetTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  try {
    await ensureAttached(tab.id);
  } catch (e) {
    return { ok: false, error: { code: e.code || "attach_failed", message: e.message } };
  }
  const resolved = await resolveRef(tab.id, args.ref, args.role, args.label);
  if (!resolved.ok) return { ok: false, error: resolved.error };
  const loc = await locate(tab.id, resolved.ref);
  if (loc.error) return { ok: false, error: loc.error };
  await cdp(tab.id, "Input.dispatchMouseEvent", { type: "mousePressed", x: loc.x, y: loc.y, button: "left", clickCount: 1 });
  await cdp(tab.id, "Input.dispatchMouseEvent", { type: "mouseReleased", x: loc.x, y: loc.y, button: "left", clickCount: 1 });
  return { ok: true, result: { output: `clicked ${args.ref}` } };
}

async function focusRef(args) {
  const tab = await resolveTargetTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  const resolved = await resolveRef(tab.id, args.ref, args.role, args.label);
  if (!resolved.ok) return { ok: false, error: resolved.error };
  const [res] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    // NOTE: the sensitive-field heuristic is inlined (not shared via SENSITIVE_JS)
    // because injected functions run under the extension CSP, which bans eval.
    func: (ref) => {
      const el = document.querySelector(`[data-suniye-ref="${ref}"]`);
      if (!el) return "stale";
      const attr = (name) => ((el.getAttribute && el.getAttribute(name)) || "").toLowerCase();
      const type = ((el.type) || "").toLowerCase();
      const hints = [attr("name"), attr("id"), attr("placeholder"), attr("aria-label")].join(" ");
      if (type === "password" || /cc-|card|cvc|cvv|password/.test(attr("autocomplete"))
          || /passw|cvv|cvc|card.?number|security.?code/.test(hints)) return "refused";
      el.focus();
      el.scrollIntoView({ block: "center" });
      return "ok";
    },
    args: [resolved.ref],
  });
  const outcome = res && res.result;
  if (outcome === "stale") return { ok: false, error: { code: "stale_ref", message: `no element ${args.ref} — call read_screen first` } };
  if (outcome === "refused") return { ok: false, error: { code: "refused", message: "I can't complete login or payment steps" } };
  return { ok: true, result: { output: `focused ${args.ref}` } };
}

async function typeRef(args) {
  const tab = await resolveTargetTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  try {
    await ensureAttached(tab.id);
  } catch (e) {
    return { ok: false, error: { code: e.code || "attach_failed", message: e.message } };
  }
  if (args.ref) {
    // Explicit target: verify identity, refuse sensitive, then focus it.
    const resolved = await resolveRef(tab.id, args.ref, args.role, args.label);
    if (!resolved.ok) return { ok: false, error: resolved.error };
    const loc = await locate(tab.id, resolved.ref);
    if (loc.error) return { ok: false, error: loc.error };
    await cdp(tab.id, "Runtime.evaluate", { expression: `document.querySelector('[data-suniye-ref=${JSON.stringify(resolved.ref)}]').focus()` });
  } else {
    // No ref (type into whatever the model just focused): refuse sensitive fields.
    const ev = await cdp(tab.id, "Runtime.evaluate", {
      expression: `(() => { const isSensitive = ${SENSITIVE_JS};
        const el = document.activeElement;
        if (!el || el === document.body) return { err: "nofocus" };
        if (isSensitive(el)) return { refused: 1 };
        return { ok: 1 }; })()`,
      returnByValue: true,
    });
    const v = ev && ev.result && ev.result.value;
    if (!v || v.err === "nofocus") return { ok: false, error: { code: "no_focus", message: "focus a field first, then type" } };
    if (v.refused) return { ok: false, error: { code: "refused", message: "I can't fill password or payment fields" } };
  }
  await cdp(tab.id, "Input.insertText", { text: String(args.text || "") });
  return { ok: true, result: { output: `typed ${String(args.text || "").length} chars` } };
}

// `text` matters: a keyDown WITHOUT text is a rawKeyDown and never runs the
// browser's default actions (Enter wouldn't submit forms). "\r" mirrors what
// Puppeteer sends for Enter.
const KEYMAP = {
  enter: { key: "Enter", code: "Enter", vk: 13, text: "\r" },
  return: { key: "Enter", code: "Enter", vk: 13, text: "\r" },
  tab: { key: "Tab", code: "Tab", vk: 9 },
  escape: { key: "Escape", code: "Escape", vk: 27 },
  backspace: { key: "Backspace", code: "Backspace", vk: 8 },
};

async function pressKey(tabId, keys) {
  const k = KEYMAP[String(keys || "").toLowerCase()];
  if (!k) return false;
  const base = { key: k.key, code: k.code, windowsVirtualKeyCode: k.vk, nativeVirtualKeyCode: k.vk };
  const down = { type: k.text ? "keyDown" : "rawKeyDown", ...base };
  if (k.text) { down.text = k.text; down.unmodifiedText = k.text; }
  await cdp(tabId, "Input.dispatchKeyEvent", down);
  await cdp(tabId, "Input.dispatchKeyEvent", { type: "keyUp", ...base });
  return true;
}

async function pressKeys(args) {
  const tab = await resolveTargetTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  try {
    await ensureAttached(tab.id);
  } catch (e) {
    return { ok: false, error: { code: e.code || "attach_failed", message: e.message } };
  }
  const sent = await pressKey(tab.id, args.keys);
  if (!sent) return { ok: false, error: { code: "unsupported_key", message: `can't press ${args.keys} on a page` } };
  return { ok: true, result: { output: `pressed ${args.keys}` } };
}

async function navigate(args) {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  let url = String(args.url || "").trim();
  if (!url) return { ok: false, error: { code: "bad_args", message: "missing url" } };
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) url = "https://" + url; // add scheme if omitted
  targetTabId = tab.id; // pin: subsequent perception/actuation follow this tab
  await chrome.tabs.update(tab.id, { url });
  const completed = await waitForComplete(tab.id, 15000);
  const note = completed ? "" : " (page may still be loading)";
  return { ok: true, result: { output: "navigated to " + url + note, url } };
}

function waitForComplete(tabId, timeoutMs) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (completed) => {
      if (done) return;
      done = true;
      chrome.tabs.onUpdated.removeListener(listener);
      resolve(completed);
    };
    const timer = setTimeout(() => finish(false), timeoutMs);
    function listener(id, info) {
      if (id === tabId && info.status === "complete") { clearTimeout(timer); finish(true); }
    }
    chrome.tabs.onUpdated.addListener(listener);
  });
}

async function readText() {
  const tab = await resolveTargetTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  const maxChars = 4000; // bounded output: the agent prompt must stay small
  const [res] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: (limit) => {
      const body = document.body;
      const text = ((body ? body.innerText : "") || "").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim().slice(0, limit);
      return { text, tc: body ? body.textContent.length : -1, vis: document.visibilityState, href: location.href };
    },
    args: [maxChars],
  });
  const r = (res && res.result) || { text: "", tc: -2, vis: "?", href: "?" };
  return { ok: true, result: { text: r.text, truncated: r.text.length >= maxChars, url: tab.url || "", title: tab.title || "", tc: r.tc, vis: r.vis, href: r.href } };
}

// MV3 service workers get evicted; an alarm wakes us to reconnect. (The app's
// 20s keepalive ping keeps us alive while connected; the alarm is the backstop.)
chrome.alarms.create("suniye-keepalive", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(() => { if (!ws || ws.readyState > 1) connect(); });
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
