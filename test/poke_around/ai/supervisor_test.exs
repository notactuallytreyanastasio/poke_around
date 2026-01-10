defmodule PokeAround.AI.SupervisorTest do
  use ExUnit.Case, async: false

  alias PokeAround.AI.Supervisor, as: AISupervisor
  alias PokeAround.AI.Axon.TextClassifier

  @test_model_path "test/support/test_model_supervisor"

  setup_all do
    # Create a test model
    File.mkdir_p!(@test_model_path)

    vocab = %{"<PAD>" => 0, "<UNK>" => 1, "test" => 2}
    tag_index = %{"test-tag" => 0}

    model = TextClassifier.build_model(vocab_size: 3, num_tags: 1)
    {init_fn, _} = Axon.build(model)
    state = init_fn.(Nx.template({1, 128}, :s32), %{})

    TextClassifier.save_model(state, vocab, tag_index, @test_model_path)

    on_exit(fn -> File.rm_rf!(@test_model_path) end)

    :ok
  end

  setup do
    # Save original config before each test
    original_config = Application.get_env(:poke_around, PokeAround.AI.AxonTagger)
    on_exit(fn -> Application.put_env(:poke_around, PokeAround.AI.AxonTagger, original_config) end)
    %{original_config: original_config}
  end

  describe "start_link/1" do
    test "starts supervisor successfully with disabled tagger" do
      Application.put_env(:poke_around, PokeAround.AI.AxonTagger, [enabled: false])

      name = :"test_ai_supervisor_#{System.unique_integer([:positive])}"
      {:ok, pid} = AISupervisor.start_link(name: name)
      assert Process.alive?(pid)

      Supervisor.stop(pid)
    end
  end

  describe "init/1" do
    test "starts AxonTagger when enabled with valid model" do
      Application.put_env(:poke_around, PokeAround.AI.AxonTagger, [
        enabled: true,
        model_path: @test_model_path,
        threshold: 0.25,
        batch_size: 10,
        interval_ms: 10000,
        langs: ["en"]
      ])

      name = :"test_ai_supervisor_enabled_#{System.unique_integer([:positive])}"
      {:ok, pid} = AISupervisor.start_link(name: name)

      Process.sleep(100)

      children = Supervisor.which_children(pid)
      assert length(children) == 1

      {_id, child_pid, _type, _modules} = hd(children)
      assert Process.alive?(child_pid)

      Supervisor.stop(pid)
    end

    test "does not start AxonTagger when disabled" do
      Application.put_env(:poke_around, PokeAround.AI.AxonTagger, [enabled: false])

      name = :"test_ai_supervisor_disabled_#{System.unique_integer([:positive])}"
      {:ok, pid} = AISupervisor.start_link(name: name)

      Process.sleep(100)

      children = Supervisor.which_children(pid)
      assert children == []

      Supervisor.stop(pid)
    end

    test "passes config options to AxonTagger" do
      Application.put_env(:poke_around, PokeAround.AI.AxonTagger, [
        enabled: true,
        model_path: @test_model_path,
        threshold: 0.5,
        batch_size: 25,
        interval_ms: 15000,
        langs: ["en", "es"]
      ])

      name = :"test_ai_supervisor_config_#{System.unique_integer([:positive])}"
      {:ok, pid} = AISupervisor.start_link(name: name)

      Process.sleep(100)

      [{_id, tagger_pid, _type, _modules}] = Supervisor.which_children(pid)

      stats = PokeAround.AI.AxonTagger.stats(tagger_pid)
      assert stats.threshold == 0.5

      Supervisor.stop(pid)
    end
  end
end
