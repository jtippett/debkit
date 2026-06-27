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

  describe "directory entries" do
    # ustar typeflag lives at offset 156 of each 512-byte header; '5' is a directory.
    defp typeflag(tar, header_index), do: binary_part(tar, header_index * 512 + 156, 1)

    defp stored_name(tar, header_index) do
      tar
      |> binary_part(header_index * 512, 100)
      |> :binary.bin_to_list()
      |> Enum.take_while(&(&1 != 0))
      |> List.to_string()
    end

    test "{:dir, name, mode} writes a directory entry (typeflag '5')" do
      assert {:ok, tar} = Tar.write([{:dir, "./usr/bin/", 0o755}])
      assert typeflag(tar, 0) == "5"
      assert stored_name(tar, 0) == "./usr/bin/"
    end

    test "{:dir, name} defaults the mode to 0o755" do
      assert {:ok, tar} = Tar.write([{:dir, "./usr/"}])
      assert typeflag(tar, 0) == "5"
      # mode field (offset 100, 8 bytes, octal ascii) encodes 0o755
      assert binary_part(tar, 100, 8) =~ "755"
    end

    test "directory and file entries interleave in order" do
      entries = [
        {:dir, "./usr/", 0o755},
        {:dir, "./usr/bin/", 0o755},
        {"./usr/bin/hello", "#!/bin/sh\n", 0o755}
      ]

      assert {:ok, tar} = Tar.write(entries)
      assert typeflag(tar, 0) == "5"
      assert typeflag(tar, 1) == "5"
      assert typeflag(tar, 2) == "0"
      assert stored_name(tar, 1) == "./usr/bin/"
      assert stored_name(tar, 2) == "./usr/bin/hello"
    end

    test "writing directory entries stays deterministic" do
      entries = [{:dir, "./usr/", 0o755}, {"./usr/x", "data"}]
      assert {:ok, a} = Tar.write(entries)
      assert {:ok, b} = Tar.write(entries)
      assert a == b
    end

    test "read/1 still returns regular files only, skipping directories" do
      tar = Tar.write!([{:dir, "./usr/", 0o755}, {"./usr/x", "data"}])
      assert {:ok, [{"./usr/x", "data"}]} = Tar.read(tar)
    end
  end
end
