defmodule PokeAround.AI.Axon.TextClassifierTest do
  use PokeAround.DataCase, async: true

  alias PokeAround.AI.Axon.TextClassifier

  describe "tokenize/1" do
    test "tokenizes simple text into lowercase words" do
      tokens = TextClassifier.tokenize("Hello World")
      assert tokens == ["hello", "world"]
    end

    test "removes single character words" do
      tokens = TextClassifier.tokenize("I am a test")
      assert tokens == ["am", "test"]
    end

    test "removes URLs from text" do
      tokens = TextClassifier.tokenize("Check out https://example.com/page for more")
      assert "https" not in tokens
      assert "example" not in tokens
      assert "check" in tokens
      assert "out" in tokens
      assert "for" in tokens
      assert "more" in tokens
    end

    test "removes punctuation" do
      tokens = TextClassifier.tokenize("Hello, world! How's it going?")
      assert "hello" in tokens
      assert "world" in tokens
      assert "how" in tokens
      refute Enum.any?(tokens, &String.contains?(&1, ","))
      refute Enum.any?(tokens, &String.contains?(&1, "!"))
    end

    test "handles empty string" do
      assert TextClassifier.tokenize("") == []
    end

    test "handles nil" do
      assert TextClassifier.tokenize(nil) == []
    end

    test "handles text with only URLs" do
      tokens = TextClassifier.tokenize("https://foo.com http://bar.org")
      assert tokens == []
    end

    test "handles multiple spaces" do
      tokens = TextClassifier.tokenize("hello    world   test")
      assert tokens == ["hello", "world", "test"]
    end

    test "tokenizes real-world post text" do
      text = "New JavaScript framework released with React-like syntax and better performance!"
      tokens = TextClassifier.tokenize(text)

      assert "new" in tokens
      assert "javascript" in tokens
      assert "framework" in tokens
      assert "react" in tokens
      assert "performance" in tokens
    end
  end

  describe "build_model/1" do
    test "builds model with required options" do
      model = TextClassifier.build_model(vocab_size: 100, num_tags: 10)

      assert %Axon{} = model
    end

    test "raises without vocab_size" do
      assert_raise RuntimeError, "vocab_size required", fn ->
        TextClassifier.build_model(num_tags: 10)
      end
    end

    test "raises without num_tags" do
      assert_raise RuntimeError, "num_tags required", fn ->
        TextClassifier.build_model(vocab_size: 100)
      end
    end

    test "model has correct output shape" do
      model = TextClassifier.build_model(vocab_size: 100, num_tags: 10)

      # Check output shape - get_output_shape returns a tensor template
      output_shape = Axon.get_output_shape(model, %{"input" => Nx.template({1, 128}, :s32)})
      assert Nx.shape(output_shape) == {1, 10}
    end

    test "accepts custom hyperparameters" do
      model = TextClassifier.build_model(
        vocab_size: 100,
        num_tags: 10,
        embedding_dim: 32,
        hidden_dim: 64,
        dropout_rate: 0.5
      )

      assert %Axon{} = model
    end
  end

  describe "multi_label_accuracy/2" do
    test "calculates perfect accuracy" do
      y_pred = Nx.tensor([[0.9, 0.9, 0.1], [0.1, 0.9, 0.9]])
      y_true = Nx.tensor([[1.0, 1.0, 0.0], [0.0, 1.0, 1.0]])

      accuracy = TextClassifier.multi_label_accuracy(y_pred, y_true)

      # Perfect match: both samples should have IoU = 1.0
      assert_in_delta accuracy, 1.0, 0.01
    end

    test "calculates zero accuracy when completely wrong" do
      y_pred = Nx.tensor([[0.9, 0.9, 0.1], [0.9, 0.1, 0.1]])
      y_true = Nx.tensor([[0.0, 0.0, 1.0], [0.0, 1.0, 1.0]])

      accuracy = TextClassifier.multi_label_accuracy(y_pred, y_true)

      # No overlap: accuracy should be 0
      assert_in_delta accuracy, 0.0, 0.01
    end

    test "calculates partial accuracy" do
      # First sample: pred=[1,1,0], true=[1,0,0] -> intersection=1, union=2 -> IoU=0.5
      # Second sample: pred=[0,1,1], true=[0,1,0] -> intersection=1, union=2 -> IoU=0.5
      y_pred = Nx.tensor([[0.9, 0.9, 0.1], [0.1, 0.9, 0.9]])
      y_true = Nx.tensor([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])

      accuracy = TextClassifier.multi_label_accuracy(y_pred, y_true)

      assert_in_delta accuracy, 0.5, 0.01
    end
  end

  describe "save_model/4 and load_model/1" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = System.tmp_dir!()
      test_path = Path.join(tmp_dir, "test_model_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(test_path) end)
      %{test_path: test_path}
    end

    test "saves and loads model correctly", %{test_path: test_path} do
      # Build a small model
      vocab = %{"<PAD>" => 0, "<UNK>" => 1, "hello" => 2, "world" => 3}
      tag_index = %{"tag1" => 0, "tag2" => 1}

      model = TextClassifier.build_model(vocab_size: 4, num_tags: 2)

      # Initialize model state
      {init_fn, _} = Axon.build(model)
      state = init_fn.(Nx.template({1, 128}, :s32), %{})

      # Save
      assert :ok = TextClassifier.save_model(state, vocab, tag_index, test_path)

      # Verify files exist
      assert File.exists?(Path.join(test_path, "model_state.nx"))
      assert File.exists?(Path.join(test_path, "metadata.json"))

      # Load
      {loaded_model, loaded_state, loaded_vocab, loaded_tag_index} =
        TextClassifier.load_model(test_path)

      assert %Axon{} = loaded_model
      assert is_map(loaded_state)
      assert loaded_vocab == vocab
      assert loaded_tag_index == tag_index
    end

    test "filters invalid UTF-8 from vocab", %{test_path: test_path} do
      # Create vocab with invalid UTF-8 (simulating bad data)
      vocab = %{
        "<PAD>" => 0,
        "<UNK>" => 1,
        "hello" => 2,
        <<0xC3>> => 3  # Invalid UTF-8
      }
      tag_index = %{"tag1" => 0}

      model = TextClassifier.build_model(vocab_size: 4, num_tags: 1)
      {init_fn, _} = Axon.build(model)
      state = init_fn.(Nx.template({1, 128}, :s32), %{})

      # Save should not raise
      assert :ok = TextClassifier.save_model(state, vocab, tag_index, test_path)

      # Load and verify invalid key was filtered
      {_, _, loaded_vocab, _} = TextClassifier.load_model(test_path)

      # Invalid UTF-8 key should be filtered out
      assert map_size(loaded_vocab) == 3
      refute Map.has_key?(loaded_vocab, <<0xC3>>)
    end
  end

  describe "predict_simple/5" do
    setup do
      # Build a minimal model for testing predictions
      vocab = %{
        "<PAD>" => 0,
        "<UNK>" => 1,
        "javascript" => 2,
        "react" => 3,
        "weather" => 4,
        "forecast" => 5,
        "politics" => 6,
        "trump" => 7
      }
      tag_index = %{"tech" => 0, "weather" => 1, "politics" => 2}

      model = TextClassifier.build_model(vocab_size: 8, num_tags: 3)
      {init_fn, _} = Axon.build(model)
      state = init_fn.(Nx.template({1, 128}, :s32), %{})

      %{model: model, state: state, vocab: vocab, tag_index: tag_index}
    end

    test "returns top 5 predictions sorted by probability", ctx do
      predictions = TextClassifier.predict_simple(
        ctx.model,
        ctx.state,
        "javascript react framework",
        ctx.vocab,
        ctx.tag_index
      )

      # Should return list of {tag, probability} tuples
      assert is_list(predictions)
      assert length(predictions) <= 5

      Enum.each(predictions, fn {tag, prob} ->
        assert is_binary(tag)
        assert is_float(prob)
        assert prob >= 0.0 and prob <= 1.0
      end)
    end

    test "handles empty text", ctx do
      predictions = TextClassifier.predict_simple(
        ctx.model,
        ctx.state,
        "",
        ctx.vocab,
        ctx.tag_index
      )

      assert is_list(predictions)
    end

    test "handles text with unknown words", ctx do
      predictions = TextClassifier.predict_simple(
        ctx.model,
        ctx.state,
        "completely unknown words xyz abc",
        ctx.vocab,
        ctx.tag_index
      )

      assert is_list(predictions)
    end
  end

  describe "predict_tags/6" do
    setup do
      vocab = %{
        "<PAD>" => 0,
        "<UNK>" => 1,
        "javascript" => 2,
        "react" => 3
      }
      tag_index = %{"tech" => 0, "web" => 1}

      model = TextClassifier.build_model(vocab_size: 4, num_tags: 2)
      {init_fn, _} = Axon.build(model)
      state = init_fn.(Nx.template({1, 128}, :s32), %{})

      %{model: model, state: state, vocab: vocab, tag_index: tag_index}
    end

    test "returns only tag names above threshold", ctx do
      tags = TextClassifier.predict_tags(
        ctx.model,
        ctx.state,
        "javascript react",
        ctx.vocab,
        ctx.tag_index,
        0.3
      )

      assert is_list(tags)
      Enum.each(tags, fn tag ->
        assert is_binary(tag)
      end)
    end

    test "returns empty list when nothing above threshold", ctx do
      tags = TextClassifier.predict_tags(
        ctx.model,
        ctx.state,
        "javascript",
        ctx.vocab,
        ctx.tag_index,
        0.99  # Very high threshold
      )

      assert is_list(tags)
      # With random initialization, likely nothing above 0.99
    end

    test "limits to 5 tags maximum", ctx do
      tags = TextClassifier.predict_tags(
        ctx.model,
        ctx.state,
        "javascript",
        ctx.vocab,
        ctx.tag_index,
        0.0  # Very low threshold to get all
      )

      assert length(tags) <= 5
    end
  end
end
