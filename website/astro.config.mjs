import { defineConfig, memoryCache } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import tailwindcss from "@tailwindcss/vite";

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
    plugins: [tailwindcss()]
  },
  server: {
    host: true
  }
});
