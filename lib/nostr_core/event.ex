defmodule NostrCore.Event do
  @moduledoc """
  Core Nostr event struct and operations.

  Implements NIP-01 event creation, ID computation, serialization, signing,
  parsing, and validation.

  ## Fields

    * `:id` - 32-byte hex-encoded SHA256 hash (set by signing)
    * `:pubkey` - 32-byte hex-encoded public key (set by signing)
    * `:kind` - integer event kind (required)
    * `:tags` - list of `NostrCore.Tag.t()`
    * `:created_at` - `DateTime` when event was created
    * `:content` - string payload (default `""`)
    * `:sig` - 64-byte hex-encoded Schnorr signature (set by signing)

  ## Examples

      iex> {:ok, event} = NostrCore.Event.create(1, content: "Hello Nostr")
      iex> seckey = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      iex> {:ok, signed} = NostrCore.Event.sign(event, seckey)
      iex> NostrCore.Event.valid?(signed)
      true

  """

  alias __MODULE__.Validator
  alias NostrCore.Tag

  @enforce_keys [:kind, :tags, :created_at, :content]
  defstruct id: nil, pubkey: nil, kind: nil, tags: [], created_at: nil, content: "", sig: nil

  @typedoc "Nostr event"
  @type t() :: %__MODULE__{
          id: <<_::32, _::_*8>> | nil,
          pubkey: <<_::32, _::_*8>> | nil,
          kind: non_neg_integer(),
          tags: [Tag.t()],
          created_at: DateTime.t(),
          content: binary(),
          sig: <<_::64, _::_*8>> | nil
        }

  # ── Creation ─────────────────────────────────────────────

  @doc """
  Create a new unsigned event.

  ## Options

    * `:pubkey` - 32-byte hex pubkey (derived from seckey during signing if omitted)
    * `:tags` - list of `NostrCore.Tag.t()` (default `[]`)
    * `:created_at` - `DateTime` (defaults to `utc_now`)
    * `:content` - string (default `""`)

  """
  @type create_reason ::
          :invalid_kind
          | :invalid_options
          | :invalid_pubkey
          | :invalid_tags
          | :invalid_created_at
          | :invalid_content

  def create(kind, opts \\ [])

  @spec create(integer(), map()) :: {:ok, t()} | {:error, create_reason()}
  def create(kind, map) when is_map(map), do: create(kind, Enum.into(map, []))

  @spec create(integer(), term()) :: {:ok, t()} | {:error, create_reason()}
  def create(kind, opts) do
    with :ok <- validate_create_kind(kind),
         :ok <- validate_create_opts(opts),
         {:ok, pubkey} <- validate_create_pubkey(Keyword.get(opts, :pubkey)),
         {:ok, tags} <- validate_create_tags(Keyword.get(opts, :tags, [])),
         {:ok, created_at} <-
           validate_create_created_at(Keyword.get(opts, :created_at, DateTime.utc_now())),
         {:ok, content} <- validate_create_content(Keyword.get(opts, :content, "")) do
      {:ok,
       %__MODULE__{
         kind: kind,
         pubkey: pubkey,
         tags: tags,
         created_at: created_at,
         content: content
       }}
    end
  end

  @doc """
  Bang variant of `create/2`.
  """
  @spec create!(term(), term()) :: t()
  def create!(kind, opts \\ []) do
    case create(kind, opts) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "could not create event: #{inspect(reason)}"
    end
  end

  defp validate_create_kind(kind) when is_integer(kind) and kind >= 0, do: :ok
  defp validate_create_kind(_), do: {:error, :invalid_kind}

  defp validate_create_opts(opts) when is_list(opts), do: :ok
  defp validate_create_opts(_), do: {:error, :invalid_options}

  defp validate_create_pubkey(nil), do: {:ok, nil}
  defp validate_create_pubkey(pubkey) when is_binary(pubkey), do: {:ok, pubkey}
  defp validate_create_pubkey(_), do: {:error, :invalid_pubkey}

  defp validate_create_tags(tags) when is_list(tags) do
    if Enum.all?(tags, &match?(%Tag{}, &1)), do: {:ok, tags}, else: {:error, :invalid_tags}
  end

  defp validate_create_tags(_), do: {:error, :invalid_tags}

  defp validate_create_created_at(%DateTime{} = created_at), do: {:ok, created_at}
  defp validate_create_created_at(_), do: {:error, :invalid_created_at}

  defp validate_create_content(content) when is_binary(content), do: {:ok, content}
  defp validate_create_content(_), do: {:error, :invalid_content}

  # ── ID, Serialization, Signing ─────────────────────────

  @doc """
  Compute the event ID from the serialized canonical form.

  Per NIP-01: SHA-256 of `[0, pubkey, created_at, kind, tags, content]`.
  """
  @spec compute_id(t()) :: binary()
  def compute_id(%__MODULE__{} = event) do
    event
    |> serialize()
    |> then(fn x -> :crypto.hash(:sha256, x) end)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Serialize an event to its canonical NIP-01 JSON array form.
  """
  @spec serialize(t()) :: String.t()
  def serialize(%__MODULE__{
        pubkey: pubkey,
        kind: kind,
        tags: tags,
        created_at: created_at,
        content: content
      }) do
    JSON.encode!([0, pubkey, DateTime.to_unix(created_at), kind, tags, content])
  end

  @type sign_reason ::
          :invalid_event
          | :mismatched_id
          | :mismatched_pubkey
          | NostrCore.Crypto.reason()

  @doc """
  Sign an event with a hex-encoded secret key.

  Auto-populates `:pubkey` and `:id` if absent, then computes the Schnorr signature.
  """
  # split this: never use existing pubkey, always compute fresh id.
  # pattern match on nil in first clause
  # you cannot sign an event who's ID has been provided beforehand
  @spec sign(t(), binary()) :: {:ok, t()} | {:error, sign_reason()}
  def sign(%__MODULE__{} = event, seckey) do
    with {:ok, derived_pubkey} <- NostrCore.Crypto.pubkey(seckey),
         :ok <- check_or_set_pubkey(event.pubkey, derived_pubkey),
         event = %__MODULE__{event | pubkey: event.pubkey || derived_pubkey},
         computed_id = compute_id(event),
         :ok <- check_or_set_id(event.id, computed_id),
         event = %__MODULE__{event | id: event.id || computed_id},
         {:ok, sig} <- NostrCore.Crypto.sign(event.id, seckey) do
      {:ok, %__MODULE__{event | sig: sig}}
    end
  rescue
    _ -> {:error, :invalid_event}
  end

  def sign(_, _), do: {:error, :invalid_event}

  @doc """
  Bang variant of `sign/2`.
  """
  @spec sign!(t(), binary()) :: t()
  def sign!(%__MODULE__{} = event, seckey) do
    case sign(event, seckey) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "could not sign event: #{inspect(reason)}"
    end
  end

  defp check_or_set_pubkey(nil, _derived_pubkey), do: :ok
  defp check_or_set_pubkey(pubkey, pubkey), do: :ok
  defp check_or_set_pubkey(_pubkey, _derived_pubkey), do: {:error, :mismatched_pubkey}

  defp check_or_set_id(nil, _computed_id), do: :ok
  defp check_or_set_id(id, id), do: :ok
  defp check_or_set_id(_id, _computed_id), do: {:error, :mismatched_id}

  # ── Parsing ──────────────────────────────────────────────

  @type parse_reason ::
          :invalid_event
          | :missing_kind
          | :invalid_kind
          | :missing_created_at
          | :invalid_created_at
          | :invalid_content
          | :invalid_tags
          | {:invalid_tag, non_neg_integer(), term()}
          | Validator.reason()

  @doc """
  Parse a raw event map (from decoded JSON) and validate ID and signature.
  """
  @spec parse(term()) :: {:ok, t()} | {:error, parse_reason()}
  def parse(event) when is_map(event) do
    with {:ok, parsed} <- parse_unverified(event),
         :ok <- Validator.validate(parsed) do
      {:ok, parsed}
    end
  end

  def parse(_), do: {:error, :invalid_event}

  @doc """
  Parse a raw event map without validating ID or signature.

  Useful for relays that need to preserve the struct for NIP-01 `OK` error
  responses even when validation fails.
  """
  @spec parse_unverified(term()) :: {:ok, t()} | {:error, parse_reason()}
  def parse_unverified(%{kind: kind, tags: tags, content: content, created_at: created_at} = event) do
    with {:ok, kind} <- parse_kind(kind),
         {:ok, created_at} <- parse_timestamp(created_at),
         {:ok, tags} <- parse_tags(tags),
         {:ok, content} <- parse_content(content) do
      {:ok,
       %__MODULE__{
         id: Map.get(event, "id"),
         pubkey: Map.get(event, "pubkey"),
         kind: kind,
         tags: tags,
         created_at: created_at,
         content: content,
         sig: Map.get(event, "sig")
       }}
    end
  end

  @spec parse_unverified(term()) :: {:ok, t()} | {:error, parse_reason()}
  def parse_unverified(%{"kind" => kind, "tags" => tags, "content" => content, "created_at" => created_at} = event) do
    with {:ok, kind} <- parse_kind(kind),
         {:ok, created_at} <- parse_timestamp(created_at),
         {:ok, tags} <- parse_tags(tags),
         {:ok, content} <- parse_content(content) do
      {:ok,
       %__MODULE__{
         id: Map.get(event, "id"),
         pubkey: Map.get(event, "pubkey"),
         kind: kind,
         tags: tags,
         created_at: created_at,
         content: content,
         sig: Map.get(event, "sig")
       }}
    end
  end
  def parse_unverified(_), do: {:error, :invalid_event}

  @doc """
  Validate an event's ID and signature. Returns `true` if both check out.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = event), do: Validator.valid?(event)

  @doc """
  Validate an event's ID and signature with a reasoned result.
  """
  @spec validate(t()) :: :ok | {:error, Validator.reason()}
  def validate(%__MODULE__{} = event), do: Validator.validate(event)

  # ── Private helpers ──────────────────────────────────────

  defp parse_kind(nil), do: {:error, :missing_kind}
  defp parse_kind(k) when is_integer(k) and k >= 0, do: {:ok, k}
  defp parse_kind(_), do: {:error, :invalid_kind}

  defp parse_timestamp(nil), do: {:error, :missing_created_at}

  defp parse_timestamp(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> {:ok, dt}
      {:error, _} -> {:error, :invalid_created_at}
    end
  end

  defp parse_timestamp(ts) when is_float(ts), do: ts |> trunc() |> parse_timestamp()
  defp parse_timestamp(_), do: {:error, :invalid_created_at}

  defp parse_content(content) when is_binary(content), do: {:ok, content}
  defp parse_content(_), do: {:error, :invalid_content}

  defp parse_tags(nil), do: {:ok, []}

  defp parse_tags(list) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {tag, index}, {:ok, acc} ->
      case Tag.parse(tag) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_tag, index, reason}}}
      end
    end)
    |> case do
      {:ok, tags} -> {:ok, Enum.reverse(tags)}
      error -> error
    end
  end

  defp parse_tags(_), do: {:error, :invalid_tags}
end

defimpl JSON.Encoder, for: NostrCore.Event do
  def encode(%NostrCore.Event{} = event, encoder) do
    JSON.encode!(
      %{
        id: event.id,
        pubkey: event.pubkey,
        kind: event.kind,
        tags: event.tags,
        created_at: DateTime.to_unix(event.created_at),
        content: event.content,
        sig: event.sig
      },
      encoder
    )
  end
end
