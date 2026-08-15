import type { LatencySummary } from "../types";
import { formatMs } from "../lib/utils";

const STAGE_LABELS: Record<string, string> = {
  end_to_end: "end→end",
  asr: "speech→text",
  magic_format: "magic format",
  llm_prefill: "llm prefill",
  model_load: "model load",
};

/**
 * Per-stage p50 (filled) over p95 (ghost) bars on one shared scale.
 * `end_to_end` is the number users feel, so it alone gets the accent.
 */
export function LatencyBars({ stages }: { stages: LatencySummary[] }) {
  const present = stages.filter((s) => s.p95 > 0 || s.p50 > 0);
  const max = Math.max(...present.map((s) => s.p95), 1);

  return (
    <div className="space-y-3">
      {stages.map((stage) => {
        const felt = stage.stage === "end_to_end";
        const empty = stage.p50 <= 0 && stage.p95 <= 0;
        return (
          <div key={stage.stage} className="grid grid-cols-[7.5rem_1fr_7rem] items-center gap-3">
            <span className="font-mono text-xs text-muted">{STAGE_LABELS[stage.stage] ?? stage.stage}</span>
            <div
              className="relative h-2.5 overflow-hidden rounded-full bg-surface"
              role="img"
              aria-label={`${STAGE_LABELS[stage.stage] ?? stage.stage}: median ${formatMs(stage.p50)}, 95th percentile ${formatMs(stage.p95)}`}
            >
              {!empty && (
                <>
                  <div
                    className="absolute inset-y-0 left-0 rounded-full bg-line"
                    style={{ width: `${Math.min(100, (stage.p95 / max) * 100)}%` }}
                  />
                  <div
                    className={felt ? "absolute inset-y-0 left-0 rounded-full bg-accent" : "absolute inset-y-0 left-0 rounded-full bg-ink/55"}
                    style={{ width: `${Math.min(100, (stage.p50 / max) * 100)}%` }}
                  />
                </>
              )}
            </div>
            <span className="text-right font-mono text-xs tabular-nums text-ink">
              {empty ? <span className="text-muted">—</span> : (
                <>
                  {formatMs(stage.p50)} <span className="text-muted">/ {formatMs(stage.p95)}</span>
                </>
              )}
            </span>
          </div>
        );
      })}
      <p className="font-mono text-[11px] text-muted">p50 / p95 · end→end is what users feel</p>
    </div>
  );
}
