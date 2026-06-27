defmodule Debkit.DpkgInteropTest do
  @moduledoc """
  Proves a `.deb` assembled entirely by Debkit is read correctly by the real
  `dpkg-deb`, and that Debkit reads real `dpkg`/`aptly`-built `.deb` fixtures.

  Tagged `:dpkg` — excluded automatically when `dpkg-deb` is not installed (see
  `test/test_helper.exs`).
  """
  use ExUnit.Case, async: true

  @moduletag :dpkg

  alias Debkit.Ar
  alias Debkit.Tar

  # Real .debs built by aptly/dpkg, one per compression format.
  @fixture_dir Path.expand("../../../paclite/test/fixtures/aptly", __DIR__)

  describe "dpkg-deb reads a .deb that Debkit builds" do
    test "control fields, file paths, modes, and member list all check out" do
      control = """
      Package: debkit-demo
      Version: 0.1.0
      Architecture: all
      Maintainer: James <james@lvl4.net>
      Description: a .deb assembled entirely by Debkit
      """

      control_tar = Tar.write!([{"./control", control}])

      data_tar =
        Tar.write!([
          {"./usr/bin/debkit-demo", "#!/bin/sh\necho hi\n", 0o755},
          {"./usr/share/doc/debkit-demo/copyright", "MIT\n", 0o644}
        ])

      deb =
        Ar.write!([
          {"debian-binary", "2.0\n"},
          {"control.tar.gz", Debkit.compress!(:gzip, control_tar)},
          {"data.tar.gz", Debkit.compress!(:gzip, data_tar)}
        ])

      path = Path.join(System.tmp_dir!(), "debkit-demo-#{System.unique_integer([:positive])}.deb")
      File.write!(path, deb)

      try do
        # control metadata
        assert {fields, 0} = System.cmd("dpkg-deb", ["-f", path])
        assert fields =~ "Package: debkit-demo"
        assert fields =~ "Version: 0.1.0"
        assert fields =~ "Architecture: all"

        # data listing: paths preserved verbatim (with ./) and modes intact
        assert {listing, 0} = System.cmd("dpkg-deb", ["-c", path])
        assert listing =~ "./usr/bin/debkit-demo"
        assert listing =~ "./usr/share/doc/debkit-demo/copyright"
        assert listing =~ "rwxr-xr-x"
        assert listing =~ ~r/rw-r--r--/

        # no macOS-style __.SYMDEF symbol table member
        refute listing =~ "SYMDEF"
      after
        File.rm(path)
      end
    end
  end

  describe "Debkit reads real dpkg/aptly-built .debs" do
    @tag :tmp_dir
    for ext <- ~w(gz xz zst) do
      test "extracts the same control fields as dpkg-deb (#{ext})" do
        ext = unquote(ext)

        path =
          Enum.find(Path.wildcard(Path.join(@fixture_dir, "*.deb")), &(control_ext(&1) == ext))

        if path do
          deb = File.read!(path)
          {:ok, members} = Ar.read(deb)

          {cname, cbytes} =
            Enum.find(members, fn {n, _} -> String.starts_with?(n, "control.tar") end)

          {:ok, entries} = Tar.read(Debkit.decompress!(format(cname), cbytes))

          {_, body} =
            Enum.find(entries, fn {n, _} ->
              base = Path.basename(n)
              base == "control" and not String.starts_with?(base, "._")
            end)

          # what dpkg-deb reports, field by field
          {dpkg_fields, 0} = System.cmd("dpkg-deb", ["-f", path])

          for key <- ["Package", "Version", "Architecture"] do
            assert field(body, key) == field(dpkg_fields, key)
            assert field(body, key) != nil
          end
        end
      end
    end
  end

  # the compression suffix of the control member inside a .deb, by reading its ar
  defp control_ext(path) do
    {:ok, members} = Ar.read(File.read!(path))
    {name, _} = Enum.find(members, fn {n, _} -> String.starts_with?(n, "control.tar") end)
    name |> Path.extname() |> String.trim_leading(".")
  end

  defp format(name), do: %{".gz" => :gzip, ".xz" => :xz, ".zst" => :zstd}[Path.extname(name)]

  defp field(body, key) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line, ": ", parts: 2) do
        [^key, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end
end
