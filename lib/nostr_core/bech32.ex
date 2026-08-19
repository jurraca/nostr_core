defmodule NostrCore.Bech32 do
  @moduledoc """
  Bech32 encoding for bare Nostr keys and IDs.

  This module is for Nostr's bare 32-byte bech32 identifiers (`npub`,
  `nsec`, and `note`), not a generic bech32 codec.

  See `NostrCore.NIP19` for `nrelay` and TLV shareable identifiers
  (`nprofile`, `nevent`, `naddr`).
  """

  @typedoc "Hex-encoded 32-byte data"
  @type hex :: String.t()

  @typedoc "Bech32-encoded string"
  @type bech32 :: String.t()

  @type encode_reason :: :invalid_hex | :invalid_length

  @doc """
  Encode 32-byte hex data with a bech32 human-readable prefix.

  Bare Nostr identifiers (`npub`, `nsec`, `note`) are always 32-byte payloads.

  ## Examples

      iex> NostrCore.Bech32.encode("npub", "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
      {:ok, "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"}
  """
  @spec encode(String.t(), hex()) :: {:ok, bech32()} | {:error, encode_reason()}
  def encode(hrp, hex) when is_binary(hrp) and is_binary(hex) do
    with {:ok, bin} <- decode_hex32(hex) do
      {:ok, Bechamel.encode(hrp, bin)}
    end
  end

  def encode(_, _), do: {:error, :invalid_hex}

  @doc """
  Decode a bech32 string to `{hrp, hex}`.

  The HRP is returned because it is part of the identifier semantics: the same
  32-byte payload can be an `npub`, `nsec`, or `note` depending on its prefix.
  """
  @spec decode(bech32()) :: {:ok, String.t(), hex()} | {:error, term()}
  def decode(str) when is_binary(str) do
    case Bechamel.decode(str) do
      {:ok, hrp, bin} -> {:ok, hrp, Base.encode16(bin, case: :lower)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Encode a secret key as `nsec`."
  @spec nsec(hex()) :: {:ok, bech32()} | {:error, encode_reason()}
  def nsec(hex), do: encode("nsec", hex)

  @doc "Encode a public key as `npub`."
  @spec npub(hex()) :: {:ok, bech32()} | {:error, encode_reason()}
  def npub(hex), do: encode("npub", hex)

  @doc "Encode an event ID as `note`."
  @spec note(hex()) :: {:ok, bech32()} | {:error, encode_reason()}
  def note(hex), do: encode("note", hex)

  @doc "Decode a bech32 string and require a 32-byte payload."
  @spec decode32(bech32()) :: {:ok, String.t(), hex()} | {:error, term()}
  def decode32(str) do
    with {:ok, hrp, hex} <- decode(str),
         {:ok, _bin} <- decode_hex32(hex) do
      {:ok, hrp, hex}
    end
  end

  @doc "Decode a bech32 string to hex, requiring a 32-byte payload."
  @spec to_hex(bech32()) :: {:ok, hex()} | {:error, term()}
  def to_hex(str) do
    with {:ok, _hrp, hex} <- decode32(str), do: {:ok, hex}
  end

  defp decode_hex32(hex) do
    case Base.decode16(hex, case: :lower) do
      {:ok, bin} when byte_size(bin) == 32 -> {:ok, bin}
      {:ok, _bin} -> {:error, :invalid_length}
      :error -> {:error, :invalid_hex}
    end
  end
end
