defmodule NostrCore.Crypto do
  @moduledoc """
  Nostr cryptographic helpers: pubkey derivation, Schnorr signing.

  Delegates to `lib_secp256k1` for all secp256k1 operations.
  """

  @type reason :: :invalid_hex | :invalid_secret_key | :invalid_message_hash | :signing_failed

  @doc """
  Derive an x-only public key (32-byte hex) from a secret key (32-byte hex).
  """
  @spec pubkey(binary()) :: {:ok, binary()} | {:error, reason()}
  def pubkey(seckey_hex) when is_binary(seckey_hex) do
    with {:ok, seckey} <- decode_hex(seckey_hex, 32, :invalid_secret_key) do
      {:ok, seckey |> Secp256k1.pubkey(:xonly) |> encode16()}
    end
  rescue
    _ -> {:error, :invalid_secret_key}
  end

  def pubkey(_), do: {:error, :invalid_secret_key}

  @doc """
  Bang variant of `pubkey/1`.
  """
  @spec pubkey!(binary()) :: binary()
  def pubkey!(seckey_hex) do
    case pubkey(seckey_hex) do
      {:ok, pubkey} -> pubkey
      {:error, reason} -> raise ArgumentError, "could not derive pubkey: #{inspect(reason)}"
    end
  end

  @doc """
  Schnorr-sign a 32-byte hex message hash with a 32-byte hex secret key.

  Returns a 64-byte hex signature (128 hex chars).
  """
  @spec sign(binary(), binary()) :: {:ok, binary()} | {:error, reason()}
  def sign(data_hex, seckey_hex) when is_binary(data_hex) and is_binary(seckey_hex) do
    with {:ok, data} <- decode_hex(data_hex, 32, :invalid_message_hash),
         {:ok, seckey} <- decode_hex(seckey_hex, 32, :invalid_secret_key) do
      {:ok, data |> Secp256k1.schnorr_sign(seckey) |> encode16()}
    end
  rescue
    _ -> {:error, :signing_failed}
  end

  def sign(_, _), do: {:error, :invalid_message_hash}

  @doc """
  Bang variant of `sign/2`.
  """
  @spec sign!(binary(), binary()) :: binary()
  def sign!(data_hex, seckey_hex) do
    case sign(data_hex, seckey_hex) do
      {:ok, sig} -> sig
      {:error, reason} -> raise ArgumentError, "could not sign: #{inspect(reason)}"
    end
  end

  @doc """
  Verify a Schnorr signature.

  * `sig_hex` - 64-byte hex signature
  * `msg_hex` - 32-byte hex message hash
  * `pubkey_hex` - 32-byte hex x-only pubkey
  """
  @spec verify?(binary(), binary(), binary()) :: boolean()
  def verify?(sig_hex, msg_hex, pubkey_hex)
      when is_binary(sig_hex) and is_binary(msg_hex) and is_binary(pubkey_hex) do
    Secp256k1.schnorr_valid?(
      decode16!(sig_hex),
      decode16!(msg_hex),
      decode16!(pubkey_hex)
    )
  rescue
    _ -> false
  end

  # ── Private ──────────────────────────────────────────────

  defp decode_hex(hex, expected_size, reason) do
    case Base.decode16(hex, case: :lower) do
      {:ok, bin} when byte_size(bin) == expected_size -> {:ok, bin}
      {:ok, _} -> {:error, reason}
      :error -> {:error, :invalid_hex}
    end
  end

  defp decode16!(hex), do: Base.decode16!(hex, case: :lower)
  defp encode16(bin), do: Base.encode16(bin, case: :lower)
end
