defmodule Debkit.Ar do
  @moduledoc """
  Read and write `ar` containers — the outermost layer of a `.deb`.

  A `.deb` is a plain Unix `ar` archive whose members are, in order,
  `debian-binary`, `control.tar.*`, and `data.tar.*`. This module reads those
  members into `{name, bytes}` pairs and writes them back out.

  ## Determinism

  `write/1` produces a byte-for-byte reproducible archive: every member header
  carries mtime `0`, uid `0`, gid `0`, and mode `0o644`, and **no symbol table**
  is emitted. (A symbol table — the `__.SYMDEF` / `/` member that macOS's `ar`
  injects — is meaningless for a `.deb` and breaks `dpkg`; its absence here is
  the whole reason this writer exists.)

  ## Example

      iex> deb = Debkit.Ar.write([
      ...>   {"debian-binary", "2.0\\n"},
      ...>   {"control.tar.gz", <<1, 2, 3>>}
      ...> ]) |> elem(1)
      iex> {:ok, members} = Debkit.Ar.read(deb)
      iex> Enum.map(members, &elem(&1, 0))
      ["debian-binary", "control.tar.gz"]
  """

  alias Debkit.Native

  @typedoc "An archive member: its name and raw contents."
  @type member :: {name :: String.t(), contents :: binary()}

  @doc """
  Reads an `ar` container into its members, in archive order.

  Returns `{:error, :corrupt}` if `binary` is not a well-formed `ar` archive.

  ## Examples

      iex> {:ok, ar} = Debkit.Ar.read(Debkit.Ar.write!([{"a", "x"}]))
      iex> ar
      [{"a", "x"}]
  """
  @spec read(binary()) :: {:ok, [member()]} | {:error, Debkit.error()}
  def read(binary) when is_binary(binary), do: Native.ar_read(binary)

  @doc "Like `read/1` but returns the members directly, raising `Debkit.Error` on failure."
  @spec read!(binary()) :: [member()]
  def read!(binary), do: Debkit.unwrap(read(binary), :"Ar.read")

  @doc """
  Writes members to a deterministic `ar` archive.

  Each member is a `{name, contents}` pair; members are written in the order
  given. Returns `{:error, :name_too_long}` if a name exceeds what the `ar`
  format can store inline (the names a `.deb` uses are always short).

  ## Examples

      iex> {:ok, bytes} = Debkit.Ar.write([{"debian-binary", "2.0\\n"}])
      iex> is_binary(bytes)
      true
  """
  @spec write([member()]) :: {:ok, binary()} | {:error, Debkit.error()}
  def write(members) when is_list(members), do: Native.ar_write(members)

  @doc "Like `write/1` but returns the bytes directly, raising `Debkit.Error` on failure."
  @spec write!([member()]) :: binary()
  def write!(members), do: Debkit.unwrap(write(members), :"Ar.write")
end
