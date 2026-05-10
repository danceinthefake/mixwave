import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath, URL } from "node:url";

// Vitest config — separate from assets/vite.config.mjs so the
// build pipeline isn't entangled with the test runner. Tests
// live under assets/vue/__tests__/ and use the same `@/...`
// alias the production code imports through.
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./assets/vue", import.meta.url)),
    },
  },
  test: {
    environment: "happy-dom",
    include: ["assets/vue/**/*.{test,spec}.{ts,js}"],
    globals: true,
    css: false,
  },
});
