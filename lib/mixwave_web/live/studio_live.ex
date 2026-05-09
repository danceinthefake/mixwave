defmodule MixwaveWeb.StudioLive do
  @moduledoc """
  The studio. One global jam room — every visitor lands here.

  Wires:
    - `Mixwave.Studio.subscribe/0` for note-event broadcasts
    - `MixwaveWeb.Presence` for "who's here, on what instrument"
    - 1-second server-side cooldown on instrument switch

  Instrument pads are Vue islands rendered inside a single
  `assets/vue/Studio.vue` parent island. See that file for why
  pads aren't rendered as separate islands.
  """
  use MixwaveWeb, :live_view

  alias MixwaveWeb.Presence
  alias Mixwave.Studio

  @instruments [:drums, :keyboard, :guitar, :bass, :pad]
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
     # Initialize so the first switch is never blocked. BEAM's
     # monotonic time can be a large negative integer at startup, so
     # `0` here would make the cooldown check (`now - last_switch_at`)
     # produce a negative result and reject every switch.
     |> assign(:last_switch_at, System.monotonic_time(:millisecond) - @switch_cooldown_ms)
     |> assign(:presences, presences)}
  end

  @impl true
  def handle_event("request_replay", _params, socket) do
    events = Mixwave.Studio.recent_events_within(30)
    {:noreply, push_event(socket, "replay_burst", events_to_replay_payload(events))}
  end

  @impl true
  def handle_event("note", payload, socket) do
    user = socket.assigns.current_user

    payload
    |> Map.put("user_id", user.id)
    |> Map.put("display_name", user.display_name)
    |> Mixwave.Studio.broadcast_note()

    {:noreply, socket}
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
  def handle_info({:studio_note, event}, socket) do
    # Filter self-events: the player's local audio already played
    # immediately on tap, so we don't need to play it again from
    # the network roundtrip. Only forward *other* users' hits.
    user_id = socket.assigns.current_user.id

    if event.payload["user_id"] != user_id do
      {:noreply, push_event(socket, "play_remote_note", event.payload)}
    else
      {:noreply, socket}
    end
  end

  defp presence_topic, do: "studio:lobby"

  ## Replay helpers

  # Trim the stored event buffer down to just the fields the Vue side
  # needs, with offsets relative to the first event so the client can
  # schedule them via setTimeout from "now."
  defp events_to_replay_payload([]), do: %{events: []}

  defp events_to_replay_payload([first | _] = events) do
    start_at = first.at

    events_payload =
      Enum.map(events, fn e ->
        %{
          instrument: e.payload["instrument"],
          style: e.payload["style"] || "synth",
          note: e.payload["note"],
          chord: e.payload["chord"],
          octave_offset: e.payload["octave_offset"] || 0,
          offset_ms: e.at - start_at
        }
      end)

    %{events: events_payload}
  end

  ## Render helpers

  defp instrument_label(:drums), do: "Drums"
  defp instrument_label(:keyboard), do: "Keyboard"
  defp instrument_label(:guitar), do: "Guitar"
  defp instrument_label(:bass), do: "Bass"
  defp instrument_label(:pad), do: "Pad"

  # Static class strings per instrument so Tailwind picks them up at
  # build time. Uses the per-instrument neon variables defined in
  # app.css. Tailwind can't synthesize these from a runtime string.
  defp active_tab_class(:drums), do: "bg-accent-drums/15 text-accent-drums"
  defp active_tab_class(:keyboard), do: "bg-accent-keyboard/15 text-accent-keyboard"
  defp active_tab_class(:guitar), do: "bg-accent-guitar/15 text-accent-guitar"
  defp active_tab_class(:bass), do: "bg-accent-bass/15 text-accent-bass"
  defp active_tab_class(:pad), do: "bg-accent-pad/15 text-accent-pad"

  defp accent_var(:drums), do: "var(--accent-drums)"
  defp accent_var(:keyboard), do: "var(--accent-keyboard)"
  defp accent_var(:guitar), do: "var(--accent-guitar)"
  defp accent_var(:bass), do: "var(--accent-bass)"
  defp accent_var(:pad), do: "var(--accent-pad)"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%!-- Break out of Layouts.app's max-w-3xl + py-10. The studio
           uses the full available width as a stage; the dock floats
           at the bottom of the viewport. --%>
      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 pt-4 pb-28">
        <div class="mx-auto max-w-5xl">
          <%!-- One live_vue island for the whole studio. Vue handles
               the v-if swap between pads internally — see Studio.vue
               for why we don't use three separate islands. --%>
          <.Studio current_instrument={Atom.to_string(@current_instrument)} />
        </div>
      </div>

      <%!-- Floating dock: instrument switcher + presence summary.
           Fixed at the viewport's bottom edge so it stays in reach
           regardless of page scroll. `pointer-events-none` on the
           outer wrapper lets clicks pass through the empty area
           around the dock to whatever is behind it. --%>
      <div class="fixed inset-x-0 bottom-4 px-4 z-40 pointer-events-none">
        <div class="mx-auto max-w-3xl pointer-events-auto">
          <div class="flex items-center gap-2 rounded-2xl border bg-card/80 backdrop-blur-md px-2 py-1.5 shadow-2xl">
            <%!-- Instrument switcher tabs --%>
            <div class="flex items-center gap-1 flex-1 overflow-x-auto">
              <button
                :for={inst <- @instruments}
                phx-click="switch_instrument"
                phx-value-to={inst}
                class={[
                  "px-3 py-1.5 text-sm rounded-lg transition-all flex items-center gap-1.5 whitespace-nowrap cursor-pointer",
                  @current_instrument == inst && active_tab_class(inst),
                  @current_instrument != inst &&
                    "text-muted-foreground hover:bg-accent hover:text-foreground"
                ]}
              >
                <span
                  class="size-2 rounded-full opacity-80"
                  style={"background-color: " <> accent_var(inst)}
                >
                </span>
                {instrument_label(inst)}
              </button>
            </div>

            <%!-- Divider --%>
            <div class="w-px h-6 bg-border shrink-0"></div>

            <%!-- Presence summary: avatar stack + count --%>
            <div class="flex items-center gap-2 pr-2 pl-1 shrink-0">
              <div class="flex -space-x-1.5">
                <span
                  :for={{user_id, %{metas: [meta | _]}} <- Enum.take(@presences, 4)}
                  class={[
                    "size-7 rounded-full flex items-center justify-center text-[10px] font-semibold border-2 border-card",
                    user_id == @current_user.id && "bg-primary text-primary-foreground",
                    user_id != @current_user.id && "bg-muted text-muted-foreground"
                  ]}
                  title={"#{meta.display_name} · #{instrument_label(meta.instrument)}"}
                >
                  {meta.display_name |> String.first() |> String.upcase()}
                </span>
              </div>
              <span class="text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                {map_size(@presences)} jamming
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
