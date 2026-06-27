defmodule Debkit.ArTest do
  use ExUnit.Case, async: true
  doctest Debkit.Ar

  alias Debkit.Ar

  @members [
    {"debian-binary", "2.0\n"},
    {"control.tar.gz", <<31, 139, 8, 0, 0>>},
    {"data.tar.xz", <<253, 55, 122, 88, 90, 0>>}
  ]

  test "round-trips members in order, preserving names and bytes" do
    assert {:ok, bytes} = Ar.write(@members)
    assert {:ok, read} = Ar.read(bytes)
    assert read == @members
  end

  test "produces a real ar archive (starts with the global header magic)" do
    assert {:ok, <<"!<arch>\n", _rest::binary>>} = Ar.write(@members)
  end

  test "writing is deterministic (no mtime/uid/gid drift, no symbol table)" do
    assert {:ok, a} = Ar.write(@members)
    assert {:ok, b} = Ar.write(@members)
    assert a == b
  end

  test "never injects a __.SYMDEF / symbol-table member (the macOS ar bug)" do
    assert {:ok, bytes} = Ar.write(@members)
    assert {:ok, read} = Ar.read(bytes)
    names = Enum.map(read, &elem(&1, 0))
    refute Enum.any?(names, &String.contains?(&1, "SYMDEF"))
    refute "/" in names
    refute "//" in names
  end

  test "empty member contents round-trip" do
    assert {:ok, bytes} = Ar.write([{"empty", ""}])
    assert {:ok, [{"empty", ""}]} = Ar.read(bytes)
  end

  test "rejects a member name that overflows the 16-byte ar field" do
    assert {:error, :name_too_long} = Ar.write([{String.duplicate("x", 17), "data"}])
  end

  test "reads corrupt input as {:error, :corrupt}" do
    assert {:error, :corrupt} = Ar.read("this is not an ar archive")
  end

  test "write!/1 and read!/1 raise on error / return values directly" do
    bytes = Ar.write!(@members)
    assert Ar.read!(bytes) == @members
    assert_raise Debkit.Error, fn -> Ar.read!("nope") end
  end
end
