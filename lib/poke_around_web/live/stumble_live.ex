defmodule PokeAroundWeb.StumbleLive do
  use PokeAroundWeb, :live_view

  alias PokeAround.Links

  @impl true
  def mount(_params, _session, socket) do
    link = Links.random_link(min_score: 20)

    {:ok,
     socket
     |> assign(:link, link)
     |> assign(:history, [])
     |> assign(:stats, get_stats())}
  end

  @impl true
  def handle_event("stumble", _params, socket) do
    # Add current link to history
    history =
      case socket.assigns.link do
        nil -> socket.assigns.history
        link -> [link.id | socket.assigns.history] |> Enum.take(50)
      end

    # Get a new random link, excluding recently seen
    link = Links.random_link(min_score: 20, exclude_ids: history)

    # Increment stumble count if we got a link
    if link, do: Links.increment_stumble_count(link.id)

    {:noreply,
     socket
     |> assign(:link, link)
     |> assign(:history, history)}
  end

  @impl true
  def handle_event("refresh-stats", _params, socket) do
    {:noreply, assign(socket, :stats, get_stats())}
  end

  defp get_stats do
    %{
      total_links: Links.count_links(),
      top_domains: Links.top_domains(5)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
      <div class="container mx-auto px-4 py-8">
        <!-- Header -->
        <header class="text-center mb-12">
          <h1 class="text-5xl font-bold text-white mb-2">poke_around</h1>
          <p class="text-purple-200 text-lg">Discover random links from Bluesky</p>
          <p class="text-purple-300 text-sm mt-2">
            <%= @stats.total_links %> links to explore
          </p>
        </header>

        <!-- Main Content -->
        <div class="max-w-2xl mx-auto">
          <%= if @link do %>
            <div class="bg-white/10 backdrop-blur-lg rounded-2xl p-8 shadow-2xl border border-white/20">
              <!-- Link Card -->
              <div class="mb-6">
                <div class="flex items-center gap-3 mb-4">
                  <div class="w-10 h-10 bg-gradient-to-br from-blue-400 to-purple-500 rounded-full flex items-center justify-center text-white font-bold">
                    <%= String.first(@link.author_handle || "?") |> String.upcase() %>
                  </div>
                  <div>
                    <p class="text-white font-medium"><%= @link.author_display_name || @link.author_handle %></p>
                    <p class="text-purple-300 text-sm">@<%= @link.author_handle %></p>
                  </div>
                  <div class="ml-auto">
                    <span class="bg-purple-500/30 text-purple-200 px-3 py-1 rounded-full text-sm">
                      <%= format_followers(@link.author_followers_count) %> followers
                    </span>
                  </div>
                </div>

                <div class="bg-black/20 rounded-xl p-4 mb-4">
                  <p class="text-white/90 text-sm mb-3"><%= truncate(@link.post_text, 200) %></p>
                </div>

                <a
                  href={@link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block bg-gradient-to-r from-blue-500 to-purple-600 hover:from-blue-600 hover:to-purple-700 text-white rounded-xl p-4 transition-all hover:scale-[1.02] hover:shadow-lg"
                >
                  <div class="flex items-center gap-3">
                    <div class="flex-shrink-0">
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                      </svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="font-medium truncate"><%= @link.domain %></p>
                      <p class="text-white/70 text-sm truncate"><%= @link.url %></p>
                    </div>
                  </div>
                </a>
              </div>

              <!-- Score Badge -->
              <div class="flex justify-center mb-6">
                <div class="bg-white/10 rounded-full px-4 py-2 flex items-center gap-2">
                  <span class="text-yellow-400">★</span>
                  <span class="text-white">Score: <%= @link.score %></span>
                </div>
              </div>
            </div>
          <% else %>
            <div class="bg-white/10 backdrop-blur-lg rounded-2xl p-8 shadow-2xl border border-white/20 text-center">
              <p class="text-white text-xl">No more links to show!</p>
              <p class="text-purple-300 mt-2">Check back later for more content.</p>
            </div>
          <% end %>

          <!-- Stumble Button -->
          <div class="flex justify-center mt-8">
            <button
              phx-click="stumble"
              class="group relative px-12 py-4 bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 rounded-full text-white font-bold text-xl shadow-lg hover:shadow-2xl transition-all hover:scale-105 active:scale-95"
            >
              <span class="relative z-10 flex items-center gap-2">
                <svg class="w-6 h-6 group-hover:rotate-12 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
                Stumble!
              </span>
            </button>
          </div>

          <!-- History indicator -->
          <%= if length(@history) > 0 do %>
            <p class="text-center text-purple-300 mt-4 text-sm">
              You've seen <%= length(@history) %> links this session
            </p>
          <% end %>
        </div>

        <!-- Stats Footer -->
        <footer class="mt-16 text-center">
          <div class="mb-4">
            <.link navigate="/bookmarklet" class="text-purple-300 hover:text-white transition-colors">
              Get the bookmarklet to save your own links →
            </.link>
          </div>
          <div class="inline-flex gap-4 flex-wrap justify-center">
            <%= for {domain, count} <- @stats.top_domains do %>
              <span class="bg-white/10 text-purple-200 px-3 py-1 rounded-full text-sm">
                <%= domain %>: <%= count %>
              </span>
            <% end %>
          </div>
        </footer>
      </div>
    </div>
    """
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."

  defp format_followers(nil), do: "?"
  defp format_followers(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_followers(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_followers(n), do: "#{n}"
end
