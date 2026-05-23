defmodule Mixchamb.Chambers.Server do
  @moduledoc """
  One GenServer per chamber, registered by slug via
  `Mixchamb.Chambers.Registry` and supervised by
  `Mixchamb.Chambers.Supervisor`.

  Holds the chamber's last N note events for join-time replay.
  Also owns the chamber lifecycle — the 30-minute grace-period
  self-check and the once-a-minute `last_activity_at` bump.

  `chamber_id` is the DB row's id — used by the lifecycle code to
  mark the chamber active or delete it. It's nilable so the
  GenServer can spin up before the persistence layer is wired in.

  The events buffer is intentionally not persisted — when the
  GenServer restarts, the jam resumes empty.
  """
  use GenServer

  @max_recent 200
  # Grace window during which the chamber must see a non-creator
  # join. If `activated_at` is still NULL when this elapses, the
  # GenServer deletes the chamber row and shuts itself down.
  @grace_period_ms 30 * 60 * 1000
  # How often the GenServer flushes the dirty flag to the DB by
  # bumping `last_activity_at`. Chosen for "rough enough that the
  # sweeper sees recent activity, cheap enough that it's not a
  # write per note even in busy chambers".
  @activity_bump_ms 60 * 1000
  # When recording is on, persisted events are buffered in memory
  # and flushed in batches. Whichever comes first wins.
  @recording_flush_interval_ms 2_000
  @recording_flush_batch_size 50

  ## Public API

  @doc """
  Returns the via-tuple for looking up a chamber's pid by slug.
  """
  def via(slug) when is_binary(slug) do
    {:via, Registry, {Mixchamb.Chambers.Registry, slug}}
  end

  @doc """
  Starts the GenServer for a slug under the dynamic supervisor if
  it isn't already running. Idempotent — returns the existing pid
  if a chamber with this slug is already up.
  """
  def ensure_started(slug, chamber_id \\ nil) when is_binary(slug) do
    case DynamicSupervisor.start_child(
           Mixchamb.Chambers.Supervisor,
           {__MODULE__, {slug, chamber_id}}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end

  def start_link({slug, chamber_id}) do
    GenServer.start_link(__MODULE__, %{slug: slug, chamber_id: chamber_id}, name: via(slug))
  end

  def child_spec({slug, _chamber_id} = args) do
    %{
      id: {__MODULE__, slug},
      start: {__MODULE__, :start_link, [args]},
      # `:transient` so the dynamic supervisor brings the chamber
      # back if it crashes (or if the supervisor LV's chaos button
      # kills it), but a clean `{:stop, :normal, _}` from the
      # grace-period delete still tears it down for good.
      restart: :transient
    }
  end

  @doc """
  Returns runtime info about a running chamber: pid, event count,
  uptime, and how many times its server has restarted in this BEAM.
  Used by the supervisor LV's per-chamber row.
  """
  def info(slug) when is_binary(slug) do
    GenServer.call(via(slug), :info, 1_000)
  catch
    :exit, _ -> nil
  end

  @doc """
  Records a note event in this chamber's buffer. When the chamber
  is recording, also enqueues the event's payload for the next
  bulk flush to `chamber_events`.
  """
  def record(slug, event), do: GenServer.cast(via(slug), {:record, event})

  ## Planning-poker API
  #
  # Each function below mutates the chamber's PokerSession (when
  # one exists) and broadcasts the matching event on the same
  # `chamber:<slug>` topic that note events use. See
  # `features/planning-poker.md` §4 for the full event vocabulary.
  # Calling these on a chamber whose activity isn't `"poker"` is a
  # no-op — the session doesn't exist, so the cast is silently
  # dropped.

  @doc "Cast or change `user_id`'s vote during `:voting`."
  def poker_vote(slug, user_id, card),
    do: GenServer.cast(via(slug), {:poker_vote, user_id, card})

  @doc "Drop `user_id`'s vote (e.g. on leave) during `:voting`."
  def poker_withdraw_vote(slug, user_id),
    do: GenServer.cast(via(slug), {:poker_withdraw_vote, user_id})

  @doc "Flip the session from `:voting` to `:revealed`."
  def poker_reveal(slug), do: GenServer.cast(via(slug), :poker_reveal)

  @doc """
  Soft reset: clear votes and return to `:voting` without bumping
  the round counter. Lets the team revote on the same story after
  a reveal that didn't converge.
  """
  def poker_revote(slug), do: GenServer.cast(via(slug), :poker_revote)

  @doc "Clear votes + increment round; optionally swap the story."
  def poker_next_round(slug, story \\ nil),
    do: GenServer.cast(via(slug), {:poker_next_round, story})

  @doc "Replace the active story line."
  def poker_set_story(slug, story),
    do: GenServer.cast(via(slug), {:poker_set_story, story})

  @doc "Switch deck — rejected when votes are in progress."
  def poker_set_deck(slug, deck),
    do: GenServer.cast(via(slug), {:poker_set_deck, deck})

  @doc """
  Replace the pre-loaded story queue. `lines` is a list of raw
  strings; blanks are trimmed out inside `PokerSession.set_queue/2`.
  """
  def poker_set_queue(slug, lines) when is_list(lines),
    do: GenServer.cast(via(slug), {:poker_set_queue, lines})

  @doc """
  Promote `target_user_id` to a co-host. Rejected when
  `requester_user_id` isn't the chamber creator. Idempotent —
  promoting someone who's already a host is a no-op.
  """
  def promote_host(slug, requester_user_id, target_user_id)
      when is_binary(requester_user_id) and is_binary(target_user_id),
      do: GenServer.cast(via(slug), {:promote_host, requester_user_id, target_user_id})

  @doc """
  Demote a co-host back to participant. The creator can demote
  anyone; a co-host can only demote themselves. The creator
  themselves can never be demoted (they're the chamber's anchor).
  """
  def demote_host(slug, requester_user_id, target_user_id)
      when is_binary(requester_user_id) and is_binary(target_user_id),
      do: GenServer.cast(via(slug), {:demote_host, requester_user_id, target_user_id})

  @doc "Synchronous snapshot of the current hosts list (creator + co-hosts)."
  def hosts(slug), do: GenServer.call(via(slug), :hosts)

  @doc """
  Synchronously read the current PokerSession (or `nil` if the
  chamber isn't in poker activity). Used by late joiners to
  rebuild their UI from the live state.
  """
  def poker_state(slug), do: GenServer.call(via(slug), :poker_state)

  @doc """
  Swap the chamber's active activity. Creates a new PokerSession
  on switch-to-poker; clears it on switch-away. Broadcasts
  `{:activity_changed, activity}` so subscribed LiveViews can
  re-render. The chamber row itself isn't updated by this call —
  the caller (`Mixchamb.Chambers.update_activity/2`) writes to DB
  first, then signals the GenServer.
  """
  def set_activity(slug, activity),
    do: GenServer.cast(via(slug), {:set_activity, activity})

  @doc """
  Updates the in-memory recording flag. Called by
  `Mixchamb.Chambers.set_recording/2` after the DB row is updated
  so subsequent `record/2` calls know whether to enqueue.
  """
  def set_recording(slug, on?) when is_boolean(on?) do
    GenServer.cast(via(slug), {:set_recording, on?})
  end

  @doc """
  Returns the buffered events oldest-first.
  """
  def recent_events(slug), do: GenServer.call(via(slug), :recent_events)

  @doc """
  Returns events from the last `seconds` seconds, oldest-first.
  """
  def recent_events_within(slug, seconds) do
    GenServer.call(via(slug), {:recent_events_within, seconds})
  end

  ## GenServer

  @impl true
  def init(state) do
    # Schedule the grace-period check. If a non-creator joins
    # before this fires, ChamberLive flips activated_at on the
    # row; when the message arrives we re-read the row and only
    # delete if it's still NULL.
    if state.chamber_id do
      Process.send_after(self(), :check_grace, @grace_period_ms)
      Process.send_after(self(), :bump_activity, @activity_bump_ms)
    end

    # Bump the per-slug restart counter. Default `-1` so the very
    # first start lands at 0; subsequent restarts (after a chaos
    # kill) tick up from there. The supervisor LV reads this.
    count = :ets.update_counter(:chamber_restart_counts, state.slug, 1, {state.slug, -1})

    # Wake the supervisor LV immediately on a restart so its row
    # flashes red without waiting for the next 1 s polling tick.
    # First-time starts (count == 0) skip this — no flash to show.
    if count > 0 do
      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Mixchamb.RestartWatcher.topic(),
        :restarts_changed
      )

      :telemetry.execute(
        [:mixchamb, :chamber, :restarted],
        %{count: 1},
        %{slug: state.slug, restart_count: count}
      )
    end

    started_at = System.monotonic_time(:millisecond)

    # Seed the recording flag + activity from the DB so a chamber
    # whose creator turned REC on (or whose activity is "poker")
    # rehydrates correctly when the GenServer is restarted by
    # the supervisor.
    {is_recording, activity, creator_user_id} =
      case state.chamber_id && Mixchamb.Chambers.find_by_id(state.chamber_id) do
        %{is_recording: rec, activity: act, creator_user_id: cid} -> {rec, act, cid}
        _ -> {false, "music", nil}
      end

    if is_recording do
      Process.send_after(self(), :flush_recording, @recording_flush_interval_ms)
    end

    # Lazily allocate a PokerSession only when the chamber is
    # actually running poker. Non-poker chambers carry `nil`, so
    # the poker cast handlers can pattern-match against it as a
    # cheap "is this chamber playing poker?" gate.
    poker_session =
      if activity == "poker" do
        Mixchamb.Chambers.PokerSession.new()
      end

    # Hosts: creator-plus-promoted set. Ephemeral by design —
    # promotions die with the chamber, same as poker / music state
    # (v4 §3.7). Creator is the single source of demote-immunity;
    # they can promote/demote anyone else, co-hosts can demote
    # themselves but can't add new hosts. nil creator_user_id only
    # happens in test fixtures that skip the DB row — the resulting
    # empty set degrades cleanly (no one is host, no one can do
    # host actions, but the chamber doesn't crash).
    hosts =
      case creator_user_id do
        nil -> MapSet.new()
        id -> MapSet.new([id])
      end

    state =
      Map.merge(state, %{
        events: [],
        count: 0,
        dirty?: false,
        started_at: started_at,
        is_recording: is_recording,
        to_persist: [],
        activity: activity,
        creator_user_id: creator_user_id,
        hosts: hosts,
        poker_session: poker_session
      })

    {:ok, state}
  end

  @impl true
  def handle_cast({:record, event}, state) do
    events = [event | state.events] |> Enum.take(@max_recent)

    to_persist =
      if state.is_recording do
        [{event.payload, DateTime.utc_now()} | state.to_persist]
      else
        state.to_persist
      end

    new_state = %{
      state
      | events: events,
        count: state.count + 1,
        dirty?: true,
        to_persist: to_persist
    }

    # Threshold-flush right away so a busy chamber doesn't keep
    # an unbounded in-memory queue between timer ticks.
    new_state =
      if length(to_persist) >= @recording_flush_batch_size,
        do: flush_recording(new_state),
        else: new_state

    {:noreply, new_state}
  end

  def handle_cast({:set_recording, on?}, state) do
    cond do
      on? == state.is_recording ->
        {:noreply, state}

      on? == true ->
        Process.send_after(self(), :flush_recording, @recording_flush_interval_ms)
        {:noreply, %{state | is_recording: true}}

      true ->
        # Turning recording off — flush whatever's pending so we
        # don't lose the tail of the session.
        state = flush_recording(state)
        {:noreply, %{state | is_recording: false}}
    end
  end

  ## Planning-poker cast handlers
  #
  # All six follow the same shape: pattern-match `state.poker_session`
  # as non-nil (chamber is in poker mode), delegate the mutation to
  # `PokerSession`, broadcast on `{:ok, _}`, swallow `{:noop, _}` /
  # `{:error, _}`. When the session is `nil`, the cast is a silent
  # no-op — the chamber isn't in poker mode, nothing to do.

  def handle_cast({:poker_vote, user_id, card}, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.cast_vote(session, user_id, card) do
      {:ok, updated} ->
        broadcast_poker(state.slug, {:poker, :vote_cast, user_id})
        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:poker_withdraw_vote, user_id}, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.withdraw_vote(session, user_id) do
      {:ok, updated} ->
        broadcast_poker(state.slug, {:poker, :vote_withdrawn, user_id})
        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(:poker_reveal, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.reveal(session) do
      {:ok, updated} ->
        broadcast_poker(state.slug, {:poker, :revealed, updated.votes})
        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(:poker_revote, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.revote(session) do
      {:ok, updated} ->
        # Reuse the :cleared event — same wire-shape (status back
        # to :voting, votes empty); clients re-derive the rest
        # from the included round + story + deck.
        broadcast_poker(
          state.slug,
          {:poker, :cleared, updated.round, updated.story, updated.deck}
        )

        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:poker_next_round, story}, %{poker_session: session} = state)
      when not is_nil(session) do
    opts = if is_nil(story), do: [], else: [story: story]

    case Mixchamb.Chambers.PokerSession.next_round(session, opts) do
      {:ok, updated} ->
        broadcast_poker(
          state.slug,
          {:poker, :cleared, updated.round, updated.story, updated.deck}
        )

        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:poker_set_story, story}, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.set_story(session, story) do
      {:ok, updated} ->
        broadcast_poker(state.slug, {:poker, :story_changed, updated.story})
        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:poker_set_deck, deck}, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.set_deck(session, deck) do
      {:ok, updated} ->
        broadcast_poker(state.slug, {:poker, :deck_changed, updated.deck})
        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:poker_set_queue, lines}, %{poker_session: session} = state)
      when not is_nil(session) do
    case Mixchamb.Chambers.PokerSession.set_queue(session, lines) do
      {:ok, updated} ->
        broadcast_poker(state.slug, {:poker, :queue_changed, updated.queue})
        {:noreply, %{state | poker_session: updated, dirty?: true}}

      _ ->
        {:noreply, state}
    end
  end

  # Cast-with-no-session fall-through: poker actions against a
  # music-mode chamber are silently dropped. Keeps the caller
  # simple (no need to check activity before casting).
  def handle_cast({:poker_vote, _, _}, state), do: {:noreply, state}
  def handle_cast({:poker_withdraw_vote, _}, state), do: {:noreply, state}
  def handle_cast(:poker_reveal, state), do: {:noreply, state}
  def handle_cast(:poker_revote, state), do: {:noreply, state}
  def handle_cast({:poker_next_round, _}, state), do: {:noreply, state}
  def handle_cast({:poker_set_story, _}, state), do: {:noreply, state}
  def handle_cast({:poker_set_deck, _}, state), do: {:noreply, state}
  def handle_cast({:poker_set_queue, _}, state), do: {:noreply, state}

  # Host management. Authorisation is enforced here (not at the
  # LV layer alone) so a hand-crafted phx push from a co-host's
  # session can't sneak in a `promote_host` for themselves.
  def handle_cast({:promote_host, requester_id, target_id}, state) do
    cond do
      # Only the creator can promote new hosts. Co-hosts can drive
      # the session but can't extend the host set further.
      requester_id != state.creator_user_id ->
        {:noreply, state}

      MapSet.member?(state.hosts, target_id) ->
        {:noreply, state}

      true ->
        new_hosts = MapSet.put(state.hosts, target_id)

        Phoenix.PubSub.broadcast(
          Mixchamb.PubSub,
          Mixchamb.Chambers.topic(state.slug),
          {:hosts_changed, MapSet.to_list(new_hosts)}
        )

        {:noreply, %{state | hosts: new_hosts}}
    end
  end

  def handle_cast({:demote_host, requester_id, target_id}, state) do
    cond do
      # Creator is the chamber's anchor — they can't be demoted by
      # anyone, including themselves. Without this an absentminded
      # creator click on their own row would lock the chamber out
      # of every host action with no way back.
      target_id == state.creator_user_id ->
        {:noreply, state}

      # Non-creators can only demote themselves. Co-host A demoting
      # co-host B would be a "kick" we haven't designed for.
      requester_id != state.creator_user_id and requester_id != target_id ->
        {:noreply, state}

      not MapSet.member?(state.hosts, target_id) ->
        {:noreply, state}

      true ->
        new_hosts = MapSet.delete(state.hosts, target_id)

        Phoenix.PubSub.broadcast(
          Mixchamb.PubSub,
          Mixchamb.Chambers.topic(state.slug),
          {:hosts_changed, MapSet.to_list(new_hosts)}
        )

        {:noreply, %{state | hosts: new_hosts}}
    end
  end

  def handle_cast({:set_activity, activity}, state) do
    poker_session =
      case activity do
        "poker" -> state.poker_session || Mixchamb.Chambers.PokerSession.new()
        _ -> nil
      end

    Phoenix.PubSub.broadcast(
      Mixchamb.PubSub,
      Mixchamb.Chambers.topic(state.slug),
      {:activity_changed, activity}
    )

    {:noreply, %{state | activity: activity, poker_session: poker_session}}
  end

  @impl true
  def handle_call(:info, _from, state) do
    uptime_ms = System.monotonic_time(:millisecond) - state.started_at
    {:reply, %{slug: state.slug, event_count: state.count, uptime_ms: uptime_ms}, state}
  end

  def handle_call(:recent_events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  def handle_call({:recent_events_within, seconds}, _from, state) do
    cutoff = System.monotonic_time(:millisecond) - seconds * 1000

    events =
      state.events
      |> Enum.filter(&(&1.at >= cutoff))
      |> Enum.reverse()

    {:reply, events, state}
  end

  def handle_call(:poker_state, _from, state) do
    {:reply, state.poker_session, state}
  end

  def handle_call(:hosts, _from, state) do
    {:reply, MapSet.to_list(state.hosts), state}
  end

  @impl true
  def handle_info(:check_grace, %{chamber_id: chamber_id, slug: slug} = state) do
    case Mixchamb.Chambers.find_by_id(chamber_id) do
      nil ->
        # Already deleted from DB out-of-band. Just terminate.
        {:stop, :normal, state}

      %{creator_user_id: nil} ->
        # System chamber (e.g., the public Chaos Chamber). No
        # creator means there's nothing to "wait for" — stays
        # alive forever.
        {:noreply, state}

      %{activated_at: nil} = chamber ->
        # Nobody but the creator showed up. Delete the row, tell
        # any subscribed LV to redirect, then shut down.
        Mixchamb.Chambers.delete(chamber)

        Phoenix.PubSub.broadcast(
          Mixchamb.PubSub,
          Mixchamb.Chambers.topic(slug),
          {:chamber_closed, slug}
        )

        {:stop, :normal, state}

      _activated ->
        # A non-creator joined within the grace window — chamber
        # stays alive. Nothing more to schedule.
        {:noreply, state}
    end
  end

  def handle_info(:flush_recording, state) do
    state = flush_recording(state)

    if state.is_recording do
      Process.send_after(self(), :flush_recording, @recording_flush_interval_ms)
    end

    {:noreply, state}
  end

  def handle_info(:bump_activity, %{chamber_id: chamber_id, dirty?: dirty?} = state) do
    # If notes came in this minute, flush a single DB write to
    # update last_activity_at. If nothing happened, skip the write
    # — the sweeper will eventually decide this chamber is idle.
    if dirty? do
      case Mixchamb.Chambers.find_by_id(chamber_id) do
        nil ->
          # Row deleted out-of-band (sweeper ran, or grace-period
          # delete fired). Stop the GenServer so we don't keep
          # trying to bump a non-existent row.
          {:stop, :normal, state}

        chamber ->
          Mixchamb.Chambers.touch_activity(chamber)
          Process.send_after(self(), :bump_activity, @activity_bump_ms)
          {:noreply, %{state | dirty?: false}}
      end
    else
      Process.send_after(self(), :bump_activity, @activity_bump_ms)
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Flush any pending recording rows so a graceful shutdown
    # doesn't lose the tail of an active session.
    _ = flush_recording(state)
    :ok
  end

  # Drains `state.to_persist` to the DB in chronological order.
  # The queue is built head-first for O(1) prepend in handle_cast,
  # so we reverse before insert.
  defp flush_recording(%{to_persist: []} = state), do: state

  defp flush_recording(%{chamber_id: nil} = state) do
    # No chamber row to attach events to (system chamber created
    # before a chamber_id was wired in). Drop the queue.
    %{state | to_persist: []}
  end

  defp flush_recording(%{chamber_id: chamber_id, to_persist: queue} = state) do
    Mixchamb.Chambers.record_events(chamber_id, Enum.reverse(queue))
    %{state | to_persist: []}
  end

  # Broadcast a poker lifecycle event on the chamber's PubSub topic.
  # LiveViews subscribed via `Mixchamb.Chambers.subscribe/1` receive
  # the message verbatim and can pattern-match on the leading
  # `:poker` tag to route to the poker UI.
  defp broadcast_poker(slug, message) do
    Phoenix.PubSub.broadcast(
      Mixchamb.PubSub,
      Mixchamb.Chambers.topic(slug),
      message
    )
  end
end
