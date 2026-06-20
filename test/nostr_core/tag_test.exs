defmodule NostrCore.TagTest do
  use ExUnit.Case, async: true

  alias NostrCore.Tag

  doctest Tag

  test "parse single tag" do
    assert Tag.parse(["t"]) == {:ok, %Tag{type: "t", data: nil, info: []}}
  end

  test "parse tag with data" do
    assert Tag.parse(["e", "abc"]) == {:ok, %Tag{type: "e", data: "abc", info: []}}
  end

  test "parse tag with info" do
    assert Tag.parse(["e", "abc", "wss://r.io"]) ==
             {:ok, %Tag{type: "e", data: "abc", info: ["wss://r.io"]}}
  end

  test "parse accepts uppercase and multi-character ASCII tag names" do
    assert Tag.parse(["A", "abc"]) == {:ok, %Tag{type: "A", data: "abc", info: []}}
    assert Tag.parse(["emoji", "abc"]) == {:ok, %Tag{type: "emoji", data: "abc", info: []}}

    assert Tag.parse(["challenge", "abc"]) ==
             {:ok, %Tag{type: "challenge", data: "abc", info: []}}
  end

  test "parse rejects empty or non-ASCII tag names" do
    assert Tag.parse(["", "abc"]) == {:error, :invalid_tag_type}
    assert Tag.parse(["é", "abc"]) == {:error, :invalid_tag_type}
    assert Tag.parse(["emoji🦆", "abc"]) == {:error, :invalid_tag_type}
  end

  test "parse empty returns error" do
    assert Tag.parse([]) == {:error, :empty_tag}
  end

  test "create with atom stores binary type without creating atoms from parses" do
    assert Tag.create(:p, "pk") == {:ok, %Tag{type: "p", data: "pk", info: []}}
  end

  test "create accepts multi-character ASCII binary or atom types" do
    assert Tag.create("emoji", "pk") == {:ok, %Tag{type: "emoji", data: "pk", info: []}}
    assert Tag.create(:challenge, "pk") == {:ok, %Tag{type: "challenge", data: "pk", info: []}}
  end

  test "create validates input" do
    assert Tag.create("", "pk") == {:error, :invalid_tag_type}
    assert Tag.create("é", "pk") == {:error, :invalid_tag_type}
    assert Tag.create(:p, 123) == {:error, :invalid_data}
    assert Tag.create(:p, "pk", [123]) == {:error, :invalid_info}
  end

  test "create!/3 raises on invalid input" do
    assert Tag.create!(:p, "pk") == %Tag{type: "p", data: "pk", info: []}
    assert_raise ArgumentError, fn -> Tag.create!("", "pk") end
    assert_raise ArgumentError, fn -> Tag.create!("é", "pk") end
  end

  test "JSON encoding roundtrip" do
    tag = Tag.create!(:e, "id", ["relay"])
    assert JSON.encode!(tag) == ~s|["e","id","relay"]|
  end
end
