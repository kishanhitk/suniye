// Suniye Browser Control — MV3 service worker.
// Connects to the Suniye app's localhost WebSocket, authenticates with the paired
// token, and answers tool requests. Phase A: read-only (read_text).
// Everything stays on 127.0.0.1; nothing is sent off the machine.

let ws = null;
let connecting = false;
let reconnectTimer = null;

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
    const response = await handleTool(msg.tool, msg.args || {});
    try { socket.send(JSON.stringify({ id: msg.id, ...response })); } catch {}
  };
  socket.onclose = () => { connecting = false; if (ws === socket) ws = null; detachDebugger(); scheduleReconnect(); };
  socket.onerror = () => { connecting = false; try { socket.close(); } catch {} };
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 2000);
}

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  return tab;
}

async function handleTool(tool, args) {
  try {
    if (tool === "read_text") return await readText(args);
    if (tool === "navigate") return await navigate(args);
    if (tool === "snapshot") return await snapshot(args);
    if (tool === "click") return await clickRef(args);
    if (tool === "focus") return await focusRef(args);
    if (tool === "type") return await typeRef(args);
    if (tool === "press") return await pressKeys(args);
    return { ok: false, error: { code: "unknown_tool", message: `unknown tool ${tool}` } };
  } catch (e) {
    return { ok: false, error: { code: "exception", message: String((e && e.message) || e) } };
  }
}

// ---- CDP (chrome.debugger) attach management: trusted input on the active tab.
// The "Suniye started debugging this browser" banner while attached is the
// intended, always-visible "automation is active" signal.
let attachedTabId = null;

async function ensureAttached(tabId) {
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

chrome.debugger.onDetach.addListener((source) => {
  if (source.tabId === attachedTabId) attachedTabId = null;
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
  const rows = [];
  let n = 0;
  const candidates = document.querySelectorAll('a, button, input, textarea, select, summary, [role], [contenteditable="true"]');
  for (const el of candidates) {
    if (n >= maxElements) break;
    const role = roleFor(el);
    if (!role) continue;
    if (el.disabled || el.getAttribute("aria-disabled") === "true" || !visible(el)) continue;
    let label = labelFor(el);
    if (label.length > 60) label = label.slice(0, 60) + "…";
    const ref = "e" + n;
    el.setAttribute("data-suniye-ref", ref);
    rows.push({ ref, role, label });
    n++;
  }
  return { rows, url: location.href, title: document.title, count: n };
}

async function snapshot() {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  const [res] = await chrome.scripting.executeScript({ target: { tabId: tab.id }, func: snapshotFn, args: [60] });
  const data = (res && res.result) || { rows: [], url: "", title: "", count: 0 };
  return { ok: true, result: { rows: JSON.stringify(data.rows), url: data.url, title: data.title, count: data.count } };
}

// ---- Actuation via CDP (trusted). Refuses password/payment targets (defense in
// depth; the app also gates .risky actions with a user confirmation).
function locateExpr(ref) {
  return `(() => {
    const el = document.querySelector('[data-suniye-ref=${JSON.stringify(ref)}]');
    if (!el) return { err: "stale" };
    const t = (el.type || "").toLowerCase();
    const ac = (el.getAttribute("autocomplete") || "").toLowerCase();
    if (t === "password" || /cc-|cardnumber|creditcard/.test(ac)) return { refused: 1 };
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
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  await ensureAttached(tab.id);
  const loc = await locate(tab.id, args.ref);
  if (loc.error) return { ok: false, error: loc.error };
  await cdp(tab.id, "Input.dispatchMouseEvent", { type: "mousePressed", x: loc.x, y: loc.y, button: "left", clickCount: 1 });
  await cdp(tab.id, "Input.dispatchMouseEvent", { type: "mouseReleased", x: loc.x, y: loc.y, button: "left", clickCount: 1 });
  return { ok: true, result: { output: `clicked ${args.ref}` } };
}

async function focusRef(args) {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  const [res] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: (ref) => { const el = document.querySelector(`[data-suniye-ref="${ref}"]`); if (!el) return "stale"; el.focus(); el.scrollIntoView({ block: "center" }); return "ok"; },
    args: [args.ref],
  });
  if ((res && res.result) === "stale") return { ok: false, error: { code: "stale_ref", message: `no element ${args.ref} — call read_screen first` } };
  return { ok: true, result: { output: `focused ${args.ref}` } };
}

async function typeRef(args) {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  await ensureAttached(tab.id);
  if (args.ref) {
    // Explicit target: locate (refuse password/payment + scroll), then focus it.
    const loc = await locate(tab.id, args.ref);
    if (loc.error) return { ok: false, error: loc.error };
    await cdp(tab.id, "Runtime.evaluate", { expression: `document.querySelector('[data-suniye-ref=${JSON.stringify(args.ref)}]').focus()` });
  } else {
    // No ref (type into whatever the model just focused): refuse password/payment.
    const ev = await cdp(tab.id, "Runtime.evaluate", {
      expression: `(() => { const el = document.activeElement;
        if (!el || el === document.body) return { err: "nofocus" };
        const t = (el.type || "").toLowerCase();
        const ac = ((el.getAttribute && el.getAttribute("autocomplete")) || "").toLowerCase();
        if (t === "password" || /cc-|cardnumber|creditcard/.test(ac)) return { refused: 1 };
        return { ok: 1 }; })()`,
      returnByValue: true,
    });
    const v = ev && ev.result && ev.result.value;
    if (!v || v.err === "nofocus") return { ok: false, error: { code: "no_focus", message: "focus a field first, then type" } };
    if (v.refused) return { ok: false, error: { code: "refused", message: "I can't fill password or payment fields" } };
  }
  await cdp(tab.id, "Input.insertText", { text: String(args.text || "") });
  if (args.submit === "true" || args.submit === true) await pressKey(tab.id, "enter");
  return { ok: true, result: { output: `typed ${String(args.text || "").length} chars` } };
}

const KEYMAP = {
  enter: { key: "Enter", code: "Enter", vk: 13 }, return: { key: "Enter", code: "Enter", vk: 13 },
  tab: { key: "Tab", code: "Tab", vk: 9 }, escape: { key: "Escape", code: "Escape", vk: 27 },
  backspace: { key: "Backspace", code: "Backspace", vk: 8 },
};

async function pressKey(tabId, keys) {
  const k = KEYMAP[String(keys || "").toLowerCase()];
  if (!k) return; // unsupported chord — ignore for v1
  const base = { key: k.key, code: k.code, windowsVirtualKeyCode: k.vk, nativeVirtualKeyCode: k.vk };
  await cdp(tabId, "Input.dispatchKeyEvent", { type: "keyDown", ...base });
  await cdp(tabId, "Input.dispatchKeyEvent", { type: "keyUp", ...base });
}

async function pressKeys(args) {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  await ensureAttached(tab.id);
  await pressKey(tab.id, args.keys);
  return { ok: true, result: { output: `pressed ${args.keys}` } };
}

async function navigate(args) {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  let url = String(args.url || "").trim();
  if (!url) return { ok: false, error: { code: "bad_args", message: "missing url" } };
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) url = "https://" + url; // add scheme if omitted
  await chrome.tabs.update(tab.id, { url });
  await waitForComplete(tab.id, 15000);
  return { ok: true, result: { output: "navigated to " + url, url } };
}

function waitForComplete(tabId, timeoutMs) {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => { if (done) return; done = true; chrome.tabs.onUpdated.removeListener(listener); resolve(); };
    const timer = setTimeout(finish, timeoutMs);
    function listener(id, info) {
      if (id === tabId && info.status === "complete") { clearTimeout(timer); finish(); }
    }
    chrome.tabs.onUpdated.addListener(listener);
  });
}

async function readText() {
  const tab = await activeTab();
  if (!tab || !tab.id) return { ok: false, error: { code: "no_tab", message: "no active browser tab" } };
  const maxChars = 4000; // keep the agent prompt/history small enough to avoid LLM timeouts
  const [res] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: (limit) => {
      const text = (document.body ? document.body.innerText : "") || "";
      return text.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim().slice(0, limit);
    },
    args: [maxChars],
  });
  const text = (res && res.result) || "";
  return { ok: true, result: { text, truncated: text.length >= maxChars, url: tab.url || "", title: tab.title || "" } };
}

// MV3 service workers get evicted; an alarm wakes us to reconnect.
chrome.alarms.create("suniye-keepalive", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(() => { if (!ws || ws.readyState > 1) connect(); });
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();
