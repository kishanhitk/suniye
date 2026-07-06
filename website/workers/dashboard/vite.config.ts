import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

// Builds the React dashboard to ./dist, which the Worker serves via the ASSETS
// binding. The Worker (src/worker/) is bundled separately by wrangler.
export default defineConfig({
  root: "src/app",
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "../../dist",
    emptyOutDir: true,
  },
});
