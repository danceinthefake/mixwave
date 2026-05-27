defmodule MixchambWeb.RetroLive do
  @moduledoc """
  Permanent read-only view of an archived retrospective. Mounted
  at `/archives/retros/:id`. Decoupled from any chamber GenServer (the
  chamber may have been reaped); just loads the session from
  Postgres and renders the Vue board in archived mode.
  """
  use MixchambWeb, :live_view

  alias Mixchamb.Retro

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Retro.get_archived_by_id(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Retro not found, or it isn't archived yet.")
         |> push_navigate(to: ~p"/")}

      session ->
        {:ok,
         socket
         |> assign(:retro_session, session)
         |> assign(:page_title, page_title_for(session))}
    end
  end

  defp page_title_for(session) do
    base = session.title || session.chamber_title_snapshot || "Retro"
    "#{base} · mixchamb"
  end

  # Shape the persisted session into the wire format RetroBoard
  # expects. Identical to ChamberLive's retro_view but resolved
  # here to keep the two LVs decoupled (RetroLive doesn't depend
  # on ChamberLive). due_date → ISO string for JSON.
  defp retro_view(session) do
    %{
      id: session.id,
      title: session.title,
      status: session.status,
      voting_enabled: session.voting_enabled,
      brainstorm_visible: session.brainstorm_visible,
      columns:
        Enum.map(session.columns, fn col ->
          %{id: col.id, name: col.name, position: col.position}
        end),
      cards:
        Enum.map(session.cards, fn card ->
          %{
            id: card.id,
            retro_column_id: card.retro_column_id,
            body: card.body,
            author_user_id: card.author_user_id,
            author_alias: card.author_alias,
            author_display_name: card.author_display_name,
            vote_count: card.vote_count,
            reactions:
              Enum.map(card.reactions, fn r ->
                %{user_id: r.user_id, emoji: r.emoji}
              end),
            comments:
              Enum.map(card.comments, fn co ->
                %{
                  id: co.id,
                  body: co.body,
                  author_user_id: co.author_user_id,
                  author_alias: co.author_alias,
                  author_display_name: co.author_display_name
                }
              end)
          }
        end),
      action_items:
        Enum.map(session.action_items, fn action ->
          %{
            id: action.id,
            source_card_id: action.source_card_id,
            body: action.body,
            assignee_alias: action.assignee_alias,
            due_date: action.due_date && Date.to_iso8601(action.due_date),
            completed: action.completed
          }
        end)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto px-4 py-6 space-y-4">
        <header class="space-y-1">
          <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
            Archived retro
          </p>
          <p
            :if={@retro_session.chamber_slug_snapshot || @retro_session.chamber_title_snapshot}
            class="text-xs text-muted-foreground"
          >
            From: {@retro_session.chamber_title_snapshot || @retro_session.chamber_slug_snapshot}<span :if={
              @retro_session.archived_at
            }>
              · archived {Calendar.strftime(@retro_session.archived_at, "%Y-%m-%d %H:%M UTC")}</span>
          </p>
        </header>

        <.RetroBoard
          chamber_slug={@retro_session.chamber_slug_snapshot || ""}
          session={retro_view(@retro_session)}
          tallies={%{}}
          my_votes={[]}
          discussing_card_id={nil}
          participant_aliases={[]}
          current_user_id=""
          current_user_alias=""
          is_host={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
