defmodule Debkit.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/jtippett/debkit"

  def project do
    [
      app: :debkit,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "Debkit",
      description:
        "A tight Rust-NIF codec library for the four nested formats inside a .deb: " <>
          "ar, tar, and gzip/xz/zstd. In-memory, deterministic, no shell-outs.",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # `:rustler` is only needed to build the NIF from source (DEBKIT_BUILD=1);
      # the default precompiled path needs only `:rustler_precompiled`.
      {:rustler, "~> 0.38", optional: true},
      {:rustler_precompiled, "~> 0.9"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Ship the Rust sources + Cargo.lock so a from-source build works for
      # consumers on targets we don't precompile. The checksum file is required
      # for rustler_precompiled to verify downloaded NIFs.
      files:
        ~w(lib native/debkit/Cargo.toml native/debkit/Cargo.lock native/debkit/src checksum-Elixir.Debkit.Native.exs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      groups_for_modules: [
        Codecs: [Debkit.Ar, Debkit.Tar, Debkit.Tar.Entry]
      ]
    ]
  end
end
