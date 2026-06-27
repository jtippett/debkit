defmodule Debkit.Native do
  @moduledoc false

  # RustlerPrecompiled downloads a prebuilt NIF for the user's target from the
  # matching GitHub release. Local development / CI forces a from-source build
  # with DEBKIT_BUILD=1 (see README "Development").
  #
  # IMPORTANT release ordering: the precompiled download is verified against
  # `checksum-Elixir.Debkit.Native.exs`. That file is regenerated AFTER the
  # release workflow uploads the NIF artifacts, via
  #   mix rustler_precompiled.download Debkit.Native --all --print
  # and must be committed before `mix hex.publish`. See UPDATE_PROCEDURE.md.

  @version Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :debkit,
    crate: "debkit",
    base_url: "https://github.com/jtippett/debkit/releases/download/v#{@version}",
    version: @version,
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-gnu
    ),
    force_build: System.get_env("DEBKIT_BUILD") in ["1", "true"]

  # Keep these stubs in sync with the #[rustler::nif] fns in
  # native/debkit/src/lib.rs. Each raises until the NIF library loads.

  def ar_read(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def ar_write(_members), do: :erlang.nif_error(:nif_not_loaded)

  def tar_read(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def tar_write(_entries), do: :erlang.nif_error(:nif_not_loaded)

  def compress(_format, _binary), do: :erlang.nif_error(:nif_not_loaded)
  def decompress(_format, _binary), do: :erlang.nif_error(:nif_not_loaded)
end
