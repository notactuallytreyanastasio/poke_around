defmodule PokeAroundWeb.BookmarkletLive do
  use PokeAroundWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :host, nil)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    %URI{host: host, port: port, scheme: scheme} = URI.parse(uri)
    base_url = "#{scheme}://#{host}#{if port && port != 80 && port != 443, do: ":#{port}", else: ""}"
    {:noreply, assign(socket, :base_url, base_url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-800">
      <div class="container mx-auto px-4 py-8">
        <!-- Header -->
        <header class="text-center mb-12">
          <h1 class="text-5xl font-bold text-white mb-2">poke_around</h1>
          <p class="text-purple-200 text-lg">Save links to stumble later</p>
        </header>

        <div class="max-w-2xl mx-auto">
          <!-- Bookmarklet Card -->
          <div class="bg-white/10 backdrop-blur-lg rounded-2xl p-8 shadow-2xl border border-white/20 mb-8">
            <h2 class="text-2xl font-bold text-white mb-4">Get the Bookmarklet</h2>

            <p class="text-purple-200 mb-6">
              Drag this button to your bookmarks bar. Click it on any page to save the link for stumbling!
            </p>

            <div class="flex justify-center mb-6">
              <a
                href={bookmarklet_code(@base_url)}
                class="inline-flex items-center gap-2 px-6 py-3 bg-gradient-to-r from-yellow-400 to-orange-500 text-black font-bold rounded-lg shadow-lg hover:shadow-xl cursor-grab active:cursor-grabbing"
                onclick="alert('Drag this to your bookmarks bar!'); return false;"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
                </svg>
                Save to PokeAround
              </a>
            </div>

            <div class="text-center">
              <p class="text-purple-300 text-sm">
                ← Drag the button above to your bookmarks bar
              </p>
            </div>
          </div>

          <!-- Instructions -->
          <div class="bg-white/10 backdrop-blur-lg rounded-2xl p-8 shadow-2xl border border-white/20">
            <h2 class="text-2xl font-bold text-white mb-4">How it works</h2>

            <ol class="space-y-4 text-purple-200">
              <li class="flex gap-3">
                <span class="flex-shrink-0 w-8 h-8 bg-purple-500 rounded-full flex items-center justify-center text-white font-bold">1</span>
                <span class="pt-1">Drag the yellow button above to your browser's bookmarks bar</span>
              </li>
              <li class="flex gap-3">
                <span class="flex-shrink-0 w-8 h-8 bg-purple-500 rounded-full flex items-center justify-center text-white font-bold">2</span>
                <span class="pt-1">When you find an interesting page, click the bookmarklet</span>
              </li>
              <li class="flex gap-3">
                <span class="flex-shrink-0 w-8 h-8 bg-purple-500 rounded-full flex items-center justify-center text-white font-bold">3</span>
                <span class="pt-1">The link is saved and others can stumble upon it!</span>
              </li>
            </ol>
          </div>

          <!-- Back Link -->
          <div class="text-center mt-8">
            <.link navigate="/" class="text-purple-300 hover:text-white transition-colors">
              ← Back to stumbling
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp bookmarklet_code(base_url) do
    # JavaScript bookmarklet code
    js = """
    (function(){
      var url=encodeURIComponent(window.location.href);
      var title=encodeURIComponent(document.title);
      fetch('#{base_url}/api/links',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({url:decodeURIComponent(url),title:decodeURIComponent(title)})
      })
      .then(r=>r.json())
      .then(d=>alert('PokeAround: '+d.message))
      .catch(e=>alert('Error saving link'));
    })();
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()

    "javascript:#{js}"
  end
end
