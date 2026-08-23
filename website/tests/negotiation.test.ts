import { describe, expect, test } from "bun:test";
import {
  alternateLinkHeader,
  markdownResponse,
  negotiate,
  notAcceptableResponse,
  varyOnAccept,
} from "../src/lib/negotiation";

describe("negotiate", () => {
  test("defaults to HTML when Accept is missing, empty, or a wildcard", () => {
    expect(negotiate(null)).toBe("html");
    expect(negotiate("")).toBe("html");
    expect(negotiate("*/*")).toBe("html");
    expect(negotiate("text/*")).toBe("html");
  });

  test("serves HTML to a browser Accept header", () => {
    expect(
      negotiate("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"),
    ).toBe("html");
  });

  test("serves Markdown when it outranks HTML", () => {
    expect(negotiate("text/markdown")).toBe("markdown");
    expect(negotiate("text/markdown, text/html;q=0.5")).toBe("markdown");
    expect(negotiate("text/html;q=0.5, text/markdown")).toBe("markdown");
    expect(negotiate("text/markdown;q=0.9, */*;q=0.1")).toBe("markdown");
  });

  test("HTML wins ties and explicit lower q-values", () => {
    expect(negotiate("text/markdown, text/html")).toBe("html");
    expect(negotiate("text/markdown;q=0.8, text/html")).toBe("html");
  });

  test("an exact type beats a wildcard regardless of order", () => {
    expect(negotiate("*/*, text/markdown")).toBe("markdown");
    expect(negotiate("text/*;q=0.2, text/markdown;q=0.3")).toBe("markdown");
  });

  test("treats q=0 as excluded", () => {
    expect(negotiate("text/html;q=0, text/markdown")).toBe("markdown");
    expect(negotiate("text/markdown;q=0, */*")).toBe("html");
    expect(negotiate("text/html;q=0, text/markdown;q=0")).toBeNull();
  });

  test("returns null when neither representation is acceptable", () => {
    expect(negotiate("application/json")).toBeNull();
    expect(negotiate("image/*")).toBeNull();
  });

  test("ignores malformed entries and parameters", () => {
    expect(negotiate("garbage, text/markdown;q=abc")).toBe("markdown");
    expect(negotiate("text/markdown;q=0.2junk, text/html;q=0.5")).toBe("markdown");
    expect(negotiate("text/markdown;q=1.5, text/html")).toBe("html");
    expect(negotiate("garbage")).toBe("html");
    expect(negotiate("text/markdown;level=1;q=1, text/html;q=0.4")).toBe("markdown");
    expect(negotiate("TEXT/MARKDOWN")).toBe("markdown");
  });
});

describe("varyOnAccept", () => {
  test("sets Vary when absent", () => {
    const h = new Headers();
    varyOnAccept(h);
    expect(h.get("Vary")).toBe("Accept");
  });

  test("appends to an existing Vary list once", () => {
    const h = new Headers({ Vary: "Accept-Encoding" });
    varyOnAccept(h);
    varyOnAccept(h);
    expect(h.get("Vary")).toBe("Accept-Encoding, Accept");
  });

  test("leaves Vary alone when it already covers Accept", () => {
    const h = new Headers({ Vary: "accept, Accept-Encoding" });
    varyOnAccept(h);
    expect(h.get("Vary")).toBe("accept, Accept-Encoding");
    const star = new Headers({ Vary: "*" });
    varyOnAccept(star);
    expect(star.get("Vary")).toBe("*");
  });
});

describe("responses", () => {
  test("markdownResponse carries the media type, Vary, status, and the HTML alternate", async () => {
    const res = markdownResponse("# Hi\n", "https://suniye.app/about", 404);
    expect(res.status).toBe(404);
    expect(res.headers.get("Content-Type")).toBe("text/markdown; charset=utf-8");
    expect(res.headers.get("Vary")).toBe("Accept");
    expect(res.headers.get("Link")).toBe(
      '<https://suniye.app/about>; rel="alternate"; type="text/html", <https://suniye.app/llms.txt>; rel="describedby"; type="text/plain"',
    );
    expect(await res.text()).toBe("# Hi\n");
  });

  test("alternateLinkHeader advertises the markdown variant for HTML pages", () => {
    expect(alternateLinkHeader("https://suniye.app/", "text/markdown")).toStartWith(
      '<https://suniye.app/>; rel="alternate"; type="text/markdown"',
    );
  });

  test("notAcceptableResponse is a 406 that still varies on Accept", () => {
    const res = notAcceptableResponse();
    expect(res.status).toBe(406);
    expect(res.headers.get("Vary")).toBe("Accept");
  });
});
