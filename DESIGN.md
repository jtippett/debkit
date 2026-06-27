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

## Tar entries are a struct

`Debkit.Tar` entries are `%Debkit.Tar.Entry{name, contents, mode, type}` — the
*same* struct produced by `read/1` and accepted by `write/1`, so an archive
round-trips. We arrived here in two steps, which is the honest way to design a
struct:

1. **v0.1: tuples.** `{name, contents}` / `{name, contents, mode}` matched the
   spec and read cleanly for the bulk file case. When directory entries were
   needed ([#1]), a `{:dir, name, mode}` tagged tuple was the minimal extension —
   but it left a heterogeneous tuple union, positional overloading (position 1
   means a binary *or* the `:dir` tag), and a `read`/`write` type mismatch.

2. **v0.2: struct.** Once the real shape was known (name + contents + mode +
   file/dir type, names verbatim), a struct beat the tuples decisively: one type
   for both directions, no positional cleverness, pattern-matchable on
   `%Entry{type: :dir}`, room to grow (symlinks), and `read/1` can now surface
   directories with their modes for free. Constructors `Tar.file/3` and
   `Tar.dir/2` keep construction terse, and a custom `Inspect` renders entries as
   `#Debkit.Tar.Entry<file "./control" 0o644 15B>`.

The lesson: don't reach for a struct until you've *earned* its field list. A
struct designed before you understand the shape is just a tuple with ceremony;
designed after, it's hard to beat.

`read/1` surfaces files and directories; symlinks, hardlinks and device nodes are
skipped (a `.deb`'s tars don't use them). `mode: nil` on an entry means "default
for the type" (`0o644` file / `0o755` dir), resolved at write time.

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
