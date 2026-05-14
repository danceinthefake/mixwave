defmodule MixwaveWeb.ChamberLive do
  @moduledoc """
  The chamber view for a single chamber. Mounted at `/chamber/:slug`.

  On mount, looks up the chamber by slug. A missing or invalid
  slug pushes the user back to the landing page with a flash.
  Otherwise, ensures the chamber's GenServer is running and
  subscribes to its PubSub + presence topics.

  Wires:
    - `Mixwave.Chambers.subscribe/1` for note-event broadcasts on
      this chamber's topic
    - `MixwaveWeb.Presence` for "who's in this chamber, on what
      instrument"
    - 1-second server-side cooldown on instrument switch

  Instrument pads are Vue islands rendered inside a single
  `assets/vue/Chamber.vue` parent island. See that file for why
  pads aren't rendered as separate islands.
  """
  use MixwaveWeb, :live_view

  alias MixwaveWeb.Presence
  alias Mixwave.Chambers

  @instruments [:drums, :keyboard, :guitar, :bass, :pad, :suling, :kendang]
  @switch_cooldown_ms 1_000

  # Anti-flood guard on the `note` event. 20/sec/user is plenty of
  # headroom for human play (a fast drummer is ~10 hits/sec) and
  # caps automated spam decisively. Drops past the budget are
  # silent client-side; the server emits a telemetry event so the
  # admin Dashboard can show how many got shed.
  @note_rate_max 20
  @note_rate_window_ms 1_000

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Chambers.find_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Chamber not found or already closed.")
         |> push_navigate(to: ~p"/")}

      chamber ->
        mount_chamber(chamber, socket)
    end
  end

  defp mount_chamber(chamber, socket) do
    user = socket.assigns.current_user
    slug = chamber.slug

    # Make sure a Chamber GenServer exists for this slug so calls
    # into Mixwave.Chambers.* don't fail with :no_such_process. Safe
    # to call on every mount — idempotent if one is already up.
    {:ok, _pid} = Mixwave.Chambers.Server.ensure_started(slug, chamber.id)

    if connected?(socket) do
      Chambers.subscribe(slug)
      Phoenix.PubSub.subscribe(Mixwave.PubSub, presence_topic(slug))

      {:ok, _} =
        Presence.track(self(), presence_topic(slug), user.id, %{
          display_name: user.display_name,
          alias: user.alias,
          instrument: :drums,
          joined_at: System.system_time(:second)
        })
    end

    presences =
      if connected?(socket),
        do: Presence.list(presence_topic(slug)),
        else: %{}

    {:ok,
     socket
     |> assign(:chamber, chamber)
     |> assign(:chamber_slug, slug)
     |> assign(:page_title, page_title_for(chamber))
     |> assign(:instruments, @instruments)
     |> assign(:current_instrument, :drums)
     |> assign(:recorded_count, Chambers.recorded_event_count(chamber.id))
     # True between Stop Recording and either Download or Reset.
     # Drives a confirm dialog on Start Recording so the user
     # doesn't lose a recording they haven't saved yet.
     |> assign(:has_pending_audio, false)
     # Initialize so the first switch is never blocked. BEAM's
     # monotonic time can be a large negative integer at startup, so
     # `0` here would make the cooldown check (`now - last_switch_at`)
     # produce a negative result and reject every switch.
     |> assign(:last_switch_at, System.monotonic_time(:millisecond) - @switch_cooldown_ms)
     |> assign(:presences, presences)}
  end

  @impl true
  def handle_event("set_kind", %{"kind" => kind}, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    cond do
      chamber.creator_user_id != user.id ->
        # Only the creator may change the chamber's audio kind. The
        # picker isn't even rendered for non-creators; this guard
        # is for hand-crafted phx-events.
        {:noreply, socket}

      chamber.kind == kind ->
        # Already on this kind — skip the DB write + broadcast.
        {:noreply, socket}

      true ->
        case Chambers.set_kind(chamber, kind) do
          {:ok, updated} ->
            Phoenix.PubSub.broadcast(
              Mixwave.PubSub,
              Mixwave.Chambers.topic(chamber.slug),
              {:chamber_updated, updated}
            )

            {:noreply, assign(socket, :chamber, updated)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't change the chamber type.")}
        end
    end
  end

  @impl true
  def handle_event("save_title", %{"title" => title}, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    # Only the creator may rename. Anyone else is silently ignored —
    # the input isn't even rendered for them, so the only path here
    # is a hand-crafted phx-event push.
    if chamber.creator_user_id != user.id do
      {:noreply, socket}
    else
      case Chambers.set_title(chamber, title) do
        {:ok, updated} ->
          # Broadcast so anyone else in the chamber sees the new
          # title without reloading.
          Phoenix.PubSub.broadcast(
            Mixwave.PubSub,
            Mixwave.Chambers.topic(chamber.slug),
            {:chamber_updated, updated}
          )

          {:noreply,
           socket
           |> assign(:chamber, updated)
           |> assign(:page_title, page_title_for(updated))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't save the title.")}
      end
    end
  end

  @impl true
  def handle_event("request_replay", _params, socket) do
    events = Mixwave.Chambers.recent_events_within(socket.assigns.chamber_slug, 30)
    {:noreply, push_event(socket, "replay_burst", events_to_replay_payload(events))}
  end

  @impl true
  def handle_event("toggle_recording", _params, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    # Only the creator may toggle. Picker isn't rendered for
    # others, so the only path here is a hand-crafted phx-event.
    if chamber.creator_user_id != user.id do
      {:noreply, socket}
    else
      case Chambers.set_recording(chamber, !chamber.is_recording) do
        {:ok, updated} ->
          # Tell every subscribed client (including this LV) that
          # the chamber row changed — `handle_info({:chamber_updated, _})`
          # picks it up and re-renders the badge.
          Phoenix.PubSub.broadcast(
            Mixwave.PubSub,
            Mixwave.Chambers.topic(chamber.slug),
            {:chamber_updated, updated}
          )

          # Tell the creator's browser to start / stop tapping
          # Tone.Recorder so the live jam can be exported as audio.
          # push_event is per-socket, so only the creator (who
          # just clicked the toggle) sees these — non-creators
          # only get the chamber_updated broadcast.
          event_name =
            if updated.is_recording, do: "start_audio_capture", else: "stop_audio_capture"

          socket =
            socket
            |> push_event(event_name, %{})
            # Set the pending-audio flag based on the new state:
            # turning REC off means a blob is about to land (pending),
            # turning REC on means we just confirmed-and-replaced any
            # previous blob (no longer pending).
            |> assign(:has_pending_audio, not updated.is_recording)

          {:noreply, assign(socket, :chamber, updated)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't toggle recording.")}
      end
    end
  end

  @impl true
  def handle_event("reset_recording", _params, socket) do
    chamber = socket.assigns.chamber
    user = socket.assigns.current_user

    cond do
      chamber.creator_user_id != user.id ->
        {:noreply, socket}

      chamber.is_recording ->
        # Refuse while recording is still on — would race with the
        # GenServer's batched flush. The button isn't rendered
        # in this state; this guard catches hand-crafted events.
        {:noreply, put_flash(socket, :error, "Stop recording before resetting.")}

      true ->
        {_count, _} = Chambers.delete_recorded_events(chamber.id)

        {:noreply,
         socket
         |> assign(:recorded_count, 0)
         |> assign(:has_pending_audio, false)
         |> push_event("clear_audio_capture", %{})}
    end
  end

  @impl true
  def handle_event("audio_downloaded", _params, socket) do
    # Vue's downloadLastRecording sends this so the LV can clear
    # the pending-audio flag — the user has saved the file, so
    # the overwrite-confirm on Start Recording shouldn't fire.
    {:noreply, assign(socket, :has_pending_audio, false)}
  end

  @impl true
  def handle_event("play_recording", _params, socket) do
    chamber = socket.assigns.chamber
    events = Chambers.recorded_events(chamber.id)
    {:noreply, push_event(socket, "replay_burst", recorded_to_replay_payload(events))}
  end

  @impl true
  def handle_event("note", payload, socket) do
    user = socket.assigns.current_user
    slug = socket.assigns.chamber_slug

    case Mixwave.RateLimiter.hit(
           {:note, user.id, slug},
           @note_rate_max,
           @note_rate_window_ms
         ) do
      :ok ->
        payload
        |> Map.put("user_id", user.id)
        |> Map.put("display_name", user.display_name)
        |> Map.put("alias", user.alias)
        |> then(&Mixwave.Chambers.broadcast_note(slug, &1))

        {:noreply, socket}

      :rate_limited ->
        :telemetry.execute(
          [:mixwave, :chamber, :note_dropped],
          %{count: 1},
          %{slug: slug, user_id: user.id}
        )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_alias", %{"alias" => value}, socket) do
    user = socket.assigns.current_user
    slug = socket.assigns.chamber_slug

    case Mixwave.Accounts.set_alias(user, value) do
      {:ok, updated} ->
        # Re-track presence so other clients see the new alias
        # without needing to re-query the DB.
        Presence.update(self(), presence_topic(slug), updated.id, fn meta ->
          %{meta | alias: updated.alias}
        end)

        {:noreply, assign(socket, :current_user, updated)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Alias is too long (max 32 chars).")}
    end
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
        slug = socket.assigns.chamber_slug

        Presence.update(self(), presence_topic(slug), user.id, fn meta ->
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
    presences = Presence.list(presence_topic(socket.assigns.chamber_slug))

    {:noreply,
     socket
     |> assign(:presences, presences)
     |> maybe_mark_active(presences)}
  end

  # Sent by the chamber's GenServer when it deletes itself because
  # the 30-minute grace period elapsed without anyone but the
  # creator joining.
  def handle_info({:chamber_closed, _slug}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Chamber closed — nobody else joined within 30 minutes.")
     |> push_navigate(to: ~p"/")}
  end

  # Broadcast by the LV that wrote the title change. Everyone else
  # in the chamber updates their assigns + page title.
  def handle_info({:chamber_updated, updated}, socket) do
    # Refresh recorded_count too — a REC-off transition makes the
    # newly-finalised session available for replay, and we need
    # the count to enable the Play button + render its label.
    {:noreply,
     socket
     |> assign(:chamber, updated)
     |> assign(:page_title, page_title_for(updated))
     |> assign(:recorded_count, Chambers.recorded_event_count(updated.id))}
  end

  @impl true
  def handle_info({:chamber_note, event}, socket) do
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

  defp presence_topic(slug) when is_binary(slug), do: "chamber:#{slug}:presence"

  # Display helpers for the (alias, display_name) pair. The
  # auto-generated display_name is always shown somewhere; the
  # alias becomes the headline when set.
  defp alias_set?(%{alias: a}) when is_binary(a) and a != "", do: true
  defp alias_set?(_), do: false

  defp primary_name(%{alias: a} = _meta) when is_binary(a) and a != "", do: a
  defp primary_name(%{display_name: name}), do: name

  # Flips the chamber's `activated_at` from NULL to a timestamp
  # the first time someone other than the creator is present.
  # Idempotent: a no-op once the chamber is already active.
  defp maybe_mark_active(socket, presences) do
    chamber = socket.assigns.chamber

    cond do
      chamber.activated_at != nil ->
        socket

      non_creator_present?(presences, chamber) ->
        case Chambers.mark_active(chamber) do
          {:ok, updated} -> assign(socket, :chamber, updated)
          {:error, _} -> socket
        end

      true ->
        socket
    end
  end

  defp non_creator_present?(presences, chamber) do
    Enum.any?(presences, fn {user_id, _meta} ->
      user_id != chamber.creator_user_id
    end)
  end

  ## Replay helpers

  # Trim the stored event buffer down to just the fields the Vue side
  # needs, with offsets relative to the first event so the client can
  # schedule them via setTimeout from "now."
  defp events_to_replay_payload([]), do: %{events: []}

  defp events_to_replay_payload([first | _] = events) do
    start_at = first.at

    events_payload =
      Enum.map(events, fn e ->
        replay_event(e.payload, e.at - start_at)
      end)

    %{events: events_payload}
  end

  # Same shape as `events_to_replay_payload/1` but starts from a
  # list of `Chambers.ChamberEvent` rows — these use absolute
  # `inserted_at` timestamps, so offsets are computed against the
  # first row's timestamp instead of monotonic time.
  defp recorded_to_replay_payload([]), do: %{events: []}

  defp recorded_to_replay_payload([first | _] = rows) do
    start_at = first.inserted_at

    events_payload =
      Enum.map(rows, fn row ->
        offset_ms = DateTime.diff(row.inserted_at, start_at, :millisecond)
        replay_event(row.payload, offset_ms)
      end)

    %{events: events_payload}
  end

  defp replay_event(payload, offset_ms) do
    %{
      instrument: payload["instrument"],
      style: payload["style"] || "synth",
      note: payload["note"],
      chord: payload["chord"],
      octave_offset: payload["octave_offset"] || 0,
      phase: payload["phase"],
      up_strum: payload["up_strum"],
      offset_ms: offset_ms
    }
  end

  ## Render helpers

  defp instrument_label(:drums), do: "Drums"
  defp instrument_label(:keyboard), do: "Keyboard"
  defp instrument_label(:guitar), do: "Guitar"
  defp instrument_label(:bass), do: "Bass"
  defp instrument_label(:pad), do: "Pad"
  defp instrument_label(:suling), do: "Suling"
  defp instrument_label(:kendang), do: "Kendang"

  # Static class strings per instrument so Tailwind picks them up at
  # build time. Uses the per-instrument neon variables defined in
  # app.css. Tailwind can't synthesize these from a runtime string.
  defp active_tab_class(:drums), do: "bg-accent-drums/15 text-accent-drums"
  defp active_tab_class(:keyboard), do: "bg-accent-keyboard/15 text-accent-keyboard"
  defp active_tab_class(:guitar), do: "bg-accent-guitar/15 text-accent-guitar"
  defp active_tab_class(:bass), do: "bg-accent-bass/15 text-accent-bass"
  defp active_tab_class(:pad), do: "bg-accent-pad/15 text-accent-pad"
  defp active_tab_class(:suling), do: "bg-accent-suling/15 text-accent-suling"
  defp active_tab_class(:kendang), do: "bg-accent-kendang/15 text-accent-kendang"

  defp accent_var(:drums), do: "var(--accent-drums)"
  defp accent_var(:keyboard), do: "var(--accent-keyboard)"
  defp accent_var(:guitar), do: "var(--accent-guitar)"
  defp accent_var(:bass), do: "var(--accent-bass)"
  defp accent_var(:pad), do: "var(--accent-pad)"
  defp accent_var(:suling), do: "var(--accent-suling)"
  defp accent_var(:kendang), do: "var(--accent-kendang)"

  # Full URL the creator can copy + paste anywhere. Built from the
  # endpoint's configured host so the link works regardless of
  # whether the user is on localhost, a staging URL, or prod.
  defp chamber_url(chamber) do
    MixwaveWeb.Endpoint.url() <> "/chamber/" <> chamber.slug
  end

  # Whether to show the creator-only invite-link banner. True iff
  # the current user IS the creator AND the chamber hasn't been
  # activated yet (i.e., still in the 30-minute grace window).
  defp show_invite_banner?(chamber, current_user) do
    chamber.activated_at == nil and chamber.creator_user_id == current_user.id
  end

  defp creator?(chamber, current_user), do: chamber.creator_user_id == current_user.id

  # Order matters — drives chip render order. From driest to wettest
  # so the picker reads as a "spectrum" left-to-right.
  @chamber_kinds ~w(vacuum anechoic room live hall cathedral plate spring echo)
  defp chamber_kinds, do: @chamber_kinds

  defp chamber_kind_label("vacuum"), do: "Vacuum"
  defp chamber_kind_label("anechoic"), do: "Anechoic"
  defp chamber_kind_label("room"), do: "Room"
  defp chamber_kind_label("live"), do: "Live"
  defp chamber_kind_label("hall"), do: "Hall"
  defp chamber_kind_label("cathedral"), do: "Cathedral"
  defp chamber_kind_label("plate"), do: "Plate"
  defp chamber_kind_label("spring"), do: "Spring"
  defp chamber_kind_label("echo"), do: "Echo"

  defp chamber_kind_blurb("vacuum"), do: "Raw signal, no FX"
  defp chamber_kind_blurb("anechoic"), do: "No room, instrument FX kept"
  defp chamber_kind_blurb("room"), do: "Small, present"
  defp chamber_kind_blurb("live"), do: "Warm, lush"
  defp chamber_kind_blurb("hall"), do: "Big, sustained"
  defp chamber_kind_blurb("cathedral"), do: "Vast, ethereal"
  defp chamber_kind_blurb("plate"), do: "Bright, vintage"
  defp chamber_kind_blurb("spring"), do: "Boingy, lo-fi"
  defp chamber_kind_blurb("echo"), do: "Discrete repeats"

  # Display title or fallback. Used both in the page <title> and
  # the heading above the stage.
  defp display_title(%{title: nil, slug: slug}), do: "Untitled chamber · #{slug}"
  defp display_title(%{title: title}), do: title

  defp page_title_for(chamber), do: "#{display_title(chamber)} · mixwave"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} banner={assigns[:banner]} draining?={assigns[:draining?] || false}>
      <%!-- Break out of Layouts.app's max-w-3xl + py-10. The chamber
           uses the full available width as a stage; the dock floats
           at the bottom of the viewport. --%>
      <%!-- Bottom padding clears the floating dock + the iOS
           home-indicator gesture area. `env(safe-area-inset-bottom)`
           is 0 on devices without a notch / home bar. --%>
      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 pt-4 pb-[calc(7rem+env(safe-area-inset-bottom))]">
        <div class="mx-auto max-w-5xl space-y-4">
          <%!-- Leave-chamber back link. Small + subtle so it
               doesn't compete with the controls; navigates back
               to the landing page. --%>
          <div>
            <.link
              navigate={~p"/"}
              class="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              <.icon name="hero-arrow-left-mini" class="size-3.5" /> Leave chamber
            </.link>
          </div>

          <%!-- Title heading. The creator gets an inline form that
               renames the chamber on submit (Enter / blur); other
               users see a static heading. The fallback when no
               title is set shows the slug so the placeholder still
               feels chamber-specific. --%>
          <div>
            <%= if creator?(@chamber, @current_user) do %>
              <form phx-submit="save_title" class="flex items-baseline gap-2">
                <input
                  type="text"
                  name="title"
                  value={@chamber.title || ""}
                  maxlength="80"
                  placeholder={"Untitled chamber · " <> @chamber.slug}
                  class="flex-1 bg-transparent border-none outline-none text-2xl font-bold tracking-tight font-display text-foreground placeholder:text-muted-foreground/50"
                />
                <%!-- The hint is just clutter on mobile, where on-screen
                     keyboards already show their own submit affordance. --%>
                <span class="hidden sm:inline text-[10px] uppercase tracking-wider text-muted-foreground/60">
                  Press enter to save
                </span>
              </form>
            <% else %>
              <h1 class="text-2xl font-bold tracking-tight font-display">
                {display_title(@chamber)}
              </h1>
            <% end %>
          </div>

          <%!-- Chamber kind. Creator gets a chip-strip to switch
               between presets; everyone else sees a single chip
               showing what's active. Changes ripple via the
               :chamber_updated broadcast so the FX bus on every
               client retunes within ~100 ms. --%>
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs uppercase tracking-wider text-muted-foreground mr-1">
              Kind
            </span>
            <%= if creator?(@chamber, @current_user) do %>
              <button
                :for={kind <- chamber_kinds()}
                phx-click="set_kind"
                phx-value-kind={kind}
                title={chamber_kind_blurb(kind)}
                class={[
                  "px-3 py-1 text-xs rounded-md border transition-colors cursor-pointer",
                  @chamber.kind == kind &&
                    "bg-primary/15 text-primary border-primary/40",
                  @chamber.kind != kind &&
                    "bg-card hover:bg-accent text-muted-foreground border-input"
                ]}
              >
                {chamber_kind_label(kind)}
              </button>
            <% else %>
              <span
                class="inline-flex items-center gap-1 px-3 py-1 text-xs rounded-md border bg-card text-foreground"
                title={chamber_kind_blurb(@chamber.kind)}
              >
                {chamber_kind_label(@chamber.kind)}
                <span class="text-muted-foreground">
                  · {chamber_kind_blurb(@chamber.kind)}
                </span>
              </span>
            <% end %>
          </div>

          <%!-- Recording controls. Creator gets a REC toggle.
               Everyone sees the live REC badge while recording is
               on, and a "Play recording" button once there's at
               least one persisted event. --%>
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs uppercase tracking-wider text-muted-foreground mr-1">
              Recording
            </span>

            <button
              :if={creator?(@chamber, @current_user)}
              phx-click="toggle_recording"
              data-confirm={
                if not @chamber.is_recording and @has_pending_audio,
                  do:
                    "Starting a new recording will replace the current audio file (it hasn't been downloaded). Continue?"
              }
              type="button"
              class={[
                "inline-flex items-center gap-1.5 px-3 py-1 text-xs rounded-md border transition-colors cursor-pointer",
                @chamber.is_recording &&
                  "bg-red-500/15 text-red-500 border-red-500/40 hover:bg-red-500/20",
                !@chamber.is_recording &&
                  "bg-card hover:bg-accent text-muted-foreground border-input"
              ]}
              title={
                if @chamber.is_recording,
                  do: "Click to stop recording",
                  else: "Click to start recording"
              }
            >
              <span class={[
                "size-2 rounded-full",
                @chamber.is_recording && "bg-red-500 animate-pulse",
                !@chamber.is_recording && "bg-muted-foreground/40"
              ]}>
              </span>
              {if @chamber.is_recording, do: "REC · click to stop", else: "Start recording"}
            </button>

            <%!-- Non-creator live badge — visible only while
                 recording is on. Mirrors the creator's button
                 style minus the click affordance. --%>
            <span
              :if={!creator?(@chamber, @current_user) and @chamber.is_recording}
              class="inline-flex items-center gap-1.5 px-3 py-1 text-xs rounded-md border bg-red-500/15 text-red-500 border-red-500/40"
            >
              <span class="size-2 rounded-full bg-red-500 animate-pulse"></span> REC
            </span>

            <%!-- Play recording — anyone. Shown only when there's
                 something to replay and recording is currently off
                 (so we don't double-stack a live jam with a replay
                 of the same jam). --%>
            <button
              :if={@recorded_count > 0 and not @chamber.is_recording}
              phx-click="play_recording"
              type="button"
              class="inline-flex items-center gap-1.5 px-3 py-1 text-xs rounded-md border bg-card hover:bg-accent text-foreground border-input cursor-pointer transition-colors"
              title={"Replay all #{@recorded_count} recorded notes"}
            >
              <.icon name="hero-play-mini" class="size-3.5" /> Play recording
              <span class="text-muted-foreground tabular-nums">· {@recorded_count}</span>
            </button>

            <%!-- Reset recording — creator-only. Wipes the persisted
                 events for this chamber and tells the client to
                 drop its captured audio blob. Disabled while
                 recording is on (would race with the GenServer's
                 batched flush). --%>
            <button
              :if={
                creator?(@chamber, @current_user) and @recorded_count > 0 and
                  not @chamber.is_recording
              }
              phx-click="reset_recording"
              data-confirm="Delete the saved recording for this chamber? This can't be undone."
              type="button"
              class="inline-flex items-center gap-1.5 px-3 py-1 text-xs rounded-md border bg-card hover:bg-destructive/10 hover:text-destructive hover:border-destructive/40 text-muted-foreground border-input cursor-pointer transition-colors"
              title="Delete this chamber's recorded events"
            >
              <.icon name="hero-trash-mini" class="size-3.5" /> Reset recording
            </button>
          </div>

          <%!-- Creator-only invite banner. Shows the chamber's
               shareable URL with a copy button while the chamber
               is still in its 30-minute grace window — disappears
               the moment somebody else joins (chamber.activated_at
               flips). Other users coming in via the link never see
               it. --%>
          <div
            :if={show_invite_banner?(@chamber, @current_user)}
            class="rounded-xl border bg-card/80 backdrop-blur-sm p-4 sm:p-5 space-y-3"
          >
            <div class="flex items-start gap-3">
              <.icon name="hero-link-mini" class="size-5 mt-0.5 text-muted-foreground" />
              <div class="space-y-1 flex-1">
                <h3 class="text-sm font-semibold tracking-tight font-display">
                  Share this chamber
                </h3>
                <p class="text-xs text-muted-foreground">
                  Anyone with the link can join. The chamber closes on its own if nobody else shows up within 30 minutes.
                </p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <code class="flex-1 truncate rounded-md bg-muted px-3 py-2 text-xs font-mono text-foreground">
                {chamber_url(@chamber)}
              </code>
              <button
                type="button"
                id="chamber-copy-link"
                phx-hook="CopyToClipboard"
                phx-update="ignore"
                data-copy-url={chamber_url(@chamber)}
                class="rounded-md border bg-card hover:bg-accent px-3 py-2 text-xs font-medium transition-colors cursor-pointer whitespace-nowrap"
              >
                Copy link
              </button>
            </div>
          </div>

          <%!-- One live_vue island for the whole chamber. Vue handles
               the v-if swap between pads internally — see Chamber.vue
               for why we don't use three separate islands. --%>
          <.Chamber
            current_instrument={Atom.to_string(@current_instrument)}
            chamber_kind={@chamber.kind}
            chamber_title={@chamber.title}
            chamber_slug={@chamber.slug}
          />
        </div>
      </div>

      <%!-- Always-visible jammer panel on the right edge. No toggle,
           so usernames are present without any user interaction.
           Hidden below lg because the chamber pads need that
           horizontal room on tablet / mobile — the dock's presence
           summary at the bottom is the fallback there. --%>
      <aside class="hidden lg:block fixed right-4 top-24 w-56 z-30">
        <div class="rounded-xl border bg-card/80 backdrop-blur-md shadow-lg">
          <div class="flex items-center justify-between px-3 py-2 border-b">
            <span class="text-xs font-semibold uppercase tracking-wider font-display">
              Jamming
            </span>
            <span class="text-xs text-muted-foreground tabular-nums">
              {map_size(@presences)}
            </span>
          </div>
          <ul class="max-h-[60vh] overflow-y-auto py-1">
            <li
              :for={{user_id, %{metas: [meta | _]}} <- @presences}
              class={[
                "flex items-start gap-2 px-3 py-1.5 text-sm",
                user_id == @current_user.id && "bg-primary/5"
              ]}
            >
              <span
                class="size-2 rounded-full shrink-0 mt-2"
                style={"background-color: " <> accent_var(meta.instrument)}
              >
              </span>
              <div class="flex-1 min-w-0">
                <%!-- Primary line: the alias if set, else the
                     auto-generated noun-adj-NN name. --%>
                <div class={[
                  "truncate leading-tight",
                  user_id == @current_user.id && "font-semibold text-foreground",
                  user_id != @current_user.id && "text-foreground"
                ]}>
                  {primary_name(meta)}
                  <span :if={user_id == @current_user.id} class="text-muted-foreground font-normal">
                    (you)
                  </span>
                </div>
                <%!-- Secondary line: the anon name whenever an
                     alias is present (so the auto-generated
                     identifier never disappears), with the
                     instrument label trailing. --%>
                <div class="text-[11px] text-muted-foreground leading-tight truncate font-mono">
                  <span :if={alias_set?(meta)}>{meta.display_name} · </span>{instrument_label(
                    meta.instrument
                  )}
                </div>
              </div>
            </li>
          </ul>
          <%!-- Inline alias editor for the current user. Submits on
               Enter or blur; empty input clears the alias. Lives at
               the bottom of the panel so it's always reachable. --%>
          <form
            phx-submit="set_alias"
            phx-change="set_alias"
            class="border-t p-2"
            id="alias-editor"
            phx-update="ignore"
          >
            <label class="block text-[10px] uppercase tracking-wider text-muted-foreground mb-1 px-1">
              Your alias
            </label>
            <input
              type="text"
              name="alias"
              value={@current_user.alias || ""}
              maxlength="32"
              placeholder="Set a nickname…"
              phx-debounce="600"
              class="w-full bg-transparent border border-input rounded-md px-2 py-1 text-xs outline-none focus:border-primary/60"
            />
            <p class="text-[10px] text-muted-foreground mt-1 px-1">
              Shown above {@current_user.display_name}. Empty to clear.
            </p>
          </form>
        </div>
      </aside>

      <%!-- Floating dock: instrument switcher + presence summary.
           Fixed at the viewport's bottom edge so it stays in reach
           regardless of page scroll. `pointer-events-none` on the
           outer wrapper lets clicks pass through the empty area
           around the dock to whatever is behind it. --%>
      <%!-- Dock floats just above the bottom edge — `max(...)` keeps
           it 1rem off the bottom on a flat-bottomed device and
           lifts it above the iOS home-indicator on a notched one. --%>
      <div class="fixed inset-x-0 bottom-[max(1rem,env(safe-area-inset-bottom))] px-4 z-40 pointer-events-none">
        <div class="mx-auto max-w-3xl pointer-events-auto">
          <div class="flex items-center gap-2 rounded-2xl border bg-card/80 backdrop-blur-md px-2 py-1.5 shadow-2xl">
            <%!-- Instrument switcher tabs --%>
            <div class="flex items-center gap-1 flex-1 overflow-x-auto">
              <button
                :for={inst <- @instruments}
                phx-click="switch_instrument"
                phx-value-to={inst}
                class={[
                  "pad-touch touch-manipulation px-3 py-1.5 text-sm rounded-lg transition-all flex items-center gap-1.5 whitespace-nowrap cursor-pointer",
                  @current_instrument == inst && active_tab_class(inst),
                  @current_instrument != inst &&
                    "text-muted-foreground hover:bg-accent hover:text-foreground"
                ]}
                title={instrument_label(inst)}
              >
                <span
                  class="size-2 rounded-full opacity-80"
                  style={"background-color: " <> accent_var(inst)}
                >
                </span>
                <%!-- On mobile, only the active tab keeps its
                     label; the rest collapse to a dot so all 7
                     fit without horizontal scroll. --%>
                <span class={[@current_instrument != inst && "hidden sm:inline"]}>
                  {instrument_label(inst)}
                </span>
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
                  title={"#{primary_name(meta)}#{if alias_set?(meta), do: " · " <> meta.display_name, else: ""} · #{instrument_label(meta.instrument)}"}
                >
                  {primary_name(meta) |> String.first() |> String.upcase()}
                </span>
              </div>
              <%!-- Just the count on mobile, full "N jamming" on
                   sm+ where the dock has room for both. --%>
              <span class="text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                {map_size(@presences)}<span class="hidden sm:inline">{" jamming"}</span>
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
