defmodule MixwaveWeb.SongLive do
  @moduledoc """
  Song detail page. Shows title, description, genre, uploader, plus
  the audio (basic <audio> for now — Player Vue island lands in the
  next pass) and a comments thread.

  The comments form posts back via standard LiveView events; comments
  are listed beneath the form, oldest first.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.{Library, Storage}
  alias Mixwave.Library.Comment

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Library.get_song(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Song not found.")
         |> push_navigate(to: ~p"/")}

      song ->
        # Presign can fail in dev if R2 isn't configured — the page
        # should still render with audio disabled rather than 500.
        audio_url =
          try do
            case Storage.presign_get(song.storage_key) do
              {:ok, url} -> url
              {:error, _} -> nil
            end
          rescue
            _ -> nil
          end

        comments = Library.list_comments(song.id)

        {:ok,
         socket
         |> assign(:song, song)
         |> assign(:audio_url, audio_url)
         |> assign(:comments, comments)
         |> assign_new_form()}
    end
  end

  defp assign_new_form(socket) do
    cs = Comment.creation_changeset(%Comment{}, %{})
    assign(socket, :form, to_form(cs))
  end

  @impl true
  def handle_event("validate", %{"comment" => params}, socket) do
    cs =
      %Comment{}
      |> Comment.creation_changeset(merge_assoc_ids(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs))}
  end

  @impl true
  def handle_event("save", %{"comment" => params}, socket) do
    case Library.create_comment(merge_assoc_ids(params, socket)) do
      {:ok, _comment} ->
        comments = Library.list_comments(socket.assigns.song.id)

        {:noreply,
         socket
         |> assign(:comments, comments)
         |> assign_new_form()
         |> put_flash(:info, "Comment posted.")}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}
    end
  end

  defp merge_assoc_ids(params, socket) do
    params
    |> Map.put("song_id", socket.assigns.song.id)
    |> Map.put("user_id", socket.assigns.current_user && socket.assigns.current_user.id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@song.title}
        <:subtitle>by {@song.user.display_name}</:subtitle>
        <:actions>
          <.link navigate={~p"/"} class="text-sm underline">← back to library</.link>
        </:actions>
      </.header>

      <p :if={@song.genre} class="text-xs uppercase tracking-wide text-muted-foreground">
        {@song.genre}
      </p>

      <p :if={@song.description} class="text-sm">{@song.description}</p>

      <audio :if={@audio_url} controls preload="metadata" src={@audio_url} class="w-full mt-4">
        Your browser doesn't support the audio element.
      </audio>

      <p :if={!@audio_url} class="mt-4 rounded-md border border-dashed p-4 text-sm text-muted-foreground">
        Audio source unavailable (R2 not configured for this environment).
      </p>

      <div class="mt-10">
        <h2 class="text-lg font-semibold mb-3">Comments</h2>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="mb-6 space-y-2"
        >
          <.input
            field={@form[:body]}
            type="textarea"
            label="Add a comment"
            placeholder={"as #{@current_user && @current_user.display_name}"}
          />
          <.button type="submit">Post</.button>
        </.form>

        <p :if={@comments == []} class="text-sm text-muted-foreground">
          No comments yet — be the first.
        </p>

        <ul :if={@comments != []} class="space-y-3">
          <li :for={c <- @comments} class="rounded-md border bg-card p-3">
            <p class="text-sm">{c.body}</p>
            <p class="mt-1 text-xs text-muted-foreground">
              {c.user.display_name} · {Calendar.strftime(c.inserted_at, "%Y-%m-%d %H:%M")}
            </p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
