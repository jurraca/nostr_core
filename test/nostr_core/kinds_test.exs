defmodule NostrCore.KindsTest do
  use ExUnit.Case, async: true

  alias NostrCore.{Event, Kinds}

  test "classifications" do
    assert Kinds.regular?(1000) == true
    assert Kinds.regular?(5000) == true
    assert Kinds.regular?(1) == false

    assert Kinds.replaceable?(10002) == true
    assert Kinds.replaceable?(20000) == false

    assert Kinds.ephemeral?(20000) == true
    assert Kinds.ephemeral?(25000) == true
    assert Kinds.ephemeral?(10000) == false

    assert Kinds.parameterized_replaceable?(30023) == true
    assert Kinds.parameterized_replaceable?(40000) == false

    assert Kinds.special?(1) == false
    assert Kinds.special?(10002) == true
    assert Kinds.special?(20000) == true
    assert Kinds.special?(30023) == true
  end

  test "accepts event structs" do
    assert Kinds.regular?(Event.create!(1500)) == true
    assert Kinds.ephemeral?(Event.create!(25000)) == true
  end
end
