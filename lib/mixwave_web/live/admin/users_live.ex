defmodule MixwaveWeb.Admin.UsersLive do
  @moduledoc """
  Admin → Users tab. Lists anonymous users newest-active first,
  with force-expire to clear a misbehaving session immediately
  rather than waiting for the 24 h idle sweep.
  """
  use MixwaveWeb, :live_view
  require Logger

  alias Mixwave.Accounts
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(5_000, :tick)
    {:ok, assign(socket, :users, Accounts.list_users())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :users, Accounts.list_users())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Accounts.delete_anonymous_user(id) do
      {:ok, user} ->
        Logger.warning("[admin/users] force-expire: id=#{id} name=#{user.display_name}")

        {:noreply,
         socket
         |> put_flash(:info, "Expired #{user.display_name}.")
         |> assign(:users, Accounts.list_users())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "User not found or could not be deleted.")}
    end
  end

  defp time_ago(nil), do: "—"

  defp time_ago(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp time_ago(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> time_ago()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell current_view={__MODULE__} flash={@flash}>
      <.header>
        Users
        <:subtitle>
          Anonymous users in the DB, ordered by most recent activity.
          Showing the latest 100 — older users get cleaned up by the
          24 h idle sweeper.
        </:subtitle>
      </.header>

      <div :if={@users == []} class="rounded-lg border border-dashed bg-card/50 p-8 text-center text-sm text-muted-foreground">
        No users in the database.
      </div>

      <div :if={@users != []} class="rounded-lg border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Display name</th>
              <th class="px-4 py-2 text-right">Active</th>
              <th class="px-4 py-2 text-right">Created</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={u <- @users} class="align-top">
              <td class="px-4 py-3 font-mono text-xs">{u.display_name}</td>
              <td class="px-4 py-3 text-right text-xs text-muted-foreground">
                {time_ago(u.last_active_at)}
              </td>
              <td class="px-4 py-3 text-right text-xs text-muted-foreground">
                {time_ago(u.inserted_at)}
              </td>
              <td class="px-4 py-3 text-right">
                <.button
                  variant="outline"
                  phx-click="delete"
                  phx-value-id={u.id}
                  data-confirm={"Force-expire #{u.display_name}? Their next request creates a fresh anonymous user."}
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  Expire
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
