defmodule NostrCore.EventTest do
  use ExUnit.Case, async: true

  alias NostrCore.Test.Fixtures
  alias NostrCore.{Event, Tag}

  doctest Event

  describe "create/2" do
    test "creates minimal event" do
      assert {:ok, event} = Event.create(1)
      assert event.kind == 1
      assert event.content == ""
      assert event.tags == []
      assert event.pubkey == nil
      assert event.id == nil
      assert event.sig == nil
      assert %DateTime{} = event.created_at
    end

    test "creates event with options" do
      ts = ~U[2024-06-01 12:00:00Z]
      tags = [Tag.create!(:e, "event_id")]

      assert {:ok, event} =
               Event.create(1,
                 content: "hello",
                 tags: tags,
                 created_at: ts,
                 pubkey: Fixtures.pubkey()
               )

      assert event.content == "hello"
      assert event.tags == tags
      assert event.created_at == ts
      assert event.pubkey == Fixtures.pubkey()
    end

    test "returns errors for invalid input" do
      assert Event.create(-1) == {:error, :invalid_kind}
      assert Event.create("1") == {:error, :invalid_kind}
      assert Event.create(1, :not_options) == {:error, :invalid_options}
      assert Event.create(1, tags: [:bad]) == {:error, :invalid_tags}
      assert Event.create(1, content: 123) == {:error, :invalid_content}
      assert Event.create(1, created_at: 123) == {:error, :invalid_created_at}
    end

    test "create!/2 raises on invalid input" do
      assert %Event{} = Event.create!(1)
      assert_raise ArgumentError, fn -> Event.create!(-1) end
    end
  end

  describe "sign/2" do
    test "signs event and populates fields" do
      assert {:ok, event} =
               1
               |> Event.create!(content: "test", created_at: ~U[2024-01-01 00:00:00Z])
               |> Event.sign(Fixtures.seckey())

      assert event.pubkey == Fixtures.pubkey()
      assert event.id != nil
      assert String.length(event.id) == 64
      assert event.sig != nil
      assert String.length(event.sig) == 128
    end

    test "returns error on mismatched id" do
      event =
        1
        |> Event.create!(content: "test", created_at: ~U[2024-01-01 00:00:00Z])
        |> Map.put(:pubkey, Fixtures.pubkey())
        |> Map.put(:id, String.duplicate("0", 64))

      assert Event.sign(event, Fixtures.seckey()) == {:error, :mismatched_id}
      assert_raise ArgumentError, fn -> Event.sign!(event, Fixtures.seckey()) end
    end

    test "create/2 ignores id because ids are derived" do
      event = Event.create!(1, id: String.duplicate("0", 64))
      assert event.id == nil
    end

    test "returns error on mismatched pubkey" do
      event = Event.create!(1, pubkey: Fixtures.pubkey2())
      assert Event.sign(event, Fixtures.seckey()) == {:error, :mismatched_pubkey}
      assert_raise ArgumentError, fn -> Event.sign!(event, Fixtures.seckey()) end
    end

    test "returns error on invalid secret key" do
      event = Event.create!(1)
      assert Event.sign(event, "not hex") == {:error, :invalid_hex}
    end
  end

  describe "compute_id/1" do
    test "id is deterministic" do
      event = Event.create!(1, content: "x", created_at: ~U[2024-01-01 00:00:00Z])
      id1 = Event.compute_id(event)
      id2 = Event.compute_id(event)
      assert id1 == id2
      assert String.length(id1) == 64
    end
  end

  describe "serialize/1" do
    test "produces canonical NIP-01 JSON" do
      event =
        Event.create!(1,
          content: "x",
          pubkey: Fixtures.pubkey(),
          created_at: ~U[2024-01-01 00:00:00Z]
        )

      json = Event.serialize(event)
      assert json == ~s|[0,"#{Fixtures.pubkey()}",1704067200,1,[],"x"]|
    end

    test "canonical JSON serialization is deterministic for escaped and unicode content" do
      event =
        Event.create!(1,
          content: "hello\n\"nostr\" \\ 🦆",
          pubkey: Fixtures.pubkey(),
          tags: [Tag.create!(:t, "测试")],
          created_at: ~U[2024-01-01 00:00:00Z]
        )

      json = Event.serialize(event)

      assert json == Event.serialize(event)

      assert JSON.decode!(json) == [
               0,
               Fixtures.pubkey(),
               1_704_067_200,
               1,
               [["t", "测试"]],
               "hello\n\"nostr\" \\ 🦆"
             ]
    end
  end

  describe "parse/1 and parse_unverified/1" do
    test "parses signed event map" do
      raw = Fixtures.raw_event_map()
      assert {:ok, %Event{}} = Event.parse(raw)
    end

    test "returns error for tampered id" do
      raw = Map.put(Fixtures.raw_event_map(), "id", String.duplicate("0", 64))
      assert Event.parse(raw) == {:error, :invalid_id}
    end

    test "parse_unverified ignores bad id" do
      raw = Map.put(Fixtures.raw_event_map(), "id", String.duplicate("0", 64))
      assert {:ok, event} = Event.parse_unverified(raw)
      assert %Event{} = event
      assert event.id == String.duplicate("0", 64)
    end
  end
end
