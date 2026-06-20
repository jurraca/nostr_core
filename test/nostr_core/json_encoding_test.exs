defmodule NostrCore.JSONEncodingTest do
  use ExUnit.Case, async: true

  alias NostrCore.{Event, Filter, Tag}
  alias NostrCore.Test.Fixtures

  test "event atom keys encode as JSON object string keys" do
    event =
      Event.create!(1,
        content: "hello",
        pubkey: Fixtures.pubkey(),
        tags: [Tag.create!(:e, "event_id")],
        created_at: ~U[2024-01-01 00:00:00Z]
      )
      |> Map.put(:id, String.duplicate("a", 64))
      |> Map.put(:sig, String.duplicate("b", 128))

    decoded = event |> JSON.encode!() |> JSON.decode!()

    assert decoded == %{
             "id" => String.duplicate("a", 64),
             "pubkey" => Fixtures.pubkey(),
             "kind" => 1,
             "tags" => [["e", "event_id"]],
             "created_at" => 1_704_067_200,
             "content" => "hello",
             "sig" => String.duplicate("b", 128)
           }
  end

  test "filter atom keys encode as JSON object string keys" do
    {:ok, filter} = Filter.parse(%{"kinds" => [1], "since" => 1000, "#e" => ["event_id"]})

    decoded = filter |> JSON.encode!() |> JSON.decode!()

    assert decoded == %{
             "kinds" => [1],
             "since" => 1000,
             "#e" => ["event_id"]
           }
  end
end
