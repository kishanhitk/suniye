/**
 * Generates a 1200x630 OG image for social sharing.
 * Run: bun scripts/generate-og.mjs
 */
import satori from "satori";
import { Resvg } from "@resvg/resvg-js";
import { readFileSync, writeFileSync } from "fs";

const fragmentMono = readFileSync("public/fonts/FragmentMono-Regular.ttf");

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
        padding: "72px 80px",
        backgroundColor: "#faf8f5",
        fontFamily: "Fragment Mono",
        position: "relative",
      },
      children: [
        // Accent bar top
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: 0,
              left: 0,
              right: 0,
              height: "6px",
              backgroundColor: "#c4441a",
            },
          },
        },
        // Waveform SVG
        {
          type: "svg",
          props: {
            viewBox: "0 0 160 80",
            width: 100,
            height: 50,
            style: { marginBottom: "24px" },
            children: [
              {
                type: "path",
                props: {
                  d: "M 8 50 Q 14 50 20 42 L 40 10 L 62 70 L 84 10 L 106 70 L 124 36 Q 130 26 140 26",
                  stroke: "#c4441a",
                  strokeWidth: "7",
                  strokeLinecap: "round",
                  strokeLinejoin: "round",
                  fill: "none",
                },
              },
            ],
          },
        },
        // Title
        {
          type: "div",
          props: {
            style: {
              fontSize: "64px",
              fontFamily: "Fragment Mono",
              color: "#1a1a1a",
              lineHeight: 1.15,
              letterSpacing: "-0.02em",
            },
            children: "Your voice. Your machine. Your text.",
          },
        },
        // Subtitle
        {
          type: "div",
          props: {
            style: {
              fontSize: "24px",
              color: "#6b635a",
              marginTop: "20px",
              lineHeight: 1.5,
            },
            children:
              "Open-source, local-first dictation for macOS. No audio leaves your machine.",
          },
        },
        // Footer
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              bottom: "40px",
              left: "80px",
              display: "flex",
              alignItems: "center",
              gap: "12px",
              fontSize: "20px",
              fontFamily: "Fragment Mono",
              color: "#6b635a",
            },
            children: "suniye.kishans.in",
          },
        },
      ],
    },
  },
  {
    width: 1200,
    height: 630,
    fonts: [
      { name: "Fragment Mono", data: fragmentMono, weight: 400 },
    ],
  }
);

const resvg = new Resvg(svg, {
  fitTo: { mode: "width", value: 1200 },
});
const png = resvg.render().asPng();

writeFileSync("public/og-image.png", png);
console.log(`Generated public/og-image.png (${(png.length / 1024).toFixed(0)} KB)`);
