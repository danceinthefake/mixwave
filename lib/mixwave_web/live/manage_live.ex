defmodule MixwaveWeb.ManageLive do
  @moduledoc """
  Manage page. Lists `current_user`'s songs with a delete action.
  Inline editing is post-v1 — keeping the talk focused on the stack
  showcase rather than CRUD ergonomics.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.{Library, Storage}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :songs, list_songs(socket))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    with %Mixwave.Library.Song{user_id: user_id} = song when user_id == user.id <-
           Library.get_song(id),
         {:ok, _} <- Library.delete_song(song) do
      _ = Storage.delete(song.storage_key)

      {:noreply,
       socket
       |> assign(:songs, list_songs(socket))
       |> put_flash(:info, "Deleted “#{song.title}”.")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Couldn't delete that song.")}
    end
  end

  defp list_songs(socket) do
    case socket.assigns[:current_user] do
      nil -> []
      user -> Library.list_user_songs(user.id)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Your songs
        <:subtitle>
          {if @current_user, do: "uploaded by #{@current_user.display_name}", else: "no user"}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/upload"}>Upload another</.button>
        </:actions>
      </.header>

      <p :if={@songs == []} class="text-muted-foreground">
        You haven't uploaded anything yet.
        <.link navigate={~p"/upload"} class="underline">Upload one</.link>.
      </p>

      <ul :if={@songs != []} class="divide-y rounded-md border">
        <li
          :for={song <- @songs}
          class="px-4 py-3 flex items-center justify-between gap-4"
        >
          <div class="min-w-0 flex-1">
            <p class="font-medium truncate">{song.title}</p>
            <p class="text-xs text-muted-foreground">
              {song.genre || "—"} · uploaded {Calendar.strftime(song.inserted_at, "%Y-%m-%d")}
            </p>
          </div>
          <div class="flex gap-2 shrink-0">
            <.button variant="outline" navigate={~p"/song/#{song.id}"}>View</.button>
            <.button
              variant="outline"
              phx-click="delete"
              phx-value-id={song.id}
              data-confirm="Delete this song? This cannot be undone."
              class="text-destructive hover:bg-destructive/10 hover:text-destructive"
            >
              Delete
            </.button>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
