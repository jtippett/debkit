# Update & release procedure

Debkit ships **precompiled NIFs**: end users download a prebuilt `.so` for their
target and never need Rust. That convenience has one moving part — a checksum
file that must be generated *after* the binaries exist on a GitHub release. This
doc is the playbook.

## Bumping a codec crate

The Rust crates (`ar`, `tar`, `flate2`, `xz2`, `zstd`) are pinned by minor line
in `native/debkit/Cargo.toml`. To bump one:

```sh
cd native/debkit
cargo update -p <crate>          # or edit the version and `cargo update`
cd ../.. && DEBKIT_BUILD=1 mix test
```

Watch for output drift: a new zstd/xz version can change compressed bytes (still
valid, but the determinism tests compare *self*-consistency, not cross-version
bytes, so they stay green). If you depend on byte-stable output across a bump,
say so in the CHANGELOG.

## Cutting a release (order matters)

1. **Bump version + roll the CHANGELOG.**

   ```sh
   just release        # or: elixir scripts/release.exs
   ```

   Picks patch/minor/major, edits `@version` in `mix.exs`, folds the CHANGELOG
   `[Unreleased]` section, then commits, tags `vX.Y.Z`, and pushes — which
   triggers `.github/workflows/release.yml`.

2. **Wait for the `build` + `release` jobs.** Confirm the GitHub release has one
   artifact per target (4 by default:
   `{x86_64,aarch64}-{apple-darwin,unknown-linux-gnu}`).

3. **The `publish` job is gated by the `hex` environment.** It regenerates
   `checksum-Elixir.Debkit.Native.exs` from the released artifacts (with
   `DEBKIT_BUILD=1` so the compile doesn't chase a not-yet-existing NIF), then
   runs `mix hex.publish`. Approve the deployment in the Actions tab when you're
   ready — this is the irreversible outward step.

   To regenerate the checksum file by hand (e.g. for a local check):

   ```sh
   DEBKIT_BUILD=1 mix rustler_precompiled.download Debkit.Native --all --print
   ```

## Verifying a clean install

On a machine with **no Rust**, a fresh project depending on `{:debkit, "~> 0.1"}`
should `mix deps.get && mix compile` with no build step — it downloads the
precompiled NIF and verifies it against the checksum file. If that works, the
release is good.

## Requirements (one-time)

- A `hex` GitHub **environment** with a required reviewer (gates the publish).
- A `HEX_API_KEY` secret with publish rights.
