defmodule NostrCore.CryptoTest do
  use ExUnit.Case, async: true

  alias NostrCore.{Crypto, Test.Fixtures}

  describe "pubkey/1" do
    test "derives correct pubkey" do
      assert Crypto.pubkey(Fixtures.seckey()) == {:ok, Fixtures.pubkey()}
    end

    test "pubkey is 64 hex chars" do
      assert {:ok, pk} = Crypto.pubkey(Fixtures.seckey())
      assert String.length(pk) == 64
      assert String.match?(pk, ~r/^[0-9a-f]+$/)
    end

    test "returns errors for invalid input" do
      assert Crypto.pubkey("not hex") == {:error, :invalid_hex}
      assert Crypto.pubkey("00") == {:error, :invalid_secret_key}
      assert Crypto.pubkey(123) == {:error, :invalid_secret_key}
    end

    test "pubkey!/1 raises on invalid input" do
      assert Crypto.pubkey!(Fixtures.seckey()) == Fixtures.pubkey()
      assert_raise ArgumentError, fn -> Crypto.pubkey!("not hex") end
    end
  end

  describe "sign/2 and verify?/3" do
    test "produces valid signature" do
      data = "0000000000000000000000000000000000000000000000000000000000000001"
      assert {:ok, sig} = Crypto.sign(data, Fixtures.seckey())
      assert String.length(sig) == 128
      assert Crypto.verify?(sig, data, Fixtures.pubkey()) == true
    end

    test "invalid signature fails" do
      data = "0000000000000000000000000000000000000000000000000000000000000001"
      bad_sig = String.duplicate("0", 128)
      assert Crypto.verify?(bad_sig, data, Fixtures.pubkey()) == false
    end

    test "different data produces different sig" do
      d1 = "0000000000000000000000000000000000000000000000000000000000000001"
      d2 = "0000000000000000000000000000000000000000000000000000000000000002"
      assert {:ok, s1} = Crypto.sign(d1, Fixtures.seckey())
      assert {:ok, s2} = Crypto.sign(d2, Fixtures.seckey())
      refute s1 == s2
    end

    test "returns errors for invalid signing input" do
      data = "0000000000000000000000000000000000000000000000000000000000000001"

      assert Crypto.sign("not hex", Fixtures.seckey()) == {:error, :invalid_hex}
      assert Crypto.sign("00", Fixtures.seckey()) == {:error, :invalid_message_hash}
      assert Crypto.sign(data, "not hex") == {:error, :invalid_hex}
      assert Crypto.sign(data, "00") == {:error, :invalid_secret_key}
      assert Crypto.sign(123, Fixtures.seckey()) == {:error, :invalid_message_hash}
    end

    test "sign!/2 raises on invalid input" do
      data = "0000000000000000000000000000000000000000000000000000000000000001"

      assert Crypto.sign!(data, Fixtures.seckey()) |> String.length() == 128
      assert_raise ArgumentError, fn -> Crypto.sign!("not hex", Fixtures.seckey()) end
    end
  end
end
