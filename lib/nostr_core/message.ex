defmodule NostrCore.Message do
  @moduledoc """
  Nostr wire message encoding and decoding.

  Messages are tuples shaped `{:op, args...}` that serialize to NIP-01 JSON arrays.
  """

  alias NostrCore.{Event, Filter}

  @type t() ::
          {:event, Event.t()}
          | {:event, binary(), Event.t()}
          | {:req, binary(), [Filter.t()]}
          | {:close, binary()}
          | {:eose, binary()}
          | {:notice, String.t()}
          | {:ok, binary(), boolean(), String.t()}
          | {:auth, Event.t() | binary()}
          | {:count, binary(), map() | [Filter.t()]}
          | {:closed, binary(), String.t()}

  @type parse_reason ::
          :invalid_message_format
          | :invalid_json
          | {:event, Event.parse_reason()}
          | {:filter, Filter.parse_reason()}

  # ── Construction ─────────────────────────────────────────

  @spec create_event(Event.t()) :: {:event, Event.t()}
  def create_event(%Event{} = event), do: {:event, event}

  @spec event(Event.t(), binary()) :: {:event, binary(), Event.t()}
  def event(%Event{} = event, sub_id) when is_binary(sub_id), do: {:event, sub_id, event}

  @spec request(Filter.t() | [Filter.t()], binary()) :: {:req, binary(), [Filter.t()]}
  def request(%Filter{} = f, sub_id), do: {:req, sub_id, [f]}
  def request(filters, sub_id) when is_list(filters), do: {:req, sub_id, filters}

  @spec close(binary()) :: {:close, binary()}
  def close(sub_id) when is_binary(sub_id), do: {:close, sub_id}

  @spec eose(binary()) :: {:eose, binary()}
  def eose(sub_id) when is_binary(sub_id), do: {:eose, sub_id}

  @spec notice(String.t()) :: {:notice, String.t()}
  def notice(msg) when is_binary(msg), do: {:notice, msg}

  @spec ok(binary(), boolean(), String.t()) :: {:ok, binary(), boolean(), String.t()}
  def ok(id, success?, msg) when is_binary(id) and is_boolean(success?) and is_binary(msg),
    do: {:ok, id, success?, msg}

  @spec closed(binary(), String.t()) :: {:closed, binary(), String.t()}
  def closed(sub_id, msg) when is_binary(sub_id) and is_binary(msg),
    do: {:closed, sub_id, msg}

  @spec auth(Event.t() | binary()) :: {:auth, Event.t() | binary()}
  def auth(%Event{} = event), do: {:auth, event}
  def auth(challenge) when is_binary(challenge), do: {:auth, challenge}

  @spec count(pos_integer() | Filter.t() | [Filter.t()], binary()) ::
          {:count, binary(), map() | [Filter.t()]}
  def count(n, sub_id) when is_integer(n), do: {:count, sub_id, %{count: n}}
  def count(%Filter{} = f, sub_id), do: {:count, sub_id, f}
  def count(filters, sub_id) when is_list(filters), do: {:count, sub_id, filters}

  # ── Serialization ──────────────────────────────────────────

  @doc """
  Serialize a message tuple to a JSON string.
  """
  @spec serialize(t()) :: binary()
  def serialize({:event, %Event{} = event}), do: JSON.encode!(["EVENT", event])

  def serialize({:event, sub_id, %Event{} = event}) when is_binary(sub_id),
    do: JSON.encode!(["EVENT", sub_id, event])

  def serialize({:req, sub_id, filters}) when is_binary(sub_id) and is_list(filters),
    do: JSON.encode!(["REQ", sub_id | filters])

  def serialize({:close, sub_id}) when is_binary(sub_id), do: JSON.encode!(["CLOSE", sub_id])

  def serialize({:eose, sub_id}) when is_binary(sub_id), do: JSON.encode!(["EOSE", sub_id])

  def serialize({:notice, message}) when is_binary(message), do: JSON.encode!(["NOTICE", message])

  def serialize({:ok, event_id, success?, message})
      when is_binary(event_id) and is_boolean(success?) and is_binary(message),
      do: JSON.encode!(["OK", event_id, success?, message])

  def serialize({:auth, %Event{} = event}), do: JSON.encode!(["AUTH", event])

  def serialize({:auth, challenge}) when is_binary(challenge),
    do: JSON.encode!(["AUTH", challenge])

  def serialize({:count, sub_id, %{count: count} = payload})
      when is_binary(sub_id) and is_integer(count),
      do: JSON.encode!(["COUNT", sub_id, payload])

  def serialize({:count, sub_id, %Filter{} = filter}) when is_binary(sub_id),
    do: JSON.encode!(["COUNT", sub_id, filter])

  def serialize({:count, sub_id, filters}) when is_binary(sub_id) and is_list(filters),
    do: JSON.encode!(["COUNT", sub_id | filters])

  def serialize({:closed, sub_id, message}) when is_binary(sub_id) and is_binary(message),
    do: JSON.encode!(["CLOSED", sub_id, message])

  # ── Parsing ──────────────────────────────────────────────

  @doc """
  Parse a raw JSON string into a message tuple.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, parse_reason()}
  def parse(msg) when is_binary(msg) do
    case JSON.decode(msg) do
      {:ok, decoded} -> parse_decoded(decoded)
      {:error, _reason} -> {:error, :invalid_json}
    end
  rescue
    _ -> {:error, :invalid_message_format}
  end

  # ── Private parsing ──────────────────────────────────────

  # Client → Relay
  defp parse_decoded(["EVENT", event]) when is_map(event) do
    case Event.parse_unverified(event) do
      {:ok, event} -> {:ok, {:event, event}}
      {:error, reason} -> {:error, {:event, reason}}
    end
  end

  # Relay → Client
  defp parse_decoded(["EVENT", sub_id, event]) when is_binary(sub_id) and is_map(event) do
    case Event.parse_unverified(event) do
      {:ok, event} -> {:ok, {:event, sub_id, event}}
      {:error, reason} -> {:error, {:event, reason}}
    end
  end

  defp parse_decoded(["REQ", sub_id | filters]) when is_binary(sub_id) and filters != [] do
    with {:ok, filters} <- parse_filters(filters), do: {:ok, {:req, sub_id, filters}}
  end

  defp parse_decoded(["CLOSE", sub_id]) when is_binary(sub_id), do: {:ok, {:close, sub_id}}

  defp parse_decoded(["AUTH", event]) when is_map(event) do
    case Event.parse_unverified(event) do
      {:ok, event} -> {:ok, {:auth, event}}
      {:error, reason} -> {:error, {:event, reason}}
    end
  end

  defp parse_decoded(["NOTICE", message]) when is_binary(message), do: {:ok, {:notice, message}}
  defp parse_decoded(["EOSE", sub_id]) when is_binary(sub_id), do: {:ok, {:eose, sub_id}}

  defp parse_decoded(["OK", event_id, success?, message])
       when is_binary(event_id) and is_boolean(success?) and is_binary(message),
       do: {:ok, {:ok, event_id, success?, message}}

  defp parse_decoded(["AUTH", challenge]) when is_binary(challenge), do: {:ok, {:auth, challenge}}

  defp parse_decoded(["CLOSED", sub_id, message])
       when is_binary(sub_id) and is_binary(message),
       do: {:ok, {:closed, sub_id, message}}

  defp parse_decoded(["COUNT", sub_id, %{"count" => count} = payload])
       when is_binary(sub_id) and is_integer(count) do
    result = %{count: count}

    result =
      if is_boolean(payload["approximate"]),
        do: Map.put(result, :approximate, payload["approximate"]),
        else: result

    result = if is_binary(payload["hll"]), do: Map.put(result, :hll, payload["hll"]), else: result
    {:ok, {:count, sub_id, result}}
  end

  defp parse_decoded(["COUNT", sub_id | filters]) when is_binary(sub_id) and filters != [] do
    with {:ok, filters} <- parse_filters(filters), do: {:ok, {:count, sub_id, filters}}
  end

  defp parse_decoded(_unknown), do: {:error, :invalid_message_format}

  defp parse_filters(filters) do
    filters
    |> Enum.reduce_while({:ok, []}, fn filter, {:ok, acc} ->
      case Filter.parse(filter) do
        {:ok, filter} -> {:cont, {:ok, [filter | acc]}}
        {:error, reason} -> {:halt, {:error, {:filter, reason}}}
      end
    end)
    |> case do
      {:ok, filters} -> {:ok, Enum.reverse(filters)}
      error -> error
    end
  end
end
