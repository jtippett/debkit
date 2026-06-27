defmodule Debkit.DebRoundtripTest do
  @moduledoc """
  Assembles a minimal `.deb` from scratch using only Debkit — through all four
  nested layers (ar → tar → compression) — then parses it back. This is the
  scenario the library exists for.
  """
  use ExUnit.Case, async: true

  alias Debkit.Ar
  alias Debkit.Tar
  alias Debkit.Tar.Entry

  for compression <- [:gzip, :xz, :zstd] do
    test "builds and parses a #{compression}-compressed .deb" do
      compression = unquote(compression)
      ext = %{gzip: "gz", xz: "xz", zstd: "zst"}[compression]

      control = """
      Package: hello
      Version: 1.0.0
      Architecture: amd64
      Maintainer: Test <test@example.com>
      Description: a tiny test package
      """

      # control.tar.<ext>
      control_tar = Tar.write!([Tar.file("./control", control)])
      control_comp = Debkit.compress!(compression, control_tar)

      # data.tar.<ext> with a dir tree and one file
      data_tar =
        Tar.write!([
          Tar.dir("./usr/", 0o755),
          Tar.dir("./usr/bin/", 0o755),
          Tar.file("./usr/bin/hello", "#!/bin/sh\necho hello\n", 0o755)
        ])

      data_comp = Debkit.compress!(compression, data_tar)

      # the ar container — exact .deb member order
      deb =
        Ar.write!([
          {"debian-binary", "2.0\n"},
          {"control.tar.#{ext}", control_comp},
          {"data.tar.#{ext}", data_comp}
        ])

      # ---- parse it back ----
      assert {:ok, members} = Ar.read(deb)
      assert [{"debian-binary", "2.0\n"}, {control_name, _}, {data_name, _}] = members
      assert control_name == "control.tar.#{ext}"
      assert data_name == "data.tar.#{ext}"

      {_, control_comp_read} = Enum.at(members, 1)
      control_tar_read = Debkit.decompress!(compression, control_comp_read)

      assert {:ok, [%Entry{name: "./control", contents: ^control, type: :file}]} =
               Tar.read(control_tar_read)

      {_, data_comp_read} = Enum.at(members, 2)
      data_tar_read = Debkit.decompress!(compression, data_comp_read)

      assert {:ok,
              [
                %Entry{name: "./usr/", type: :dir},
                %Entry{name: "./usr/bin/", type: :dir},
                %Entry{name: "./usr/bin/hello", contents: "#!/bin/sh\necho hello\n", type: :file}
              ]} = Tar.read(data_tar_read)
    end
  end

  test "the whole .deb is byte-for-byte reproducible" do
    build = fn ->
      ctl = Tar.write!([Tar.file("./control", "Package: x\n")])
      Ar.write!([{"debian-binary", "2.0\n"}, {"control.tar.gz", Debkit.compress!(:gzip, ctl)}])
    end

    assert build.() == build.()
  end
end
