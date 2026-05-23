defmodule Mixchamb.Chambers.PokerSession do
  @moduledoc """
  Per-chamber state for the planning-poker activity. Owned by
  `Mixchamb.Chambers.Server`'s GenServer state and ephemeral —
  lives in memory only, dies with the chamber.

  Design: `features/planning-poker.md`. All mutations return one
  of:

    * `{:ok, new_session}` — state changed; caller should broadcast
    * `{:noop, session}`   — no-op (idempotent re-vote, etc.); caller skips broadcast
    * `{:error, reason}`   — validation failure; caller logs / ignores

  Mutations don't broadcast on their own; that's the GenServer's
  job so the cast/call surface stays the only place messages leave
  the process.
  """

  @decks ~w(fibonacci modified_fibonacci tshirt pow2)a
  def decks, do: @decks

  @cards_by_deck %{
    fibonacci: ~w(1 2 3 5 8 13 21 ? ☕),
    modified_fibonacci: ~w(0 ½ 1 2 3 5 8 13 20 40 100 ? ☕),
    tshirt: ~w(XS S M L XL ?),
    pow2: ~w(1 2 4 8 16 32 ? ☕)
  }

  @doc "Returns the card list for `deck`, oldest-first ordering."
  def cards_for(deck) when deck in @decks, do: Map.fetch!(@cards_by_deck, deck)

  defstruct status: :voting,
            deck: :fibonacci,
            story: nil,
            votes: %{},
            round: 1,
            # Completed rounds, newest-first. Pushed on `next_round`
            # (not `revote` — re-vote means "redo this round, don't
            # remember the previous attempt"). Each entry snapshots
            # the deck so the verdict computation on the client side
            # still has the right card ordering even if the deck
            # was swapped between rounds.
            history: [],
            # Pre-loaded backlog the host wants to estimate in
            # sequence. Head is consumed by `next_round/2` into
            # `:story` whenever the queue is non-empty (and no
            # explicit `:story` was passed). Empty queue → next_round
            # behaves as before. Host edits via `set_queue/2`,
            # which replaces the whole list; appending is "open the
            # editor, paste-append, save" since the textarea on the
            # client is pre-filled with the current contents.
            queue: []

  @max_queue_length 50

  @type history_entry :: %{
          round: pos_integer(),
          story: String.t() | nil,
          deck: atom(),
          votes: %{optional(String.t()) => String.t()}
        }

  @type t :: %__MODULE__{
          status: :voting | :revealed,
          deck: atom(),
          story: String.t() | nil,
          votes: %{optional(String.t()) => String.t()},
          round: pos_integer(),
          history: [history_entry()],
          queue: [String.t()]
        }

  @doc "Fresh session at round 1 with the given deck."
  def new(deck \\ :fibonacci) when deck in @decks do
    %__MODULE__{deck: deck}
  end

  @doc """
  Cast a vote during `:voting`. Idempotent — re-voting the same
  card is a no-op. Rejected during `:revealed`. Returns
  `{:error, :invalid_card}` if `card` isn't in the active deck.
  """
  def cast_vote(%__MODULE__{status: :voting} = s, user_id, card)
      when is_binary(user_id) and is_binary(card) do
    cond do
      card not in cards_for(s.deck) -> {:error, :invalid_card}
      Map.get(s.votes, user_id) == card -> {:noop, s}
      true -> {:ok, %{s | votes: Map.put(s.votes, user_id, card)}}
    end
  end

  def cast_vote(%__MODULE__{} = s, _user_id, _card), do: {:noop, s}

  @doc """
  Drop a user's vote during `:voting`. No-op if the user hasn't
  voted yet or the session is already revealed. Also called when
  a participant leaves the chamber (via Presence).
  """
  def withdraw_vote(%__MODULE__{status: :voting, votes: votes} = s, user_id)
      when is_binary(user_id) do
    if Map.has_key?(votes, user_id) do
      {:ok, %{s | votes: Map.delete(votes, user_id)}}
    else
      {:noop, s}
    end
  end

  def withdraw_vote(%__MODULE__{} = s, _user_id), do: {:noop, s}

  @doc """
  Flip from `:voting` to `:revealed`. Re-revealing is a no-op.
  Reveal with zero votes is allowed (the doc explicitly chose not
  to gate on "≥1 vote required").
  """
  def reveal(%__MODULE__{status: :voting} = s), do: {:ok, %{s | status: :revealed}}
  def reveal(%__MODULE__{} = s), do: {:noop, s}

  @doc """
  Clear the round: votes wiped, round counter incremented, status
  back to `:voting`. Optionally accepts a `:story` to swap to.
  Always succeeds (it's the host's "next" button).
  """
  def next_round(%__MODULE__{round: r} = s, opts \\ []) do
    # Story precedence (highest first):
    #   1. Explicit `:story` opt (host edited the title before
    #      clicking Next round — that intent wins).
    #   2. Queue head (preloaded backlog — pop it).
    #   3. Existing `s.story` (carry over — current behavior).
    {new_story, new_queue} =
      cond do
        Keyword.has_key?(opts, :story) ->
          {Keyword.get(opts, :story), s.queue}

        s.queue != [] ->
          [head | rest] = s.queue
          {head, rest}

        true ->
          {s.story, s.queue}
      end

    # Push the just-finished round into history *only* if the team
    # actually engaged with it — at least one vote or a non-nil
    # story. A host who clicks Next Round on an empty placeholder
    # round shouldn't leave "R3 — Untitled" debris in the timeline.
    history =
      if s.votes == %{} and is_nil(s.story) do
        s.history
      else
        entry = %{round: s.round, story: s.story, deck: s.deck, votes: s.votes}
        [entry | s.history]
      end

    {:ok,
     %{
       s
       | status: :voting,
         votes: %{},
         round: r + 1,
         story: new_story,
         history: history,
         queue: new_queue
     }}
  end

  @doc """
  Soft reset: clear votes and return to `:voting` while keeping the
  current round number, story, and deck. Useful from `:revealed`
  when the team wants to vote again on the same story without
  bumping the round counter.
  """
  def revote(%__MODULE__{status: :voting, votes: votes} = s) when votes == %{},
    do: {:noop, s}

  def revote(%__MODULE__{} = s), do: {:ok, %{s | status: :voting, votes: %{}}}

  @doc """
  Replace the active story line. Nil clears the story (display
  falls back to "Round N"). Always succeeds.
  """
  def set_story(%__MODULE__{} = s, story) when is_nil(story) or is_binary(story) do
    if s.story == story, do: {:noop, s}, else: {:ok, %{s | story: story}}
  end

  @doc """
  Switch to a different deck. Allowed only while `votes` is empty
  — mid-round deck switches would orphan card values that no longer
  exist in the new deck.
  """
  def set_deck(%__MODULE__{votes: votes}, _) when votes != %{},
    do: {:error, :votes_in_progress}

  def set_deck(%__MODULE__{deck: same} = s, deck) when deck == same, do: {:noop, s}

  def set_deck(%__MODULE__{} = s, deck) when deck in @decks,
    do: {:ok, %{s | deck: deck}}

  def set_deck(%__MODULE__{} = _s, _), do: {:error, :invalid_deck}

  @doc """
  Replace the pre-loaded story queue. `lines` is a list of raw
  strings (e.g., from a textarea split on newlines); blanks are
  trimmed out, contents are not deduplicated (a team might
  intentionally re-estimate the same item), and the result is
  capped at `@max_queue_length` so a stray paste of a 10k-line
  CSV can't bloat ephemeral chamber state. No-op when the new
  queue is identical to the current one.
  """
  def set_queue(%__MODULE__{} = s, lines) when is_list(lines) do
    cleaned =
      lines
      |> Enum.map(&maybe_trim/1)
      |> Enum.reject(&(&1 == nil or &1 == ""))
      |> Enum.take(@max_queue_length)

    if cleaned == s.queue, do: {:noop, s}, else: {:ok, %{s | queue: cleaned}}
  end

  def set_queue(%__MODULE__{} = _s, _), do: {:error, :invalid_queue}

  defp maybe_trim(value) when is_binary(value), do: String.trim(value)
  defp maybe_trim(_), do: nil
end
