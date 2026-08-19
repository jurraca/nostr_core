# NostrCore

Minimal Elixir library for the Nostr protocol. Events, tags, filters, messages, Schnorr crypto, and NIP-19 identifiers.

Built for composing into clients, relays, bots, and other Nostr libraries on the BEAM.

## Install

```elixir
defp deps do
  [
    {:nostr_core, "~> 0.1.0"}
  ]
end
```

Requires Elixir ~> 1.18 and uses Elixir's built-in `JSON` module.

## What you get

| Module | Purpose |
|--------|---------|
| `NostrCore.Event` | Create, sign, parse, validate, classify, and serialize NIP-01 events |
| `NostrCore.Tag` | Parse and create NIP-01 event tags |
| `NostrCore.Filter` | Parse and encode NIP-01 subscription filters |
| `NostrCore.Message` | Encode/decode NIP-01 wire messages |
| `NostrCore.Crypto` | x-only pubkey derivation and Schnorr sign/verify via `libsecp256k1` |
| `NostrCore.Kinds` | NIP-16 kind classification helpers |
| `NostrCore.Bech32` | Bare 32-byte bech32 keys/IDs (`npub`, `nsec`, `note`) |
| `NostrCore.NIP19` | NIP-19 identifiers (`npub`, `nsec`, `note`, `nrelay`, `nprofile`, `nevent`, `naddr`) |

## Design principles

- **Protocol-only.** No WebSocket client, no relay supervision tree, no agent framework, no storage layer.
- **Minimal NIP scope.** Core NIP-01 primitives plus NIP-16 kind classification and NIP-19 encodings.
- **No per-kind modules.** The core is agnostic to NIP content schemas. Higher-level packages can parse kind-specific content.
- **Safe public APIs.** Parsing, creation, and signing return `{:ok, value}` / `{:error, reason}`. Bang variants are available for trusted/static inputs.

## Quick Start

```elixir
alias NostrCore.{Event, Message}

# Create and sign an event
seckey = "1111111111111111111111111111111111111111111111111111111111111111"
{:ok, event} = Event.create(1, content: "Hello from Elixir!")
{:ok, signed} = Event.sign(event, seckey)

# Serialize for the wire
json = Message.serialize(Message.create_event(signed))

# Parse incoming wire JSON. Message.parse/1 checks the message shape and
# builds embedded events, but does not validate event id/signature.
{:ok, {:event, %Event{} = parsed}} = Message.parse(json)

# Validate event id and signature explicitly when you need authenticity.
:ok = Event.validate(parsed)
```

For trusted/static values, bang constructors are available:

```elixir
event = Event.create!(1, content: "trusted")
signed = Event.sign!(event, seckey)
```

## Filters

`NostrCore.Filter` parses and encodes NIP-01 subscription filters:

```elixir
{:ok, filter} = NostrCore.Filter.parse(%{"kinds" => [1], "#t" => ["nostr"]})
json = JSON.encode!(filter)
```

This library does **not** implement filter/event matching. Relays, clients, and indexes should apply their own matching/storage policy.

## NIP-19

`NostrCore.NIP19` supports universal decoding:

```elixir
{:ok, :npub, pubkey} = NostrCore.NIP19.decode(npub)
{:ok, :nrelay, relay_url} = NostrCore.NIP19.decode(nrelay)
{:ok, :nprofile, profile} = NostrCore.NIP19.decode(nprofile)
```

It also exposes specific encoders/decoders for `nrelay`, `nprofile`, `nevent`, and `naddr`. Bare 32-byte `npub`/`nsec`/`note` helpers live in `NostrCore.Bech32`.

## Testing

This project depends on `libsecp256k1` through a NIF. Use the provided Nix shell when running project commands:

```bash
nix develop -c mix test
```

For local development outside Nix, ensure the native secp256k1 dependency can be compiled and loaded by the BEAM.

## License

MIT

## Related

- [`nostr_ex`](https://github.com/jurraca/nostr_ex) — WebSocket client built on `nostr_core`
