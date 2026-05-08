defmodule MixwaveWeb.UploadLive do
  @moduledoc """
  Upload page. Pattern A: browser PUTs the audio file directly to R2
  via a short-lived presigned URL. Phoenix never sees the bytes.

  Flow:
    1. User picks a file. LiveView's allow_upload validates type +
       size client-side.
    2. When the user submits, LiveView fires the `external` callback
       (`presign_upload/2`) which mints a presigned PUT URL via
       Mixwave.Storage and returns it as part of the entry's meta.
    3. The S3 uploader in app.js PUTs the file to R2.
    4. Once done, our consume_uploaded_entries callback HEAD-verifies
       the object, inserts a `songs` row, and we redirect to the
       song page.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.{Library, Storage}

  @max_file_size 25_000_000
  @accepted ~w(.mp3 .m4a .ogg .flac)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:title, "")
      |> assign(:description, "")
      |> assign(:genre, "")
      |> assign(:saving, false)
      |> assign(:error, nil)
      |> allow_upload(:audio,
        accept: @accepted,
        max_entries: 1,
        max_file_size: @max_file_size,
        external: &presign_upload/2
      )

    {:ok, socket}
  end

  defp presign_upload(entry, socket) do
    user = socket.assigns.current_user
    ext = entry.client_name |> Path.extname() |> String.downcase()
    key = "uploads/#{user.id}/#{Ecto.UUID.generate()}#{ext}"

    case Storage.presign_put(key, entry.client_type) do
      {:ok, url} ->
        meta = %{uploader: "S3", key: key, url: url}
        {:ok, meta, socket}

      {:error, reason} ->
        {:error, reason, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"song" => params}, socket) do
    {:noreply,
     socket
     |> assign(:title, params["title"] || "")
     |> assign(:description, params["description"] || "")
     |> assign(:genre, params["genre"] || "")}
  end

  @impl true
  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  @impl true
  def handle_event("save", %{"song" => params}, socket) do
    socket = assign(socket, :saving, true)

    # consume_uploaded_entries fires once per completed upload entry.
    # For each, we use the meta we attached during presign to look the
    # object up in R2, HEAD-verify it, and create the songs row.
    results =
      consume_uploaded_entries(socket, :audio, fn meta, _entry ->
        case Storage.head(meta.key) do
          {:ok, _info} ->
            attrs = %{
              user_id: socket.assigns.current_user.id,
              title: nonblank(params["title"]) || "Untitled",
              description: nonblank(params["description"]),
              genre: nonblank(params["genre"]),
              storage_key: meta.key
            }

            case Library.create_song(attrs) do
              {:ok, song} -> {:ok, song}
              {:error, cs} -> {:postpone, {:error, cs}}
            end

          {:error, reason} ->
            {:postpone, {:error, reason}}
        end
      end)

    case results do
      [%Mixwave.Library.Song{} = song] ->
        {:noreply, push_navigate(socket, to: ~p"/song/#{song.id}")}

      [{:error, %Ecto.Changeset{} = cs}] ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:error, format_changeset_errors(cs))}

      [{:error, reason}] ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:error, "Upload verification failed: #{inspect(reason)}")}

      [] ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:error, "No file picked yet.")}
    end
  end

  defp nonblank(nil), do: nil
  defp nonblank(""), do: nil
  defp nonblank(s) when is_binary(s), do: String.trim(s)

  defp format_changeset_errors(%Ecto.Changeset{} = cs) do
    cs.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join("; ")
  end

  defp format_upload_error(:too_large), do: "File is larger than 25 MB."
  defp format_upload_error(:not_accepted), do: "File type not accepted (mp3, m4a, ogg, flac only)."
  defp format_upload_error(:too_many_files), do: "Only one file at a time."
  defp format_upload_error(other), do: "Upload error: #{inspect(other)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Upload a song
        <:subtitle>mp3, m4a, ogg, or flac · up to 25 MB · stored in R2</:subtitle>
      </.header>

      <form
        phx-submit="save"
        phx-change="validate"
        class="space-y-6"
      >
        <.input name="song[title]" label="Title" value={@title} required />
        <.input
          type="textarea"
          name="song[description]"
          label="Description"
          value={@description}
        />
        <.input name="song[genre]" label="Genre (optional)" value={@genre} />

        <div>
          <p class="block mb-1.5 text-sm font-medium">Audio file</p>
          <label
            phx-drop-target={@uploads.audio.ref}
            class="block rounded-md border-2 border-dashed border-input bg-card p-8 text-center cursor-pointer hover:bg-accent"
          >
            <.live_file_input upload={@uploads.audio} class="hidden" />
            <p class="text-sm text-muted-foreground">
              Drop a file here or click to browse
            </p>
          </label>

          <div :for={entry <- @uploads.audio.entries} class="mt-3 rounded-md border p-3">
            <div class="flex justify-between items-center text-sm">
              <span class="truncate font-medium">{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel"
                phx-value-ref={entry.ref}
                class="text-destructive hover:underline"
              >
                Cancel
              </button>
            </div>
            <div class="mt-2 h-2 rounded bg-muted overflow-hidden">
              <div class="h-full bg-primary" style={"width: #{entry.progress}%"}></div>
            </div>
            <p :for={err <- upload_errors(@uploads.audio, entry)} class="mt-2 text-xs text-destructive">
              {format_upload_error(err)}
            </p>
          </div>

          <p :for={err <- upload_errors(@uploads.audio)} class="mt-2 text-xs text-destructive">
            {format_upload_error(err)}
          </p>
        </div>

        <p :if={@error} class="text-sm text-destructive">{@error}</p>

        <div class="flex gap-2">
          <.button type="submit" disabled={@saving}>
            {if @saving, do: "Saving…", else: "Upload"}
          </.button>
          <.button variant="outline" navigate={~p"/"}>Cancel</.button>
        </div>
      </form>
    </Layouts.app>
    """
  end
end
