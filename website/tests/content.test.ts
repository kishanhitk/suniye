import { describe, expect, test } from "bun:test";
import { authoredMarkdown } from "../src/lib/content/authored";
import { FAQS, MODELS, homeMarkdown } from "../src/lib/content/home";
import { COLLECTED, NEVER_COLLECTED, emphasisToHtml, privacyMarkdown } from "../src/lib/content/privacy";
import { changelogMarkdown, parseFullChangelogUrl, parseReleaseItems } from "../src/lib/releases";
import { organizationSchema, webSiteSchema } from "../src/lib/seo";
import { SITE_URL } from "../src/lib/site";

describe("homeMarkdown", () => {
  const md = homeMarkdown();

  test("opens with a single H1 and carries every section the HTML page has", () => {
    expect(md.startsWith("# Suniye — Private Dictation for macOS\n")).toBe(true);
    expect(md.match(/^# /gm)?.length).toBe(1);
    for (const heading of [
      "## Every other dictation app sends your voice away.",
      "## Hold a key. Talk. Let go.",
      "## Speak like a person. Paste like an editor.",
      "## One key, every text field.",
      "## Twelve ways to listen.",
      "## Two ways in.",
      "## FAQ",
    ]) {
      expect(md).toContain(heading);
    }
  });

  test("lists every speech model and every FAQ", () => {
    for (const m of MODELS) expect(md).toContain(`| ${m.name} |`);
    for (const f of FAQS) {
      expect(md).toContain(`### ${f.q}`);
      expect(md).toContain(f.a);
    }
  });

  test("contains no HTML entities or tags", () => {
    expect(md).not.toMatch(/&[a-z]+;|<[a-z]+[ >]/i);
  });
});

describe("privacy content", () => {
  test("privacyMarkdown lists what is and is not collected", () => {
    const md = privacyMarkdown();
    for (const [term, detail] of COLLECTED) expect(md).toContain(`- **${term}** — ${detail}`);
    for (const item of NEVER_COLLECTED) expect(md).toContain(`- ${item}`);
    expect(md).toContain("## How it stays private");
    expect(md).toContain("## Website analytics");
  });

  test("emphasisToHtml renders bold spans and escapes everything else", () => {
    expect(emphasisToHtml("a **b** c")).toBe('a <strong class="text-ink">b</strong> c');
    expect(emphasisToHtml("<img> & **x**", "hi")).toBe('&lt;img&gt; &amp; <strong class="hi">x</strong>');
    expect(emphasisToHtml("no emphasis")).toBe("no emphasis");
  });
});

describe("releases", () => {
  const body = [
    "## What's Changed",
    "* [codex] Add thing by @kishanhitk in https://github.com/kishanhitk/suniye/pull/1",
    "* Fix other thing",
    "* Fix other thing",
    "",
    "**Full Changelog**: https://github.com/kishanhitk/suniye/compare/v1...v2",
  ].join("\n");

  test("parseReleaseItems keeps unique bullet titles without the PR suffix or [codex] prefix", () => {
    expect(parseReleaseItems(body)).toEqual([{ title: "Add thing" }, { title: "Fix other thing" }]);
    expect(parseReleaseItems(null)).toEqual([]);
  });

  test("parseFullChangelogUrl extracts the compare link", () => {
    expect(parseFullChangelogUrl(body)).toBe("https://github.com/kishanhitk/suniye/compare/v1...v2");
    expect(parseFullChangelogUrl("nothing")).toBeUndefined();
  });

  test("changelogMarkdown renders releases, and a fallback when none loaded", () => {
    const md = changelogMarkdown([
      {
        version: "v0.0.68",
        date: "Aug 22, 2026",
        status: "Latest",
        href: "https://github.com/kishanhitk/suniye/releases/tag/v0.0.68",
        items: [{ title: "Warm up the ORT sessions" }],
        fullChangelogUrl: "https://github.com/kishanhitk/suniye/compare/v0.0.67...v0.0.68",
      },
      { version: "v0.0.67", date: "Aug 21, 2026", href: "https://example.com/r", items: [] },
    ]);
    expect(md).toContain("## v0.0.68 — Aug 22, 2026 (Latest)");
    expect(md).toContain("- Warm up the ORT sessions");
    expect(md).toContain("Full changelog: https://github.com/kishanhitk/suniye/compare/v0.0.67...v0.0.68");
    expect(md).toContain("## v0.0.67 — Aug 21, 2026\n\nNo release notes published for this release.");
    expect(changelogMarkdown([])).toContain("Release notes could not be loaded right now.");
  });
});

describe("organization JSON-LD", () => {
  test("points contact at GitHub and claims only a country, never a person", () => {
    const org = organizationSchema();
    expect(org["@type"]).toBe("Organization");
    expect(org.url).toBe(SITE_URL);
    expect(org.contactPoint[0]).toEqual({
      "@type": "ContactPoint",
      contactType: "customer support",
      url: "https://github.com/kishanhitk/suniye/issues",
      availableLanguage: "English",
    });
    expect(org.address).toEqual({ "@type": "PostalAddress", addressCountry: "IN" });
    expect(org.sameAs).toEqual(["https://github.com/kishanhitk/suniye"]);
    expect(JSON.stringify(org)).not.toMatch(/[\w.]+@[\w.]+|founder|Person|email|telephone/);
  });

  test("the WebSite node points at the Organization by @id", () => {
    expect(webSiteSchema().publisher).toEqual({ "@id": `${SITE_URL}/#organization` });
    expect(organizationSchema()["@id"]).toBe(`${SITE_URL}/#organization`);
  });
});

describe("authoredMarkdown", () => {
  test("turns the posts' inline HTML into Markdown links and absolutizes site paths", () => {
    const body = [
      "Intro with a [relative link](/privacy) and an [external](https://example.com/).",
      "",
      '<a href="/" class="btn-press not-prose">',
      '  <svg viewBox="0 0 24 24"><path d="M1 1" /></svg>',
      "  Download Suniye for macOS",
      "</a>",
      "",
      '*Sources: <a href="https://superwhisper.com/" rel="nofollow noopener" target="_blank">Superwhisper pricing</a>.*',
    ].join("\n");
    expect(authoredMarkdown(body)).toBe(
      [
        "Intro with a [relative link](https://suniye.app/privacy) and an [external](https://example.com/).",
        "",
        "[Download Suniye for macOS](https://suniye.app/)",
        "",
        "*Sources: [Superwhisper pricing](https://superwhisper.com/).*",
      ].join("\n"),
    );
  });

  test("leaves plain Markdown alone apart from trimming", () => {
    expect(authoredMarkdown("\n## Heading\n\nText with `code` and **bold**.\n")).toBe(
      "## Heading\n\nText with `code` and **bold**.",
    );
  });
});
