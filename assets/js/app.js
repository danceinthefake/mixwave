import "vite/modulepreload-polyfill";
// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/mixchamb"
import topbar from "topbar"
import {getHooks} from "live_vue"
import liveVueApp from "../vue"

// Copies the value of `data-copy-url` to the clipboard and briefly
// swaps the button label to "Copied!". Lives in a Phoenix Hook
// instead of an inline `onclick=` so the strict prod CSP can drop
// `'unsafe-inline'` from `script-src`.
//
// `navigator.clipboard` only resolves in secure contexts (HTTPS,
// localhost, 127.0.0.1). When mixchamb is opened over plain HTTP
// on a LAN IP — the common dev/cross-device-test scenario — that
// API silently rejects, so the fallback uses a hidden textarea +
// `document.execCommand("copy")`, which still works there.
const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", async () => {
      const url = this.el.dataset.copyUrl
      if (!url) return

      const ok = await copyText(url)
      const original = this.el.textContent
      this.el.textContent = ok ? "Copied!" : "Copy failed"
      setTimeout(() => {
        this.el.textContent = original
      }, 1500)
    })
  },
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (err) {
      console.warn("clipboard.writeText failed, falling back:", err)
    }
  }

  // Legacy path. execCommand is deprecated but is the only thing
  // that copies from non-secure contexts, and every current browser
  // still implements it.
  const ta = document.createElement("textarea")
  ta.value = text
  ta.setAttribute("readonly", "")
  ta.style.position = "fixed"
  ta.style.top = "-1000px"
  ta.style.opacity = "0"
  document.body.appendChild(ta)
  ta.select()
  ta.setSelectionRange(0, text.length)
  let ok = false
  try {
    ok = document.execCommand("copy")
  } catch (err) {
    console.warn("execCommand('copy') threw:", err)
  }
  document.body.removeChild(ta)
  return ok
}

// Drag handle for floating panels. Listens for pointerdown on a
// child `[data-drag-handle]` element, then translates the panel via
// inline `left` / `top` so the position survives LV diffs (which
// only touch the children, not the root element's style attribute).
// Position is persisted in localStorage per `data-storage-key` so
// the user's choice survives reloads.
//
// Clamps the panel to the viewport on every move + on window
// resize, so a saved position can't strand the panel off-screen
// after a smaller monitor swap.
//
// Pointer events cover mouse + touch with one code path; the
// hook does nothing if there's no `[data-drag-handle]` (panel
// stays at its CSS-defined position).
const DraggablePanel = {
  mounted() {
    const el = this.el
    const handle = el.querySelector("[data-drag-handle]")
    if (!handle) return

    const storageKey = el.dataset.storageKey || `mixchamb:panel:${el.id}`

    const clamp = (left, top) => ({
      left: Math.max(8, Math.min(window.innerWidth - el.offsetWidth - 8, left)),
      top: Math.max(8, Math.min(window.innerHeight - el.offsetHeight - 8, top)),
    })

    const setPosition = (left, top) => {
      const c = clamp(left, top)
      el.style.left = `${c.left}px`
      el.style.top = `${c.top}px`
      el.style.right = "auto"
      el.style.bottom = "auto"
    }

    // Restore the saved position if it parses.
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) || "null")
      if (saved && Number.isFinite(saved.left) && Number.isFinite(saved.top)) {
        setPosition(saved.left, saved.top)
      }
    } catch {
      /* corrupt JSON / disabled storage — let CSS default win */
    }

    let drag = null

    const onPointerDown = (e) => {
      // Don't initiate drag from a button / input / form field —
      // the handle is the bar around them, not them.
      if (e.target.closest("button, input, textarea, select, a, [contenteditable]")) {
        return
      }
      const rect = el.getBoundingClientRect()
      drag = {
        startX: e.clientX,
        startY: e.clientY,
        startLeft: rect.left,
        startTop: rect.top,
      }
      handle.setPointerCapture(e.pointerId)
      handle.classList.add("is-dragging")
      e.preventDefault()
    }

    const onPointerMove = (e) => {
      if (!drag) return
      setPosition(drag.startLeft + (e.clientX - drag.startX), drag.startTop + (e.clientY - drag.startY))
    }

    const onPointerUp = () => {
      if (!drag) return
      drag = null
      handle.classList.remove("is-dragging")
      try {
        localStorage.setItem(storageKey, JSON.stringify({
          left: parseFloat(el.style.left),
          top: parseFloat(el.style.top),
        }))
      } catch {
        /* localStorage quota / private mode — drag still worked
           for the session, just won't persist */
      }
    }

    const onResize = () => {
      // Only re-clamp if the user has positioned the panel.
      // Otherwise leave CSS defaults alone.
      if (!el.style.left) return
      setPosition(parseFloat(el.style.left), parseFloat(el.style.top))
    }

    handle.addEventListener("pointerdown", onPointerDown)
    handle.addEventListener("pointermove", onPointerMove)
    handle.addEventListener("pointerup", onPointerUp)
    handle.addEventListener("pointercancel", onPointerUp)
    window.addEventListener("resize", onResize)

    this.cleanup = () => {
      handle.removeEventListener("pointerdown", onPointerDown)
      handle.removeEventListener("pointermove", onPointerMove)
      handle.removeEventListener("pointerup", onPointerUp)
      handle.removeEventListener("pointercancel", onPointerUp)
      window.removeEventListener("resize", onResize)
    }
  },
  destroyed() {
    this.cleanup?.()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...getHooks(liveVueApp), CopyToClipboard, DraggablePanel},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
