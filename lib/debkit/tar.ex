defmodule Debkit.Tar do
  @moduledoc """
  Read and write `tar` archives — the middle layer of a `.deb`.

  Inside a `.deb`, both `control.tar.*` and `data.tar.*` are tar archives (once
  decompressed). This module reads regular-file entries into `{name, bytes}`
  pairs and writes entries back out as a deterministic [ustar][ustar] archive.

  > #### Regular files only {: .info}
  >
  > `read/1` returns **regular file** entries. Directory, symlink, hardlink, and
  > device entries are skipped — `.deb` control tars are all regular files, which
  > is the case this library targets. (Data tars you typically store and serve
  > verbatim rather than read through here.)

  ## Determinism

  `write/1` emits ustar entries with mtime `0`, uid `0`, and gid `0`, so equal
  input yields equal output — the basis for reproducible packages.

  ## Example

      iex> tar = Debkit.Tar.write!([
      ...>   {"./control", "Package: hello\\n"},
      ...>   {"./md5sums", "", 0o644}
      ...> ])
      iex> {:ok, entries} = Debkit.Tar.read(tar)
      iex> Enum.map(entries, &elem(&1, 0))
      ["./control", "./md5sums"]

  [ustar]: https://en.wikipedia.org/wiki/Tar_(computing)#UStar_format
  """

  alias Debkit.Native

  @default_mode 0o644
  @default_dir_mode 0o755

  @typedoc "An entry read from an archive: its name and contents."
  @type entry :: {name :: String.t(), contents :: binary()}

  @typedoc """
  An entry to write:

    * `{name, contents}` — a regular file (mode defaults to `0o644`)
    * `{name, contents, mode}` — a regular file with an explicit mode
    * `{:dir, name}` — a directory (mode defaults to `0o755`)
    * `{:dir, name, mode}` — a directory with an explicit mode

  Directory names are stored verbatim, so include the trailing `/` and any
  leading `./` yourself — e.g. `{:dir, "./usr/bin/", 0o755}` — matching the
  `.deb` convention.
  """
  @type write_entry ::
          {name :: String.t(), contents :: binary()}
          | {name :: String.t(), contents :: binary(), mode :: non_neg_integer()}
          | {:dir, name :: String.t()}
          | {:dir, name :: String.t(), mode :: non_neg_integer()}

  @doc """
  Reads a tar archive into its regular-file entries, in archive order.

  Returns `{:error, :corrupt}` if `binary` is not a well-formed tar archive.

  ## Examples

      iex> {:ok, entries} = Debkit.Tar.read(Debkit.Tar.write!([{"./x", "hi"}]))
      iex> entries
      [{"./x", "hi"}]
  """
  @spec read(binary()) :: {:ok, [entry()]} | {:error, Debkit.error()}
  def read(binary) when is_binary(binary), do: Native.tar_read(binary)

  @doc "Like `read/1` but returns the entries directly, raising `Debkit.Error` on failure."
  @spec read!(binary()) :: [entry()]
  def read!(binary), do: Debkit.unwrap(read(binary), :"Tar.read")

  @doc """
  Writes entries to a deterministic ustar archive.

  Entries are written in the order given. Each is a regular file
  (`{name, contents}` or `{name, contents, mode}`) or a directory
  (`{:dir, name}` or `{:dir, name, mode}`). See `t:write_entry/0`.

  Directory entries (ustar typeflag `5`) are what a `.deb`'s `data.tar`
  conventionally lists for each parent directory; emit them explicitly, in order,
  before the files they contain.

  ## Examples

      iex> {:ok, tar} = Debkit.Tar.write([{"./control", "Package: hello\\n", 0o644}])
      iex> is_binary(tar)
      true

      iex> {:ok, tar} = Debkit.Tar.write([
      ...>   {:dir, "./usr/", 0o755},
      ...>   {:dir, "./usr/bin/", 0o755},
      ...>   {"./usr/bin/hello", "#!/bin/sh\\n", 0o755}
      ...> ])
      iex> is_binary(tar)
      true
  """
  @spec write([write_entry()]) :: {:ok, binary()} | {:error, Debkit.error()}
  def write(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize/1)
    |> Native.tar_write()
  end

  @doc "Like `write/1` but returns the bytes directly, raising `Debkit.Error` on failure."
  @spec write!([write_entry()]) :: binary()
  def write!(entries), do: Debkit.unwrap(write(entries), :"Tar.write")

  # The NIF takes a uniform {name, contents, mode, kind} tuple; default the mode
  # and tag the kind here so the common cases stay short tuples. A directory has
  # no contents, so it carries an empty body.
  defp normalize({:dir, name}) when is_binary(name),
    do: {name, "", @default_dir_mode, :dir}

  defp normalize({:dir, name, mode})
       when is_binary(name) and is_integer(mode) and mode >= 0,
       do: {name, "", mode, :dir}

  defp normalize({name, contents}) when is_binary(name) and is_binary(contents),
    do: {name, contents, @default_mode, :file}

  defp normalize({name, contents, mode})
       when is_binary(name) and is_binary(contents) and is_integer(mode) and mode >= 0,
       do: {name, contents, mode, :file}
end
