defmodule MixchambWeb.LandingLiveTest do
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.Chambers

  describe "GET /" do
    test "renders all three entry cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Chaos chamber"
      assert html =~ "Music chamber"
      assert html =~ "Planning poker"
    end
  end

  describe "enter_chaos" do
    test "ensures the chaos chamber exists and navigates to it", %{conn: conn} do
      assert is_nil(Chambers.find_by_slug(Chambers.chaos_slug()))

      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: target}}} =
               view |> element("button[phx-click=\"enter_chaos\"]") |> render_click()

      assert target == ~p"/chamber/#{Chambers.chaos_slug()}"
      assert %{} = Chambers.find_by_slug(Chambers.chaos_slug())
    end
  end

  describe "create_chamber" do
    test "creates a music chamber and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> element("button[phx-value-activity=\"music\"]")
               |> render_click()

      assert target =~ ~r"^/chamber/[A-Za-z0-9_-]+$"
      slug = String.replace_prefix(target, "/chamber/", "")
      assert %Mixchamb.Chambers.Chamber{activity: "music"} = Chambers.find_by_slug(slug)
    end

    test "creates a poker chamber and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> element("button[phx-value-activity=\"poker\"]")
               |> render_click()

      assert target =~ ~r"^/chamber/[A-Za-z0-9_-]+$"
      slug = String.replace_prefix(target, "/chamber/", "")
      assert %Mixchamb.Chambers.Chamber{activity: "poker"} = Chambers.find_by_slug(slug)
    end
  end

  describe "Resume where you left off" do
    test "no Resume section for a fresh visitor with no visit history", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      refute html =~ "Resume where you left off"
    end

    test "renders one row per recent visit, newest-first", %{conn: conn} do
      # current_user is created by the EnsureAnonUser plug on the conn.
      conn = get(conn, ~p"/")
      user = conn.assigns.current_user

      {:ok, music} = Chambers.create_chamber(user.id, "music")
      {:ok, poker} = Chambers.create_chamber(user.id, "poker")

      :ok = Chambers.touch_visit(user.id, music.id)
      :timer.sleep(1100)
      :ok = Chambers.touch_visit(user.id, poker.id)

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Resume where you left off"
      # Both chambers' slugs appear in the rendered links.
      assert html =~ music.slug
      assert html =~ poker.slug
      # Poker is the most-recent visit, should appear before music.
      poker_idx = :binary.match(html, poker.slug) |> elem(0)
      music_idx = :binary.match(html, music.slug) |> elem(0)
      assert poker_idx < music_idx
    end

    test "labels each row with the matching activity", %{conn: conn} do
      conn = get(conn, ~p"/")
      user = conn.assigns.current_user

      {:ok, chamber} = Chambers.create_chamber(user.id, "poker")
      :ok = Chambers.touch_visit(user.id, chamber.id)

      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Poker"
    end
  end
end
