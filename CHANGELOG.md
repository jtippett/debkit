# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Breaking:** `Debkit.Tar` entries are now `Debkit.Tar.Entry` structs instead
  of tuples. The same struct flows through `read/1` and `write/1`, so an archive
  round-trips through it.
  - Build entries with the new `Debkit.Tar.file/3` and `Debkit.Tar.dir/2`
    constructors (replacing the `{name, contents}` / `{name, contents, mode}` and
    `{:dir, ...}` tuple forms).
  - `Debkit.Tar.read/1` now returns `Debkit.Tar.Entry` structs and surfaces
    **directory** entries (with `mode` and `type`) in addition to files; symlinks
    and device nodes are still skipped.

### Added

- Directory entries (ustar typeflag `5`) for `.deb` `data.tar` archives, via
  `Debkit.Tar.dir/2`. Names are stored verbatim (keep the trailing `/`). ([#1])

[#1]: https://github.com/jtippett/debkit/issues/1

## 0.1.1 - 2026-06-27

### Added

- Initial release. Codecs for the four nested formats inside a Debian `.deb`:
  - `Debkit.Ar` — read and write `ar` containers (deterministic headers, no
    symbol table).
  - `Debkit.Tar` — read and write `tar` archives (deterministic ustar, names
    stored verbatim including a leading `./`).
  - `Debkit.compress/2` and `Debkit.decompress/2` for `:gzip`, `:xz`, `:zstd`.
- `!`-raising variants and an `Debkit.Error` exception.
- Precompiled NIFs for `{x86_64,aarch64}-{apple-darwin,unknown-linux-gnu}`.
