import { defineConfig } from 'vite'
import vue from "@vitejs/plugin-vue";
import liveVuePlugin from "live_vue/vitePlugin";
import tailwindcss from "@tailwindcss/vite";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  server: {
    // 0.0.0.0 so other machines on the LAN can fetch dev assets
    // when running with DEV_LAN_HOST set (see config/dev.exs).
    host: "0.0.0.0",
    port: 5173,
    strictPort: true,
    // Permissive CORS in dev — the requesting origin will be the
    // browser's window, which depends on which machine is connecting.
    cors: true,
  },
  optimizeDeps: {
    // https://vitejs.dev/guide/dep-pre-bundling#monorepos-and-linked-dependencies
    include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"],
  },
  ssr: {
      noExternal: process.env.NODE_ENV === "production" ? true : undefined,
      resolve: { conditions: ["import", "module", "browser", "default"] },
    },
    build: {
    manifest: false,
    ssrManifest: false,
    rollupOptions: {
      input: ["js/app.js", "css/app.css"],
    },
    outDir: "../priv/static",
    emptyOutDir: true,
  },
  // LV Colocated JS and Hooks
  // https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.ColocatedJS.html#module-internals
  resolve: {
    alias: {
      // shadcn-vue convention: @/components/ui/button → assets/vue/components/ui/button
      "@": fileURLToPath(new URL("./vue", import.meta.url)),
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
  },
  plugins: [
    tailwindcss(),
    vue(),
    liveVuePlugin()
  ],
  // Vitest config. happy-dom is the lighter DOM stub (preferred
  // over jsdom for component mounts that don't lean on quirky
  // browser APIs). Coverage is v8-backed and only counts the
  // Vue island sources — node_modules + tests are excluded so
  // the report reflects our actual code, not dependency churn.
  test: {
    environment: "happy-dom",
    include: ["vue/__tests__/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["vue/**/*.{ts,vue}"],
      exclude: [
        "vue/__tests__/**",
        "vue/components/ui/**"
      ],
      reporter: ["text", "html"]
    }
  }
});
