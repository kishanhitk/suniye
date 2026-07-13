import { createBeaconCore, type BeaconCore } from "./beaconCore";

const ENDPOINT = "/api/track";
const SCROLL_THRESHOLDS = [25, 50, 75, 100];

function sessionId(): string {
  try {
    const k = "suniye_sid";
    let v = sessionStorage.getItem(k);
    if (!v) {
      v = crypto.randomUUID();
      sessionStorage.setItem(k, v);
    }
    return v;
  } catch {
    return crypto.randomUUID(); // private mode / storage blocked — ephemeral in-memory id
  }
}

function send(body: string): void {
  try {
    if (navigator.sendBeacon && navigator.sendBeacon(ENDPOINT, new Blob([body], { type: "application/json" }))) return;
  } catch {
    /* fall through */
  }
  fetch(ENDPOINT, { method: "POST", body, keepalive: true, headers: { "Content-Type": "application/json" } }).catch(() => {});
}

function pageviewProps(): Record<string, string> {
  const q = new URLSearchParams(location.search);
  const props: Record<string, string> = {
    path: location.pathname,
    device: window.matchMedia("(pointer: coarse)").matches ? "mobile" : "desktop",
    viewport: window.innerWidth < 640 ? "sm" : window.innerWidth < 1024 ? "md" : "lg",
  };
  for (const k of ["utm_source", "utm_medium", "utm_campaign"]) {
    const v = q.get(k);
    if (v) props[k] = v.slice(0, 256);
  }
  return props;
}

export function initBeacon(): void {
  if (typeof window === "undefined") return;
  const core: BeaconCore = createBeaconCore({
    sessionId: sessionId(),
    send,
    genId: () => crypto.randomUUID(),
    now: () => Date.now(),
  });

  core.track({ name: "pageview", props: pageviewProps() });

  // Click delegation: elements opt in via data-track="event:value".
  document.addEventListener(
    "click",
    (e) => {
      const el = (e.target as HTMLElement | null)?.closest?.("[data-track]") as HTMLElement | null;
      if (!el) return;
      const [name, value] = (el.dataset.track ?? "").split(":");
      if (!name) return;
      const key = name === "download_click" ? "target" : name === "outbound_click" ? "host" : "cta";
      core.track({ name, props: { [key]: value ?? "", path: location.pathname } });
      if (name === "download_click") core.flush(); // precedes navigation
    },
    { capture: true },
  );

  // Scroll depth.
  let ticking = false;
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const doc = document.documentElement;
      const pct = ((window.scrollY + window.innerHeight) / doc.scrollHeight) * 100;
      for (const t of SCROLL_THRESHOLDS) if (pct >= t) core.trackScrollDepth(t, location.pathname);
    });
  };
  window.addEventListener("scroll", onScroll, { passive: true });

  // Demo video plays (any <video data-track-video>).
  document.querySelectorAll("video[data-track-video]").forEach((v) =>
    v.addEventListener("play", () => core.track({ name: "video_play", props: { path: location.pathname } }), { once: true }),
  );

  // Flush on the way out.
  const flush = () => core.flush();
  document.addEventListener("visibilitychange", () => document.visibilityState === "hidden" && flush());
  window.addEventListener("pagehide", flush);
}
