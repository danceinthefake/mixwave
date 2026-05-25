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

  # --- Retro API ------------------------------------------------
  # All retro casts are dropped silently if the chamber isn't in
  # "retro" activity (retro_state is nil) — same pattern as the
  # poker fall-throughs. Host-gated actions check `state.hosts`
  # inside the cast handler; non-host actions just check the
  # session is live.

  @doc """
  Start a fresh retro session for this chamber. Host-only.
  Idempotent — does nothing if a non-archived session already
  exists.
  """
  def retro_start_session(slug, user_id) when is_binary(user_id),
    do: GenServer.cast(via(slug), {:retro_start_session, user_id})

  @doc "Update session title. Host-only."
  def retro_set_title(slug, user_id, title) when is_binary(user_id),
    do: GenServer.cast(via(slug), {:retro_set_title, user_id, title})

  @doc "Toggle voting_enabled. Host-only. See spec §5 for transition rules."
  def retro_set_voting_enabled(slug, user_id, enabled)
      when is_binary(user_id) and is_boolean(enabled),
      do: GenServer.cast(via(slug), {:retro_set_voting_enabled, user_id, enabled})

  @doc "Toggle brainstorm_visible. Host-only, :setup-only."
  def retro_set_brainstorm_visible(slug, user_id, visible)
      when is_binary(user_id) and is_boolean(visible),
      do: GenServer.cast(via(slug), {:retro_set_brainstorm_visible, user_id, visible})

  @doc "Rename a column. Host-only, :setup-only (spec §2)."
  def retro_rename_column(slug, user_id, column_id, name)
      when is_binary(user_id) and is_binary(column_id) and is_binary(name),
      do: GenServer.cast(via(slug), {:retro_rename_column, user_id, column_id, name})

  @doc "Advance the phase machine by one step. Host-only."
  def retro_advance_phase(slug, user_id) when is_binary(user_id),
    do: GenServer.cast(via(slug), {:retro_advance_phase, user_id})

  @doc """
  Add a brainstorm card. Anyone in the chamber. Snapshots both
  the alias (`user.alias`) and display_name (`user.display_name`)
  separately so the card can render the same two-piece
  `alias · display_name` pattern poker reveal uses (spec §3).
  `author_alias` is required and falls back to the display_name
  on the LV side when no alias is set; `author_display_name` is
  nullable for cards predating this column.
  """
  def retro_add_card(slug, user_id, column_id, body, author_alias, author_display_name)
      when is_binary(user_id) and is_binary(column_id) and is_binary(body) and
             is_binary(author_alias) and is_binary(author_display_name),
      do:
        GenServer.cast(
          via(slug),
          {:retro_add_card, user_id, column_id, body, author_alias, author_display_name}
        )

  @doc "Edit your own card's body. Author-only, :brainstorm-only."
  def retro_update_card(slug, user_id, card_id, body)
      when is_binary(user_id) and is_binary(card_id) and is_binary(body),
      do: GenServer.cast(via(slug), {:retro_update_card, user_id, card_id, body})

  @doc "Delete your own card. Author-only, :brainstorm-only."
  def retro_delete_card(slug, user_id, card_id)
      when is_binary(user_id) and is_binary(card_id),
      do: GenServer.cast(via(slug), {:retro_delete_card, user_id, card_id})

  @doc "Vote for a card during :voting. Capped at 3 per user."
  def retro_vote(slug, user_id, card_id)
      when is_binary(user_id) and is_binary(card_id),
      do: GenServer.cast(via(slug), {:retro_vote, user_id, card_id})

  @doc "Withdraw a vote for a card during :voting."
  def retro_withdraw_vote(slug, user_id, card_id)
      when is_binary(user_id) and is_binary(card_id),
      do: GenServer.cast(via(slug), {:retro_withdraw_vote, user_id, card_id})

  @doc "Highlight a card as currently-discussing. Host-only, :discuss-only."
  def retro_set_discussing(slug, user_id, card_id_or_nil)
      when is_binary(user_id) and (is_binary(card_id_or_nil) or is_nil(card_id_or_nil)),
      do: GenServer.cast(via(slug), {:retro_set_discussing, user_id, card_id_or_nil})

  @doc """
  Add an action item during :discuss. Anyone in the chamber.
  `attrs` should include :body and may include :source_card_id,
  :assignee_alias, :due_date, :created_by_user_id.
  """
  def retro_add_action_item(slug, attrs) when is_map(attrs),
    do: GenServer.cast(via(slug), {:retro_add_action_item, attrs})

  @doc "Update an action item. Anyone in the chamber, :discuss-only."
  def retro_update_action_item(slug, action_id, attrs)
      when is_binary(action_id) and is_map(attrs),
      do: GenServer.cast(via(slug), {:retro_update_action_item, action_id, attrs})

  @doc "Delete an action item. Anyone in the chamber, :discuss-only."
  def retro_delete_action_item(slug, action_id) when is_binary(action_id),
    do: GenServer.cast(via(slug), {:retro_delete_action_item, action_id})

  @doc """
  Synchronously read the current retro EphemeralState (or `nil`
  if not in retro activity). Used by LV mount + Presence-leave
  cleanup.
  """
  def retro_state(slug), do: GenServer.call(via(slug), :retro_state)

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

    # Retro is similar but persistent — the EphemeralState
    # struct points at the live session row (if any) and holds
    # the vote map + discussing-card focus that don't deserve a
    # DB column. Re-hydrated from the latest non-archived
    # session on GenServer restart; nil if no session exists yet
    # (the LV's first host action creates one).
    retro_state =
      if activity == "retro" and state.chamber_id do
        case Mixchamb.Retro.current_session(state.chamber_id) do
          nil ->
            nil

          session ->
            Mixchamb.Retro.EphemeralState.new(
              session.id,
              String.to_existing_atom(session.status)
            )
        end
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
        poker_session: poker_session,
        retro_state: retro_state
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

  # --- Retro cast handlers -----------------------------------------
  # Pattern: pattern-match `state.retro_state` (non-nil = chamber
  # is in retro mode with a live session). Host-gated actions also
  # check `state.hosts`. Persistent ops go through `Mixchamb.Retro`;
  # on success, broadcast and refresh the cached EphemeralState.
  # Most handlers don't update the EphemeralState struct itself —
  # only the vote / phase / discussing-focus ones do, because
  # those are the only fields the struct carries.

  def handle_cast({:retro_start_session, user_id}, state) do
    cond do
      state.activity != "retro" ->
        {:noreply, state}

      not MapSet.member?(state.hosts, user_id) ->
        {:noreply, state}

      live_retro_state?(state.retro_state) ->
        # Idempotent — a non-archived session already exists.
        {:noreply, state}

      true ->
        case Mixchamb.Retro.start_session(state.chamber_id) do
          {:ok, session} ->
            retro_state =
              Mixchamb.Retro.EphemeralState.new(
                session.id,
                String.to_existing_atom(session.status)
              )

            broadcast_retro(state.slug, {:retro, :session_started, session.id})
            {:noreply, %{state | retro_state: retro_state}}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle_cast({:retro_set_title, user_id, title}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    if not MapSet.member?(state.hosts, user_id) do
      {:noreply, state}
    else
      with %_{} = session <- Mixchamb.Retro.load_session(rs.session_id),
           {:ok, updated} <- Mixchamb.Retro.set_title(session, title) do
        broadcast_retro(state.slug, {:retro, :title_changed, updated.title})
      end

      {:noreply, state}
    end
  end

  def handle_cast(
        {:retro_set_brainstorm_visible, user_id, visible},
        %{retro_state: rs} = state
      )
      when not is_nil(rs) do
    if not MapSet.member?(state.hosts, user_id) do
      {:noreply, state}
    else
      session = Mixchamb.Retro.load_session(rs.session_id)

      case Mixchamb.Retro.set_brainstorm_visible(session, visible) do
        {:ok, _updated} ->
          broadcast_retro(state.slug, {:retro, :brainstorm_visible_changed, visible})

        _ ->
          :ok
      end

      {:noreply, state}
    end
  end

  def handle_cast({:retro_set_voting_enabled, user_id, enabled}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    if not MapSet.member?(state.hosts, user_id) do
      {:noreply, state}
    else
      session = Mixchamb.Retro.load_session(rs.session_id)

      case Mixchamb.Retro.set_voting_enabled(session, enabled) do
        {:ok, _updated} ->
          broadcast_retro(state.slug, {:retro, :voting_enabled_changed, enabled})

          # Special case from spec §5: toggling off mid-:voting
          # discards the vote map and auto-advances to :discuss
          # (no materialisation).
          if rs.phase == :voting and enabled == false do
            reloaded = Mixchamb.Retro.load_session(rs.session_id)

            case Mixchamb.Retro.set_phase(reloaded, :discuss) do
              {:ok, _} ->
                {:ok, new_rs} = Mixchamb.Retro.EphemeralState.set_phase(rs, :discuss)
                broadcast_retro(state.slug, {:retro, :phase_changed, :discuss})
                {:noreply, %{state | retro_state: new_rs}}

              _ ->
                {:noreply, state}
            end
          else
            {:noreply, state}
          end

        _ ->
          {:noreply, state}
      end
    end
  end

  def handle_cast(
        {:retro_rename_column, user_id, column_id, name},
        %{retro_state: rs} = state
      )
      when not is_nil(rs) do
    if not MapSet.member?(state.hosts, user_id) do
      {:noreply, state}
    else
      session = Mixchamb.Retro.load_session(rs.session_id)
      column = Mixchamb.Retro.get_column(column_id)

      if column && column.retro_session_id == rs.session_id do
        case Mixchamb.Retro.rename_column(column, name, session) do
          {:ok, updated} ->
            broadcast_retro(
              state.slug,
              {:retro, :column_renamed, updated.id, updated.name}
            )

          _ ->
            :ok
        end
      end

      {:noreply, state}
    end
  end

  def handle_cast({:retro_advance_phase, user_id}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    cond do
      not MapSet.member?(state.hosts, user_id) ->
        {:noreply, state}

      true ->
        session = Mixchamb.Retro.load_session(rs.session_id)

        # If exiting :voting → :discuss, materialise the vote
        # counts onto retro_cards.vote_count first, then clear
        # the ephemeral vote map via set_phase.
        if rs.phase == :voting do
          counts = Mixchamb.Retro.EphemeralState.tally(rs)
          Mixchamb.Retro.materialize_vote_counts(session, counts)
        end

        case Mixchamb.Retro.advance_phase(session) do
          {:ok, updated} ->
            new_phase = String.to_existing_atom(updated.status)
            broadcast_retro(state.slug, {:retro, :phase_changed, new_phase})

            # On archive, drop the EphemeralState entirely — the
            # session is no longer "live" from the GenServer's
            # point of view. Without this, retro_start_session
            # refuses to create a new session because its
            # "already-active" guard sees the stale archived
            # struct. Subsequent retro_* casts against an
            # archived state hit the nil fall-throughs and
            # silently no-op.
            new_state =
              if new_phase == :archived do
                %{state | retro_state: nil}
              else
                {:ok, new_rs} = Mixchamb.Retro.EphemeralState.set_phase(rs, new_phase)
                %{state | retro_state: new_rs}
              end

            {:noreply, new_state}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle_cast(
        {:retro_add_card, user_id, column_id, body, author_alias, author_display_name},
        %{retro_state: rs} = state
      )
      when not is_nil(rs) do
    session = Mixchamb.Retro.load_session(rs.session_id)
    column = Mixchamb.Retro.get_column(column_id)

    if column && column.retro_session_id == rs.session_id do
      case Mixchamb.Retro.add_card(session, column, %{
             body: body,
             author_user_id: user_id,
             author_alias: author_alias,
             author_display_name: author_display_name
           }) do
        {:ok, card} ->
          broadcast_retro(state.slug, {:retro, :card_added, card_to_wire(card)})

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_cast({:retro_update_card, user_id, card_id, body}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    session = Mixchamb.Retro.load_session(rs.session_id)
    card = Mixchamb.Retro.get_card(card_id)

    if card && card.retro_session_id == rs.session_id do
      case Mixchamb.Retro.update_card(card, body, user_id, session) do
        {:ok, updated} ->
          broadcast_retro(state.slug, {:retro, :card_edited, updated.id, updated.body})

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_cast({:retro_delete_card, user_id, card_id}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    session = Mixchamb.Retro.load_session(rs.session_id)
    card = Mixchamb.Retro.get_card(card_id)

    if card && card.retro_session_id == rs.session_id do
      case Mixchamb.Retro.delete_card(card, user_id, session) do
        {:ok, _} ->
          broadcast_retro(state.slug, {:retro, :card_deleted, card.id})

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_cast({:retro_vote, user_id, card_id}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    case Mixchamb.Retro.EphemeralState.cast_vote(rs, user_id, card_id) do
      {:ok, new_rs} ->
        tallies = Mixchamb.Retro.EphemeralState.tally(new_rs)
        broadcast_retro(state.slug, {:retro, :vote_cast, user_id, card_id, tallies})
        {:noreply, %{state | retro_state: new_rs}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:retro_withdraw_vote, user_id, card_id}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    case Mixchamb.Retro.EphemeralState.withdraw_vote(rs, user_id, card_id) do
      {:ok, new_rs} ->
        tallies = Mixchamb.Retro.EphemeralState.tally(new_rs)
        broadcast_retro(state.slug, {:retro, :vote_withdrawn, user_id, card_id, tallies})
        {:noreply, %{state | retro_state: new_rs}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:retro_set_discussing, user_id, card_id_or_nil}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    if not MapSet.member?(state.hosts, user_id) do
      {:noreply, state}
    else
      case Mixchamb.Retro.EphemeralState.set_discussing(rs, card_id_or_nil) do
        {:ok, new_rs} ->
          broadcast_retro(state.slug, {:retro, :discussing, card_id_or_nil})
          {:noreply, %{state | retro_state: new_rs}}

        _ ->
          {:noreply, state}
      end
    end
  end

  def handle_cast({:retro_add_action_item, attrs}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    session = Mixchamb.Retro.load_session(rs.session_id)

    case Mixchamb.Retro.add_action_item(session, attrs) do
      {:ok, action} ->
        broadcast_retro(state.slug, {:retro, :action_added, action_to_wire(action)})

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_cast({:retro_update_action_item, action_id, attrs}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    session = Mixchamb.Retro.load_session(rs.session_id)
    action = Mixchamb.Retro.get_action_item(action_id)

    if action && action.retro_session_id == rs.session_id do
      case Mixchamb.Retro.update_action_item(action, attrs, session) do
        {:ok, updated} ->
          broadcast_retro(
            state.slug,
            {:retro, :action_updated, action_to_wire(updated)}
          )

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_cast({:retro_delete_action_item, action_id}, %{retro_state: rs} = state)
      when not is_nil(rs) do
    session = Mixchamb.Retro.load_session(rs.session_id)
    action = Mixchamb.Retro.get_action_item(action_id)

    if action && action.retro_session_id == rs.session_id do
      case Mixchamb.Retro.delete_action_item(action, session) do
        {:ok, _} ->
          broadcast_retro(state.slug, {:retro, :action_deleted, action.id})

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  # Retro fall-throughs when retro_state is nil (chamber isn't
  # in retro mode or hasn't started a session yet). Note no
  # fall-through for :retro_start_session — its primary handler
  # doesn't gate on retro_state, so it always matches.
  def handle_cast({:retro_set_title, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_set_brainstorm_visible, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_set_voting_enabled, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_rename_column, _, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_advance_phase, _}, state), do: {:noreply, state}
  def handle_cast({:retro_add_card, _, _, _, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_update_card, _, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_delete_card, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_vote, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_withdraw_vote, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_set_discussing, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_add_action_item, _}, state), do: {:noreply, state}
  def handle_cast({:retro_update_action_item, _, _}, state), do: {:noreply, state}
  def handle_cast({:retro_delete_action_item, _}, state), do: {:noreply, state}

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

    # Retro persists across activity switches (spec §9): when
    # flipping back to "retro" we re-hydrate the EphemeralState
    # from the live DB session if one exists; nil otherwise (the
    # LV's first host action creates a session). Switching away
    # clears the ephemeral struct but leaves the DB rows alone.
    retro_state =
      case activity do
        "retro" ->
          case Mixchamb.Retro.current_session(state.chamber_id) do
            nil ->
              nil

            session ->
              Mixchamb.Retro.EphemeralState.new(
                session.id,
                String.to_existing_atom(session.status)
              )
          end

        _ ->
          nil
      end

    Phoenix.PubSub.broadcast(
      Mixchamb.PubSub,
      Mixchamb.Chambers.topic(state.slug),
      {:activity_changed, activity}
    )

    {:noreply,
     %{state | activity: activity, poker_session: poker_session, retro_state: retro_state}}
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

  def handle_call(:retro_state, _from, state) do
    {:reply, state.retro_state, state}
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

  # Same shape as broadcast_poker. Retro events carry a leading
  # `:retro` tag so the LV's handle_info can route them.
  defp broadcast_retro(slug, message) do
    Phoenix.PubSub.broadcast(
      Mixchamb.PubSub,
      Mixchamb.Chambers.topic(slug),
      message
    )
  end

  # "Live" = non-nil EphemeralState pointing at a session that
  # hasn't been archived. The proactive archive path clears
  # retro_state to nil on phase exit, but stale state can survive
  # across code reloads of an already-archived chamber's
  # GenServer — this defensive check makes start_session recover
  # instead of staying stuck.
  defp live_retro_state?(nil), do: false
  defp live_retro_state?(%{phase: :archived}), do: false
  defp live_retro_state?(_), do: true

  # Wire-format helpers — strip Ecto struct metadata so broadcast
  # payloads are plain maps (cheap to encode for the LV → Vue
  # round trip).
  defp card_to_wire(card) do
    %{
      id: card.id,
      retro_column_id: card.retro_column_id,
      body: card.body,
      author_user_id: card.author_user_id,
      author_alias: card.author_alias,
      author_display_name: card.author_display_name,
      vote_count: card.vote_count
    }
  end

  defp action_to_wire(action) do
    %{
      id: action.id,
      source_card_id: action.source_card_id,
      body: action.body,
      assignee_alias: action.assignee_alias,
      due_date: action.due_date,
      completed: action.completed
    }
  end
end
