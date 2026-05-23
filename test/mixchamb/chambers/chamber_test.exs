defmodule Mixchamb.Chambers.ChamberTest do
  use Mixchamb.DataCase, async: true

  alias Mixchamb.Chambers.Chamber

  describe "creation_changeset/2" do
    test "rejects an invalid activity" do
      cs = Chamber.creation_changeset(%Chamber{}, %{slug: "abc", creator_user_id: Ecto.UUID.generate(), activity: "icebreaker"})
      refute cs.valid?
      assert {"is invalid", _} = cs.errors[:activity]
    end

    test "rejects an invalid kind" do
      cs =
        Chamber.creation_changeset(%Chamber{}, %{
          slug: "abc",
          creator_user_id: Ecto.UUID.generate(),
          kind: "outer-space"
        })

      refute cs.valid?
      assert {"is invalid", _} = cs.errors[:kind]
    end

    test "requires a slug" do
      cs = Chamber.creation_changeset(%Chamber{}, %{creator_user_id: Ecto.UUID.generate()})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:slug]
    end
  end

  describe "title_changeset/2" do
    test "trims surrounding whitespace" do
      cs = Chamber.title_changeset(%Chamber{}, %{title: "  Cleanup  "})
      assert get_change(cs, :title) == "Cleanup"
    end

    test "blank-only titles collapse to nil" do
      cs = Chamber.title_changeset(%Chamber{title: "old"}, %{title: "   "})
      assert get_change(cs, :title) == nil
    end

    test "rejects titles longer than 80 chars" do
      cs = Chamber.title_changeset(%Chamber{}, %{title: String.duplicate("x", 81)})
      refute cs.valid?
    end
  end

  describe "kind_changeset/2" do
    test "accepts a valid kind" do
      cs = Chamber.kind_changeset(%Chamber{}, %{kind: "anechoic"})
      assert cs.valid?
    end

    test "rejects an invalid kind" do
      cs = Chamber.kind_changeset(%Chamber{}, %{kind: "fake"})
      refute cs.valid?
    end
  end

  describe "activity_changeset/2" do
    test "accepts music + poker" do
      assert Chamber.activity_changeset(%Chamber{}, %{activity: "music"}).valid?
      assert Chamber.activity_changeset(%Chamber{}, %{activity: "poker"}).valid?
    end

    test "rejects anything else" do
      refute Chamber.activity_changeset(%Chamber{}, %{activity: "standup"}).valid?
    end
  end

  describe "system_changeset/2" do
    test "accepts a slug without a creator (the chaos chamber's shape)" do
      cs = Chamber.system_changeset(%Chamber{}, %{slug: "chaos", kind: "room"})
      assert cs.valid?
    end

    test "still requires the slug" do
      cs = Chamber.system_changeset(%Chamber{}, %{kind: "room"})
      refute cs.valid?
    end
  end
end
