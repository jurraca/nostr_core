defmodule NostrCore do
  @moduledoc """
  Minimal Elixir library for the Nostr protocol.

  Provides the building blocks for Nostr applications on the BEAM:

    * `NostrCore.Event` — create, sign, parse, validate, classify, and serialize events
    * `NostrCore.Tag` — event tag parsing and creation
    * `NostrCore.Filter` — NIP-01 subscription filter parsing and encoding
    * `NostrCore.Message` — NIP-01 wire message serialization and parsing
    * `NostrCore.Crypto` — x-only pubkey derivation and Schnorr signing/verification
    * `NostrCore.Kinds` — NIP-16 kind classification helpers
    * `NostrCore.Bech32` — bare 32-byte bech32 encoding (`npub`, `nsec`, `note`)
    * `NostrCore.NIP19` — NIP-19 identifiers (`npub`, `nsec`, `note`, `nrelay`, `nprofile`, `nevent`, `naddr`)

  ## When to use NostrCore

  You want this library if you're building:

    * A Nostr **client** (add your own WebSocket pooling)
    * A Nostr **relay** (add your own storage and supervision)
    * A **bot** or background processor
    * Shared event processing logic across multiple apps

  ## When NOT to use NostrCore

  NostrCore is intentionally minimal. It does not provide:

    * Per-NIP content schemas (e.g. parsing `kind: 0` profile JSON)
    * WebSocket connections or connection pooling
    * Relay supervision trees or storage backends
    * Filter/event matching or storage policy
    * NIP-04/NIP-44 encryption, NIP-05 HTTP resolution, or NIP-13 proof-of-work

  Those belong in higher-level libraries or application code.

  ## API style

  Public creation, parsing, and signing functions return `{:ok, value}` or
  `{:error, reason}`. Bang variants such as `Event.create!/2`, `Event.sign!/2`,
  and `Tag.create!/3` are available for trusted/static inputs.

  `NostrCore.Message.parse/1` validates the wire message shape and parses
  embedded events without checking event id/signature. Call `NostrCore.Event.validate/1`
  when authenticity matters.

  ## Examples

  ### Create and sign an event

      iex> alias NostrCore.Event
      iex> {:ok, event} = Event.create(1, content: "Hello Nostr")
      iex> {:ok, signed} = Event.sign(event, seckey)
      iex> :ok = Event.validate(signed)

  ### Parse a wire message

      iex> {:ok, {:event, event}} = NostrCore.Message.parse(json)
      iex> :ok = NostrCore.Event.validate(event)

  ### Parse a subscription filter

      iex> {:ok, filter} = NostrCore.Filter.parse(%{"kinds" => [1], "#t" => ["nostr"]})
      iex> filter.kinds
      [1]

  ### Decode a NIP-19 identifier

      iex> {:ok, :nrelay, relay} = NostrCore.NIP19.decode(nrelay)

  """
end
