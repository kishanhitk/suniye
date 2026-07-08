import { describe, expect, test } from "bun:test";
import { dailyVisitorHash, utcDate } from "../src/lib/webAnalytics/visitor";

describe("dailyVisitorHash", () => {
  test("is deterministic for the same inputs", async () => {
    const a = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    const b = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    expect(a).toBe(b);
  });

  test("differs across day (salt rotation window)", async () => {
    const a = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    const b = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-08", "salt");
    expect(a).not.toBe(b);
  });

  test("differs across IP and never contains the raw IP", async () => {
    const a = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    const b = await dailyVisitorHash("9.9.9.9", "UA", "2026-07-07", "salt");
    expect(a).not.toBe(b);
    expect(a).not.toContain("1.2.3.4");
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });

  test("utcDate formats YYYY-MM-DD in UTC", () => {
    expect(utcDate(Date.UTC(2026, 6, 7, 23, 30))).toBe("2026-07-07");
  });
});
