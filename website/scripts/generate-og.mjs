/**
 * Generates a 1200x630 OG image for social sharing.
 * Run: bun scripts/generate-og.mjs
 *
 * The card is the hero, cropped: same painting, same serif headline, same
 * promise. The subtitle is serif here where the page sets it in Google Sans:
 * that face ships only as a variable font, and satori's parser cannot read
 * an fvar table. Instancing it to a static weight (fonttools) is the fix.
 *
 * A share preview that matches the page it links to is the whole point
 * — a separate "designed" card just means the visitor arrives somewhere they
 * have not seen before.
 */
import satori from "satori";
import { Resvg } from "@resvg/resvg-js";
import { readFileSync, writeFileSync, statSync } from "fs";
import { execFileSync } from "child_process";

// Satori can't parse woff2, so TTF copies live here as build-time assets.
// Georgia stands in for the site's Iowan Old Style, which ships only as a .ttc.
const georgia = readFileSync("scripts/fonts/Georgia.ttf");
const fragmentMono = readFileSync("scripts/fonts/FragmentMono-Regular.ttf");

// The painting, pre-cropped to the card's aspect. Inlined because resvg
// resolves no network requests.
const background = `data:image/jpeg;base64,${readFileSync("scripts/og-bg.jpg").toString("base64")}`;

const svg = await satori(
  {
    type: "div",
    props: {
      style: {
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        alignItems: "center",
        padding: "0 100px",
        backgroundColor: "#2b6cc4",
        position: "relative",
      },
      children: [
        {
          type: "img",
          props: {
            src: background,
            width: 1200,
            height: 630,
            style: { position: "absolute", top: 0, left: 0 },
          },
        },
        // The sky is bright enough that white type needs its own ground. A soft
        // dark wash across the upper half keeps the headline legible without
        // dimming the painting into mud.
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: 0,
              left: 0,
              width: "1200px",
              height: "560px",
              backgroundImage:
                "linear-gradient(180deg, rgba(10,28,50,0.72) 0%, rgba(10,28,50,0.52) 45%, rgba(10,28,50,0.20) 78%, rgba(10,28,50,0) 100%)",
            },
          },
        },
        {
          type: "div",
          props: {
            style: {
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              marginTop: "-150px",
            },
            children: [
              {
                type: "div",
                props: {
                  style: {
                    fontSize: "122px",
                    fontFamily: "Georgia",
                    color: "#ffffff",
                    lineHeight: 1.02,
                    letterSpacing: "-0.02em",
                    textShadow: "0 2px 18px rgba(8,24,44,0.55)",
                  },
                  children: "Speak freely.",
                },
              },
              {
                type: "div",
                props: {
                  style: {
                    fontSize: "32px",
                    color: "#ffffff",
                    marginTop: "22px",
                    textShadow: "0 1px 12px rgba(8,24,44,0.6)",
                    lineHeight: 1.45,
                    textAlign: "center",
                    maxWidth: "830px",
                  },
                  children:
                    "Dictation for macOS, built for privacy and speed. The models run on your Mac.",
                },
              },
            ],
          },
        },
        // The wordmark sits on lit meadow, the brightest part of the frame, so it
        // gets a short wash of its own rather than relying on a text shadow.
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              bottom: "0px",
              left: "0px",
              width: "1200px",
              height: "170px",
              backgroundImage:
                "linear-gradient(180deg, rgba(10,28,50,0) 0%, rgba(10,28,50,0.30) 60%, rgba(10,28,50,0.48) 100%)",
            },
          },
        },
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              bottom: "44px",
              left: "0px",
              width: "1200px",
              display: "flex",
              justifyContent: "center",
              fontSize: "23px",
              fontFamily: "Fragment Mono",
              letterSpacing: "0.14em",
              color: "rgba(255,255,255,0.95)",
              textShadow: "0 1px 10px rgba(8,24,44,0.6)",
            },
            children: "SUNIYE.APP",
          },
        },
      ],
    },
  },
  {
    width: 1200,
    height: 630,
    fonts: [
      { name: "Georgia", data: georgia, weight: 400 },
      { name: "Fragment Mono", data: fragmentMono, weight: 400 },
    ],
  }
);

const resvg = new Resvg(svg, {
  fitTo: { mode: "width", value: 1200 },
});
const png = resvg.render().asPng();

// Shipped as JPEG: this card is a photograph, and the PNG of it is ~1 MB for
// no visible gain. resvg only emits PNG, so hand off to sips for the encode.
writeFileSync("/tmp/og-image.png", png);
execFileSync("sips", [
  "-s", "format", "jpeg",
  "-s", "formatOptions", "86",
  "/tmp/og-image.png",
  "--out", "public/og-image.jpg",
]);
const bytes = statSync("public/og-image.jpg").size;
console.log(`Generated public/og-image.jpg (${(bytes / 1024).toFixed(0)} KB)`);
