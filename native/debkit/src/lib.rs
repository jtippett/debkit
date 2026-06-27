//! Debkit NIF — codecs for the four nested formats inside a Debian `.deb`.
//!
//! A `.deb` is an `ar` container of `tar` members compressed with gzip / xz /
//! zstd. This crate is a thin wrapper over the mature `ar`, `tar`, `flate2`,
//! `xz2`, and `zstd` crates: it reads and writes each layer in memory and hands
//! the bytes back to Elixir. There is no novel logic and no `.deb` *semantics*
//! here — assembling members into a package and parsing control fields stays on
//! the Elixir side.
//!
//! Conventions:
//!   * Every NIF returns `{:ok, term}` or `{:error, atom}` and never panics
//!     across the BEAM boundary (no `unwrap`/`expect` on caller-controlled data).
//!   * Writers are deterministic: zeroed mtime/uid/gid and no ar symbol table,
//!     so equal input yields equal output (reproducible packages).

#![deny(clippy::unwrap_used, clippy::expect_used)]

use std::io::{Cursor, Read, Write};

use rustler::{Atom, Binary, Env, NifUnitEnum, OwnedBinary};

// All reasons are referenced from Elixir's documented error set; `unsupported`
// is part of the stable vocabulary but isn't produced in v0.1 (non-regular tar
// entries are skipped rather than rejected), so allow it to sit unused.
#[allow(dead_code)]
mod atoms {
    rustler::atoms! { corrupt, unsupported, name_too_long }
}

/// The compression format, decoded straight from the `:gzip | :xz | :zstd` atom.
#[derive(NifUnitEnum)]
enum Format {
    Gzip,
    Xz,
    Zstd,
}

/// ar member identifiers must fit the 16-byte header field. Every name a `.deb`
/// uses is far shorter; reject anything longer rather than silently corrupt.
const AR_NAME_MAX: usize = 16;

// --- helpers ---------------------------------------------------------------

/// Copies `bytes` into a fresh BEAM binary. The only failure is allocation,
/// which for our in-memory scope is effectively unreachable; we still map it to
/// `:corrupt` rather than panic.
fn to_binary<'a>(env: Env<'a>, bytes: &[u8]) -> Result<Binary<'a>, Atom> {
    let mut bin = OwnedBinary::new(bytes.len()).ok_or_else(atoms::corrupt)?;
    bin.as_mut_slice().copy_from_slice(bytes);
    Ok(bin.release(env))
}

/// Turns owned `{name, bytes}` pairs into `[{name, binary}]` for return.
fn encode_members<'a>(
    env: Env<'a>,
    pairs: Vec<(String, Vec<u8>)>,
) -> Result<Vec<(String, Binary<'a>)>, Atom> {
    pairs
        .into_iter()
        .map(|(name, bytes)| Ok((name, to_binary(env, &bytes)?)))
        .collect()
}

/// Writes `name` verbatim into a ustar header's `name` (and `prefix`, if the
/// path is too long for the 100-byte name field) without the `.`-component
/// normalization tar-rs applies. ustar stores a long path as `prefix/name`, so
/// we split on a `/` boundary. Returns `:name_too_long` if it can't fit.
fn set_ustar_name(header: &mut tar::Header, name: &str) -> Result<(), Atom> {
    let bytes = name.as_bytes();
    let ustar = header.as_ustar_mut().ok_or_else(atoms::corrupt)?;
    ustar.name.fill(0);
    ustar.prefix.fill(0);

    let max_name = ustar.name.len(); // 100
    let max_prefix = ustar.prefix.len(); // 155

    if bytes.len() <= max_name {
        ustar.name[..bytes.len()].copy_from_slice(bytes);
        return Ok(());
    }

    // Need a prefix split. Pick the earliest `/` that leaves a name part within
    // 100 bytes; the leading part must then fit the 155-byte prefix.
    let earliest = bytes.len().saturating_sub(max_name);
    match (earliest..bytes.len()).find(|&i| bytes[i] == b'/') {
        Some(split) if split <= max_prefix => {
            ustar.prefix[..split].copy_from_slice(&bytes[..split]);
            let tail = &bytes[split + 1..];
            ustar.name[..tail.len()].copy_from_slice(tail);
            Ok(())
        }
        _ => Err(atoms::name_too_long()),
    }
}

// --- ar --------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn ar_read<'a>(env: Env<'a>, data: Binary<'a>) -> Result<Vec<(String, Binary<'a>)>, Atom> {
    let mut archive = ar::Archive::new(Cursor::new(data.as_slice()));
    let mut pairs: Vec<(String, Vec<u8>)> = Vec::new();

    while let Some(entry) = archive.next_entry() {
        let mut entry = entry.map_err(|_| atoms::corrupt())?;
        let name = String::from_utf8_lossy(entry.header().identifier()).into_owned();
        let mut buf = Vec::with_capacity(entry.header().size() as usize);
        entry.read_to_end(&mut buf).map_err(|_| atoms::corrupt())?;
        pairs.push((name, buf));
    }

    encode_members(env, pairs)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn ar_write<'a>(env: Env<'a>, members: Vec<(String, Binary)>) -> Result<Binary<'a>, Atom> {
    let mut builder = ar::Builder::new(Vec::new());

    for (name, contents) in &members {
        if name.len() > AR_NAME_MAX {
            return Err(atoms::name_too_long());
        }

        // `ar::Header::new` zeroes mtime/uid/gid and sets mode 0o644 — the
        // deterministic, symbol-table-free header a `.deb` wants.
        let header = ar::Header::new(name.clone().into_bytes(), contents.as_slice().len() as u64);
        builder
            .append(&header, contents.as_slice())
            .map_err(|_| atoms::corrupt())?;
    }

    let bytes = builder.into_inner().map_err(|_| atoms::corrupt())?;
    to_binary(env, &bytes)
}

// --- tar -------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn tar_read<'a>(env: Env<'a>, data: Binary<'a>) -> Result<Vec<(String, Binary<'a>)>, Atom> {
    let mut archive = tar::Archive::new(Cursor::new(data.as_slice()));
    let entries = archive.entries().map_err(|_| atoms::corrupt())?;
    let mut pairs: Vec<(String, Vec<u8>)> = Vec::new();

    for entry in entries {
        let mut entry = entry.map_err(|_| atoms::corrupt())?;

        // Regular files only — directories, symlinks, hardlinks, devices are
        // skipped (a `.deb` control tar is all regular files).
        if !entry.header().entry_type().is_file() {
            continue;
        }

        let name = entry
            .path()
            .map_err(|_| atoms::corrupt())?
            .to_string_lossy()
            .into_owned();
        let mut buf = Vec::new();
        entry.read_to_end(&mut buf).map_err(|_| atoms::corrupt())?;
        pairs.push((name, buf));
    }

    encode_members(env, pairs)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn tar_write<'a>(env: Env<'a>, entries: Vec<(String, Binary, u32)>) -> Result<Binary<'a>, Atom> {
    let mut builder = tar::Builder::new(Vec::new());

    for (name, contents, mode) in &entries {
        let mut header = tar::Header::new_ustar();
        header.set_entry_type(tar::EntryType::Regular);
        header.set_size(contents.as_slice().len() as u64);
        header.set_mode(*mode);
        // Deterministic ownership/time for reproducible archives.
        header.set_mtime(0);
        header.set_uid(0);
        header.set_gid(0);

        // Store the name verbatim. tar's `set_path`/`append_data` drop `.`
        // components, which would turn a `.deb`-style "./control" into
        // "control"; we want exact round-tripping, so fill the ustar name (and
        // prefix, for long paths) fields ourselves, then checksum and append.
        set_ustar_name(&mut header, name)?;
        header.set_cksum();

        builder
            .append(&header, contents.as_slice())
            .map_err(|_| atoms::corrupt())?;
    }

    let bytes = builder.into_inner().map_err(|_| atoms::corrupt())?;
    to_binary(env, &bytes)
}

// --- compression -----------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn compress<'a>(env: Env<'a>, format: Format, data: Binary) -> Result<Binary<'a>, Atom> {
    let out = match format {
        Format::Gzip => gzip_compress(data.as_slice()),
        Format::Xz => xz_compress(data.as_slice()),
        Format::Zstd => zstd_compress(data.as_slice()),
    }
    .map_err(|_| atoms::corrupt())?;

    to_binary(env, &out)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decompress<'a>(env: Env<'a>, format: Format, data: Binary) -> Result<Binary<'a>, Atom> {
    let out = match format {
        Format::Gzip => gzip_decompress(data.as_slice()),
        Format::Xz => xz_decompress(data.as_slice()),
        Format::Zstd => zstd_decompress(data.as_slice()),
    }
    .map_err(|_| atoms::corrupt())?;

    to_binary(env, &out)
}

fn gzip_compress(data: &[u8]) -> std::io::Result<Vec<u8>> {
    // `GzBuilder` with no mtime/filename set writes a header with mtime 0 and no
    // name — deterministic, unlike a default GzEncoder configured by the caller.
    let mut enc = flate2::GzBuilder::new().write(Vec::new(), flate2::Compression::default());
    enc.write_all(data)?;
    enc.finish()
}

fn gzip_decompress(data: &[u8]) -> std::io::Result<Vec<u8>> {
    let mut out = Vec::new();
    flate2::read::GzDecoder::new(data).read_to_end(&mut out)?;
    Ok(out)
}

fn xz_compress(data: &[u8]) -> std::io::Result<Vec<u8>> {
    let mut enc = xz2::write::XzEncoder::new(Vec::new(), 6);
    enc.write_all(data)?;
    enc.finish()
}

fn xz_decompress(data: &[u8]) -> std::io::Result<Vec<u8>> {
    let mut out = Vec::new();
    xz2::read::XzDecoder::new(data).read_to_end(&mut out)?;
    Ok(out)
}

fn zstd_compress(data: &[u8]) -> std::io::Result<Vec<u8>> {
    zstd::stream::encode_all(data, 3)
}

fn zstd_decompress(data: &[u8]) -> std::io::Result<Vec<u8>> {
    zstd::stream::decode_all(data)
}

rustler::init!("Elixir.Debkit.Native");
