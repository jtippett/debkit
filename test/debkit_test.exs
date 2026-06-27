defmodule DebkitTest do
  use ExUnit.Case, async: true
  doctest Debkit

  @formats [:gzip, :xz, :zstd]

  describe "compress/2 and decompress/2 round-trip" do
    for format <- @formats do
      test "#{format}: round-trips arbitrary bytes" do
        for payload <- ["", "hello", String.duplicate("deb\n", 5_000), <<0, 255, 1, 254>>] do
          assert {:ok, comp} = Debkit.compress(unquote(format), payload)
          assert is_binary(comp)
          assert {:ok, ^payload} = Debkit.decompress(unquote(format), comp)
        end
      end

      test "#{format}: compression is deterministic" do
        payload = String.duplicate("reproducible builds\n", 1_000)
        assert {:ok, a} = Debkit.compress(unquote(format), payload)
        assert {:ok, b} = Debkit.compress(unquote(format), payload)
        assert a == b
      end

      test "#{format}: actually compresses redundant data" do
        payload = String.duplicate("a", 100_000)
        assert {:ok, comp} = Debkit.compress(unquote(format), payload)
        assert byte_size(comp) < byte_size(payload)
      end

      test "#{format}: rejects a corrupt stream" do
        assert {:error, :corrupt} =
                 Debkit.decompress(unquote(format), "definitely not compressed")
      end
    end

    test "formats are not interchangeable (xz stream is not gzip)" do
      {:ok, xz} = Debkit.compress(:xz, "payload")
      assert {:error, :corrupt} = Debkit.decompress(:gzip, xz)
    end
  end

  describe "guards" do
    test "an unknown format raises a FunctionClauseError (caller bug, not data error)" do
      # `apply/3` keeps the bad atom opaque to the compile-time type checker —
      # we're asserting the *runtime* guard, not a type error.
      assert_raise FunctionClauseError, fn -> apply(Debkit, :compress, [:lz4, "x"]) end
      assert_raise FunctionClauseError, fn -> apply(Debkit, :decompress, [:lz4, "x"]) end
    end
  end

  describe "bang variants" do
    test "compress!/2 and decompress!/2 return bytes directly" do
      gz = Debkit.compress!(:gzip, "hi")
      assert Debkit.decompress!(:gzip, gz) == "hi"
    end

    test "decompress!/2 raises Debkit.Error carrying the reason" do
      err = assert_raise Debkit.Error, fn -> Debkit.decompress!(:gzip, "garbage") end
      assert err.reason == :corrupt
      assert err.operation == :decompress
      assert Exception.message(err) =~ "corrupt"
    end
  end
end
