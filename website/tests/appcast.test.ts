import { describe, expect, test } from "bun:test";
import { handleAppcastRequest, handleTipAppcastRequest } from "../src/lib/appcast";

const xml = `<?xml version="1.0" encoding="utf-8"?><rss version="2.0"></rss>`;

describe("appcast endpoint", () => {
  test("proxies latest release appcast XML", async () => {
    const response = await handleAppcastRequest(
      new Request("https://suniye.test/appcast.xml"),
      async (input) => {
        expect(input).toBe("https://github.com/kishanhitk/suniye/releases/latest/download/appcast.xml");
        return new Response(xml, {
          status: 200,
          headers: {
            "Content-Type": "application/xml",
          },
        });
      }
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("application/rss+xml; charset=utf-8");
    expect(response.headers.get("Cache-Control")).toContain("s-maxage=300");
    expect(await response.text()).toBe(xml);
  });

  test("returns 502 when upstream appcast is unavailable", async () => {
    const response = await handleAppcastRequest(
      new Request("https://suniye.test/appcast.xml"),
      async () => new Response("not found", { status: 404 })
    );

    expect(response.status).toBe(502);
  });

  test("proxies tip appcast XML", async () => {
    const response = await handleTipAppcastRequest(
      new Request("https://suniye.test/appcast-tip.xml"),
      async (input) => {
        expect(input).toBe("https://github.com/kishanhitk/suniye/releases/download/tip/appcast.xml");
        return new Response(xml, {
          status: 200,
          headers: {
            "Content-Type": "application/xml",
          },
        });
      }
    );

    expect(response.status).toBe(200);
    expect(await response.text()).toBe(xml);
  });

  test("rejects unsupported methods", async () => {
    const response = await handleAppcastRequest(
      new Request("https://suniye.test/appcast.xml", { method: "POST" }),
      async () => new Response(xml)
    );

    expect(response.status).toBe(405);
    expect(response.headers.get("Allow")).toBe("GET, HEAD");
  });
});
