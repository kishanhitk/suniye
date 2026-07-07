import type { FilterDim } from "../types";

/** Readable labels for the filter menu (browse + value rows). */
export const DIM_LABEL: Record<FilterDim, string> = {
  version: "version", channel: "channel", chip: "chip", ram: "ram gb",
  os: "macos", mac_model: "mac model", arch: "arch", cpu_cores: "cpu cores",
  asr_model: "asr model", cleanup_model: "llm model", language: "language",
  target: "target app", country: "country",
};

/** Compact keys for the active-filter chips, so they read like a query line. */
export const CHIP_KEY: Record<FilterDim, string> = {
  version: "version", channel: "channel", chip: "chip", ram: "ram",
  os: "macos", mac_model: "mac", arch: "arch", cpu_cores: "cores",
  asr_model: "asr", cleanup_model: "llm", language: "lang",
  target: "target", country: "country",
};

/** Menu grouping — dimensions clustered by what they describe (aids discovery). */
export const DIM_GROUPS: Array<{ label: string; dims: FilterDim[] }> = [
  { label: "release", dims: ["version", "channel"] },
  { label: "device", dims: ["chip", "ram", "os", "mac_model", "arch", "cpu_cores"] },
  { label: "model", dims: ["asr_model", "cleanup_model"] },
  { label: "context", dims: ["language", "target", "country"] },
];
