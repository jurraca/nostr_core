defmodule NostrCore.NIP19 do
  @moduledoc """
  NIP-19: Bech32-encoded shareable identifiers with TLV metadata.

  Supports bare keys (`npub`, `nsec`, `note`), bare relay URLs (`nrelay`),
  and TLV identifiers (`nprofile`, `nevent`, `naddr`).

  For bare key/id encoding without metadata, see `NostrCore.Bech32`.
  """

  alias NostrCore.NIP19.TLV

  @max_tlv_value_size 255
  @max_u32 4_294_967_295

  defmodule Profile do
    @moduledoc "Decoded nprofile TLV struct."
    defstruct [:pubkey, relays: []]

    @type t :: %__MODULE__{pubkey: String.t(), relays: [String.t()]}
  end

  defmodule Event do
    @moduledoc "Decoded nevent TLV struct."
    defstruct [:event_id, :author, :kind, relays: []]

    @type t :: %__MODULE__{
            event_id: String.t(),
            author: String.t() | nil,
            kind: non_neg_integer() | nil,
            relays: [String.t()]
          }
  end

  defmodule Address do
    @moduledoc "Decoded naddr TLV struct (addressable event coordinate)."
    defstruct [:identifier, :pubkey, :kind, relays: []]

    @type t :: %__MODULE__{
            identifier: String.t(),
            pubkey: String.t(),
            kind: non_neg_integer(),
            relays: [String.t()]
          }
  end

  # ── Encoding ─────────────────────────────────────────────

  @doc """
  Encode a relay URL as an `nrelay`.
  """
  @spec encode_nrelay(String.t()) :: {:ok, String.t()} | {:error, :invalid_relay}
  def encode_nrelay(relay) when is_binary(relay), do: {:ok, Bechamel.encode("nrelay", relay)}
  def encode_nrelay(_), do: {:error, :invalid_relay}

  @doc """
  Encode a public key with optional relay hints as an `nprofile`.
  """
  @spec encode_nprofile(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, atom()}
  def encode_nprofile(pubkey, relays \\ []) do
    with {:ok, pk_bin} <- hex_to_bin(pubkey, 32),
         {:ok, relay_entries} <- relay_entries(relays) do
      entries = [{TLV.special(), pk_bin}] ++ relay_entries

      with {:ok, encoded} <- TLV.encode_tlvs(entries),
           do: {:ok, Bechamel.encode("nprofile", encoded)}
    end
  end

  @doc """
  Encode an event ID with optional metadata as an `nevent`.

  Options: `:relays`, `:author` (hex pubkey), `:kind`.
  """
  @spec encode_nevent(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def encode_nevent(event_id, opts \\ []) do
    relays = Keyword.get(opts, :relays, [])
    author = Keyword.get(opts, :author)
    kind = Keyword.get(opts, :kind)

    with {:ok, id_bin} <- hex_to_bin(event_id, 32, :invalid_event_id),
         {:ok, auth_bin} <- maybe_hex_to_bin(author, 32),
         {:ok, relay_entries} <- relay_entries(relays),
         {:ok, kind_entries} <- maybe_kind(kind) do
      entries =
        [{TLV.special(), id_bin}] ++ relay_entries ++ maybe_author(auth_bin) ++ kind_entries

      with {:ok, encoded} <- TLV.encode_tlvs(entries),
           do: {:ok, Bechamel.encode("nevent", encoded)}
    end
  end

  @doc """
  Encode an addressable event coordinate as an `naddr`.

  `identifier` is the raw UTF-8/binary `d` tag value. `kind` must fit in an
  unsigned 32-bit integer because NIP-19 encodes it as four bytes.
  """
  @spec encode_naddr(String.t(), String.t(), non_neg_integer(), [String.t()]) ::
          {:ok, String.t()} | {:error, atom()}
  def encode_naddr(identifier, pubkey, kind, relays \\ []) do
    with :ok <- validate_identifier(identifier),
         :ok <- validate_kind(kind),
         {:ok, pk_bin} <- hex_to_bin(pubkey, 32),
         {:ok, relay_entries} <- relay_entries(relays) do
      entries =
        [{TLV.special(), identifier}] ++
          relay_entries ++
          [{TLV.author(), pk_bin}, {TLV.kind(), <<kind::unsigned-big-integer-32>>}]

      with {:ok, encoded} <- TLV.encode_tlvs(entries),
           do: {:ok, Bechamel.encode("naddr", encoded)}
    end
  end

  # ── Decoding: TLV identifiers ────────────────────────────

  @doc "Decode an `nrelay` string."
  @spec decode_nrelay(String.t()) :: {:ok, String.t()} | {:error, term()}
  def decode_nrelay("nrelay" <> _ = bech32) do
    with {:ok, "nrelay", relay} <- Bechamel.decode(bech32, ignore_length: true),
         true <- is_binary(relay) do
      {:ok, relay}
    else
      false -> {:error, :invalid_relay}
      {:ok, _hrp, _data} -> {:error, :invalid_prefix}
      {:error, reason} -> {:error, reason}
    end
  end

  def decode_nrelay(_), do: {:error, :invalid_prefix}

  @doc "Decode an `nprofile` string."
  @spec decode_nprofile(String.t()) :: {:ok, Profile.t()} | {:error, term()}
  def decode_nprofile("nprofile" <> _ = bech32) do
    with {:ok, "nprofile", data} <- Bechamel.decode(bech32, ignore_length: true),
         {:ok, entries} <- TLV.decode_tlvs(data) do
      case TLV.find_first(entries, TLV.special()) do
        nil ->
          {:error, :missing_pubkey}

        pk when byte_size(pk) == 32 ->
          {:ok, %Profile{pubkey: encode16(pk), relays: TLV.find_all(entries, TLV.relay())}}

        _ ->
          {:error, :invalid_pubkey}
      end
    end
  end

  def decode_nprofile(_), do: {:error, :invalid_prefix}

  @doc "Decode an `nevent` string."
  @spec decode_nevent(String.t()) :: {:ok, Event.t()} | {:error, term()}
  def decode_nevent("nevent" <> _ = bech32) do
    with {:ok, "nevent", data} <- Bechamel.decode(bech32, ignore_length: true),
         {:ok, entries} <- TLV.decode_tlvs(data) do
      case TLV.find_first(entries, TLV.special()) do
        nil ->
          {:error, :missing_event_id}

        id when byte_size(id) == 32 ->
          {:ok,
           %Event{
             event_id: encode16(id),
             relays: TLV.find_all(entries, TLV.relay()),
             author: parse_author(TLV.find_first(entries, TLV.author())),
             kind: parse_kind(TLV.find_first(entries, TLV.kind()))
           }}

        _ ->
          {:error, :invalid_event_id}
      end
    end
  end

  def decode_nevent(_), do: {:error, :invalid_prefix}

  @doc "Decode an `naddr` string."
  @spec decode_naddr(String.t()) :: {:ok, Address.t()} | {:error, term()}
  def decode_naddr("naddr" <> _ = bech32) do
    with {:ok, "naddr", data} <- Bechamel.decode(bech32, ignore_length: true),
         {:ok, entries} <- TLV.decode_tlvs(data) do
      identifier = TLV.find_first(entries, TLV.special()) || ""
      author = TLV.find_first(entries, TLV.author())
      kind_bin = TLV.find_first(entries, TLV.kind())
      relays = TLV.find_all(entries, TLV.relay())

      cond do
        is_nil(author) ->
          {:error, :missing_author}

        byte_size(author) != 32 ->
          {:error, :invalid_author}

        is_nil(kind_bin) ->
          {:error, :missing_kind}

        byte_size(kind_bin) != 4 ->
          {:error, :invalid_kind}

        true ->
          <<kind::unsigned-big-integer-32>> = kind_bin

          {:ok,
           %Address{identifier: identifier, pubkey: encode16(author), kind: kind, relays: relays}}
      end
    end
  end

  def decode_naddr(_), do: {:error, :invalid_prefix}

  # ── Universal decode ─────────────────────────────────────

  @doc """
  Decode any NIP-19 string and return `{type, data}`.

  Types: `:npub`, `:nsec`, `:note`, `:nrelay`, `:nprofile`, `:nevent`, `:naddr`.
  """
  @spec decode(String.t()) ::
          {:ok, atom(), String.t() | Profile.t() | Event.t() | Address.t()} | {:error, term()}
  def decode("npub" <> _ = str), do: decode_bare(str, "npub", :npub, :invalid_pubkey)
  def decode("nsec" <> _ = str), do: decode_bare(str, "nsec", :nsec, :invalid_secret_key)
  def decode("note" <> _ = str), do: decode_bare(str, "note", :note, :invalid_event_id)

  def decode("nrelay" <> _ = str) do
    with {:ok, relay} <- decode_nrelay(str), do: {:ok, :nrelay, relay}
  end

  def decode("nprofile" <> _ = str) do
    with {:ok, profile} <- decode_nprofile(str), do: {:ok, :nprofile, profile}
  end

  def decode("nevent" <> _ = str) do
    with {:ok, event} <- decode_nevent(str), do: {:ok, :nevent, event}
  end

  def decode("naddr" <> _ = str) do
    with {:ok, addr} <- decode_naddr(str), do: {:ok, :naddr, addr}
  end

  def decode(_), do: {:error, :unknown_prefix}

  # ── Private ──────────────────────────────────────────────

  defp decode_bare(str, expected_hrp, type, length_error) do
    with {:ok, ^expected_hrp, data} <- Bechamel.decode(str),
         true <- byte_size(data) == 32 do
      {:ok, type, encode16(data)}
    else
      false -> {:error, length_error}
      {:ok, _hrp, _data} -> {:error, :invalid_prefix}
      {:error, reason} -> {:error, reason}
    end
  end

  defp hex_to_bin(hex, size, error \\ :invalid_pubkey) do
    case Base.decode16(hex, case: :lower) do
      {:ok, bin} when byte_size(bin) == size -> {:ok, bin}
      _ -> {:error, error}
    end
  end

  defp maybe_hex_to_bin(nil, _size), do: {:ok, nil}
  defp maybe_hex_to_bin(hex, size), do: hex_to_bin(hex, size, :invalid_author)

  defp validate_identifier(identifier)
       when is_binary(identifier) and byte_size(identifier) <= @max_tlv_value_size, do: :ok

  defp validate_identifier(identifier) when is_binary(identifier),
    do: {:error, :invalid_identifier}

  defp validate_identifier(_), do: {:error, :invalid_identifier}

  defp validate_kind(kind) when is_integer(kind) and kind >= 0 and kind <= @max_u32, do: :ok
  defp validate_kind(_), do: {:error, :invalid_kind}

  defp relay_entries(relays) when is_list(relays) do
    relays
    |> Enum.reduce_while({:ok, []}, fn relay, {:ok, acc} ->
      cond do
        not is_binary(relay) -> {:halt, {:error, :invalid_relay}}
        byte_size(relay) > @max_tlv_value_size -> {:halt, {:error, :invalid_relay}}
        true -> {:cont, {:ok, [{TLV.relay(), relay} | acc]}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp relay_entries(_), do: {:error, :invalid_relay}

  defp maybe_author(nil), do: []
  defp maybe_author(bin), do: [{TLV.author(), bin}]

  defp maybe_kind(nil), do: {:ok, []}

  defp maybe_kind(k) do
    with :ok <- validate_kind(k), do: {:ok, [{TLV.kind(), <<k::unsigned-big-integer-32>>}]}
  end

  defp parse_author(bin) when is_binary(bin) and byte_size(bin) == 32, do: encode16(bin)
  defp parse_author(_), do: nil

  defp parse_kind(<<k::unsigned-big-integer-32>>), do: k
  defp parse_kind(_), do: nil

  defp encode16(bin), do: Base.encode16(bin, case: :lower)
end
