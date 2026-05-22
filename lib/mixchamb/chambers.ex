defmodule Mixchamb.Chambers do
  @moduledoc """
  The Chambers context — secret chambers identified by an
  unguessable slug.

  Each chamber gets a random URL token at creation; anyone with
  the resulting link can join. A chamber starts in a "grace"
  state (`activated_at: nil`); the first time someone other than
  the creator joins, `mark_active/1` flips it to active. If
  nobody else joins within 30 minutes,
  `Mixchamb.Chambers.Server` deletes the row.

  Persistence + runtime audio fan-out both live here:

    - CRUD + lifecycle: `create_chamber/1`, `find_by_slug/1`,
      `mark_active/1`, `set_title/2`, `set_kind/2`, `delete/1`,
      `touch_activity/1`, `delete_idle_since/1`.
    - Realtime audio: `topic/1`, `subscribe/1`, `broadcast_note/2`,
      `recent_events/1`, `recent_events_within/2`. The actual
      events buffer lives in `Mixchamb.Chambers.Server` (one
      GenServer per active chamber).
  """

  import Ecto.Query

  alias Mixchamb.Chambers.{Chamber, ChamberEvent, Server}
  alias Mixchamb.Repo

  @doc """
  Creates a new chamber owned by `creator_user_id`, running the
  given `activity` (default `"music"`). The slug is generated
  automatically. `activity` must be one of `Chamber.activities/0`
  — currently `"music"` or `"poker"`.
  """
  def create_chamber(creator_user_id, activity \\ "music")
      when is_binary(creator_user_id) and is_binary(activity) do
    %Chamber{}
    |> Chamber.creation_changeset(%{
      slug: generate_slug(),
      creator_user_id: creator_user_id,
      activity: activity
    })
    |> Repo.insert()
    |> tap(fn
      {:ok, chamber} ->
        :telemetry.execute(
          [:mixchamb, :chamber, :created],
          %{count: 1},
          %{
            slug: chamber.slug,
            kind: chamber.kind,
            activity: chamber.activity,
            system: false
          }
        )

      _ ->
        :ok
    end)
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
  Slug of the public Chaos Chamber — a singleton, always-on
  chamber anyone can join without a link.
  """
  @chaos_slug "chaos"
  def chaos_slug, do: @chaos_slug

  @doc """
  Returns the Chaos Chamber, creating it on first call. The row
  has `creator_user_id` NULL, which marks it as a system chamber:
  the per-chamber GenServer skips its grace-period check, the
  idle sweeper skips it, and the chamber UI shows nobody as the
  creator (so title + kind aren't editable).
  """
  def ensure_chaos_chamber do
    case find_by_slug(@chaos_slug) do
      nil ->
        %Chamber{}
        |> Chamber.system_changeset(%{
          slug: @chaos_slug,
          title: "Chaos chamber",
          # "echo" picked deliberately — repeats stack up and the
          # public chamber turns into a wash of overlapping sounds,
          # which suits the "chaos" name.
          kind: "echo"
        })
        |> Repo.insert()

      chamber ->
        {:ok, chamber}
    end
  end

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
  Flips the chamber's activity (music ↔ poker). Persists to the DB
  and casts to the chamber's GenServer so the in-memory state
  (PokerSession allocation, broadcast) matches the row.
  """
  def set_activity(%Chamber{} = chamber, activity) when is_binary(activity) do
    chamber
    |> Chamber.activity_changeset(%{activity: activity})
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> Server.set_activity(updated.slug, updated.activity)
      _ -> :ok
    end)
  end

  @doc """
  Flips the chamber's REC toggle. On success, casts the new value
  to the chamber's GenServer so its in-memory persistence flag
  matches the row without re-reading the DB on every note.
  """
  def set_recording(%Chamber{} = chamber, on?) when is_boolean(on?) do
    chamber
    |> Chamber.recording_changeset(%{is_recording: on?})
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> Server.set_recording(updated.slug, updated.is_recording)
      _ -> :ok
    end)
  end

  @doc """
  Bulk-inserts persisted note events. Each tuple in `events` is
  `{payload, inserted_at}` — the timestamp is captured by the
  chamber's GenServer at the moment the note was broadcast, so
  rapid bursts keep their relative timing when later replayed.
  """
  def record_events(_chamber_id, []), do: {:ok, 0}

  def record_events(chamber_id, events) when is_list(events) do
    rows =
      Enum.map(events, fn {payload, inserted_at} ->
        %{
          id: Ecto.UUID.generate(),
          chamber_id: chamber_id,
          payload: payload,
          inserted_at: inserted_at
        }
      end)

    {count, _} = Repo.insert_all(ChamberEvent, rows)
    {:ok, count}
  end

  @doc """
  Returns every persisted event for `chamber_id`, oldest first.
  Used to materialize a "play recording" replay.
  """
  def recorded_events(chamber_id) when is_binary(chamber_id) do
    ChamberEvent
    |> where([e], e.chamber_id == ^chamber_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Total number of persisted events for `chamber_id`. Drives the
  "Play recording" button's disabled/enabled state.
  """
  def recorded_event_count(chamber_id) when is_binary(chamber_id) do
    ChamberEvent
    |> where([e], e.chamber_id == ^chamber_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Wipes every persisted event for `chamber_id`. Returns
  `{count_deleted, nil}` matching Repo.delete_all's shape.
  Used by the Reset Recording button.
  """
  def delete_recorded_events(chamber_id) when is_binary(chamber_id) do
    ChamberEvent
    |> where([e], e.chamber_id == ^chamber_id)
    |> Repo.delete_all()
  end

  @doc """
  Permanently deletes a chamber row. Called when the chamber's
  GenServer terminates because nobody but the creator showed up.
  """
  def delete(%Chamber{} = chamber) do
    chamber
    |> Repo.delete()
    |> tap(fn
      {:ok, deleted} ->
        :telemetry.execute(
          [:mixchamb, :chamber, :deleted],
          %{count: 1},
          %{slug: deleted.slug, kind: deleted.kind}
        )

      _ ->
        :ok
    end)
  end

  @doc """
  Bumps `last_activity_at` to now. Called from the chamber's
  GenServer about once a minute when notes have been played, so
  the sweeper can tell active chambers apart from abandoned ones.
  """
  def touch_activity(%Chamber{} = chamber) do
    chamber
    |> Ecto.Changeset.change(last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  # Must match the chamber GenServer's @grace_period_ms. The
  # Server's timer is the happy path for unactivated chambers;
  # this constant is the sweeper backstop for chambers whose
  # GenServer died before the grace check could fire (BEAM
  # restart, supervisor giving up after too many crashes, etc.).
  @grace_period_minutes 30

  @doc """
  Deletes idle chambers in two passes:

    * **Activated chambers** (someone other than the creator
      joined): swept when `last_activity_at < cutoff` (the
      sweeper passes `cutoff = now - 24h`).
    * **Unactivated chambers**: swept when their row is older
      than the #{@grace_period_minutes}-minute grace window.
      The chamber's GenServer normally deletes these via its
      `:check_grace` timer; this is the backstop for the case
      where the GenServer died before grace fired.

  System chambers (`creator_user_id` is NULL — the Chaos
  chamber) are exempt and live forever.
  """

  def delete_idle_since(%DateTime{} = cutoff) do
    grace_cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@grace_period_minutes * 60, :second)

    {count, _} =
      from(c in Chamber,
        where:
          not is_nil(c.creator_user_id) and
            ((not is_nil(c.activated_at) and c.last_activity_at < ^cutoff) or
               (is_nil(c.activated_at) and c.inserted_at < ^grace_cutoff))
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
    Phoenix.PubSub.subscribe(Mixchamb.PubSub, topic(slug))
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
    Phoenix.PubSub.broadcast(Mixchamb.PubSub, topic(slug), {:chamber_note, event})

    # Echo on a global topic for the admin Activity feed. Tagged
    # with the slug so subscribers can identify the source without
    # subscribing to each chamber separately.
    Phoenix.PubSub.broadcast(
      Mixchamb.PubSub,
      activity_topic(),
      {:activity, slug, event}
    )

    # Telemetry event for the admin Dashboard counters. Metadata
    # carries the instrument so the counter can break down by it.
    :telemetry.execute(
      [:mixchamb, :chamber, :note],
      %{count: 1},
      %{
        slug: slug,
        instrument: payload["instrument"] || payload[:instrument],
        style: payload["style"] || payload[:style]
      }
    )

    :ok
  end

  @doc """
  Single firehose topic the admin Activity LV subscribes to. Every
  call to `broadcast_note/2` echoes here in addition to the chamber
  topic, so admins don't have to subscribe per-chamber.
  """
  def activity_topic, do: "admin:activity"

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

  @doc """
  Lists every running chamber GenServer as `{slug, pid}` tuples.
  Powers the supervisor LV's per-chamber chaos-button table.
  """
  def list_running do
    Registry.select(
      Mixchamb.Chambers.Registry,
      [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}]
    )
  end

  @doc """
  How many times the GenServer for `slug` has been restarted by the
  dynamic supervisor in this BEAM. First start counts as 0.
  """
  def restart_count(slug) when is_binary(slug) do
    case :ets.lookup(:chamber_restart_counts, slug) do
      [{^slug, count}] -> max(count, 0)
      _ -> 0
    end
  end

  @doc """
  Total chamber rows in the DB.
  """
  def count_chambers, do: Repo.aggregate(Chamber, :count, :id)

  @doc """
  Chambers that have been activated (someone other than the creator
  joined). Excludes those still in the grace window.
  """
  def count_activated_chambers do
    import Ecto.Query
    Repo.aggregate(from(c in Chamber, where: not is_nil(c.activated_at)), :count, :id)
  end

  @doc """
  Lists every chamber row, newest activity first. The admin
  Chambers tab uses this; the per-row PID + presence count are
  added on the LV side from the Registry + Presence.
  """
  def list_all do
    import Ecto.Query

    from(c in Chamber, order_by: [desc: c.last_activity_at, desc: c.inserted_at])
    |> Repo.all()
  end

  # Generates a ~64-bit URL-safe token. 8 random bytes encode to 11
  # url-base64 chars. Collision probability stays negligible at any
  # realistic chamber count.
  defp generate_slug do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
