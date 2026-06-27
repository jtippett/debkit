defmodule Debkit.TarTest do
  use ExUnit.Case, async: true
  doctest Debkit.Tar

  alias Debkit.Tar
  alias Debkit.Tar.Entry

  @entries [
    Tar.file("./control", "Package: hello\nVersion: 1.0\n"),
    Tar.file("./md5sums", "abc123  ./usr/bin/hello\n"),
    Tar.file("./postinst", "#!/bin/sh\nexit 0\n", 0o755)
  ]

  describe "constructors" do
    test "file/2 defaults the mode to 0o644" do
      assert Tar.file("./x", "hi") == %Entry{
               name: "./x",
               contents: "hi",
               mode: 0o644,
               type: :file
             }
    end

    test "dir/1 defaults the mode to 0o755 and has empty contents" do
      assert Tar.dir("./usr/") == %Entry{name: "./usr/", contents: "", mode: 0o755, type: :dir}
    end
  end

  describe "round-trip" do
    test "preserves order, names, contents, modes and types" do
      assert {:ok, tar} = Tar.write(@entries)
      assert {:ok, read} = Tar.read(tar)
      assert read == @entries
    end

    test "the same struct flows through write and read" do
      entries = [Tar.dir("./usr/", 0o755), Tar.file("./usr/x", "data", 0o600)]
      assert {:ok, ^entries} = Tar.read(Tar.write!(entries))
    end

    test "empty file contents round-trip" do
      assert {:ok, [%Entry{name: "./empty", contents: ""}]} =
               Tar.read(Tar.write!([Tar.file("./empty", "")]))
    end
  end

  describe "writing" do
    test "is deterministic (zeroed mtime/uid/gid)" do
      assert {:ok, a} = Tar.write(@entries)
      assert {:ok, b} = Tar.write(@entries)
      assert a == b
    end

    test "is a ustar archive (magic at offset 257)" do
      assert {:ok, tar} = Tar.write([Tar.file("./control", "x")])
      assert binary_part(tar, 257, 5) == "ustar"
    end

    test "resolves a nil mode to the per-type default" do
      entries = [%Entry{name: "./f"}, %Entry{name: "./d/", type: :dir}]

      assert {:ok, [%Entry{mode: 0o644, type: :file}, %Entry{mode: 0o755, type: :dir}]} =
               Tar.read(Tar.write!(entries))
    end
  end

  describe "directory entries" do
    # ustar typeflag lives at offset 156 of each 512-byte header; '5' is a directory.
    defp typeflag(tar, header_index), do: binary_part(tar, header_index * 512 + 156, 1)

    test "dir/2 writes a directory entry (typeflag '5') with a verbatim trailing slash" do
      assert {:ok, tar} = Tar.write([Tar.dir("./usr/bin/", 0o755)])
      assert typeflag(tar, 0) == "5"
      assert {:ok, [%Entry{name: "./usr/bin/", type: :dir, mode: 0o755}]} = Tar.read(tar)
    end

    test "directories and files interleave in order" do
      entries = [
        Tar.dir("./usr/", 0o755),
        Tar.dir("./usr/bin/"),
        Tar.file("./usr/bin/hello", "#!/bin/sh\n", 0o755)
      ]

      assert {:ok, tar} = Tar.write(entries)
      assert typeflag(tar, 0) == "5"
      assert typeflag(tar, 1) == "5"
      assert typeflag(tar, 2) == "0"
      assert {:ok, ^entries} = Tar.read(tar)
    end
  end

  describe "errors" do
    test "reads corrupt input as {:error, :corrupt}" do
      assert {:error, :corrupt} = Tar.read(String.duplicate("not a tar header block", 50))
    end

    test "write!/1 and read!/1 return values directly / raise on error" do
      tar = Tar.write!([Tar.file("./x", "hi")])
      assert [%Entry{name: "./x", contents: "hi"}] = Tar.read!(tar)
      assert_raise Debkit.Error, fn -> Tar.read!(String.duplicate("garbage block!!!", 50)) end
    end
  end

  describe "Entry inspect" do
    test "renders type, name, mode and (for files) size" do
      assert inspect(Tar.file("./control", "hello")) ==
               ~s(#Debkit.Tar.Entry<file "./control" 0o644 5B>)

      assert inspect(Tar.dir("./usr/bin/")) ==
               ~s(#Debkit.Tar.Entry<dir "./usr/bin/" 0o755>)
    end
  end
end
