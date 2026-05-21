import { h, defineAsyncComponent, type AsyncComponentLoader, type Component } from "vue"
import { createLiveVue, findComponent, type LiveHook, type ComponentMap } from "live_vue"

// needed to make $live available in the Vue component
declare module "vue" {
  interface ComponentCustomProperties {
    $live: LiveHook
  }
}

// Wrap each lazy `() => import(...)` glob entry in defineAsyncComponent
// so the resolver returns a *synchronous* Vue component handle that
// Vue internally hydrates from the dynamic import. Returning the raw
// Promise here races live_vue's `mounted()` against its own `updated()`:
// mounted awaits the import before setting `this.vue`, but a LiveView
// patch arriving during that window calls `updated()` against an
// undefined `this.vue` and throws (hooks.ts:55-57). defineAsyncComponent
// gives the hook a real component immediately while keeping the bundle
// split — Vite still sees the `() => import(...)` factory and emits a
// per-component chunk.
function lazy(glob: Record<string, () => Promise<unknown>>): Record<string, Component> {
  return Object.fromEntries(
    Object.entries(glob).map(([path, factory]) => [
      path,
      defineAsyncComponent(factory as AsyncComponentLoader),
    ]),
  )
}

export default createLiveVue({
  // name will be passed as-is in v-component of the .vue HEEX component
  resolve: (name) => {
    // Lazy globs — each .vue file becomes its own dynamic-import chunk.
    // Tone.js + audio.ts + tonejs-instruments only ship to the browser
    // when the user actually opens a chamber, not on every page hit.
    //
    // The LiveView-collocated tree (../../lib) stays in the same
    // pattern for consistency.
    // https://vite.dev/guide/features.html#glob-import
    const components = {
      ...lazy(import.meta.glob("./**/*.vue")),
      ...lazy(import.meta.glob("../../lib/**/*.vue")),
    } as ComponentMap

    // finds component by name or path suffix and gives a nice error message.
    // `path/to/component/index.vue` can be found as `path/to/component` or simply `component`
    // `path/to/Component.vue` can be found as `path/to/Component` or simply `Component`
    return findComponent(components as ComponentMap, name)
  },
  // it's a default implementation of creating and mounting vue app, you can easily extend it to add your own plugins, directives etc.
  setup: ({ createApp, component, props, slots, plugin, el }) => {
    const app = createApp({ render: () => h(component as Component, props, slots) })
    app.use(plugin)
    // add your own plugins here
    // app.use(pinia)
    app.mount(el)
    return app
  },
})
