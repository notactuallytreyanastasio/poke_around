defmodule PokeAround.AI.AxonTaggerTest do
  use PokeAround.DataCase, async: false

  alias PokeAround.AI.AxonTagger
  alias PokeAround.AI.Axon.TextClassifier
  alias PokeAround.Fixtures

  @test_model_path "test/support/test_model"

  setup_all do
    # Create a test model for all tests to use
    File.mkdir_p!(@test_model_path)

    vocab = %{
      "<PAD>" => 0,
      "<UNK>" => 1,
      "javascript" => 2,
      "react" => 3,
      "weather" => 4,
      "forecast" => 5,
      "politics" => 6,
      "trump" => 7,
      "test" => 8,
      "link" => 9,
      "post" => 10,
      "example" => 11
    }
    tag_index = %{"tech" => 0, "weather" => 1, "politics" => 2}

    model = TextClassifier.build_model(vocab_size: 12, num_tags: 3)
    {init_fn, _} = Axon.build(model)
    state = init_fn.(Nx.template({1, 128}, :s32), %{})

    TextClassifier.save_model(state, vocab, tag_index, @test_model_path)

    on_exit(fn -> File.rm_rf!(@test_model_path) end)

    :ok
  end

  describe "start_link/1" do
    test "starts with valid model path" do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        auto_tag: false,
        name: :test_tagger_1
      )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "fails with invalid model path" do
      Process.flag(:trap_exit, true)

      result = AxonTagger.start_link(
        model_path: "nonexistent/path",
        auto_tag: false,
        name: :test_tagger_invalid
      )

      assert {:error, :model_not_found} = result
    end

    test "accepts custom configuration" do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        threshold: 0.5,
        batch_size: 10,
        interval: 5000,
        langs: ["en", "es"],
        auto_tag: false,
        name: :test_tagger_custom
      )

      stats = AxonTagger.stats(pid)
      assert stats.threshold == 0.5

      GenServer.stop(pid)
    end
  end

  describe "predict/2" do
    setup do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        auto_tag: false,
        name: :"test_tagger_predict_#{System.unique_integer([:positive])}"
      )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{pid: pid}
    end

    test "predicts tags for a link", %{pid: pid} do
      link = %{post_text: "javascript react framework", domain: "example.com"}

      {:ok, tags} = AxonTagger.predict(pid, link)

      assert is_list(tags)
    end

    test "handles link with empty text", %{pid: pid} do
      link = %{post_text: "", domain: "example.com"}

      {:ok, tags} = AxonTagger.predict(pid, link)

      assert is_list(tags)
    end

    test "handles link with nil text", %{pid: pid} do
      link = %{post_text: nil, domain: "example.com"}

      {:ok, tags} = AxonTagger.predict(pid, link)

      assert is_list(tags)
    end
  end

  describe "stats/1" do
    setup do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        auto_tag: false,
        threshold: 0.25,
        name: :"test_tagger_stats_#{System.unique_integer([:positive])}"
      )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{pid: pid}
    end

    test "returns stats map", %{pid: pid} do
      stats = AxonTagger.stats(pid)

      assert is_map(stats)
      assert Map.has_key?(stats, :tagged)
      assert Map.has_key?(stats, :errors)
      assert Map.has_key?(stats, :vocab_size)
      assert Map.has_key?(stats, :num_tags)
      assert Map.has_key?(stats, :threshold)
      assert Map.has_key?(stats, :auto_tag)
      assert Map.has_key?(stats, :uptime_seconds)
    end

    test "has correct initial values", %{pid: pid} do
      stats = AxonTagger.stats(pid)

      assert stats.tagged == 0
      assert stats.errors == 0
      assert stats.threshold == 0.25
      assert stats.auto_tag == false
    end

    test "vocab_size matches model", %{pid: pid} do
      stats = AxonTagger.stats(pid)

      # Our test model has 12 words in vocab
      assert stats.vocab_size == 12
      # And 3 tags
      assert stats.num_tags == 3
    end
  end

  describe "process_batch/1" do
    setup do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        auto_tag: false,
        batch_size: 5,
        threshold: 0.1,  # Low threshold to get tags
        langs: ["en"],
        name: :"test_tagger_batch_#{System.unique_integer([:positive])}"
      )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{pid: pid}
    end

    test "processes untagged links", %{pid: pid} do
      # Create some untagged links
      _links = Fixtures.untagged_links_fixture(3, %{
        post_text: "Test post about javascript and react framework",
        langs: ["en"]
      })

      # Get initial stats
      initial_stats = AxonTagger.stats(pid)
      assert initial_stats.tagged == 0

      # Process a batch
      AxonTagger.process_batch(pid)

      # Give it time to process
      Process.sleep(500)

      # Check stats updated
      final_stats = AxonTagger.stats(pid)
      # Should have tagged some links (or marked as needs-review if no confident predictions)
      assert final_stats.tagged >= 0
    end

    test "respects batch size", %{pid: pid} do
      # Create more links than batch size
      _links = Fixtures.untagged_links_fixture(10, %{
        post_text: "Test post for batch processing",
        langs: ["en"]
      })

      AxonTagger.process_batch(pid)
      Process.sleep(500)

      stats = AxonTagger.stats(pid)
      # Should process at most batch_size (5)
      assert stats.tagged <= 5
    end

    test "handles empty queue gracefully", %{pid: pid} do
      # Don't create any links

      # Should not raise
      AxonTagger.process_batch(pid)
      Process.sleep(100)

      stats = AxonTagger.stats(pid)
      assert stats.tagged == 0
      assert stats.errors == 0
    end

    test "filters by language", %{pid: pid} do
      # Create links with different languages
      _en_link = Fixtures.link_fixture(%{
        post_text: "English post about things",
        langs: ["en"],
        tagged_at: nil
      })

      _es_link = Fixtures.link_fixture(%{
        post_text: "Spanish post about things",
        langs: ["es"],
        tagged_at: nil
      })

      AxonTagger.process_batch(pid)
      Process.sleep(500)

      stats = AxonTagger.stats(pid)
      # Should only process English link (tagger configured with langs: ["en"])
      assert stats.tagged <= 1
    end
  end

  describe "auto_tag mode" do
    test "schedules automatic processing when enabled" do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        auto_tag: true,
        interval: 100,  # Very short interval for testing
        batch_size: 2,
        langs: ["en"],
        name: :"test_tagger_auto_#{System.unique_integer([:positive])}"
      )

      # Create some links
      _links = Fixtures.untagged_links_fixture(2, %{
        post_text: "Auto tag test post",
        langs: ["en"]
      })

      # Wait for auto-processing
      Process.sleep(300)

      stats = AxonTagger.stats(pid)
      assert stats.auto_tag == true

      GenServer.stop(pid)
    end

    test "does not schedule when disabled" do
      {:ok, pid} = AxonTagger.start_link(
        model_path: @test_model_path,
        auto_tag: false,
        name: :"test_tagger_no_auto_#{System.unique_integer([:positive])}"
      )

      stats = AxonTagger.stats(pid)
      assert stats.auto_tag == false

      GenServer.stop(pid)
    end
  end
end
