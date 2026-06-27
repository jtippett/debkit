defmodule Debkit.Error do
  @moduledoc """
  Raised by the `!`-suffixed functions (`Debkit.decompress!/2`,
  `Debkit.Ar.read!/1`, …) when the underlying codec returns `{:error, reason}`.

  The non-bang functions never raise — they return `{:error, reason}` — so reach
  for these only when a failure should abort the calling process.

  The `:reason` field carries the same atom the tuple form would return. See
  `t:Debkit.error/0` for the documented set.
  """

  @typedoc "An `Debkit.Error` exception struct."
  @type t :: %__MODULE__{reason: Debkit.error(), operation: atom()}

  defexception [:reason, :operation]

  @impl true
  def message(%__MODULE__{reason: reason, operation: operation}) do
    "Debkit.#{operation} failed: #{describe(reason)} (#{inspect(reason)})"
  end

  defp describe(:corrupt), do: "input is not valid for this codec"
  defp describe(:unsupported), do: "input uses an unsupported feature"
  defp describe(:name_too_long), do: "a member name does not fit the archive format"
  defp describe(_other), do: "codec error"
end
