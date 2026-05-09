defmodule Mixwave.Chambers do
  @moduledoc """
  The Chambers context — secret rooms identified by an unguessable
  slug.

  Each chamber gets a random URL token at creation; anyone with
  the resulting link can join. A chamber starts in a "grace"
  state (`activated_at: nil`); the first time someone other than
  the creator joins, `mark_active/1` flips it to active. If
  nobody else joins within 5 minutes,
  `Mixwave.Chambers.Server` deletes the row.

  Persistence + runtime audio fan-out both live here:

    - CRUD + lifecycle: `create_chamber/1`, `find_by_slug/1`,
      `mark_active/1`, `set_title/2`, `set_kind/2`, `delete/1`,
      `touch_activity/1`, `delete_idle_since/1`.
    - Realtime audio: `topic/1`, `subscribe/1`, `broadcast_note/2`,
      `recent_events/1`, `recent_events_within/2`. The actual
      events buffer lives in `Mixwave.Chambers.Server` (one
      GenServer per active chamber).
  """

  import Ecto.Query

  alias Mixwave.Chambers.{Chamber, Server}
  alias Mixwave.Repo

  @doc """
  Creates a new chamber owned by `creator_user_id`. The slug is
  generated automatically.
  """
  def create_chamber(creator_user_id) when is_binary(creator_user_id) do
    %Chamber{}
    |> Chamber.creation_changeset(%{
      slug: generate_slug(),
      creator_user_id: creator_user_id
    })
    |> Repo.insert()
  end

  @doc """
  Looks up a chamber by its URL slug. Returns nil if not found.
  """
  def find_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Chamber, slug: slug)
  end

  @doc """
  Looks up a chamber by primary key. Used by the per-chamber
  GenServer's grace-period check.
  """
  def find_by_id(id) when is_binary(id), do: Repo.get(Chamber, id)

  @doc """
  Marks a chamber active — called the first time a non-creator
  joins. No-op if already active.
  """
  def mark_active(%Chamber{activated_at: nil} = chamber) do
    chamber
    |> Chamber.activation_changeset()
    |> Repo.update()
  end

  def mark_active(%Chamber{} = chamber), do: {:ok, chamber}

  @doc """
  Sets or clears the chamber's title. Whitespace-only input is
  treated as nil (no title), so users can clear the field by
  submitting an empty string.
  """
  def set_title(%Chamber{} = chamber, title) do
    chamber
    |> Chamber.title_changeset(%{title: title})
    |> Repo.update()
  end

  @doc """
  Sets the chamber's audio kind (anechoic / room / live / etc.).
  Each kind matches a preset in the client-side FX bus.
  """
  def set_kind(%Chamber{} = chamber, kind) when is_binary(kind) do
    chamber
    |> Chamber.kind_changeset(%{kind: kind})
    |> Repo.update()
  end

  @doc """
  Permanently deletes a chamber row. Called when the chamber's
  GenServer terminates because nobody but the creator showed up.
  """
  def delete(%Chamber{} = chamber), do: Repo.delete(chamber)

  @doc """
  Bumps `last_activity_at` to now. Called from the chamber's
  GenServer about once a minute when notes have been played, so
  the sweeper can tell active chambers apart from abandoned ones.
  """
  def touch_activity(%Chamber{} = chamber) do
    chamber
    |> Ecto.Changeset.change(
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
  end

  @doc """
  Deletes every chamber whose `last_activity_at` is older than the
  given cutoff. Returns the count of deleted rows. The sweeper
  passes `cutoff = now - 24h`.

  Only sweeps chambers that have been activated — non-activated
  chambers are owned by their GenServer's grace-period timer.
  """
  def delete_idle_since(%DateTime{} = cutoff) do
    {count, _} =
      from(c in Chamber,
        where: not is_nil(c.activated_at) and c.last_activity_at < ^cutoff
      )
      |> Repo.delete_all()

    count
  end

  ## Realtime audio fan-out

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
  stores it in the chamber's recent-events buffer (held by the
  per-slug GenServer).
  """
  def broadcast_note(slug, payload) when is_binary(slug) do
    event = %{
      kind: :note,
      payload: payload,
      at: System.monotonic_time(:millisecond)
    }

    Server.record(slug, event)
    Phoenix.PubSub.broadcast(Mixwave.PubSub, topic(slug), {:chamber_note, event})
    :ok
  end

  @doc """
  Returns the chamber's recent events (oldest first).
  """
  def recent_events(slug) when is_binary(slug), do: Server.recent_events(slug)

  @doc """
  Returns the chamber's events within the last `seconds` seconds,
  oldest first. Powers the "replay last 30s" button.
  """
  def recent_events_within(slug, seconds)
      when is_binary(slug) and is_integer(seconds) do
    Server.recent_events_within(slug, seconds)
  end

  # Generates a ~64-bit URL-safe token. 8 random bytes encode to 11
  # url-base64 chars. Collision probability stays negligible at any
  # realistic chamber count.
  defp generate_slug do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
