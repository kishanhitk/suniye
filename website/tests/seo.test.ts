import { describe, expect, test } from "bun:test";
import {
  SITE_URL,
  SITE_PAGES,
  buildSitemapXml,
  softwareApplicationSchema,
  faqPageSchema,
  jsonLdString,
} from "../src/lib/seo";

describe("sitemap", () => {
  test("lists every public page as an absolute URL", () => {
    const xml = buildSitemapXml();
    expect(xml).toStartWith('<?xml version="1.0" encoding="UTF-8"?>');
    expect(xml).toContain('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
    for (const path of SITE_PAGES) {
      expect(xml).toContain(`<loc>${new URL(path, SITE_URL).toString()}</loc>`);
    }
  });

  test("covers the home, changelog, and privacy pages", () => {
    expect(SITE_PAGES).toEqual(["/", "/changelog", "/privacy"]);
  });

  test("emits one <url> entry per page", () => {
    const xml = buildSitemapXml();
    expect(xml.match(/<url>/g)?.length).toBe(SITE_PAGES.length);
  });
});

describe("softwareApplicationSchema", () => {
  test("describes Suniye as a free macOS app", () => {
    const schema = softwareApplicationSchema();
    expect(schema["@context"]).toBe("https://schema.org");
    expect(schema["@type"]).toBe("SoftwareApplication");
    expect(schema.name).toBe("Suniye");
    expect(schema.operatingSystem).toBe("macOS");
    expect(schema.offers).toEqual({ "@type": "Offer", price: "0", priceCurrency: "USD" });
    expect(schema.url).toBe(SITE_URL);
    expect(schema.downloadUrl).toContain("Suniye.dmg");
  });
});

describe("jsonLdString", () => {
  test("escapes < so answers cannot close the script tag", () => {
    const out = jsonLdString({ a: "</script><img src=x>" });
    expect(out).not.toContain("</script>");
    expect(out).toContain("\\u003c/script>");
    expect(JSON.parse(out)).toEqual({ a: "</script><img src=x>" });
  });
});

describe("faqPageSchema", () => {
  test("maps question/answer pairs into FAQPage entities", () => {
    const schema = faqPageSchema([
      { q: "Is it free?", a: "Yes." },
      { q: "Does it work offline?", a: "Yes, after model download." },
    ]);
    expect(schema["@type"]).toBe("FAQPage");
    expect(schema.mainEntity).toHaveLength(2);
    expect(schema.mainEntity[0]).toEqual({
      "@type": "Question",
      name: "Is it free?",
      acceptedAnswer: { "@type": "Answer", text: "Yes." },
    });
  });
});
