defmodule NostrCore.FilterTest do
  use ExUnit.Case, async: true

  alias NostrCore.Filter

  describe "parse/1" do
    test "parses basic filter" do
      raw = %{"kinds" => [1, 2], "limit" => 10}
      assert {:ok, filter} = Filter.parse(raw)
      assert filter.kinds == [1, 2]
      assert filter.limit == 10
    end

    test "parses tag filters" do
      raw = %{"#e" => ["abc"], "#t" => ["nostr"]}
      assert {:ok, filter} = Filter.parse(raw)
      assert filter.tags == %{"#e" => ["abc"], "#t" => ["nostr"]}
    end

    test "parses timestamps" do
      raw = %{"since" => 1_700_000_000, "until" => 1_800_000_000}
      assert {:ok, filter} = Filter.parse(raw)
      assert %DateTime{} = filter.since
      assert %DateTime{} = filter.until
    end
  end
end
