defmodule PokeAroundWeb.IngestionLive do
  @moduledoc """
  Live view showing real-time ingestion of links from the firehose
  and tagging results as they happen.
  """

  use PokeAroundWeb, :live_view

  alias PokeAround.Links
  alias PokeAround.Links.Extractor
  alias PokeAround.AI.AxonTagger

  @max_links 100
  @max_tags 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to new links and tagging events
      Phoenix.PubSub.subscribe(PokeAround.PubSub, "links:new")
      Phoenix.PubSub.subscribe(PokeAround.PubSub, "links:tagged")

      # Refresh stats periodically
      :timer.send_interval(5_000, self(), :refresh_stats)
    end

    {:ok,
     socket
     |> assign(:links, [])
     |> assign(:tag_events, [])
     |> assign(:stats, get_stats())
     |> assign(:paused, false)}
  end

  @impl true
  def handle_info({:new_link, link}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      # Prepend new link, keep max
      links =
        [format_link(link) | socket.assigns.links]
        |> Enum.take(@max_links)

      {:noreply, assign(socket, :links, links)}
    end
  end

  @impl true
  def handle_info({:link_tagged, event}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      # Prepend new tag event, keep max
      tag_events =
        [format_tag_event(event) | socket.assigns.tag_events]
        |> Enum.take(@max_tags)

      # Also update the link in the links list if present
      links =
        Enum.map(socket.assigns.links, fn link ->
          if link.id == event.link_id do
            %{link | tags: event.tags}
          else
            link
          end
        end)

      {:noreply,
       socket
       |> assign(:tag_events, tag_events)
       |> assign(:links, links)}
    end
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply, assign(socket, :stats, get_stats())}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:links, [])
     |> assign(:tag_events, [])}
  end

  defp get_stats do
    extractor_stats =
      try do
        Extractor.get_stats()
      rescue
        _ -> %{posts_processed: 0, links_found: 0, links_qualified: 0}
      end

    tagger_stats =
      try do
        AxonTagger.stats()
      rescue
        _ -> %{tagged: 0, num_tags: 0}
      end

    %{
      total_links: Links.count_links(),
      posts_processed: extractor_stats[:posts_processed] || 0,
      links_found: extractor_stats[:links_found] || 0,
      links_qualified: extractor_stats[:links_qualified] || 0,
      tagged: tagger_stats[:tagged] || 0,
      num_tags: tagger_stats[:num_tags] || 0
    }
  end

  defp format_link(link) do
    %{
      id: link.id,
      url: link.url,
      domain: link.domain,
      post_text: truncate(link.post_text, 120),
      author_handle: link.author_handle,
      score: link.score,
      tags: [],
      inserted_at: link.inserted_at
    }
  end

  defp format_tag_event(event) do
    %{
      link_id: event.link_id,
      tags: event.tags,
      source: event.source,
      timestamp: DateTime.utc_now()
    }
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');

      * { box-sizing: border-box; }

      .mac-desktop {
        height: 100vh;
        background-color: #808080;
        background-image: url("data:image/svg+xml,%3Csvg width='2' height='2' viewBox='0 0 2 2' xmlns='http://www.w3.org/2000/svg'%3E%3Crect x='0' y='0' width='1' height='1' fill='%23a0a0a0'/%3E%3Crect x='1' y='1' width='1' height='1' fill='%23a0a0a0'/%3E%3C/svg%3E");
        background-size: 2px 2px;
        image-rendering: pixelated;
        padding: 20px;
        font-family: 'Geneva', 'VT323', 'Chicago', monospace;
        display: flex;
        flex-direction: column;
        overflow: hidden;
      }

      .mac-menubar {
        background: #ffffff;
        border-bottom: 2px solid #000000;
        padding: 2px 8px;
        display: flex;
        gap: 16px;
        font-size: 12px;
        font-weight: bold;
        width: 95%;
        max-width: 1400px;
        margin: 0 auto 20px auto;
        flex-shrink: 0;
      }

      .mac-menu-item {
        padding: 2px 8px;
        cursor: default;
      }

      .mac-menu-item:hover {
        background: #000000;
        color: #ffffff;
      }

      .windows-container {
        display: flex;
        gap: 20px;
        flex: 1;
        min-height: 0;
        width: 95%;
        max-width: 1400px;
        margin: 0 auto;
      }

      .mac-window {
        background: #ffffff;
        border: 2px solid #000000;
        box-shadow: 2px 2px 0 #000000, inset -1px -1px 0 #808080, inset 1px 1px 0 #dfdfdf;
        flex: 1;
        display: flex;
        flex-direction: column;
        min-height: 0;
        overflow: hidden;
      }

      .mac-window.narrow {
        flex: 0 0 350px;
      }

      .mac-titlebar {
        background: linear-gradient(to bottom, #ffffff 0%, #cccccc 100%);
        border-bottom: 2px solid #000000;
        padding: 2px 4px;
        display: flex;
        align-items: center;
        height: 20px;
        flex-shrink: 0;
      }

      .mac-titlebar-lines {
        flex: 1;
        height: 12px;
        margin: 0 8px;
        background: repeating-linear-gradient(to bottom, #000000 0px, #000000 1px, #ffffff 1px, #ffffff 3px);
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
        flex: 1;
        display: flex;
        flex-direction: column;
        min-height: 0;
        overflow: hidden;
      }

      .mac-text-area {
        flex: 1;
        font-family: 'Monaco', 'VT323', monospace;
        font-size: 11px;
        line-height: 1.4;
        padding: 8px;
        background: #ffffff;
        overflow-y: auto;
        min-height: 0;
      }

      .link-row {
        padding: 4px 6px;
        border-bottom: 1px dotted #cccccc;
        animation: flash-in 0.3s ease-out;
      }

      @keyframes flash-in {
        from { background: #ffffcc; }
        to { background: #ffffff; }
      }

      .link-row:hover {
        background: #f0f0f0;
      }

      .link-header {
        display: flex;
        justify-content: space-between;
        margin-bottom: 2px;
      }

      .link-domain {
        font-weight: bold;
        color: #000080;
      }

      .link-score {
        background: #dddddd;
        padding: 0 4px;
        font-size: 10px;
      }

      .link-text {
        color: #333333;
        font-size: 10px;
        margin-bottom: 2px;
      }

      .link-meta {
        display: flex;
        gap: 8px;
        font-size: 9px;
        color: #666666;
      }

      .link-tags {
        display: flex;
        gap: 4px;
        flex-wrap: wrap;
        margin-top: 2px;
      }

      .tag {
        background: #000080;
        color: #ffffff;
        padding: 1px 4px;
        font-size: 9px;
      }

      .tag.new {
        background: #008000;
        animation: tag-flash 0.5s ease-out;
      }

      @keyframes tag-flash {
        from { background: #00ff00; }
        to { background: #008000; }
      }

      .tag-event {
        padding: 4px 6px;
        border-bottom: 1px dotted #cccccc;
        animation: flash-in 0.3s ease-out;
      }

      .tag-event-header {
        font-size: 10px;
        color: #666666;
        margin-bottom: 2px;
      }

      .tag-event-tags {
        display: flex;
        gap: 4px;
        flex-wrap: wrap;
      }

      .mac-statusbar {
        background: #dddddd;
        border-top: 1px solid #000000;
        padding: 4px 8px;
        font-size: 10px;
        display: flex;
        justify-content: space-between;
        flex-shrink: 0;
      }

      .stats-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 8px;
        padding: 8px;
        background: #eeeeee;
        border-bottom: 1px solid #000000;
      }

      .stat-box {
        text-align: center;
      }

      .stat-value {
        font-size: 18px;
        font-weight: bold;
      }

      .stat-label {
        font-size: 9px;
        color: #666666;
      }

      .controls {
        display: flex;
        gap: 8px;
        padding: 8px;
        background: #eeeeee;
        border-bottom: 1px solid #000000;
        flex-shrink: 0;
      }

      .mac-btn {
        background: #dddddd;
        border: 2px outset #ffffff;
        padding: 4px 12px;
        font-family: 'Geneva', 'VT323', monospace;
        font-size: 11px;
        cursor: pointer;
      }

      .mac-btn:active {
        border-style: inset;
        background: #cccccc;
      }

      .mac-btn.active {
        background: #000080;
        color: #ffffff;
      }

      .empty-state {
        padding: 20px;
        text-align: center;
        color: #666666;
        font-size: 12px;
      }

      .pulse {
        animation: pulse 1s infinite;
      }

      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
      }
    </style>

    <div class="mac-desktop">
      <div class="mac-menubar">
        <div class="mac-menu-item">🍎</div>
        <div class="mac-menu-item">File</div>
        <div class="mac-menu-item">Edit</div>
        <div class="mac-menu-item">View</div>
        <a href="/" class="mac-menu-item" style="text-decoration: none; color: inherit;">Stumble</a>
      </div>

      <div class="windows-container">
        <!-- Main Links Window -->
        <div class="mac-window">
          <div class="mac-titlebar">
            <div class="mac-close-btn"></div>
            <div class="mac-titlebar-lines"></div>
            <div class="mac-title">
              Incoming Links
              <%= if !@paused do %>
                <span class="pulse">●</span>
              <% end %>
            </div>
            <div class="mac-titlebar-lines"></div>
          </div>

          <div class="stats-grid">
            <div class="stat-box">
              <div class="stat-value"><%= @stats.total_links %></div>
              <div class="stat-label">Total Links</div>
            </div>
            <div class="stat-box">
              <div class="stat-value"><%= @stats.posts_processed %></div>
              <div class="stat-label">Posts Processed</div>
            </div>
            <div class="stat-box">
              <div class="stat-value"><%= @stats.links_qualified %></div>
              <div class="stat-label">Links Qualified</div>
            </div>
          </div>

          <div class="controls">
            <button class={"mac-btn #{if @paused, do: "active"}"} phx-click="toggle_pause">
              <%= if @paused, do: "▶ Resume", else: "⏸ Pause" %>
            </button>
            <button class="mac-btn" phx-click="clear">Clear</button>
          </div>

          <div class="mac-content">
            <div class="mac-text-area">
              <%= if @links == [] do %>
                <div class="empty-state">
                  Waiting for links from the firehose...<br/>
                  <span class="pulse">●</span>
                </div>
              <% else %>
                <%= for link <- @links do %>
                  <div class="link-row">
                    <div class="link-header">
                      <span class="link-domain"><%= link.domain %></span>
                      <span class="link-score"><%= link.score %></span>
                    </div>
                    <div class="link-text"><%= link.post_text %></div>
                    <div class="link-meta">
                      <span>@<%= link.author_handle %></span>
                    </div>
                    <%= if link.tags != [] do %>
                      <div class="link-tags">
                        <%= for tag <- link.tags do %>
                          <span class="tag new"><%= tag %></span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <div class="mac-statusbar">
            <span><%= length(@links) %> links in view</span>
            <span><%= if @paused, do: "PAUSED", else: "LIVE" %></span>
          </div>
        </div>

        <!-- Tagging Window -->
        <div class="mac-window narrow">
          <div class="mac-titlebar">
            <div class="mac-close-btn"></div>
            <div class="mac-titlebar-lines"></div>
            <div class="mac-title">Tagging Activity</div>
            <div class="mac-titlebar-lines"></div>
          </div>

          <div class="stats-grid" style="grid-template-columns: 1fr 1fr;">
            <div class="stat-box">
              <div class="stat-value"><%= @stats.tagged %></div>
              <div class="stat-label">Links Tagged</div>
            </div>
            <div class="stat-box">
              <div class="stat-value"><%= @stats.num_tags %></div>
              <div class="stat-label">Unique Tags</div>
            </div>
          </div>

          <div class="mac-content">
            <div class="mac-text-area">
              <%= if @tag_events == [] do %>
                <div class="empty-state">
                  Waiting for tagging results...<br/>
                  <span class="pulse">●</span>
                </div>
              <% else %>
                <%= for event <- @tag_events do %>
                  <div class="tag-event">
                    <div class="tag-event-header">
                      Link #<%= event.link_id %> • <%= event.source %>
                    </div>
                    <div class="tag-event-tags">
                      <%= for tag <- event.tags do %>
                        <span class="tag new"><%= tag %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <div class="mac-statusbar">
            <span><%= length(@tag_events) %> events</span>
            <span>Axon ML</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
