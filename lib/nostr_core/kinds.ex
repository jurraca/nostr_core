defmodule NostrCore.Kinds do
  @moduledoc """
  NIP-16 event kind classification helpers.

  These functions accept either a raw kind integer or an `%NostrCore.Event{}` struct.
  """

  alias NostrCore.Event

  @doc "Kind 1000–9999: regular events."
  @spec regular?(non_neg_integer() | Event.t()) :: boolean()
  def regular?(%Event{kind: k}), do: regular?(k)
  def regular?(k) when is_integer(k), do: k >= 1000 and k < 10000

  @doc "Kind 10000–19999: replaceable events."
  @spec replaceable?(non_neg_integer() | Event.t()) :: boolean()
  def replaceable?(%Event{kind: k}), do: replaceable?(k)
  def replaceable?(k) when is_integer(k), do: k >= 10000 and k < 20000

  @doc "Kind 20000–29999: ephemeral events (not stored by relays)."
  @spec ephemeral?(non_neg_integer() | Event.t()) :: boolean()
  def ephemeral?(%Event{kind: k}), do: ephemeral?(k)
  def ephemeral?(k) when is_integer(k), do: k >= 20000 and k < 30000

  @doc "Kind 30000–39999: parameterized replaceable events."
  @spec parameterized_replaceable?(non_neg_integer() | Event.t()) :: boolean()
  def parameterized_replaceable?(%Event{kind: k}), do: parameterized_replaceable?(k)

  def parameterized_replaceable?(k) when is_integer(k),
    do: k >= 30000 and k < 40000

  @doc "Any NIP-16 special kind (not a regular numbered kind)."
  @spec special?(non_neg_integer() | Event.t()) :: boolean()
  def special?(event_or_kind),
    do:
      replaceable?(event_or_kind) or ephemeral?(event_or_kind) or
        parameterized_replaceable?(event_or_kind)
end
