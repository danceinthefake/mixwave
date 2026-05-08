defmodule MixwaveWeb.StudioLive do
  @moduledoc """
  The studio. One global jam room. Every visitor lands here.

  Wires:
    - `Mixwave.Studio.subscribe/0` for note-event broadcasts
    - `MixwaveWeb.Presence` for "who's here, on what instrument"
    - Server-side cooldown on instrument switch (1s; BRAINSTORM §9)

  Instrument pads themselves are Vue islands — DrumPad, KeyboardPad,
  GuitarPad — and live in `assets/vue/instruments/`. They land in
  the next commit.
  """
  use MixwaveWeb, :live_view

  alias MixwaveWeb.Presence
  alias Mixwave.Studio

  @instruments [:drums, :keyboard, :guitar]
  @switch_cooldown_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Studio.subscribe()
      Phoenix.PubSub.subscribe(Mixwave.PubSub, presence_topic())

      {:ok, _} =
        Presence.track(self(), presence_topic(), user.id, %{
          display_name: user.display_name,
          instrument: :drums,
          joined_at: System.system_time(:second)
        })
    end

    presences =
      if connected?(socket),
        do: Presence.list(presence_topic()),
        else: %{}

    {:ok,
     socket
     |> assign(:instruments, @instruments)
     |> assign(:current_instrument, :drums)
     |> assign(:last_switch_at, 0)
     |> assign(:presences, presences)}
  end

  @impl true
  def handle_event("switch_instrument", %{"to" => to}, socket) do
    instrument = String.to_existing_atom(to)
    now = System.monotonic_time(:millisecond)

    cond do
      instrument not in @instruments ->
        {:noreply, socket}

      now - socket.assigns.last_switch_at < @switch_cooldown_ms ->
        # Cooldown — ignore the request silently.
        {:noreply, socket}

      true ->
        user = socket.assigns.current_user

        Presence.update(self(), presence_topic(), user.id, fn meta ->
          %{meta | instrument: instrument}
        end)

        {:noreply,
         socket
         |> assign(:current_instrument, instrument)
         |> assign(:last_switch_at, now)}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :presences, Presence.list(presence_topic()))}
  end

  @impl true
  def handle_info({:studio_note, _event}, socket) do
    # Note-event handling lands with DrumPad in the next commit:
    # we'll push the event down to the Vue island via push_event.
    {:noreply, socket}
  end

  defp presence_topic, do: "studio:lobby"

  ## Render helpers

  defp instrument_label(:drums), do: "Drums"
  defp instrument_label(:keyboard), do: "Keyboard"
  defp instrument_label(:guitar), do: "Guitar"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Studio
        <:subtitle>
          {if @current_user, do: "you are #{@current_user.display_name}", else: "anonymous"}
        </:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-[14rem_1fr] gap-6">
        <%!-- Presence sidebar --%>
        <aside class="rounded-lg border bg-card p-3">
          <h3 class="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
            In the room ({map_size(@presences)})
          </h3>
          <ul class="space-y-1 text-sm">
            <li :for={{user_id, %{metas: [meta | _]}} <- @presences} class="flex items-center gap-2">
              <span
                class={[
                  "size-2 rounded-full",
                  user_id == @current_user.id && "bg-primary",
                  user_id != @current_user.id && "bg-muted-foreground/40"
                ]}
              />
              <span class="truncate">{meta.display_name}</span>
              <span class="ml-auto text-xs text-muted-foreground">
                {instrument_label(meta.instrument)}
              </span>
            </li>
          </ul>
        </aside>

        <%!-- Instrument area --%>
        <section>
          <%!-- Tabs --%>
          <div class="inline-flex items-center gap-1 rounded-md border bg-card p-1 mb-4">
            <button
              :for={inst <- @instruments}
              phx-click="switch_instrument"
              phx-value-to={inst}
              class={[
                "px-3 py-1.5 text-sm rounded-sm transition-colors",
                @current_instrument == inst &&
                  "bg-primary text-primary-foreground",
                @current_instrument != inst &&
                  "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              ]}
            >
              {instrument_label(inst)}
            </button>
          </div>

          <%!-- Instrument pad slot — Vue islands land in the next commit --%>
          <div class="rounded-lg border bg-card p-8 min-h-[18rem] flex items-center justify-center">
            <p class="text-sm text-muted-foreground">
              {instrument_label(@current_instrument)} pad coming next.
              The wiring for note events through Studio.PubSub is ready;
              this is just where the Vue island will mount.
            </p>
          </div>
        </section>
      </div>

      <p class="mt-6 text-center text-xs text-muted-foreground">
        Best-effort sync — distant users may sound a beat off.
      </p>
    </Layouts.app>
    """
  end
end
