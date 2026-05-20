import { h, type Component } from "vue"
import { createLiveVue, findComponent, type LiveHook, type ComponentMap } from "live_vue"

// needed to make $live available in the Vue component
declare module "vue" {
  interface ComponentCustomProperties {
    $live: LiveHook
  }
}

export default createLiveVue({
  // name will be passed as-is in v-component of the .vue HEEX component
  resolve: (name) => {
    // Lazy globs — each .vue file becomes its own dynamic-import chunk.
    // `ComponentMap` allows `Promise<Component>` values (see live_vue
    // types.ts), so the resolver hands the promise straight through;
    // Vue resolves it on mount. The big win: Tone.js + audio.ts +
    // tonejs-instruments only ship to the browser when the user
    // actually opens a chamber, not on every page hit.
    //
    // The LiveView-collocated tree (../../lib) stays in the same
    // pattern for consistency.
    // https://vite.dev/guide/features.html#glob-import
    const components = {
      ...import.meta.glob("./**/*.vue"),
      ...import.meta.glob("../../lib/**/*.vue"),
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
