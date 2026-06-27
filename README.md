# Debkit

A tight codec library for the four formats nested inside a Debian `.deb`:
the [**ar**](https://en.wikipedia.org/wiki/Ar_(Unix)) container, the **tar**
members, and **gzip / xz / zstd** compression — all in memory, deterministic,
with no shell-outs.

```
┌─ ar ──────────────────────────────────┐
│ debian-binary                          │
│ control.tar.gz  ─► tar ─► gzip/xz/zstd │
│ data.tar.xz     ─► tar ─► gzip/xz/zstd │
└────────────────────────────────────────┘
```

A `.deb` is four formats deep, and stitching them together in Elixir means
touching `ar`, `tar`, and three compressors at once. Debkit is a thin
[Rustler](https://hexdocs.pm/rustler) NIF over the mature `ar`, `tar`, `flate2`,
`xz2`, and `zstd` Rust crates — so you get all five codecs from one dependency,
with **no `xz` / `zstd` / `ar` / `tar` binaries at runtime**.

Debkit handles the *codecs* only. Assembling members into a valid package and
parsing control fields is left to you — that is `.deb` *semantics*, not codec
work.

## Installation

Add `debkit` to your deps:

```elixir
def deps do
  [
    {:debkit, "~> 0.1"}
  ]
end
```

Precompiled NIFs ship for `x86_64`/`aarch64` on macOS and Linux, so there's
**no Rust toolchain needed to use it**. On other targets it builds from source
(needs Rust and a C compiler for liblzma/libzstd).

## Usage

### Compression

The format is explicit — in a `.deb` you already know it from the member name
(`control.tar.xz` → `:xz`), so nothing is sniffed.

```elixir
{:ok, gz}  = Debkit.compress(:gzip, "hello")
{:ok, raw} = Debkit.decompress(:gzip, gz)   # "hello"

# :gzip | :xz | :zstd
{:ok, xz} = Debkit.compress(:xz, payload)
```

### ar

```elixir
deb_bytes =
  Debkit.Ar.write!([
    {"debian-binary", "2.0\n"},
    {"control.tar.gz", control_gz},
    {"data.tar.gz", data_gz}
  ])

{:ok, members} = Debkit.Ar.read(deb_bytes)
# [{"debian-binary", "2.0\n"}, {"control.tar.gz", <<...>>}, ...]
```

`write/1` is deterministic — zeroed mtime/uid/gid, mode `0o644`, and crucially
**no symbol table** (the `__.SYMDEF` member that macOS's `ar` injects and that
breaks `dpkg`).

### tar

Entries are `Debkit.Tar.Entry` structs — the same struct flows through `read/1`
and `write/1`, so an archive round-trips. Build them with `Tar.file/3` and
`Tar.dir/2`:

```elixir
tar = Debkit.Tar.write!([
  Debkit.Tar.dir("./usr/", 0o755),                  # directory (ustar typeflag 5)
  Debkit.Tar.dir("./usr/bin/"),                      # mode defaults to 0o755
  Debkit.Tar.file("./control", "Package: hello\n"), # file; mode defaults to 0o644
  Debkit.Tar.file("./usr/bin/hello", "#!/bin/sh\n", 0o755)
])

{:ok, entries} = Debkit.Tar.read(tar)
# [#Debkit.Tar.Entry<dir "./usr/" 0o755>,
#  #Debkit.Tar.Entry<dir "./usr/bin/" 0o755>,
#  #Debkit.Tar.Entry<file "./control" 0o644 15B>,
#  #Debkit.Tar.Entry<file "./usr/bin/hello" 0o755 10B>]
```

A `.deb`'s `data.tar` lists an explicit directory entry for each parent dir, so
emit `dir/2` entries before the files they contain. Names are stored
**verbatim**, including a leading `./` and a directory's trailing `/` — unlike
most tar writers, which normalise `.` components away. `read/1` returns file and
directory entries; symlinks and device nodes are skipped.

### Putting it together

```elixir
control_tar = Debkit.Tar.write!([Debkit.Tar.file("./control", control_text)])

data_tar =
  Debkit.Tar.write!([
    Debkit.Tar.dir("./usr/", 0o755),
    Debkit.Tar.dir("./usr/bin/", 0o755),
    Debkit.Tar.file("./usr/bin/hello", script, 0o755)
  ])

deb =
  Debkit.Ar.write!([
    {"debian-binary", "2.0\n"},
    {"control.tar.gz", Debkit.compress!(:gzip, control_tar)},
    {"data.tar.gz", Debkit.compress!(:gzip, data_tar)}
  ])
```

The result is byte-for-byte reproducible and reads cleanly under `dpkg-deb`.

## Errors

The non-bang functions return `{:ok, result}` or `{:error, reason}` and never
raise across the NIF boundary. The `!` variants raise `Debkit.Error` with the
same reason.

| reason | meaning |
|---|---|
| `:corrupt` | the input is malformed for the codec (bad magic, truncated stream, bad headers) |
| `:unsupported` | well-formed but uses a feature this library doesn't implement |
| `:name_too_long` | (writers) a member name doesn't fit the target archive format |

## Development

The NIF is built from source for local work and CI:

```sh
DEBKIT_BUILD=1 mix test     # or: just test
just fmt                    # mix format + cargo fmt
```

Releases are cut with `just release` (bump, tag, push); a GitHub Actions
workflow builds the per-target NIFs, attaches them to the release, and publishes
to Hex behind a manual approval gate. See [`UPDATE_PROCEDURE.md`](UPDATE_PROCEDURE.md).

## License

MIT © James Tippett
