defmodule NostrCore.NIP19.TLV do
  @moduledoc """
  Simple TLV (Type-Length-Value) encoding for NIP-19 shareable identifiers.

  NIP-19 uses 1-byte type, 1-byte length, variable value.
  """

  @type tlv_type :: 0..255
  @type tlv_entry :: {tlv_type(), binary()}
  @type encode_reason :: :invalid_type | :invalid_value | :value_too_long | :invalid_entries

  @special 0
  @relay 1
  @author 2
  @kind 3

  def special, do: @special
  def relay, do: @relay
  def author, do: @author
  def kind, do: @kind

  @doc """
  Encode a single TLV entry.
  """
  @spec encode_tlv(term(), term()) :: {:ok, binary()} | {:error, encode_reason()}
  def encode_tlv(type, value)
      when is_integer(type) and type >= 0 and type <= 255 and is_binary(value) do
    if byte_size(value) <= 255 do
      {:ok, <<type::8, byte_size(value)::8, value::binary>>}
    else
      {:error, :value_too_long}
    end
  end

  def encode_tlv(type, _value) when not is_integer(type) or type < 0 or type > 255,
    do: {:error, :invalid_type}

  def encode_tlv(_type, _value), do: {:error, :invalid_value}

  @doc "Bang variant of `encode_tlv/2`."
  @spec encode_tlv!(term(), term()) :: binary()
  def encode_tlv!(type, value) do
    case encode_tlv(type, value) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, "could not encode TLV: #{inspect(reason)}"
    end
  end

  @doc """
  Encode a list of TLV entries.
  """
  @spec encode_tlvs(term()) :: {:ok, binary()} | {:error, encode_reason()}
  def encode_tlvs(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, <<>>}, fn
      {type, value}, {:ok, acc} ->
        case encode_tlv(type, value) do
          {:ok, encoded} -> {:cont, {:ok, acc <> encoded}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _entry, _acc ->
        {:halt, {:error, :invalid_entries}}
    end)
  end

  def encode_tlvs(_), do: {:error, :invalid_entries}

  @doc "Bang variant of `encode_tlvs/1`."
  @spec encode_tlvs!(term()) :: binary()
  def encode_tlvs!(entries) do
    case encode_tlvs(entries) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, "could not encode TLVs: #{inspect(reason)}"
    end
  end

  @doc """
  Decode binary into a list of TLV entries.

  Ignores unknown types and handles trailing zero padding.
  """
  @spec decode_tlvs(binary()) :: {:ok, [tlv_entry()]} | {:error, :incomplete_tlv}
  def decode_tlvs(data) when is_binary(data) do
    decode_tlvs_acc(data, [])
  end

  defp decode_tlvs_acc(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  # Trailing zero padding from bech32 5-to-8 conversion
  defp decode_tlvs_acc(<<0>>, acc), do: {:ok, Enum.reverse(acc)}
  defp decode_tlvs_acc(<<0, 0>>, acc), do: {:ok, Enum.reverse(acc)}
  defp decode_tlvs_acc(<<0, 0, 0>>, acc), do: {:ok, Enum.reverse(acc)}
  defp decode_tlvs_acc(<<0, 0, 0, 0>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_tlvs_acc(<<type::8, length::8, rest::binary>>, acc) do
    if byte_size(rest) >= length do
      <<value::binary-size(^length), remaining::binary>> = rest
      decode_tlvs_acc(remaining, [{type, value} | acc])
    else
      {:error, :incomplete_tlv}
    end
  end

  defp decode_tlvs_acc(_data, _acc), do: {:error, :incomplete_tlv}

  @doc """
  Find all values for a given TLV type.
  """
  @spec find_all([tlv_entry()], tlv_type()) :: [binary()]
  def find_all(entries, type) do
    entries
    |> Enum.filter(fn {t, _} -> t == type end)
    |> Enum.map(fn {_, v} -> v end)
  end

  @doc """
  Find the first value for a given TLV type.
  """
  @spec find_first([tlv_entry()], tlv_type()) :: binary() | nil
  def find_first(entries, type) do
    case Enum.find(entries, fn {t, _} -> t == type end) do
      {_, v} -> v
      nil -> nil
    end
  end
end
