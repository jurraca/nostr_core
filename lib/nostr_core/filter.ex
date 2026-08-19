defmodule NostrCore.Filter do
  @moduledoc """
  Nostr subscription filter.

  Supports NIP-01 filtering by ids, authors, kinds, timestamps, tags,
  and free-form search. Tag filters use `#<letter>` keys (e.g. `"#e"`).
  """

  defstruct [
    :ids,
    :authors,
    :kinds,
    :since,
    :until,
    :limit,
    :search,
    :tags
  ]

  @type t() :: %__MODULE__{
          ids: nil | [binary()],
          authors: nil | [binary()],
          kinds: nil | [non_neg_integer()],
          since: nil | DateTime.t(),
          until: nil | DateTime.t(),
          limit: nil | pos_integer(),
          search: nil | String.t(),
          tags: nil | %{String.t() => [binary()]}
        }

  @type parse_reason ::
          :invalid_filter
          | {:invalid_field, atom()}
          | {:invalid_tag_filter, String.t()}

  @known_keys %{
    "ids" => :ids,
    "authors" => :authors,
    "kinds" => :kinds,
    "since" => :since,
    "until" => :until,
    "limit" => :limit,
    "search" => :search
  }

  @tag_pattern ~r/^#[a-zA-Z]$/

  # ── Parsing ──────────────────────────────────────────────

  @doc """
  Parse a filter from a decoded JSON map.
  """
  @spec parse(term()) :: {:ok, t()} | {:error, parse_reason()}
  def parse(filter) when is_map(filter) do
    with {:ok, known, extra_tags} <- split_fields(filter),
         {:ok, known} <- validate_known(known),
         {:ok, tags} <- validate_tag_filters(extra_tags) do
      known = if map_size(tags) > 0, do: Map.put(known, :tags, tags), else: known
      {:ok, struct(__MODULE__, known)}
    end
  end

  def parse(filter) when is_list(filter) do
    if Keyword.keyword?(filter),
      do: filter |> Enum.into(%{}) |> parse(),
      else: {:error, :invalid_filter}
  end

  def parse(_), do: {:error, :invalid_filter}

  # ── Private parse helpers ────────────────────────────────

  defp split_fields(filter) do
    result =
      Enum.reduce_while(filter, {:ok, %{}, %{}}, fn {key, value}, {:ok, known_acc, tags_acc} ->
        str_key = if is_atom(key), do: Atom.to_string(key), else: key

        cond do
          not is_binary(str_key) ->
            {:halt, {:error, :invalid_filter}}

          Map.has_key?(@known_keys, str_key) ->
            {:cont, {:ok, Map.put(known_acc, @known_keys[str_key], value), tags_acc}}

          Regex.match?(@tag_pattern, str_key) ->
            {:cont, {:ok, known_acc, Map.put(tags_acc, str_key, value)}}

          true ->
            {:cont, {:ok, known_acc, tags_acc}}
        end
      end)

    result
  end

  defp validate_known(known) do
    known
    |> Enum.reduce_while({:ok, %{}}, fn {field, value}, {:ok, acc} ->
      case validate_field(field, value) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_field(field, value) when field in [:ids, :authors] do
    if string_list?(value), do: {:ok, value}, else: {:error, {:invalid_field, field}}
  end

  defp validate_field(:kinds, value) do
    if is_list(value) and Enum.all?(value, &(is_integer(&1) and &1 >= 0)) do
      {:ok, value}
    else
      {:error, {:invalid_field, :kinds}}
    end
  end

  defp validate_field(field, value) when field in [:since, :until] do
    unix = if is_float(value), do: trunc(value), else: value

    with true <- is_integer(unix),
         {:ok, dt} <- DateTime.from_unix(unix) do
      {:ok, dt}
    else
      _ -> {:error, {:invalid_field, field}}
    end
  end

  defp validate_field(:limit, value) do
    if is_integer(value) and value > 0, do: {:ok, value}, else: {:error, {:invalid_field, :limit}}
  end

  defp validate_field(:search, value) do
    if is_binary(value), do: {:ok, value}, else: {:error, {:invalid_field, :search}}
  end

  defp validate_tag_filters(tags) do
    Enum.reduce_while(tags, {:ok, %{}}, fn {key, values}, {:ok, acc} ->
      if string_list?(values) do
        {:cont, {:ok, Map.put(acc, key, values)}}
      else
        {:halt, {:error, {:invalid_tag_filter, key}}}
      end
    end)
  end

  defp string_list?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)
end

defimpl JSON.Encoder, for: NostrCore.Filter do
  def encode(%NostrCore.Filter{} = filter, encoder) do
    extra = filter.tags || %{}

    filter
    |> Map.update!(:since, &encode_unix/1)
    |> Map.update!(:until, &encode_unix/1)
    |> Map.from_struct()
    |> Map.delete(:tags)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
    |> Map.merge(extra)
    |> JSON.encode!(encoder)
  end

  defp encode_unix(nil), do: nil
  defp encode_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
end
