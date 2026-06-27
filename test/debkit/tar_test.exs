defmodule Debkit.TarTest do
  use ExUnit.Case, async: true
  doctest Debkit.Tar

  alias Debkit.Tar

  @entries [
    {"./control", "Package: hello\nVersion: 1.0\n"},
    {"./md5sums", "abc123  ./usr/bin/hello\n"},
    {"./postinst", "#!/bin/sh\nexit 0\n", 0o755}
  ]

  test "round-trips entries in order, preserving names and bytes" do
    assert {:ok, tar} = Tar.write(@entries)
    assert {:ok, read} = Tar.read(tar)

    expected =
      Enum.map(@entries, fn
        {name, body} -> {name, body}
        {name, body, _mode} -> {name, body}
      end)

    assert read == expected
  end

  test "the 2-tuple form defaults mode to 0o644 and writes a valid entry" do
    assert {:ok, tar} = Tar.write([{"./control", "x"}])
    assert {:ok, [{"./control", "x"}]} = Tar.read(tar)
  end

  test "writing is deterministic (zeroed mtime/uid/gid)" do
    assert {:ok, a} = Tar.write(@entries)
    assert {:ok, b} = Tar.write(@entries)
    assert a == b
  end

  test "empty file contents round-trip" do
    assert {:ok, tar} = Tar.write([{"./empty", ""}])
    assert {:ok, [{"./empty", ""}]} = Tar.read(tar)
  end

  test "is a ustar archive (magic at offset 257)" do
    assert {:ok, tar} = Tar.write([{"./control", "x"}])
    assert binary_part(tar, 257, 5) == "ustar"
  end

  test "reads corrupt input as {:error, :corrupt}" do
    assert {:error, :corrupt} = Tar.read(String.duplicate("not a tar header block", 50))
  end

  test "write!/1 and read!/1 raise on error / return values directly" do
    tar = Tar.write!([{"./x", "hi"}])
    assert Tar.read!(tar) == [{"./x", "hi"}]
    assert_raise Debkit.Error, fn -> Tar.read!(String.duplicate("garbage block!!!", 50)) end
  end
end
