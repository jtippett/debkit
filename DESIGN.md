# Design notes

Why Debkit looks the way it does. Short, opinionated, and meant to save the next
maintainer a re-derivation.

## Scope: codecs, not packages

Debkit reads and writes the four nested *formats* in a `.deb` (ar, tar, and
gzip/xz/zstd) and stops there. It does **not** know what a control file is, what
members a valid `.deb` must have, or how to compute `md5sums`. That is `.deb`
*semantics* and belongs to the caller. Keeping the boundary here is what lets the
library stay ~250 lines of Rust with no domain logic to rot.

## A thin Rust NIF, not pure Elixir or shell-outs

`:zlib` and `:erl_tar` exist, but there is **no mature pure-Elixir xz**, and ar
would stay hand-rolled. Shelling out to `xz`/`zstd`/`ar` means runtime binary
deps and non-hermetic behaviour (macOS's `ar` injects a `__.SYMDEF` member that
breaks `dpkg`). One Rust NIF over `ar`/`tar`/`flate2`/`xz2`/`zstd` covers all
five codecs with battle-tested crates and ships precompiled, so users need no
Rust toolchain.

## Determinism is the default, not an option

Every writer zeroes mtime/uid/gid, ar uses mode `0o644` and emits no symbol
table, and gzip writes no header timestamp or filename. Equal input ⇒ equal
output. Reproducible packages are the norm for `.deb` tooling, and making it the
only behaviour removes a footgun.

## tar names are stored verbatim

This is the one place Debkit fights its underlying crate. tar-rs (like most tar
writers) normalises away `.` path components, turning the `.deb`-conventional
`./control` into `control`. We fill the ustar `name`/`prefix` fields directly so
the name round-trips exactly — `dpkg-deb -c` shows `./usr/bin/foo`, not
`usr/bin/foo`. `read/1` is already verbatim, so write now matches it.

`read/1` returns regular-file entries only; directories, symlinks, hardlinks and
devices are skipped. `.deb` control tars are all regular files — the targeted
case — and surfacing the rest would mean inventing a richer entry type the spec
deliberately avoids.

`write/1` *does* emit directory entries (typeflag `5`) via `{:dir, name, mode}`
tuples, because a `.deb`'s `data.tar` lists an explicit entry per parent dir
([#1]). The asymmetry with `read/1` (which skips them) is intentional: building a
`data.tar` needs dir entries, but the read path targets control tars, which have
none. The tagged-tuple shape was chosen over a `Tar.dir/2` helper or a
`{name, contents, mode, type}` 4-tuple — it's plain data that composes with
`Enum.map`, mirrors the bare file tuples, and a directory carries no contents to
put in a 4-tuple's `contents` slot.

[#1]: https://github.com/jtippett/debkit/issues/1

## The error vocabulary

NIFs never raise across the BEAM boundary; they return `{:ok, _}` or
`{:error, atom}`. The atom set is small and documented (`:corrupt`,
`:unsupported`, `:name_too_long`). The `!` variants raise `Debkit.Error` carrying
the same atom — the idiomatic Elixir pairing, where the tuple form is for control
flow and the bang form for "this must not fail".

## API shape

`{name, bytes}` tuples, not structs. They match the spec, destructure cleanly,
and a `.deb`'s members/entries genuinely are just name + contents at this layer.
`Tar.write/1` accepts a 2-tuple (mode defaults to `0o644`) or a 3-tuple — the
one ergonomic concession, because most control-tar entries want the default mode.
