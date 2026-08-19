defmodule NostrCore.MessageTest do
  use ExUnit.Case, async: true

  alias NostrCore.{Event, Filter, Message}

  describe "serialization roundtrip" do
    test "EVENT" do
      event = Event.create!(1, content: "c")
      msg = Message.create_event(event)
      json = Message.serialize(msg)
      assert json =~ ~s|"EVENT"|
      assert json =~ "c"
    end

    test "EVENT preserves nested tag arrays" do
      event = Event.create!(1, content: "c", tags: [NostrCore.Tag.create!(:e, "id", ["relay"])])

      json = Message.serialize(Message.create_event(event))

      assert ["EVENT", encoded_event] = JSON.decode!(json)
      assert encoded_event["tags"] == [["e", "id", "relay"]]
    end

    test "REQ" do
      {:ok, filter} = Filter.parse(%{"kinds" => [1]})
      msg = Message.request(filter, "sub1")
      json = Message.serialize(msg)
      assert json == ~s|["REQ","sub1",{"kinds":[1]}]|
    end

    test "REQ with multiple filters preserves filter list as multiple message elements" do
      {:ok, filter1} = Filter.parse(%{"kinds" => [1]})
      {:ok, filter2} = Filter.parse(%{"authors" => ["pubkey"]})

      json = Message.serialize(Message.request([filter1, filter2], "sub1"))

      assert JSON.decode!(json) == [
               "REQ",
               "sub1",
               %{"kinds" => [1]},
               %{"authors" => ["pubkey"]}
             ]
    end

    test "CLOSE" do
      msg = Message.close("sub1")
      assert Message.serialize(msg) == ~s|["CLOSE","sub1"]|
    end

    test "NOTICE" do
      msg = Message.notice("hello")
      assert Message.serialize(msg) == ~s|["NOTICE","hello"]|
    end

    test "EOSE" do
      msg = Message.eose("sub1")
      assert Message.serialize(msg) == ~s|["EOSE","sub1"]|
    end

    test "OK" do
      msg = Message.ok("id123", true, "saved")
      assert Message.serialize(msg) == ~s|["OK","id123",true,"saved"]|
    end
  end

  describe "parse/1" do
    test "parses EVENT from relay" do
      event = Event.create!(1, content: "x", created_at: ~U[2024-01-01 00:00:00Z])
      assert {:ok, signed} = Event.sign(event, NostrCore.Test.Fixtures.seckey())

      raw =
        signed
        |> Map.from_struct()
        |> Map.update!(:created_at, &DateTime.to_unix/1)
        |> Map.update!(:tags, fn tags ->
          Enum.map(tags, fn t -> [t.type, t.data | t.info] end)
        end)

      json = JSON.encode!(["EVENT", "sub1", raw])
      assert {:ok, {:event, "sub1", %Event{}}} = Message.parse(json)
    end

    test "parses REQ" do
      assert {:ok, {:req, "sub1", [%Filter{}]}} = Message.parse(~s|["REQ","sub1",{"kinds":[1]}]|)
    end

    test "parses CLOSE" do
      assert {:ok, {:close, "sub1"}} = Message.parse(~s|["CLOSE","sub1"]|)
    end

    test "parses NOTICE" do
      assert {:ok, {:notice, "msg"}} = Message.parse(~s|["NOTICE","msg"]|)
    end

    test "parses EOSE" do
      assert {:ok, {:eose, "sub1"}} = Message.parse(~s|["EOSE","sub1"]|)
    end

    test "parses OK" do
      assert {:ok, {:ok, "id", true, "saved"}} = Message.parse(~s|["OK","id",true,"saved"]|)
    end

    test "returns :error for invalid JSON" do
      assert Message.parse("not json") == {:error, :invalid_json}
    end

    test "accepts valid JSON string escapes" do
      assert Message.parse(~s|["NOTICE","hello\\nworld"]|) ==
               {:ok, {:notice, "hello\nworld"}}

      assert Message.parse(~s|["NOTICE","hello\\u0020world"]|) ==
               {:ok, {:notice, "hello world"}}

      assert Message.parse(~s|["AUTH","challenge\\tvalue"]|) ==
               {:ok, {:auth, "challenge\tvalue"}}
    end

    test "does not validate EVENT id/signature while parsing message shape" do
      raw =
        NostrCore.Test.Fixtures.raw_event_map()
        |> Map.put("id", String.duplicate("0", 64))
        |> Map.put("sig", String.duplicate("0", 128))

      assert {:ok, {:event, event}} = Message.parse(JSON.encode!(["EVENT", raw]))
      assert event.id == String.duplicate("0", 64)
      assert Event.validate(event) == {:error, :invalid_id}
    end

    test "returns :error instead of raising for malformed EVENT payloads" do
      malformed_events = [
        ~s|["EVENT",{}]|,
        ~s|["EVENT",{"kind":1,"created_at":"bad","tags":[],"content":"","id":"bad","pubkey":"bad","sig":"bad"}]|,
        ~s|["EVENT","sub1",{}]|,
        ~s|["EVENT","sub1",{"kind":1,"created_at":"bad","tags":[],"content":"","id":"bad","pubkey":"bad","sig":"bad"}]|,
        ~s|["AUTH",{}]|
      ]

      for json <- malformed_events do
        assert {:error, {:event, _reason}} = Message.parse(json)
      end
    end

    test "returns :error instead of raising for malformed REQ filters" do
      malformed_reqs = [
        ~s|["REQ","sub1",123]|,
        ~s|["REQ","sub1",null]|
      ]

      for json <- malformed_reqs do
        assert {:error, {:filter, _reason}} = Message.parse(json)
      end
    end

    test "returns :error instead of raising for malformed COUNT filters" do
      malformed_counts = [
        ~s|["COUNT","sub1",123]|,
        ~s|["COUNT","sub1",null]|
      ]

      for json <- malformed_counts do
        assert {:error, {:filter, _reason}} = Message.parse(json)
      end
    end
  end
end
