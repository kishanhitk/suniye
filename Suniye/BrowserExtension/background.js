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
  socket.onclose = () => { connecting = false; if (ws === socket) ws = null; scheduleReconnect(); };
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
    return { ok: false, error: { code: "unknown_tool", message: `unknown tool ${tool}` } };
  } catch (e) {
    return { ok: false, error: { code: "exception", message: String((e && e.message) || e) } };
  }
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
  const maxChars = 12000;
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
