defmodule MixchambWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Emits a Content-Security-Policy header for every browser response
  and stamps a per-request nonce so inline `<script>` tags rendered
  by the root layout can opt-in.

  Two policies are emitted depending on environment:

    * **prod** (no `:live_vue, :vite_host` set) — nonce-based,
      strict. Only same-origin scripts and inline scripts with the
      matching nonce execute; no `'unsafe-inline'`, no
      `'unsafe-eval'`. Inline styles are allowed (Tailwind emits
      runtime CSS and templates use the `style=` attribute).
    * **dev** — permissive (`'unsafe-inline'` + `'unsafe-eval'`,
      and the Vite dev server's HMR origin allow-listed) so Vite,
      Phoenix's LiveReloader, and live-reloader debug overlays all
      keep working.

  External hosts allowed in `connect-src` cover the Tone.js sample
  CDNs the chamber pads fetch from (Salamander Grand Piano on
  tonejs.github.io and Nick Brosowsky's instrument samples on
  nbrosowsky.github.io). Update both if a pad starts pulling
  from a new origin.

  Read the nonce in templates via `@csp_nonce` (assigned on
  `conn.assigns`). HEEx emits no attribute when the value is `nil`,
  so dev (which uses `'unsafe-inline'` instead) just renders
  plain `<script>`.
  """
  @behaviour Plug

  @sample_cdns "https://tonejs.github.io https://nbrosowsky.github.io"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = generate_nonce()
    policy = policy(dev?(), nonce)

    conn
    |> Plug.Conn.assign(:csp_nonce, if(dev?(), do: nil, else: nonce))
    |> Plug.Conn.put_resp_header("content-security-policy", policy)
  end

  ## Nonce

  defp generate_nonce do
    16 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
  end

  ## Policy

  # Dev: lax enough that Vite HMR + LiveReloader + LiveDashboard +
  # live_debugger can all run. The Vite host is read from the
  # runtime config — so `DEV_LAN_HOST=192.168.x.y` for cross-machine
  # testing flows through automatically. live_debugger lives on its
  # own loopback port (default 4007) and injects its client script
  # into every dev HTML response; without an explicit allow-list its
  # script + WS get blocked and clutter the console.
  defp policy(true = _dev?, _nonce) do
    vite = vite_origin()
    live_debugger = "http://localhost:4007 http://127.0.0.1:4007"

    # The Vite dev server is cross-origin from Phoenix
    # (`localhost:4000` ↔ `localhost:5173`), so every directive
    # that can load a sub-resource needs the Vite host on its
    # allow-list — otherwise Vite's HMR client hammers retries
    # against the wall while styles vanish.
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval' #{vite} #{live_debugger} blob:",
      "style-src 'self' 'unsafe-inline' #{vite} #{live_debugger} https://fonts.googleapis.com",
      "font-src 'self' #{vite} #{live_debugger} https://fonts.gstatic.com data:",
      "img-src 'self' #{vite} #{live_debugger} data: blob:",
      # Loose connect-src in dev to cover Vite WS HMR + live_reload
      # WS + live_debugger WS + any future devtool. Tightened in
      # prod below. `blob:` is required because Tone.js wraps sample
      # buffers as object URLs and fetches them via fetch().
      "connect-src 'self' #{vite} #{live_debugger} ws: wss: blob: #{@sample_cdns}",
      "worker-src 'self' #{vite} blob:",
      "frame-ancestors 'none'",
      "form-action 'self'",
      "base-uri 'self'",
      "object-src 'none'"
    ]
    |> Enum.join("; ")
  end

  defp policy(false = _dev?, nonce) do
    [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}'",
      # Inline styles stay — Tailwind v4 emits a runtime stylesheet
      # without a nonce, and our HEEx templates use `style=`
      # attributes for instrument accent colours. The mitigation
      # we're getting from CSP here is in `script-src`; locking
      # styles down would force a much bigger refactor for a
      # marginal payoff.
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      "font-src 'self' https://fonts.gstatic.com data:",
      "img-src 'self' data:",
      "connect-src 'self' blob: #{@sample_cdns}",
      "worker-src 'self' blob:",
      "frame-ancestors 'none'",
      "form-action 'self'",
      "base-uri 'self'",
      "object-src 'none'"
    ]
    |> Enum.join("; ")
  end

  defp dev? do
    Application.get_env(:live_vue, :vite_host) != nil
  end

  # Strip the `http://` from the configured vite_host because CSP
  # source expressions can be a full URL ("http://localhost:5173")
  # — keep it as-is but defend against a nil value at compile time
  # of the dev policy.
  defp vite_origin do
    Application.get_env(:live_vue, :vite_host) || ""
  end
end
