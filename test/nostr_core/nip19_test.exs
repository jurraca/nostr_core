defmodule NostrCore.NIP19Test do
  use ExUnit.Case, async: true

  alias NostrCore.NIP19

  @pubkey "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
  @seckey "1111111111111111111111111111111111111111111111111111111111111111"

  describe "bare keys" do
    test "npub roundtrip" do
      {:ok, npub} = NostrCore.Bech32.npub(@pubkey)
      {:ok, "npub", hex} = NostrCore.Bech32.decode(npub)
      assert hex == @pubkey
    end

    test "nsec roundtrip" do
      {:ok, nsec} = NostrCore.Bech32.nsec(@seckey)
      {:ok, "nsec", hex} = NostrCore.Bech32.decode(nsec)
      assert hex == @seckey
    end

    test "note roundtrip" do
      id = String.duplicate("ab", 32)
      {:ok, note} = NostrCore.Bech32.note(id)
      {:ok, "note", hex} = NostrCore.Bech32.decode(note)
      assert hex == id
    end

    test "bare encoders require 32-byte hex payloads" do
      assert NostrCore.Bech32.npub("00") == {:error, :invalid_length}
      assert NostrCore.Bech32.nsec("00") == {:error, :invalid_length}
      assert NostrCore.Bech32.note("00") == {:error, :invalid_length}
      assert NostrCore.Bech32.npub("not hex") == {:error, :invalid_hex}
    end

    test "decode returns HRP and to_hex requires 32-byte payload" do
      {:ok, short} = NostrCore.Bech32.encode("npub", @pubkey)
      assert {:ok, "npub", @pubkey} = NostrCore.Bech32.decode(short)
      assert {:ok, @pubkey} = NostrCore.Bech32.to_hex(short)

      raw_short = Bechamel.encode("npub", <<1, 2, 3>>)
      assert {:ok, "npub", "010203"} = NostrCore.Bech32.decode(raw_short)
      assert NostrCore.Bech32.to_hex(raw_short) == {:error, :invalid_length}
    end
  end

  describe "nrelay" do
    test "encode and decode" do
      relay = "wss://relay.example.com"
      {:ok, nrelay} = NIP19.encode_nrelay(relay)
      assert String.starts_with?(nrelay, "nrelay1")
      assert {:ok, ^relay} = NIP19.decode_nrelay(nrelay)
      assert {:ok, :nrelay, ^relay} = NIP19.decode(nrelay)
    end

    test "rejects non-binary relay" do
      assert NIP19.encode_nrelay(123) == {:error, :invalid_relay}
    end
  end

  describe "nprofile" do
    test "encode and decode" do
      relays = ["wss://relay.example.com"]
      {:ok, nprofile} = NIP19.encode_nprofile(@pubkey, relays)
      assert String.starts_with?(nprofile, "nprofile1")

      {:ok, profile} = NIP19.decode_nprofile(nprofile)
      assert profile.pubkey == @pubkey
      assert profile.relays == relays
    end

    test "validates relay hints" do
      assert NIP19.encode_nprofile(@pubkey, [123]) == {:error, :invalid_relay}

      assert NIP19.encode_nprofile(@pubkey, String.duplicate("x", 256)) ==
               {:error, :invalid_relay}
    end
  end

  describe "nevent" do
    test "encode and decode with metadata" do
      id = String.duplicate("ab", 32)
      relays = ["wss://r.io"]
      {:ok, nevent} = NIP19.encode_nevent(id, relays: relays, author: @pubkey, kind: 1)
      assert String.starts_with?(nevent, "nevent1")

      {:ok, event} = NIP19.decode_nevent(nevent)
      assert event.event_id == id
      assert event.author == @pubkey
      assert event.kind == 1
      assert event.relays == relays
    end

    test "validates kind and relay hints" do
      id = String.duplicate("ab", 32)
      assert NIP19.encode_nevent(id, kind: -1) == {:error, :invalid_kind}
      assert NIP19.encode_nevent(id, kind: 4_294_967_296) == {:error, :invalid_kind}
      assert NIP19.encode_nevent(id, relays: [123]) == {:error, :invalid_relay}
    end
  end

  describe "naddr" do
    test "encode and decode" do
      {:ok, naddr} = NIP19.encode_naddr("hello", @pubkey, 30023, ["wss://r.io"])
      assert String.starts_with?(naddr, "naddr1")

      {:ok, addr} = NIP19.decode_naddr(naddr)
      assert addr.identifier == "hello"
      assert addr.pubkey == @pubkey
      assert addr.kind == 30023
      assert addr.relays == ["wss://r.io"]
    end

    test "supports binary unicode identifiers" do
      {:ok, naddr} = NIP19.encode_naddr("测试", @pubkey, 30023)
      assert {:ok, addr} = NIP19.decode_naddr(naddr)
      assert addr.identifier == "测试"
    end

    test "validates identifier, kind, and relay hints" do
      assert NIP19.encode_naddr(123, @pubkey, 30023) == {:error, :invalid_identifier}

      assert NIP19.encode_naddr(String.duplicate("x", 256), @pubkey, 30023) ==
               {:error, :invalid_identifier}

      assert NIP19.encode_naddr("hello", @pubkey, -1) == {:error, :invalid_kind}
      assert NIP19.encode_naddr("hello", @pubkey, 4_294_967_296) == {:error, :invalid_kind}
      assert NIP19.encode_naddr("hello", @pubkey, 30023, [123]) == {:error, :invalid_relay}
    end
  end

  describe "decode/1 dispatch" do
    test "bare npub" do
      {:ok, npub} = NostrCore.Bech32.npub(@pubkey)
      assert {:ok, :npub, @pubkey} = NIP19.decode(npub)
    end

    test "rejects bare identifiers with invalid payload lengths" do
      short_npub = Bechamel.encode("npub", <<1, 2, 3>>)
      short_nsec = Bechamel.encode("nsec", <<1, 2, 3>>)
      short_note = Bechamel.encode("note", <<1, 2, 3>>)

      assert NIP19.decode(short_npub) == {:error, :invalid_pubkey}
      assert NIP19.decode(short_nsec) == {:error, :invalid_secret_key}
      assert NIP19.decode(short_note) == {:error, :invalid_event_id}
    end

    test "unknown prefix" do
      assert {:error, :unknown_prefix} = NIP19.decode("xyz123")
    end
  end
end
