defmodule MixwaveWeb.Plugs.EnsureAnonUser do
  @moduledoc """
  Attaches an anonymous user to every request.

  - First visit: creates a new `Mixwave.Accounts.AnonymousUser` and
    stores its id in the session. The user gets a funny Javanese-
    style display name from `Mixwave.Accounts.NameGenerator` —
    something like `tempe-gendheng-42` or `bakso-mendhem-17`.
  - Subsequent visits: loads the user from the session id. If the
    sweeper has reaped that user (24h idle), starts fresh.
  - Bumps `last_active_at` only when more than 60 seconds have passed
    since the last bump, to avoid a write per request.

  The current user is assigned to `conn.assigns.current_user` and
  stays in the session under `:user_id`.
  """
  @behaviour Plug

  import Plug.Conn

  alias Mixwave.Accounts

  # Don't write last_active_at more than once per minute. Anything finer
  # turns every page view into a write; anything coarser delays the
  # sweep window meaningfully.
  @bump_interval_seconds 60

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        create_and_assign(conn)

      user_id ->
        case Accounts.get_anonymous_user(user_id) do
          nil ->
            # Session points at a user the sweeper deleted. Issue a fresh one.
            conn
            |> delete_session(:user_id)
            |> create_and_assign()

          user ->
            user = maybe_bump(user)
            assign(conn, :current_user, user)
        end
    end
  end

  defp create_and_assign(conn) do
    {:ok, user} = Accounts.create_anonymous_user()

    conn
    |> put_session(:user_id, user.id)
    |> assign(:current_user, user)
  end

  defp maybe_bump(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    age = DateTime.diff(now, user.last_active_at)

    if age >= @bump_interval_seconds do
      case Accounts.touch_anonymous_user(user, now) do
        {:ok, updated} -> updated
        {:error, _} -> user
      end
    else
      user
    end
  end
end
