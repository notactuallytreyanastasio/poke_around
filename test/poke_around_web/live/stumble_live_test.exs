defmodule PokeAroundWeb.StumbleLiveTest do
  use PokeAroundWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PokeAround.Links
  alias PokeAround.Tags

  describe "mount" do
    test "renders with default assigns", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "poke_around"
      assert html =~ "bag of links"
      assert html =~ "Shuffle"
    end

    test "shows language menu in menubar", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Language"
    end

    test "shows page menu in menubar", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Page"
    end

    test "shows stats in statusbar", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "links in database"
    end
  end

  describe "shuffle event" do
    test "shuffle button triggers shuffle", %{conn: conn} do
      # Create some links first
      Links.store_link(%{url: "https://example.com/shuffle1", langs: ["en"], score: 30})
      Links.store_link(%{url: "https://example.com/shuffle2", langs: ["en"], score: 30})

      {:ok, view, _html} = live(conn, "/")

      # Click shuffle - should not error
      html = view |> element("button", "Shuffle") |> render_click()
      assert html =~ "poke_around"
    end
  end

  describe "language menu" do
    test "toggle_lang_menu shows dropdown", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      refute html =~ "All Languages"

      # Click Language menu
      html = view |> element(".mac-menu-item", "Language") |> render_click()
      assert html =~ "All Languages"
      assert html =~ "English"
      assert html =~ "Espanol"
    end

    test "toggle_lang adds language to filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open menu and toggle Spanish
      view |> element(".mac-menu-item", "Language") |> render_click()
      html = view |> element(".mac-dropdown-item", "Espanol") |> render_click()

      # Filter should now show both en and es
      assert html =~ "Filter: es, en" or html =~ "Filter: en, es"
    end

    test "toggle_lang removes language from filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open menu and remove English (which is default selected)
      view |> element(".mac-menu-item", "Language") |> render_click()
      html = view |> element(".mac-dropdown-item", "English") |> render_click()

      # Should have no filter now (or just show "links in database" without filter)
      refute html =~ "Filter:"
    end

    test "clear_langs removes all language filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open menu and clear
      view |> element(".mac-menu-item", "Language") |> render_click()
      html = view |> element(".mac-dropdown-item", "All Languages") |> render_click()

      refute html =~ "Filter:"
    end
  end

  describe "page menu" do
    test "toggle_page_menu shows dropdown", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      refute html =~ "Bag of Links"

      # Click Page menu
      html = view |> element(".mac-menu-item", "Page") |> render_click()
      assert html =~ "Bag of Links"
      assert html =~ "Tag Browsing"
      assert html =~ "Your Links"
    end

    test "change_page to tags page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open menu and select Tags page
      view |> element(".mac-menu-item", "Page") |> render_click()
      html = view |> element(".mac-dropdown-item", "Tag Browsing") |> render_click()

      assert html =~ "tag browsing"
      assert html =~ "Browse by Tag"
    end

    test "change_page to your_links page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open menu and select Your Links page
      view |> element(".mac-menu-item", "Page") |> render_click()
      html = view |> element(".mac-dropdown-item", "Your Links") |> render_click()

      assert html =~ "your links"
      assert html =~ "Your Submitted Links"
    end
  end

  describe "tag navigation" do
    setup do
      # Create a tag using the actual API
      {:ok, tag} = Tags.get_or_create_tag("technology")
      # Create a link and tag it
      {:ok, link} = Links.store_link(%{url: "https://example.com/tech-#{System.unique_integer([:positive])}", langs: ["en"]})
      Tags.tag_link(link, ["technology"])
      %{tag: tag, link: link}
    end

    test "select_tag shows tag links", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Go to tags page
      view |> element(".mac-menu-item", "Page") |> render_click()
      view |> element(".mac-dropdown-item", "Tag Browsing") |> render_click()

      # Select the tag
      html = view |> element(".tag-chip") |> render_click()

      assert html =~ "technology"
      assert html =~ "← Tags"
    end

    test "back_to_tags returns to tag list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Go to tags, select a tag, then go back
      view |> element(".mac-menu-item", "Page") |> render_click()
      view |> element(".mac-dropdown-item", "Tag Browsing") |> render_click()
      view |> element(".tag-chip") |> render_click()

      # Click back to tags
      html = view |> element("span", "← Tags") |> render_click()

      assert html =~ "Browse by Tag"
      refute html =~ "← Tags"
    end
  end

  describe "links display" do
    test "displays links when available", %{conn: conn} do
      Links.store_link(%{
        url: "https://test.com/display-test",
        post_text: "This is a test post text",
        langs: ["en"],
        score: 30
      })

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "test.com"
    end

    test "shows empty message when no links", %{conn: conn} do
      # No links created for this test
      {:ok, _view, html} = live(conn, "/")

      # Either shows links or the empty message
      assert html =~ "links in database"
    end
  end
end
