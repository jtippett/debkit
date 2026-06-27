defmodule Debkit do
  @moduledoc """
  A tight codec library for the formats nested inside a Debian `.deb`.

  A `.deb` is four formats deep: an [**ar**](https://en.wikipedia.org/wiki/Ar_(Unix))
  container holding `debian-binary`, `control.tar.*` and `data.tar.*` members;
  each `.tar` is a **tar** archive; and each tar is compressed with **gzip**,
  **xz**, or **zstd**. Debkit gives you a small, faithful codec for each layer
  and nothing else — assembling them into a valid `.deb` (and parsing the control
  fields) is left to the caller.

      ┌─ ar ──────────────────────────────────┐
      │ debian-binary                          │
      │ control.tar.gz  ─► tar ─► gzip/xz/zstd │
      │ data.tar.xz     ─► tar ─► gzip/xz/zstd │
      └────────────────────────────────────────┘

  Everything is **in-memory** and **deterministic**: writers zero out mtime / uid
  / gid and omit the ar symbol table, so the same input bytes always produce the
  same output bytes (the basis for reproducible packages). The whole thing is a
  thin [Rustler](https://hexdocs.pm/rustler) NIF over the mature `ar`, `tar`,
  `flate2`, `xz2`, and `zstd` crates — no `xz`/`zstd`/`ar`/`tar` binaries at
  runtime, no shelling out.

  ## Modules

    * `Debkit` — `compress/2` and `decompress/2` for `:gzip | :xz | :zstd`.
    * `Debkit.Ar` — read and write `ar` containers.
    * `Debkit.Tar` — read and write `tar` archives.

  ## Errors

  The non-bang functions return `{:ok, result}` or `{:error, t:error/0}`; they
  never raise across the NIF boundary. The `!` variants raise `Debkit.Error`
  with the same reason. The documented reasons are:

    * `:corrupt` — the input is malformed for the codec (bad magic, truncated
      stream, bad headers, decompression failure).
    * `:unsupported` — the input is well-formed but uses a feature this library
      does not implement (e.g. a tar entry that is not a regular file).
    * `:name_too_long` — (writers only) a member name does not fit the target
      archive format.

  ## Example: round-trip a gzip stream

      iex> {:ok, gz} = Debkit.compress(:gzip, "hello, deb")
      iex> Debkit.decompress(:gzip, gz)
      {:ok, "hello, deb"}
  """

  alias Debkit.Native

  @typedoc "A supported compression format."
  @type format :: :gzip | :xz | :zstd

  @typedoc "A failure reason. See the \"Errors\" section above."
  @type error :: :corrupt | :unsupported | :name_too_long

  @formats [:gzip, :xz, :zstd]

  @doc """
  Compresses `data` with the given `format`.

  `format` is one of `:gzip`, `:xz`, or `:zstd`. Output is deterministic: the
  gzip header carries no mtime or filename, and none of the codecs embed a
  timestamp, so equal input yields equal output.

  ## Examples

      iex> {:ok, xz} = Debkit.compress(:xz, "control file body\\n")
      iex> Debkit.decompress(:xz, xz)
      {:ok, "control file body\\n"}
  """
  @spec compress(format(), binary()) :: {:ok, binary()} | {:error, error()}
  def compress(format, data) when format in @formats and is_binary(data) do
    Native.compress(format, data)
  end

  @doc """
  Like `compress/2` but returns the bytes directly, raising `Debkit.Error` on
  failure.
  """
  @spec compress!(format(), binary()) :: binary()
  def compress!(format, data), do: unwrap(compress(format, data), :compress)

  @doc """
  Decompresses `data`, which must be a single `format` stream.

  `format` is given explicitly rather than sniffed from a filename or magic
  bytes — in a `.deb` the format is known from the member name (`control.tar.xz`
  → `:xz`).

  Returns `{:error, :corrupt}` if `data` is not a valid stream for `format`.

  ## Examples

      iex> {:ok, z} = Debkit.compress(:zstd, "data")
      iex> Debkit.decompress(:zstd, z)
      {:ok, "data"}

      iex> Debkit.decompress(:gzip, "not actually gzip")
      {:error, :corrupt}
  """
  @spec decompress(format(), binary()) :: {:ok, binary()} | {:error, error()}
  def decompress(format, data) when format in @formats and is_binary(data) do
    Native.decompress(format, data)
  end

  @doc """
  Like `decompress/2` but returns the bytes directly, raising `Debkit.Error`
  on failure.
  """
  @spec decompress!(format(), binary()) :: binary()
  def decompress!(format, data), do: unwrap(decompress(format, data), :decompress)

  @doc false
  # Shared by every `!` wrapper in the library.
  def unwrap({:ok, value}, _operation), do: value

  def unwrap({:error, reason}, operation),
    do: raise(Debkit.Error, reason: reason, operation: operation)
end
