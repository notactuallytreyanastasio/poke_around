defmodule Mix.Tasks.Poke.TagAxon do
  @moduledoc """
  Run the Axon tagger to process untagged links.

  ## Usage

      # Tag with defaults (English only, 0.25 threshold)
      mix poke.tag_axon

      # Custom settings
      mix poke.tag_axon --threshold 0.3 --batch 50 --all-langs

      # One-shot mode (process once, don't loop)
      mix poke.tag_axon --once

  ## Options

    * `--threshold` or `-t` - Minimum confidence threshold (default: 0.25)
    * `--batch` or `-b` - Batch size (default: 20)
    * `--interval` or `-i` - Seconds between batches (default: 10)
    * `--all-langs` - Process all languages, not just English
    * `--once` - Process one batch and exit
    * `--model` or `-m` - Model path (default: priv/models/tagger)
  """

  use Mix.Task

  require Logger

  alias PokeAround.AI.AxonTagger

  @shortdoc "Process untagged links using Axon model"

  @impl Mix.Task
  def run(args) do
    # Ensure XLA uses CPU target (optimized for Apple Silicon)
    System.put_env("XLA_TARGET", System.get_env("XLA_TARGET") || "cpu")
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          threshold: :float,
          batch: :integer,
          interval: :integer,
          all_langs: :boolean,
          once: :boolean,
          model: :string
        ],
        aliases: [t: :threshold, b: :batch, i: :interval, m: :model]
      )

    threshold = opts[:threshold] || 0.25
    batch_size = opts[:batch] || 20
    interval = (opts[:interval] || 10) * 1000
    langs = if opts[:all_langs], do: [], else: ["en"]
    once = opts[:once] || false
    model_path = opts[:model] || "priv/models/tagger"

    # Start required applications
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:exla)
    Mix.Task.run("app.config")
    {:ok, _} = PokeAround.Repo.start_link([])

    # Set EXLA backend
    Nx.default_backend(EXLA.Backend)

    IO.puts("""

    ╔══════════════════════════════════════════════════════════════╗
    ║               🧠 AXON TAGGER                                 ║
    ╠══════════════════════════════════════════════════════════════╣
    ║  Model: #{String.pad_trailing(model_path, 42)} ║
    ║  Threshold: #{String.pad_trailing("#{threshold}", 38)} ║
    ║  Batch size: #{String.pad_trailing("#{batch_size}", 37)} ║
    ║  Interval: #{String.pad_trailing("#{div(interval, 1000)}s", 39)} ║
    ║  Languages: #{String.pad_trailing(if(langs == [], do: "all", else: inspect(langs)), 38)} ║
    ║  Mode: #{String.pad_trailing(if(once, do: "one-shot", else: "continuous"), 43)} ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    if once do
      # One-shot mode: start, process once, exit
      {:ok, pid} = AxonTagger.start_link(
        model_path: model_path,
        threshold: threshold,
        batch_size: batch_size,
        langs: langs,
        auto_tag: false
      )

      IO.puts("Processing one batch...")
      AxonTagger.process_batch(pid)
      # Give it time to process
      :timer.sleep(5000)
      stats = AxonTagger.stats(pid)
      IO.puts("\n✅ Complete! Tagged #{stats.tagged} links, #{stats.errors} errors")
    else
      # Continuous mode
      {:ok, _pid} = AxonTagger.start_link(
        model_path: model_path,
        threshold: threshold,
        batch_size: batch_size,
        interval: interval,
        langs: langs,
        auto_tag: true
      )

      IO.puts("Tagger running. Press Ctrl+C to stop.\n")

      # Keep the process alive
      receive do
        :stop -> :ok
      end
    end
  end
end
