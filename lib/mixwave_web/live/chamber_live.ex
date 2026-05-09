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

  @instruments [:drums, :keyboard, :guitar, :bass, :pad]
  @switch_cooldown_ms 1_000

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
  def handle_event("note", payload, socket) do
    user = socket.assigns.current_user

    payload
    |> Map.put("user_id", user.id)
    |> Map.put("display_name", user.display_name)
    |> then(&Mixwave.Chambers.broadcast_note(socket.assigns.chamber_slug, &1))

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
  # the 5-minute grace period elapsed without anyone but the
  # creator joining.
  def handle_info({:chamber_closed, _slug}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Chamber closed — nobody else joined within 5 minutes.")
     |> push_navigate(to: ~p"/")}
  end

  # Broadcast by the LV that wrote the title change. Everyone else
  # in the chamber updates their assigns + page title.
  def handle_info({:chamber_updated, updated}, socket) do
    {:noreply,
     socket
     |> assign(:chamber, updated)
     |> assign(:page_title, page_title_for(updated))}
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
        %{
          instrument: e.payload["instrument"],
          style: e.payload["style"] || "synth",
          note: e.payload["note"],
          chord: e.payload["chord"],
          octave_offset: e.payload["octave_offset"] || 0,
          phase: e.payload["phase"],
          up_strum: e.payload["up_strum"],
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

  # Full URL the creator can copy + paste anywhere. Built from the
  # endpoint's configured host so the link works regardless of
  # whether the user is on localhost, a staging URL, or prod.
  defp chamber_url(chamber) do
    MixwaveWeb.Endpoint.url() <> "/chamber/" <> chamber.slug
  end

  # Whether to show the creator-only invite-link banner. True iff
  # the current user IS the creator AND the chamber hasn't been
  # activated yet (i.e., still in the 5-minute grace window).
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
    <Layouts.app flash={@flash}>
      <%!-- Break out of Layouts.app's max-w-3xl + py-10. The chamber
           uses the full available width as a stage; the dock floats
           at the bottom of the viewport. --%>
      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 pt-4 pb-28">
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
                <span class="text-[10px] uppercase tracking-wider text-muted-foreground/60">
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

          <%!-- Creator-only invite banner. Shows the chamber's
               shareable URL with a copy button while the chamber
               is still in its 5-minute grace window — disappears
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
                  Anyone with the link can join. The chamber closes on its own if nobody else shows up within 5 minutes.
                </p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <code
                class="flex-1 truncate rounded-md bg-muted px-3 py-2 text-xs font-mono text-foreground"
              >
                {chamber_url(@chamber)}
              </code>
              <button
                type="button"
                class="rounded-md border bg-card hover:bg-accent px-3 py-2 text-xs font-medium transition-colors cursor-pointer whitespace-nowrap"
                data-url={chamber_url(@chamber)}
                onclick="navigator.clipboard.writeText(this.dataset.url).then(() => { const o = this.textContent; this.textContent = 'Copied!'; setTimeout(() => { this.textContent = o; }, 1500); })"
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
          />
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
