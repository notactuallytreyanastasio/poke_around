defmodule PokeAround.ATProto.TID do
  @moduledoc """
  Generate TID (Timestamp Identifier) for ATProto record keys.

  TID format: 13-character base32-sortable string encoding:
  - 53 bits: microseconds since Unix epoch
  - 10 bits: clock identifier (random per process)

  TIDs are designed to be:
  - Globally unique
  - Roughly time-ordered (sortable)
  - URL-safe
  """

  use Agent
  import Bitwise

  @base32_chars "234567abcdefghijklmnopqrstuvwxyz"

  @doc """
  Start the TID agent with a random clock ID.
  """
  def start_link(_opts \\ []) do
    clock_id = :rand.uniform(1024) - 1
    Agent.start_link(fn -> clock_id end, name: __MODULE__)
  end

  @doc """
  Generate a new TID.

  Returns a 13-character base32-sortable string.

  ## Examples

      iex> tid = PokeAround.ATProto.TID.generate()
      iex> String.length(tid)
      13

  """
  def generate do
    timestamp_us = System.os_time(:microsecond)
    clock_id = get_clock_id()

    # Combine: 53 bits timestamp + 10 bits clock_id = 63 bits
    # We use the lower 53 bits of the timestamp
    timestamp_bits = timestamp_us &&& ((1 <<< 53) - 1)
    combined = (timestamp_bits <<< 10) ||| (clock_id &&& 0x3FF)

    encode_base32(combined)
  end

  @doc """
  Parse a TID and return the timestamp as DateTime.

  ## Examples

      iex> {:ok, dt} = PokeAround.ATProto.TID.to_datetime("3k2yihx5l3s22")
      iex> dt.year
      2024

  """
  def to_datetime(tid) when is_binary(tid) and byte_size(tid) == 13 do
    case decode_base32(tid) do
      {:ok, combined} ->
        timestamp_us = combined >>> 10
        {:ok, DateTime.from_unix!(timestamp_us, :microsecond)}

      {:error, _} = error ->
        error
    end
  end

  def to_datetime(_), do: {:error, :invalid_tid}

  @doc """
  Check if a string is a valid TID format.
  """
  def valid?(tid) when is_binary(tid) and byte_size(tid) == 13 do
    tid
    |> String.graphemes()
    |> Enum.all?(&String.contains?(@base32_chars, &1))
  end

  def valid?(_), do: false

  # Private functions

  defp get_clock_id do
    case Process.whereis(__MODULE__) do
      nil ->
        # Fallback if agent not started - use random
        :rand.uniform(1024) - 1

      _pid ->
        Agent.get(__MODULE__, & &1)
    end
  end

  defp encode_base32(value) do
    # Encode 63 bits into 13 base32 characters (5 bits each, 65 bits capacity)
    # We pad from the left
    chars = @base32_chars

    0..12
    |> Enum.map(fn i ->
      shift = (12 - i) * 5
      index = (value >>> shift) &&& 0x1F
      String.at(chars, index)
    end)
    |> Enum.join()
  end

  defp decode_base32(str) do
    chars = @base32_chars

    result =
      str
      |> String.graphemes()
      |> Enum.reduce_while({:ok, 0}, fn char, {:ok, acc} ->
        case :binary.match(chars, char) do
          {index, 1} ->
            {:cont, {:ok, (acc <<< 5) ||| index}}

          :nomatch ->
            {:halt, {:error, :invalid_character}}
        end
      end)

    result
  end
end
