defmodule MixwaveWeb.AdminSessionHTML do
  use MixwaveWeb, :html

  @doc """
  Login form for `/admin/login`. Inlined here rather than embedded
  templates because the form is one short page and embedding
  would make iteration on the styling more annoying.
  """
  attr :error, :string, default: nil
  attr :username, :string, default: ""

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-sm mx-auto mt-12 space-y-6">
        <div class="text-center space-y-1">
          <h1 class="text-2xl font-bold tracking-tight font-display">
            Admin login
          </h1>
          <p class="text-sm text-muted-foreground">
            Credentials live in the
            <code class="text-xs px-1 py-0.5 rounded bg-muted">ADMIN_USER</code>
            / <code class="text-xs px-1 py-0.5 rounded bg-muted">ADMIN_PASSWORD</code>
            env vars.
          </p>
        </div>

        <div
          :if={@error}
          class="rounded-md border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive"
        >
          {@error}
        </div>

        <form
          action={~p"/admin/login"}
          method="post"
          class="rounded-xl border bg-card p-6 space-y-4"
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

          <div class="space-y-1.5">
            <label
              for="session_username"
              class="text-xs uppercase tracking-wider text-muted-foreground"
            >
              Username
            </label>
            <input
              id="session_username"
              type="text"
              name="session[username]"
              value={@username}
              autocomplete="username"
              autofocus
              required
              class="w-full rounded-md border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          <div class="space-y-1.5">
            <label
              for="session_password"
              class="text-xs uppercase tracking-wider text-muted-foreground"
            >
              Password
            </label>
            <input
              id="session_password"
              type="password"
              name="session[password]"
              autocomplete="current-password"
              required
              class="w-full rounded-md border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          <button
            type="submit"
            class="w-full rounded-md bg-primary text-primary-foreground px-4 py-2 text-sm font-medium hover:opacity-90 transition"
          >
            Sign in
          </button>
        </form>

        <p class="text-center text-xs text-muted-foreground">
          <.link navigate={~p"/"} class="underline">Back to mixwave</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end
end
