defmodule Mix.Tasks.Poke.Train do
  @moduledoc """
  Train the Axon-based text classifier on existing tagged links.

  ## Usage

      # Train with defaults
      mix poke.train

      # Custom epochs
      mix poke.train --epochs 30

      # Save to custom path
      mix poke.train --output priv/models/tagger_v2

  ## Options

    * `--epochs` or `-e` - Number of training epochs (default: 20)
    * `--batch-size` or `-b` - Batch size (default: 32)
    * `--min-tags` - Minimum tag count to include (default: 5)
    * `--output` or `-o` - Output path for model (default: priv/models/tagger)
    * `--test` - Run test predictions after training
    * `--from-file` - Train from priv/ml/training_data.json instead of database
  """

  use Mix.Task

  require Logger

  alias PokeAround.AI.Axon.TextClassifier

  @shortdoc "Train the Axon tagger on existing data"

  @default_epochs 20
  @default_batch_size 32
  @default_min_tags 5
  @default_output "priv/models/tagger"

  @impl Mix.Task
  def run(args) do
    # Ensure XLA uses CPU target (optimized for Apple Silicon)
    System.put_env("XLA_TARGET", System.get_env("XLA_TARGET") || "cpu")
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          epochs: :integer,
          batch_size: :integer,
          min_tags: :integer,
          output: :string,
          test: :boolean,
          from_file: :boolean
        ],
        aliases: [e: :epochs, b: :batch_size, o: :output]
      )

    epochs = opts[:epochs] || @default_epochs
    batch_size = opts[:batch_size] || @default_batch_size
    min_tags = opts[:min_tags] || @default_min_tags
    output_path = opts[:output] || @default_output
    run_test = opts[:test] || false
    from_file = opts[:from_file] || false

    # Start required apps
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:exla)
    Mix.Task.run("app.config")
    {:ok, _} = PokeAround.Repo.start_link([])

    # Set EXLA as default backend
    Nx.default_backend(EXLA.Backend)

    data_source = if from_file, do: "priv/ml/training_data.json", else: "database"

    IO.puts("""

    ╔══════════════════════════════════════════════════════════════╗
    ║               🧠 AXON TAGGER TRAINING                        ║
    ╠══════════════════════════════════════════════════════════════╣
    ║  Data source: #{String.pad_trailing(data_source, 14)}                   ║
    ║  Epochs: #{String.pad_trailing("#{epochs}", 20)}                   ║
    ║  Batch size: #{String.pad_trailing("#{batch_size}", 16)}                   ║
    ║  Min tag count: #{String.pad_trailing("#{min_tags}", 13)}                   ║
    ║  Output: #{String.pad_trailing(output_path, 20)}                   ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    # Step 1: Prepare training data
    IO.puts("📊 Step 1: Preparing training data...")
    start_time = System.monotonic_time(:second)

    {inputs, labels, vocab, tag_index} =
      if from_file do
        TextClassifier.prepare_training_data_from_file(min_tag_count: min_tags)
      else
        TextClassifier.prepare_training_data(min_tag_count: min_tags)
      end

    data_time = System.monotonic_time(:second) - start_time
    IO.puts("   ✓ Data prepared in #{data_time}s")
    IO.puts("   • #{Nx.axis_size(inputs, 0)} training samples")
    IO.puts("   • #{map_size(vocab)} word vocabulary")
    IO.puts("   • #{map_size(tag_index)} target tags")

    # Step 2: Build model
    IO.puts("\n🏗️  Step 2: Building model...")
    model = TextClassifier.build_model(
      vocab_size: map_size(vocab),
      num_tags: map_size(tag_index)
    )
    IO.puts("   ✓ Model architecture created")
    IO.puts("   #{inspect(Axon.get_output_shape(model, %{"input" => Nx.template({1, 128}, :s32)}))}")

    # Step 3: Train
    IO.puts("\n🚀 Step 3: Training (#{epochs} epochs)...")
    train_start = System.monotonic_time(:second)

    trained_state = TextClassifier.train(model, inputs, labels,
      epochs: epochs,
      batch_size: batch_size
    )

    train_time = System.monotonic_time(:second) - train_start
    IO.puts("\n   ✓ Training complete in #{train_time}s")

    # Step 4: Save model
    IO.puts("\n💾 Step 4: Saving model...")
    TextClassifier.save_model(trained_state, vocab, tag_index, output_path)
    IO.puts("   ✓ Model saved to #{output_path}")

    # Step 5: Test predictions (optional)
    if run_test do
      IO.puts("\n🧪 Step 5: Testing predictions...")
      run_test_predictions(model, trained_state, vocab, tag_index)
    end

    total_time = System.monotonic_time(:second) - start_time
    IO.puts("\n✅ Complete! Total time: #{total_time}s")
  end

  defp run_test_predictions(model, state, vocab, tag_index) do
    test_texts = [
      "New JavaScript framework released with React-like syntax and better performance",
      "Trump announces new immigration policy affecting border states",
      "Manchester United wins premier league match against Liverpool",
      "Bitcoin reaches new all-time high as institutional investors buy",
      "NASA discovers new exoplanet in habitable zone",
      "Heavy rain and thunderstorms expected across the midwest today"
    ]

    Enum.each(test_texts, fn text ->
      predictions = TextClassifier.predict_simple(model, state, text, vocab, tag_index)
      tags = Enum.map(predictions, fn {tag, prob} -> "#{tag}(#{prob})" end)

      IO.puts("\n   Text: #{String.slice(text, 0, 60)}...")
      IO.puts("   Tags: #{Enum.join(tags, ", ")}")
    end)
  end
end
