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
end
