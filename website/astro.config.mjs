import { fileURLToPath } from "node:url";
import { defineConfig, memoryCache } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import tailwindcss from "@tailwindcss/vite";
import sharp from "sharp";

// The colour of the sky along the top-centre of the hero painting — the strip a
// portrait viewport shows under the status bar. The homepage hands it to iOS
// Safari as the document background so the status-bar band matches the
// painting. Sampled here, in Node, because the Cloudflare adapter prerenders
// pages inside workerd, where sharp cannot load (importing it from page
// frontmatter leaves an empty index.html behind while the build still reports
// success).
async function heroSkyColor() {
  const art = sharp(fileURLToPath(new URL("./public/hero-1672.webp", import.meta.url)));
  const { width, height } = await art.metadata();
  if (!width || !height) throw new Error("hero-1672.webp: could not read dimensions");
  const { data } = await art
    .extract({
      left: Math.round(width * 0.3),
      top: 0,
      width: Math.round(width * 0.4),
      height: Math.max(1, Math.round(height * 0.01)),
    })
    .resize(1, 1, { fit: "fill" })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return `#${Array.from(data.subarray(0, 3), (c) => c.toString(16).padStart(2, "0")).join("")}`;
}

export default defineConfig({
  site: "https://suniye.app",
  adapter: cloudflare({
    imageService: "compile"
  }),
  experimental: {
    cache: {
      provider: memoryCache()
    }
  },
  vite: {
    plugins: [tailwindcss()],
    define: {
      __HERO_SKY__: JSON.stringify(await heroSkyColor())
    }
  },
  server: {
    host: true
  }
});
