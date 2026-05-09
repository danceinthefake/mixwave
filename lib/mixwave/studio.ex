defmodule Mixwave.Studio do
  @moduledoc """
  The Studio context — runtime audio for chambers.

  Each chamber gets its own PubSub topic (`"chamber:\#{slug}"`)
  and its own GenServer (`Mixwave.Studio.Chamber`) holding the
  recent-events buffer. Persistence (chamber rows, slug
  generation) lives in `Mixwave.Chambers`; this module deals
  only with the live audio fan-out + per-chamber buffer.

  Presence is handled by `MixwaveWeb.Presence` directly inside
  the LiveView, scoped to the same per-chamber topic.
  """

  alias Mixwave.Studio.Chamber

  @doc """
  PubSub topic for a chamber's note events.
  """
  def topic(slug) when is_binary(slug), do: "chamber:#{slug}"

  @doc """
  Subscribes the calling process to a chamber's note events.
  """
  def subscribe(slug) when is_binary(slug) do
    Phoenix.PubSub.subscribe(Mixwave.PubSub, topic(slug))
  end

  @doc """
  Broadcasts a note event to every subscriber of the chamber and
  stores it in the chamber's recent-events buffer.
  """
  def broadcast_note(slug, payload) when is_binary(slug) do
    event = %{
      kind: :note,
      payload: payload,
      at: System.monotonic_time(:millisecond)
    }

    Chamber.record(slug, event)
    Phoenix.PubSub.broadcast(Mixwave.PubSub, topic(slug), {:studio_note, event})
    :ok
  end

  @doc """
  Returns the chamber's recent events (oldest first).
  """
  def recent_events(slug) when is_binary(slug), do: Chamber.recent_events(slug)

  @doc """
  Returns the chamber's events within the last `seconds` seconds,
  oldest first. Powers the "replay last 30s" button.
  """
  def recent_events_within(slug, seconds)
      when is_binary(slug) and is_integer(seconds) do
    Chamber.recent_events_within(slug, seconds)
  end
end
