defmodule PokeAroundWeb.StumbleLive do
  use PokeAroundWeb, :live_view

  alias PokeAround.Links

  @links_per_page 20

  @supported_langs [
    {"en", "English"},
    {"es", "Espanol"},
    {"pt", "Portugues"},
    {"de", "Deutsch"},
    {"fr", "Francais"},
    {"ja", "Japanese"},
    {"ko", "Korean"},
    {"zh", "Chinese"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    selected_langs = []
    links = fetch_links(selected_langs)

    {:ok,
     socket
     |> assign(:links, links)
     |> assign(:selected_index, nil)
     |> assign(:selected_langs, selected_langs)
     |> assign(:supported_langs, @supported_langs)
     |> assign(:show_lang_menu, false)
     |> assign(:stats, get_stats())}
  end

  @impl true
  def handle_event("shuffle", _params, socket) do
    links = fetch_links(socket.assigns.selected_langs)
    {:noreply, assign(socket, :links, links)}
  end

  @impl true
  def handle_event("toggle_lang_menu", _params, socket) do
    {:noreply, assign(socket, :show_lang_menu, !socket.assigns.show_lang_menu)}
  end

  @impl true
  def handle_event("toggle_lang", %{"lang" => lang}, socket) do
    current = socket.assigns.selected_langs

    new_langs =
      if lang in current do
        List.delete(current, lang)
      else
        [lang | current]
      end

    links = fetch_links(new_langs)

    {:noreply,
     socket
     |> assign(:selected_langs, new_langs)
     |> assign(:links, links)}
  end

  @impl true
  def handle_event("clear_langs", _params, socket) do
    links = fetch_links([])

    {:noreply,
     socket
     |> assign(:selected_langs, [])
     |> assign(:links, links)}
  end

  @impl true
  def handle_event("select", %{"index" => index}, socket) do
    {:noreply, assign(socket, :selected_index, String.to_integer(index))}
  end

  @impl true
  def handle_event("open", %{"url" => url, "id" => id}, socket) do
    Links.increment_stumble_count(String.to_integer(id))
    {:noreply, redirect(socket, external: url)}
  end

  defp get_stats do
    %{
      total_links: Links.count_links(),
      top_domains: Links.top_domains(5)
    }
  end

  defp fetch_links(selected_langs) do
    opts = [min_score: 20]
    opts = if selected_langs != [], do: Keyword.put(opts, :langs, selected_langs), else: opts
    Links.random_links(@links_per_page, opts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');

      * {
        box-sizing: border-box;
      }

      .mac-desktop {
        min-height: 100vh;
        background-color: #808080;
        background-image: url("data:image/svg+xml,%3Csvg width='2' height='2' viewBox='0 0 2 2' xmlns='http://www.w3.org/2000/svg'%3E%3Crect x='0' y='0' width='1' height='1' fill='%23a0a0a0'/%3E%3Crect x='1' y='1' width='1' height='1' fill='%23a0a0a0'/%3E%3C/svg%3E");
        background-size: 2px 2px;
        image-rendering: pixelated;
        padding: 20px;
        font-family: 'Geneva', 'VT323', 'Chicago', monospace;
      }

      .mac-window {
        background: #ffffff;
        border: 2px solid #000000;
        box-shadow:
          2px 2px 0 #000000,
          inset -1px -1px 0 #808080,
          inset 1px 1px 0 #dfdfdf;
        width: 95%;
        max-width: 1000px;
        margin: 0 auto;
      }

      .mac-titlebar {
        background: linear-gradient(to bottom, #ffffff 0%, #cccccc 100%);
        border-bottom: 2px solid #000000;
        padding: 2px 4px;
        display: flex;
        align-items: center;
        height: 20px;
      }

      .mac-titlebar-lines {
        flex: 1;
        height: 12px;
        margin: 0 8px;
        background: repeating-linear-gradient(
          to bottom,
          #000000 0px,
          #000000 1px,
          #ffffff 1px,
          #ffffff 3px
        );
      }

      .mac-close-btn {
        width: 12px;
        height: 12px;
        border: 1px solid #000000;
        background: #ffffff;
        margin-right: 4px;
      }

      .mac-title {
        font-size: 12px;
        font-weight: bold;
        white-space: nowrap;
        padding: 0 8px;
      }

      .mac-content {
        background: #ffffff;
        padding: 0;
      }

      .mac-scrollbar {
        display: flex;
      }

      .mac-text-area {
        flex: 1;
        font-family: 'Monaco', 'VT323', monospace;
        font-size: 11px;
        line-height: 1.4;
        padding: 8px;
        min-height: 500px;
        background: #ffffff;
      }

      .mac-scrollbar-track {
        width: 16px;
        background: #ffffff;
        border-left: 1px solid #000000;
        display: flex;
        flex-direction: column;
      }

      .mac-scroll-btn {
        width: 16px;
        height: 16px;
        background: #dddddd;
        border: 1px solid #000000;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 8px;
        cursor: pointer;
      }

      .mac-scroll-btn:active {
        background: #000000;
        color: #ffffff;
      }

      .mac-scroll-track {
        flex: 1;
        background: repeating-linear-gradient(
          to bottom,
          #ffffff 0px,
          #ffffff 1px,
          #dddddd 1px,
          #dddddd 2px
        );
        position: relative;
      }

      .mac-scroll-thumb {
        position: absolute;
        top: 10%;
        left: 0;
        right: 0;
        height: 40px;
        background: #dddddd;
        border: 1px solid #000000;
      }

      .link-row {
        padding: 2px 4px;
        cursor: pointer;
        display: flex;
        border-bottom: 1px dotted #cccccc;
      }

      .link-row:hover {
        background: #000000;
        color: #ffffff;
      }

      .link-row.selected {
        background: #000080;
        color: #ffffff;
      }

      .link-domain {
        width: 180px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        flex-shrink: 0;
      }

      .link-text {
        flex: 1;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        padding-left: 8px;
      }


      .mac-statusbar {
        background: #dddddd;
        border-top: 1px solid #000000;
        padding: 2px 8px;
        font-size: 10px;
        display: flex;
        justify-content: space-between;
      }

      .mac-btn {
        background: #dddddd;
        border: 2px outset #ffffff;
        padding: 4px 16px;
        font-family: 'Geneva', 'VT323', monospace;
        font-size: 12px;
        cursor: pointer;
        margin: 8px;
      }

      .mac-btn:active {
        border-style: inset;
        background: #cccccc;
      }

      .mac-menubar {
        background: #ffffff;
        border-bottom: 2px solid #000000;
        padding: 2px 8px;
        margin-bottom: 20px;
        display: flex;
        gap: 16px;
        font-size: 12px;
        font-weight: bold;
        width: 95%;
        max-width: 1000px;
        margin: 0 auto 20px auto;
      }

      .mac-menu-item {
        padding: 2px 8px;
        cursor: default;
        position: relative;
      }

      .mac-menu-item:hover {
        background: #000000;
        color: #ffffff;
      }

      .mac-dropdown {
        position: absolute;
        top: 100%;
        left: 0;
        background: #ffffff;
        border: 1px solid #000000;
        box-shadow: 2px 2px 0 #000000;
        min-width: 150px;
        z-index: 100;
        font-weight: normal;
      }

      .mac-dropdown-item {
        padding: 4px 8px;
        cursor: pointer;
        display: flex;
        align-items: center;
        color: #000000;
      }

      .mac-dropdown-item:hover {
        background: #000000;
        color: #ffffff;
      }

      .mac-check {
        width: 16px;
        font-family: monospace;
      }

      .mac-divider {
        border-top: 1px solid #000000;
        margin: 2px 0;
      }

      .shuffle-row {
        display: flex;
        justify-content: center;
        padding: 8px;
        border-top: 1px solid #000000;
        background: #eeeeee;
      }

      .header-row {
        display: flex;
        padding: 4px;
        background: #dddddd;
        border-bottom: 2px solid #000000;
        font-size: 10px;
        font-weight: bold;
      }

      .header-text { flex: 1; }
      .header-domain { width: 180px; padding-left: 8px; }
    </style>

    <div class="mac-desktop">
      <div class="mac-menubar">
        <div class="mac-menu-item">🍎</div>
        <div class="mac-menu-item">File</div>
        <div class="mac-menu-item">Edit</div>
        <div class="mac-menu-item">View</div>
        <div class="mac-menu-item" phx-click="toggle_lang_menu">
          Language
          <%= if @show_lang_menu do %>
            <div class="mac-dropdown">
              <div class="mac-dropdown-item" phx-click="clear_langs">
                <span class="mac-check"><%= if @selected_langs == [], do: "✓", else: " " %></span>
                All Languages
              </div>
              <div class="mac-divider"></div>
              <%= for {code, name} <- @supported_langs do %>
                <div class="mac-dropdown-item" phx-click="toggle_lang" phx-value-lang={code}>
                  <span class="mac-check"><%= if code in @selected_langs, do: "✓", else: " " %></span>
                  <%= name %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        <div class="mac-menu-item">Special</div>
      </div>

      <div class="mac-window">
        <div class="mac-titlebar">
          <div class="mac-close-btn"></div>
          <div class="mac-titlebar-lines"></div>
          <div class="mac-title">poke_around - grab bag</div>
          <div class="mac-titlebar-lines"></div>
        </div>

        <div class="mac-content">
          <div class="header-row">
            <div class="header-text">Post</div>
            <div class="header-domain">Domain</div>
          </div>

          <div class="mac-scrollbar">
            <div class="mac-text-area">
              <%= for {link, index} <- Enum.with_index(@links) do %>
                <div
                  class={"link-row #{if @selected_index == index, do: "selected", else: ""}"}
                  phx-click="open"
                  phx-value-url={link.url}
                  phx-value-id={link.id}
                >
                  <div class="link-text"><%= truncate(link.post_text, 100) %></div>
                  <div class="link-domain"><%= link.domain %></div>
                </div>
              <% end %>

              <%= if @links == [] do %>
                <div style="padding: 20px; text-align: center; color: #666;">
                  No links found. Check back later!
                </div>
              <% end %>
            </div>

            <div class="mac-scrollbar-track">
              <div class="mac-scroll-btn">▲</div>
              <div class="mac-scroll-track">
                <div class="mac-scroll-thumb"></div>
              </div>
              <div class="mac-scroll-btn">▼</div>
            </div>
          </div>

          <div class="shuffle-row">
            <button class="mac-btn" phx-click="shuffle">
              ↻ Shuffle
            </button>
          </div>
        </div>

        <div class="mac-statusbar">
          <span><%= length(@links) %> items</span>
          <span>
            <%= if @selected_langs != [] do %>
              Filter: <%= Enum.join(@selected_langs, ", ") %> |
            <% end %>
            <%= @stats.total_links %> links in database
          </span>
        </div>
      </div>

      <div style="text-align: center; margin-top: 16px;">
        <.link navigate="/bookmarklet" style="color: #ffffff; font-size: 11px; font-family: Geneva, monospace;">
          Get the bookmarklet →
        </.link>
      </div>
    </div>
    """
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "…"
end
