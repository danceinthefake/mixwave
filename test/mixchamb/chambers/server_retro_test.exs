defmodule Mixchamb.Chambers.ServerRetroTest do
  use Mixchamb.DataCase, async: false

  alias Mixchamb.{Accounts, Chambers, Retro}
  alias Mixchamb.Chambers.Server

  setup do
    {:ok, host} = Accounts.create_anonymous_user()
    {:ok, other} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(host.id, "retro")
    {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
    Phoenix.PubSub.subscribe(Mixchamb.PubSub, Chambers.topic(chamber.slug))

    on_exit(fn ->
      try do
        GenServer.stop(Server.via(chamber.slug))
      catch
        :exit, _ -> :ok
      end
    end)

    %{host: host, other: other, chamber: chamber}
  end

  describe "retro_start_session/2" do
    test "host can start a session, non-host can't", %{host: host, other: other, chamber: chamber} do
      Server.retro_start_session(chamber.slug, other.id)
      refute_receive {:retro, :session_started, _}, 100

      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _session_id}, 500

      # Idempotent — second call no-ops.
      Server.retro_start_session(chamber.slug, host.id)
      refute_receive {:retro, :session_started, _}, 100
    end
  end

  describe "host-gated actions" do
    setup %{chamber: chamber, host: host} do
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _}, 500
      :ok
    end

    test "retro_set_title broadcasts title_changed", %{chamber: chamber, host: host} do
      Server.retro_set_title(chamber.slug, host.id, "Sprint 23 retro")
      assert_receive {:retro, :title_changed, "Sprint 23 retro"}, 500
    end

    test "retro_set_voting_enabled broadcasts the new value", %{chamber: chamber, host: host} do
      Server.retro_set_voting_enabled(chamber.slug, host.id, true)
      assert_receive {:retro, :voting_enabled_changed, true}, 500
    end

    test "retro_set_brainstorm_visible broadcasts the new value during :setup",
         %{chamber: chamber, host: host} do
      Server.retro_set_brainstorm_visible(chamber.slug, host.id, true)
      assert_receive {:retro, :brainstorm_visible_changed, true}, 500
    end

    test "retro_set_brainstorm_visible rejected by non-host", %{chamber: chamber, other: other} do
      Server.retro_set_brainstorm_visible(chamber.slug, other.id, true)
      refute_receive {:retro, :brainstorm_visible_changed, _}, 100
    end

    test "retro_rename_column broadcasts column_renamed", %{chamber: chamber, host: host} do
      session = Retro.current_session(chamber.id) |> then(&Retro.load_session(&1.id))
      [col | _] = session.columns
      col_id = col.id

      Server.retro_rename_column(chamber.slug, host.id, col_id, "Liked")
      assert_receive {:retro, :column_renamed, ^col_id, "Liked"}, 500
    end

    test "non-host cannot advance phase", %{chamber: chamber, other: other} do
      Server.retro_advance_phase(chamber.slug, other.id)
      refute_receive {:retro, :phase_changed, _}, 100
    end
  end

  describe "phase machine via casts" do
    setup %{chamber: chamber, host: host} do
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _}, 500
      :ok
    end

    test "advance walks setup → brainstorm → reveal → discuss (voting off)",
         %{chamber: chamber, host: host} do
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :brainstorm}, 500

      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :reveal}, 500

      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :discuss}, 500

      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :archived}, 500
    end

    test "with voting enabled, reveal advances to voting then discuss",
         %{chamber: chamber, host: host} do
      Server.retro_set_voting_enabled(chamber.slug, host.id, true)
      assert_receive {:retro, :voting_enabled_changed, true}, 500

      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :brainstorm}, 500
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :reveal}, 500
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :voting}, 500
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :discuss}, 500
    end
  end

  describe "voting" do
    setup %{chamber: chamber, host: host} do
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _}, 500
      Server.retro_set_voting_enabled(chamber.slug, host.id, true)
      assert_receive {:retro, :voting_enabled_changed, true}, 500
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :brainstorm}, 500

      # Seed two cards so we have targets to vote on.
      session = Retro.current_session(chamber.id) |> then(&Retro.load_session(&1.id))
      [col | _] = session.columns

      Server.retro_add_card(chamber.slug, host.id, col.id, "Pairing helped", "host-alias", "host-display")
      assert_receive {:retro, :card_added, card1}, 500

      Server.retro_add_card(chamber.slug, host.id, col.id, "Slow CI", "host-alias", "host-display")
      assert_receive {:retro, :card_added, card2}, 500

      # Advance to :voting
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :reveal}, 500
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :voting}, 500

      %{card1: card1, card2: card2}
    end

    test "vote broadcasts vote_cast with current tallies",
         %{chamber: chamber, host: host, other: other, card1: card1} do
      Server.retro_vote(chamber.slug, host.id, card1.id)
      assert_receive {:retro, :vote_cast, _user_id, _card_id, tallies}, 500
      assert tallies[card1.id] == 1

      Server.retro_vote(chamber.slug, other.id, card1.id)
      assert_receive {:retro, :vote_cast, _, _, tallies2}, 500
      assert tallies2[card1.id] == 2
    end

    test "advance from :voting → :discuss materialises vote counts on cards",
         %{chamber: chamber, host: host, other: other, card1: card1, card2: card2} do
      Server.retro_vote(chamber.slug, host.id, card1.id)
      assert_receive {:retro, :vote_cast, _, _, _}, 500
      Server.retro_vote(chamber.slug, other.id, card1.id)
      assert_receive {:retro, :vote_cast, _, _, _}, 500
      Server.retro_vote(chamber.slug, other.id, card2.id)
      assert_receive {:retro, :vote_cast, _, _, _}, 500

      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :discuss}, 500

      # Counts materialised onto the cards.
      assert Retro.get_card(card1.id).vote_count == 2
      assert Retro.get_card(card2.id).vote_count == 1
    end

    test "voting toggle off mid-voting discards votes + auto-advances to discuss",
         %{chamber: chamber, host: host, card1: card1} do
      Server.retro_vote(chamber.slug, host.id, card1.id)
      assert_receive {:retro, :vote_cast, _, _, _}, 500

      Server.retro_set_voting_enabled(chamber.slug, host.id, false)
      assert_receive {:retro, :voting_enabled_changed, false}, 500
      assert_receive {:retro, :phase_changed, :discuss}, 500

      # Votes were discarded — no materialisation.
      assert Retro.get_card(card1.id).vote_count == 0
    end
  end

  describe "action items" do
    setup %{chamber: chamber, host: host} do
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _}, 500

      # Walk to :discuss
      Enum.each([:brainstorm, :reveal, :discuss], fn phase ->
        Server.retro_advance_phase(chamber.slug, host.id)
        assert_receive {:retro, :phase_changed, ^phase}, 500
      end)

      :ok
    end

    test "add + update + delete cycle", %{chamber: chamber, host: host} do
      Server.retro_add_action_item(chamber.slug, %{
        body: "Talk to design",
        created_by_user_id: host.id
      })

      assert_receive {:retro, :action_added, action}, 500
      assert action.body == "Talk to design"

      Server.retro_update_action_item(chamber.slug, action.id, %{completed: true})
      assert_receive {:retro, :action_updated, %{completed: true}}, 500

      Server.retro_delete_action_item(chamber.slug, action.id)
      assert_receive {:retro, :action_deleted, _}, 500
    end
  end

  describe "card lifecycle through casts" do
    setup %{chamber: chamber, host: host} do
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _}, 500
      Server.retro_advance_phase(chamber.slug, host.id)
      assert_receive {:retro, :phase_changed, :brainstorm}, 500

      session = Retro.current_session(chamber.id) |> then(&Retro.load_session(&1.id))
      [col | _] = session.columns
      %{column: col}
    end

    test "add + edit + delete by author", %{chamber: chamber, host: host, column: col} do
      Server.retro_add_card(chamber.slug, host.id, col.id, "Pairing helped", "host-alias", "host-display")
      assert_receive {:retro, :card_added, card}, 500
      card_id = card.id

      Server.retro_update_card(chamber.slug, host.id, card_id, "Pairing helped a lot")
      assert_receive {:retro, :card_edited, ^card_id, "Pairing helped a lot"}, 500

      Server.retro_delete_card(chamber.slug, host.id, card_id)
      assert_receive {:retro, :card_deleted, ^card_id}, 500
    end

    test "non-author edit is silently dropped", %{
      chamber: chamber,
      host: host,
      other: other,
      column: col
    } do
      Server.retro_add_card(chamber.slug, host.id, col.id, "x", "host-alias", "host-display")
      assert_receive {:retro, :card_added, card}, 500

      Server.retro_update_card(chamber.slug, other.id, card.id, "evil edit")
      refute_receive {:retro, :card_edited, _, _}, 100
    end
  end

  describe "start → archive → start round-trip" do
    test "host can start a new session after archiving the previous one",
         %{chamber: chamber, host: host} do
      # Start the first session.
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, first_id}, 500

      # Walk it all the way to :archived (4 advances, voting off).
      Enum.each([:brainstorm, :reveal, :discuss, :archived], fn phase ->
        Server.retro_advance_phase(chamber.slug, host.id)
        assert_receive {:retro, :phase_changed, ^phase}, 500
      end)

      # GenServer should have cleared retro_state on archive so a
      # new start_session works.
      assert Server.retro_state(chamber.slug) == nil
      assert Retro.current_session(chamber.id) == nil

      # Start a fresh session — different id from the archived one.
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, second_id}, 500
      assert second_id != first_id

      # Confirm the new session is live + in :setup.
      assert %_{status: "setup", id: ^second_id} = Retro.current_session(chamber.id)
    end

    test "recovers if retro_state is stale (phase: :archived) — defensive",
         %{chamber: chamber, host: host} do
      # Simulate the bug: an existing chamber GenServer whose state
      # still carries an EphemeralState with phase :archived (the
      # situation after hot-reload of an already-archived chamber).
      # Build a real archived session in the DB so current_session
      # returns nil — then poke the GenServer state directly.
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _first_id}, 500

      Enum.each([:brainstorm, :reveal, :discuss, :archived], fn phase ->
        Server.retro_advance_phase(chamber.slug, host.id)
        assert_receive {:retro, :phase_changed, ^phase}, 500
      end)

      # After my proactive fix, retro_state is nil here. Reach into
      # the GenServer and re-stash an archived ephemeral struct to
      # simulate the pre-fix state.
      :sys.replace_state(Server.via(chamber.slug), fn s ->
        archived =
          Mixchamb.Retro.EphemeralState.new(Ecto.UUID.generate(), :archived)

        %{s | retro_state: archived}
      end)

      assert match?(%{phase: :archived}, Server.retro_state(chamber.slug))

      # The defensive guard should treat archived as "no live
      # session" and let a new one start.
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _second_id}, 500
      assert match?(%{phase: :setup}, Server.retro_state(chamber.slug))
    end
  end

  describe "activity switch" do
    test "switching away then back rehydrates retro_state from DB",
         %{chamber: chamber, host: host} do
      Server.retro_start_session(chamber.slug, host.id)
      assert_receive {:retro, :session_started, _}, 500

      # Switch to music — retro_state should go nil but session row stays.
      Server.set_activity(chamber.slug, "music")
      assert_receive {:activity_changed, "music"}, 500
      assert Server.retro_state(chamber.slug) == nil

      # Persisted session still exists in DB.
      assert %_{} = Retro.current_session(chamber.id)

      # Switch back to retro — retro_state should be re-hydrated.
      Server.set_activity(chamber.slug, "retro")
      assert_receive {:activity_changed, "retro"}, 500
      rs = Server.retro_state(chamber.slug)
      assert rs != nil
      assert rs.phase == :setup
    end
  end
end
