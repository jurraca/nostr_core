defmodule NostrCore.Tag do
  @moduledoc """
  Nostr event tag.

  Tags are string arrays attached to events. Tag names are stored as binaries,
  not atoms, so parsing untrusted events cannot exhaust the BEAM atom table.

  This core accepts any non-empty ASCII tag name. Filter tag selectors remain
  stricter and are validated separately as `#<single ASCII letter>` in
  `NostrCore.Filter`.

  Wire format per NIP-01: `["type", "data", ...info]` or `["type"]`.
  """

  @enforce_keys [:type]
  defstruct type: nil, data: nil, info: []

  @type type :: binary()
  @type parse_reason :: :empty_tag | :invalid_tag | :invalid_tag_type
  @type create_reason :: :invalid_tag_type | :invalid_data | :invalid_info

  @type t() :: %__MODULE__{
          type: type(),
          data: binary() | nil,
          info: [binary()]
        }

  @doc """
  Parse a JSON tag array into a `Tag` struct.

  Tag names must be non-empty ASCII strings and are kept as binaries to avoid
  creating atoms from untrusted input.
  """
  @spec parse(term()) :: {:ok, t()} | {:error, parse_reason()}
  def parse([]), do: {:error, :empty_tag}

  def parse([type]) when is_binary(type) do
    with {:ok, type} <- parse_type(type) do
      {:ok, %__MODULE__{type: type, data: nil, info: []}}
    end
  end

  def parse([type, data | info]) when is_binary(type) and is_binary(data) do
    with {:ok, type} <- parse_type(type),
         {:ok, info} <- validate_info(info) do
      {:ok, %__MODULE__{type: type, data: data, info: info}}
    else
      {:error, :invalid_info} -> {:error, :invalid_tag}
      error -> error
    end
  end

  def parse([type | _]) when is_binary(type), do: parse([type])
  def parse(_), do: {:error, :invalid_tag}

  @doc """
  Create a type-only tag.
  """
  @spec create(atom() | binary()) :: {:ok, t()} | {:error, create_reason()}
  def create(type) do
    with {:ok, type} <- validate_type(type) do
      {:ok, %__MODULE__{type: type}}
    end
  end

  @doc """
  Create a tag with data and optional extra info.
  """
  @spec create(atom() | binary(), binary(), [binary()]) :: {:ok, t()} | {:error, create_reason()}
  def create(type, data, info \\ []) do
    with {:ok, type} <- validate_type(type),
         :ok <- validate_data(data),
         {:ok, info} <- validate_info(info) do
      {:ok, %__MODULE__{type: type, data: data, info: info}}
    end
  end

  @doc "Bang variant of `create/1`."
  @spec create!(atom() | binary()) :: t()
  def create!(type) do
    case create(type) do
      {:ok, tag} -> tag
      {:error, reason} -> raise ArgumentError, "could not create tag: #{inspect(reason)}"
    end
  end

  @doc "Bang variant of `create/3`."
  @spec create!(atom() | binary(), binary(), [binary()]) :: t()
  def create!(type, data, info \\ []) do
    case create(type, data, info) do
      {:ok, tag} -> tag
      {:error, reason} -> raise ArgumentError, "could not create tag: #{inspect(reason)}"
    end
  end

  defp parse_type(type) do
    if ascii?(type), do: {:ok, type}, else: {:error, :invalid_tag_type}
  end

  defp validate_type(type) when is_atom(type), do: type |> Atom.to_string() |> validate_type()
  defp validate_type(type) when is_binary(type), do: parse_type(type)
  defp validate_type(_), do: {:error, :invalid_tag_type}

  defp validate_data(data) when is_binary(data), do: :ok
  defp validate_data(_), do: {:error, :invalid_data}

  defp validate_info(items) when is_list(items) do
    if Enum.all?(items, &is_binary/1), do: {:ok, items}, else: {:error, :invalid_info}
  end

  defp validate_info(_), do: {:error, :invalid_info}

  defp ascii?(<<>>), do: false
  defp ascii?(value), do: Enum.all?(:binary.bin_to_list(value), &(&1 <= 127))
end

defimpl JSON.Encoder, for: NostrCore.Tag do
  def encode(%NostrCore.Tag{data: nil} = tag, encoder) do
    JSON.encode!([tag.type], encoder)
  end

  def encode(%NostrCore.Tag{} = tag, encoder) do
    JSON.encode!([tag.type, tag.data | tag.info], encoder)
  end
end
