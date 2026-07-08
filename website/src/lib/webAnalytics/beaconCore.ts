export interface BeaconEvent {
  name: string;
  props: Record<string, string | number | boolean>;
}

export interface BeaconCoreDeps {
  sessionId: string;
  send: (body: string) => void;
  genId: () => string;
  now: () => number;
}

export interface BeaconCore {
  track(ev: BeaconEvent): void;
  trackScrollDepth(depth: number, path: string): void;
  flush(): void;
}

/**
 * DOM-agnostic beacon buffer. Holds events until flush(), which serializes the
 * batch envelope and hands it to `send` (the DOM layer wires sendBeacon). Pure
 * and unit-testable; scroll thresholds are de-duplicated here.
 */
export function createBeaconCore(deps: BeaconCoreDeps): BeaconCore {
  const queue: Array<{ event_id: string; event_ts: number; session_id: string; name: string; props: Record<string, string | number | boolean> }> = [];
  const firedDepths = new Set<number>();

  function track(ev: BeaconEvent): void {
    queue.push({ event_id: deps.genId(), event_ts: deps.now(), session_id: deps.sessionId, name: ev.name, props: ev.props });
  }

  function trackScrollDepth(depth: number, path: string): void {
    if (firedDepths.has(depth)) return;
    firedDepths.add(depth);
    track({ name: "scroll_depth", props: { depth, path } });
  }

  function flush(): void {
    if (queue.length === 0) return;
    const events = queue.splice(0, queue.length);
    deps.send(JSON.stringify({ sent_at: deps.now(), events }));
  }

  return { track, trackScrollDepth, flush };
}
