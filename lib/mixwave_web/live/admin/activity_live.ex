defmodule MixwaveWeb.Admin.ActivityLive do
  @moduledoc """
  Admin → Activity tab. Live firehose of every note broadcast across
  every chamber. Subscribes to `Chambers.activity_topic/0`, which
  every `broadcast_note/2` echoes to.

  The buffer caps at @max_events to keep the LV's diff small even
  in busy chambers (a single user mashing keys can push 10+ events/
  sec); older entries fall off the end.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.Chambers
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @max_events 200

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Chambers.activity_topic())
    end

    {:ok,
     socket
     |> stream_configure(:events, dom_id: &"event-#{&1.id}")
     |> stream(:events, [], at: 0, limit: @max_events)
     |> assign(:event_seq, 0)
     |> assign(:paused, false)}
  end

  @impl true
  def handle_event("toggle_pause", _, socket) do
    {:noreply, update(socket, :paused, &(not &1))}
  end

  def handle_event("clear", _, socket) do
    {:noreply, stream(socket, :events, [], reset: true)}
  end

  @impl true
  def handle_info({:activity, slug, event}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      seq = socket.assigns.event_seq + 1
      row = build_row(seq, slug, event)

      {:noreply,
       socket
       |> assign(:event_seq, seq)
       |> stream_insert(:events, row, at: 0, limit: @max_events)}
    end
  end

  defp build_row(seq, slug, event) do
    payload = event.payload || %{}

    %{
      id: seq,
      slug: slug,
      instrument: Map.get(payload, "instrument") || Map.get(payload, :instrument) || "?",
      style: Map.get(payload, "style") || Map.get(payload, :style),
      note:
        Map.get(payload, "note") || Map.get(payload, :note) ||
          Map.get(payload, "chord") || Map.get(payload, :chord) || "",
      display_name:
        Map.get(payload, "display_name") || Map.get(payload, :display_name) || "(unknown)",
      ts: DateTime.utc_now()
    }
  end

  defp short_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell current_view={__MODULE__} flash={@flash}>
      <.header>
        Activity
        <:subtitle>
          Live firehose of every note broadcast across every chamber.
          Useful for sanity-checking PubSub fan-out and spotting
          abuse. Capped at {@max_events} most-recent events.
        </:subtitle>
        <:actions>
          <.button variant="outline" phx-click="toggle_pause">
            {if @paused, do: "Resume", else: "Pause"}
          </.button>
          <.button variant="outline" phx-click="clear">Clear</.button>
        </:actions>
      </.header>

      <div class="rounded-lg border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2 w-24">Time</th>
              <th class="px-4 py-2">Chamber</th>
              <th class="px-4 py-2">Player</th>
              <th class="px-4 py-2">Instrument</th>
              <th class="px-4 py-2">Style</th>
              <th class="px-4 py-2">Note</th>
            </tr>
          </thead>
          <tbody id="activity-stream" phx-update="stream" class="divide-y">
            <tr
              :for={{dom_id, e} <- @streams.events}
              id={dom_id}
              class="align-top"
            >
              <td class="px-4 py-2 font-mono text-xs text-muted-foreground tabular-nums">
                {short_time(e.ts)}
              </td>
              <td class="px-4 py-2 font-mono text-xs">
                <.link navigate={~p"/chamber/#{e.slug}"} class="hover:underline">
                  {e.slug}
                </.link>
              </td>
              <td class="px-4 py-2 font-mono text-xs">{e.display_name}</td>
              <td class="px-4 py-2 text-xs">{e.instrument}</td>
              <td class="px-4 py-2 text-xs text-muted-foreground">{e.style || "—"}</td>
              <td class="px-4 py-2 font-mono text-xs">{e.note}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="mt-4 text-xs text-muted-foreground">
        Paused stops accepting new events; the stream keeps the last
        {@max_events} you've seen. Clear empties the visible buffer.
      </p>
    </AdminLayouts.admin_shell>
    """
  end
end
