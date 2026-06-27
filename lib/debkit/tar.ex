defmodule Debkit.Tar do
  @moduledoc """
  Read and write `tar` archives — the middle layer of a `.deb`.

  Inside a `.deb`, both `control.tar.*` and `data.tar.*` are tar archives (once
  decompressed). Entries are `Debkit.Tar.Entry` structs — the same struct flows
  through `read/1` and `write/1`, so an archive round-trips. Build entries with
  the `file/3` and `dir/2` constructors:

      tar = Debkit.Tar.write!([
        Debkit.Tar.dir("./usr/", 0o755),
        Debkit.Tar.dir("./usr/bin/"),
        Debkit.Tar.file("./usr/bin/hello", "#!/bin/sh\\n", 0o755)
      ])

  Directory entries (ustar typeflag `5`) are what a `.deb`'s `data.tar`
  conventionally lists for each parent directory; emit them explicitly, in order,
  before the files they contain.

  > #### Files and directories only {: .info}
  >
  > `read/1` returns regular-file and directory entries. Symlinks, hardlinks, and
  > device nodes are skipped — `.deb` control/data tars don't use them.

  ## Determinism

  `write/1` emits ustar entries with mtime `0`, uid `0`, and gid `0`, and stores
  names verbatim, so equal input yields equal output — the basis for reproducible
  packages.
  """

  alias Debkit.Native
  alias Debkit.Tar.Entry

  @default_file_mode 0o644
  @default_dir_mode 0o755

  @doc """
  Builds a regular-file `Debkit.Tar.Entry`.

  ## Examples

      iex> Debkit.Tar.file("./control", "Package: hello\\n")
      #Debkit.Tar.Entry<file "./control" 0o644 15B>
  """
  @spec file(String.t(), binary(), non_neg_integer()) :: Entry.t()
  def file(name, contents, mode \\ @default_file_mode)
      when is_binary(name) and is_binary(contents) and is_integer(mode) and mode >= 0 do
    %Entry{name: name, contents: contents, mode: mode, type: :file}
  end

  @doc """
  Builds a directory `Debkit.Tar.Entry`.

  Keep the trailing `/` in `name` — it's stored verbatim.

  ## Examples

      iex> Debkit.Tar.dir("./usr/bin/")
      #Debkit.Tar.Entry<dir "./usr/bin/" 0o755>
  """
  @spec dir(String.t(), non_neg_integer()) :: Entry.t()
  def dir(name, mode \\ @default_dir_mode)
      when is_binary(name) and is_integer(mode) and mode >= 0 do
    %Entry{name: name, contents: "", mode: mode, type: :dir}
  end

  @doc """
  Reads a tar archive into `Debkit.Tar.Entry` structs, in archive order.

  Returns regular-file and directory entries; other entry types are skipped.
  Returns `{:error, :corrupt}` if `binary` is not a well-formed tar archive.

  ## Examples

      iex> {:ok, [entry]} = Debkit.Tar.read(Debkit.Tar.write!([Debkit.Tar.file("./x", "hi")]))
      iex> entry
      #Debkit.Tar.Entry<file "./x" 0o644 2B>
  """
  @spec read(binary()) :: {:ok, [Entry.t()]} | {:error, Debkit.error()}
  def read(binary) when is_binary(binary) do
    with {:ok, raw} <- Native.tar_read(binary) do
      {:ok, Enum.map(raw, &from_native/1)}
    end
  end

  @doc "Like `read/1` but returns the entries directly, raising `Debkit.Error` on failure."
  @spec read!(binary()) :: [Entry.t()]
  def read!(binary), do: Debkit.unwrap(read(binary), :"Tar.read")

  @doc """
  Writes `Debkit.Tar.Entry` structs to a deterministic ustar archive, in order.

  An entry's `mode` of `nil` is resolved to the default for its type (`0o644` for
  a file, `0o755` for a directory). Use `file/3` and `dir/2` to build entries
  conveniently.

  ## Examples

      iex> {:ok, tar} = Debkit.Tar.write([Debkit.Tar.file("./control", "Package: hello\\n")])
      iex> is_binary(tar)
      true
  """
  @spec write([Entry.t()]) :: {:ok, binary()} | {:error, Debkit.error()}
  def write(entries) when is_list(entries) do
    entries
    |> Enum.map(&to_native/1)
    |> Native.tar_write()
  end

  @doc "Like `write/1` but returns the bytes directly, raising `Debkit.Error` on failure."
  @spec write!([Entry.t()]) :: binary()
  def write!(entries), do: Debkit.unwrap(write(entries), :"Tar.write")

  # The NIF speaks a uniform {name, contents, mode, type} tuple. Resolve a nil
  # mode to the per-type default on the way down, and rebuild the struct on the
  # way back up.
  defp to_native(%Entry{name: name, contents: contents, mode: mode, type: type})
       when is_binary(name) and is_binary(contents) and type in [:file, :dir] do
    {name, contents, mode || default_mode(type), type}
  end

  defp from_native({name, contents, mode, type}) do
    %Entry{name: name, contents: contents, mode: mode, type: type}
  end

  defp default_mode(:file), do: @default_file_mode
  defp default_mode(:dir), do: @default_dir_mode
end
