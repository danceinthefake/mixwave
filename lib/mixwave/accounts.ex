defmodule Mixwave.Accounts do
  @moduledoc """
  The Accounts context — anonymous-only authentication.

  Anonymous users are created on first request by
  `MixwaveWeb.Plugs.EnsureAnonUser`, identified solely by a signed
  session cookie. After 24 hours of inactivity the
  `Mixwave.Accounts.Sweeper` GenServer reaps them; cascading FK
  constraints take their songs and comments with them.
  """

  alias Mixwave.Accounts.{AnonymousUser, NameGenerator}
  alias Mixwave.Repo

  @doc """
  Creates a new anonymous user with a generated funny-Javanese-style
  display name (see `NameGenerator`) and `last_active_at` set to now.
  """
  def create_anonymous_user(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    %AnonymousUser{}
    |> AnonymousUser.creation_changeset(%{
      display_name: NameGenerator.generate(),
      last_active_at: now
    })
    |> Repo.insert()
  end

  @doc """
  Fetches an anonymous user by id, or returns nil. Used by the auth
  plug to resolve the session's user_id back into a struct.
  """
  def get_anonymous_user(id), do: Repo.get(AnonymousUser, id)

  @doc """
  Bulk fetch anonymous users by id. Returns a map keyed by id so
  callers can resolve N rows without N queries. Missing ids
  silently drop out of the map (the caller decides what to show
  for a deleted user).
  """
  def list_users_by_ids([]), do: %{}

  def list_users_by_ids(ids) when is_list(ids) do
    import Ecto.Query

    # The caller might hand us arbitrary strings (e.g. telemetry
    # rows from before the user existed). Filter to valid UUIDs
    # so a bad id never blows up the query.
    valid_ids =
      ids
      |> Enum.filter(&is_binary/1)
      |> Enum.filter(fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end)

    case valid_ids do
      [] ->
        %{}

      ids ->
        AnonymousUser
        |> where([u], u.id in ^ids)
        |> Repo.all()
        |> Map.new(fn u -> {u.id, u} end)
    end
  end

  @doc """
  Bumps `last_active_at`. Caller is responsible for any debounce; this
  function unconditionally writes.
  """
  def touch_anonymous_user(%AnonymousUser{} = user, now) do
    user
    |> AnonymousUser.touch_changeset(now)
    |> Repo.update()
  end

  @doc """
  Sets the user's optional alias. Pass an empty string (or only
  whitespace) to clear it back to `nil`. The auto-generated
  `display_name` is never touched.
  """
  def set_alias(%AnonymousUser{} = user, value) do
    user
    |> AnonymousUser.alias_changeset(%{"alias" => value})
    |> Repo.update()
  end

  @doc """
  Deletes anonymous users idle for more than `hours` hours. Returns
  the number of rows deleted. Cascade FK constraints take care of
  songs + comments.
  """
  def sweep_idle_users(hours \\ 24) do
    import Ecto.Query

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-hours * 3600, :second)
      |> DateTime.truncate(:second)

    {count, _} =
      from(u in AnonymousUser, where: u.last_active_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  @doc """
  Total anonymous users in the table.
  """
  def count_users do
    Repo.aggregate(AnonymousUser, :count, :id)
  end

  @doc """
  Anonymous users whose `last_active_at` is within the last
  `minutes` minutes — a rough "currently around" gauge for the
  admin dashboard.
  """
  def count_active_users(minutes \\ 5) do
    import Ecto.Query

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-minutes * 60, :second)
      |> DateTime.truncate(:second)

    Repo.aggregate(
      from(u in AnonymousUser, where: u.last_active_at >= ^cutoff),
      :count,
      :id
    )
  end

  @doc """
  Lists anonymous users newest-first, paginated. Powers the admin
  Users tab.
  """
  def list_users(opts \\ []) do
    import Ecto.Query

    limit = Keyword.get(opts, :limit, 100)

    from(u in AnonymousUser,
      order_by: [desc: u.last_active_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Force-deletes an anonymous user — admin override of the 24h
  idle-sweep policy.
  """
  def delete_anonymous_user(%AnonymousUser{} = user), do: Repo.delete(user)

  def delete_anonymous_user(id) when is_binary(id) do
    case get_anonymous_user(id) do
      nil -> {:error, :not_found}
      user -> Repo.delete(user)
    end
  end
end
