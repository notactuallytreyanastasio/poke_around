defmodule PokeAround.ATProto.TIDTest do
  use ExUnit.Case, async: true

  alias PokeAround.ATProto.TID

  describe "generate/0" do
    test "returns a 13-character string" do
      tid = TID.generate()
      assert String.length(tid) == 13
    end

    test "uses only base32-sortable characters" do
      tid = TID.generate()
      # Base32-sortable uses: 234567abcdefghijklmnopqrstuvwxyz
      assert Regex.match?(~r/^[234567a-z]+$/, tid)
    end

    test "generates unique values" do
      tids = for _ <- 1..100, do: TID.generate()
      unique_tids = Enum.uniq(tids)
      assert length(unique_tids) == 100
    end

    test "generates roughly time-ordered values" do
      tid1 = TID.generate()
      Process.sleep(1)
      tid2 = TID.generate()
      # Lexicographic ordering should work for time-based TIDs
      assert tid1 < tid2
    end
  end

  describe "to_datetime/1" do
    test "parses valid TID to DateTime" do
      tid = TID.generate()
      assert {:ok, %DateTime{}} = TID.to_datetime(tid)
    end

    test "returns DateTime close to current time" do
      tid = TID.generate()
      {:ok, dt} = TID.to_datetime(tid)

      now = DateTime.utc_now()
      diff_seconds = abs(DateTime.diff(now, dt, :second))
      # Should be within 1 second of now
      assert diff_seconds < 1
    end

    test "returns error for invalid TID length" do
      assert {:error, :invalid_tid} = TID.to_datetime("short")
      assert {:error, :invalid_tid} = TID.to_datetime("this-is-way-too-long")
    end

    test "returns error for invalid characters" do
      # Using characters not in base32-sortable (0, 1, 8, 9)
      assert {:error, :invalid_character} = TID.to_datetime("0000000000000")
    end

    test "returns error for nil" do
      assert {:error, :invalid_tid} = TID.to_datetime(nil)
    end

    test "roundtrip preserves time (within clock_id variance)" do
      # Generate a TID and parse it back
      tid = TID.generate()
      {:ok, dt} = TID.to_datetime(tid)

      # The datetime should be recent (within last second)
      now = DateTime.utc_now()
      diff_us = DateTime.diff(now, dt, :microsecond)
      assert diff_us >= 0 and diff_us < 1_000_000
    end
  end

  describe "valid?/1" do
    test "returns true for valid TID" do
      tid = TID.generate()
      assert TID.valid?(tid) == true
    end

    test "returns true for known valid TID format" do
      # All valid base32-sortable characters
      assert TID.valid?("2345672345672") == true
      assert TID.valid?("abcdefghijklm") == true
    end

    test "returns false for wrong length" do
      assert TID.valid?("short") == false
      assert TID.valid?("this-is-too-long") == false
      assert TID.valid?("") == false
    end

    test "returns false for invalid characters" do
      # 0, 1, 8, 9 are not in base32-sortable alphabet
      assert TID.valid?("0000000000000") == false
      assert TID.valid?("1111111111111") == false
      assert TID.valid?("8888888888888") == false
      assert TID.valid?("9999999999999") == false
      # Uppercase not allowed
      assert TID.valid?("ABCDEFGHIJKLM") == false
    end

    test "returns false for nil" do
      assert TID.valid?(nil) == false
    end

    test "returns false for non-string" do
      assert TID.valid?(12345) == false
      assert TID.valid?([]) == false
    end
  end

  describe "start_link/1" do
    test "starts the agent" do
      # Stop if already running from another test
      if Process.whereis(TID), do: Agent.stop(TID)

      assert {:ok, pid} = TID.start_link()
      assert is_pid(pid)
      assert Process.whereis(TID) == pid

      Agent.stop(TID)
    end
  end
end
