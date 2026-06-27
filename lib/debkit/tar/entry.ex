defmodule Debkit.Tar.Entry do
  @moduledoc """
  A single tar entry: a regular file or a directory.

  The same struct is produced by `Debkit.Tar.read/1` and accepted by
  `Debkit.Tar.write/1`, so an archive round-trips through it. Build entries with
  the `Debkit.Tar.file/3` and `Debkit.Tar.dir/2` constructors, or directly:

      %Debkit.Tar.Entry{name: "./control", contents: "Package: hello\\n"}

  ## Fields

    * `:name` — the entry path, stored **verbatim** (keep a leading `./` and, for
      a directory, the trailing `/`). Required.
    * `:contents` — the file body; always `""` for a directory.
    * `:mode` — the permission bits. `nil` means "default for the type" — `0o644`
      for a file, `0o755` for a directory — resolved by `Debkit.Tar.write/1`.
    * `:type` — `:file` or `:dir`.
  """

  @enforce_keys [:name]
  defstruct [:name, contents: "", mode: nil, type: :file]

  @typedoc "A tar entry's type."
  @type type :: :file | :dir

  @type t :: %__MODULE__{
          name: String.t(),
          contents: binary(),
          mode: non_neg_integer() | nil,
          type: type()
        }

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{name: name, contents: contents, mode: mode, type: type}, _opts) do
      mode_doc = if mode, do: "0o" <> Integer.to_string(mode, 8), else: "mode:default"

      detail =
        case type do
          :dir -> []
          _ -> ["#{byte_size(contents)}B"]
        end

      parts = [Atom.to_string(type), inspect(name), mode_doc] ++ detail
      concat(["#Debkit.Tar.Entry<", Enum.join(parts, " "), ">"])
    end
  end
end
