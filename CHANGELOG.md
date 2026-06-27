# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial release. Codecs for the four nested formats inside a Debian `.deb`:
  - `Debkit.Ar` — read and write `ar` containers (deterministic headers, no
    symbol table).
  - `Debkit.Tar` — read and write `tar` archives (deterministic ustar, names
    stored verbatim including a leading `./`).
  - `Debkit.compress/2` and `Debkit.decompress/2` for `:gzip`, `:xz`, `:zstd`.
- `!`-raising variants and an `Debkit.Error` exception.
- Precompiled NIFs for `{x86_64,aarch64}-{apple-darwin,unknown-linux-gnu}`.
