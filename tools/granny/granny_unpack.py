"""
Unpacker for Hades II Granny asset bundles (GPK + SDB pairs).

Hades II ships character meshes and animations as paired files:
  <Name>.gpk  - LZ4-compressed bundle of Granny entries, with their type names
                and STRING-typed fields replaced by integer indices.
  <Name>.sdb  - String database. A normal Granny file whose sector 0 holds
                an indexed list of strings (~700 entries: type names, bone
                names, material paths, etc.) deduplicated across the bundle.

This tool merges the two back into N standalone .gr2 files (one per entry),
each loadable by Granny Viewer or arves100/opengr2 without further fixup.

Reverse engineering credit: alexpeattie's gist
  github.com/alexpeattie  (gist id: 12a644299a9f913c0514db9d628a2b39)
Saved locally at C:\\Users\\matte\\src\\granny-format-notes.md

Phase 1 (this file's current scope):
  - Parse GPK outer container header
  - Iterate entries: name + LZ4-compressed payload
  - Decompress each entry
  - Sanity check: first 8 bytes match the Granny v7 64-bit LE magic
  - Write per-entry raw Granny bytes to disk for inspection
"""

import argparse
import os
import struct
import sys
from pathlib import Path

try:
    import lz4.block
except ImportError:
    sys.stderr.write(
        "Missing dependency: lz4. Install with `pip install lz4` "
        "(use the same Python interpreter you'll run this script from).\n"
    )
    sys.exit(2)

# Granny v7 64-bit little-endian magic (gist: "Magic Header (32 bytes)").
GRANNY_MAGIC_LE_64 = bytes.fromhex("E59B495E6F631F141E13EBA990BEEDC4")

# Layout constants from the gist § "File Info Structure" and § "Sector Info Structure".
MAGIC_LEN = 32        # Granny magic header is 32 bytes total (16-byte signature + 16 bytes trailer).
FILE_INFO_LEN = 72    # 64-bit Granny v7 file-info struct.
SECTOR_INFO_LEN = 44  # Each sector descriptor is 44 bytes.
SECTOR_COUNT = 8      # Granny always has 8 sectors, sectors 1-4 and 7 typically empty.
SECTOR_INFOS_START = MAGIC_LEN + FILE_INFO_LEN   # = 104
FIXUP_ENTRY_LEN = 12  # Each fixup is (src_offset u32, dst_sector u32, dst_offset u32).


class SectorInfo:
    """One entry of the per-file sector descriptor table.

    Fields mirror the gist § "Sector Info Structure (44 bytes each)". We
    only read what we use — compression, the data range, and the fixup
    table coordinates. Marshall tables are typically empty in Hades II
    files so we skip parsing them.
    """

    __slots__ = (
        "compression",
        "data_offset",
        "compressed_length",
        "decompressed_length",
        "fixup_offset",
        "fixup_count",
    )

    @classmethod
    def from_bytes(cls, raw: bytes, offset: int) -> "SectorInfo":
        s = cls()
        (
            s.compression,
            s.data_offset,
            s.compressed_length,
            s.decompressed_length,
            _alignment,
            _oodle_stop_0,
            _oodle_stop_1,
            s.fixup_offset,
            s.fixup_count,
            _marshall_offset,
            _marshall_count,
        ) = struct.unpack_from("<11I", raw, offset)
        return s


def _parse_granny_sectors(raw: bytes) -> list:
    """Verify the Granny magic and return the 8 SectorInfo entries."""
    if not has_granny_magic(raw):
        raise ValueError(
            "buffer is not a Granny v7 64-bit LE file (magic mismatch)"
        )
    return [
        SectorInfo.from_bytes(raw, SECTOR_INFOS_START + i * SECTOR_INFO_LEN)
        for i in range(SECTOR_COUNT)
    ]


def _sector_data(raw: bytes, sector: SectorInfo) -> bytes:
    """Return the bytes of one sector. Hades II files use compression=0
    (uncompressed) so we just slice; Oodle decompression would go here
    if we ever encountered compression=1.
    """
    if sector.compression != 0:
        raise NotImplementedError(
            f"sector compression {sector.compression} not implemented "
            "(Hades II files observed to use 0 = uncompressed)"
        )
    return raw[sector.data_offset : sector.data_offset + sector.decompressed_length]


def _read_cstring(buf: bytes, offset: int) -> str:
    """Read a NUL-terminated ASCII/UTF-8 string starting at offset."""
    end = buf.find(b"\x00", offset)
    if end == -1:
        end = len(buf)
    return buf[offset:end].decode("utf-8", errors="replace")


def parse_sdb_string_table(path: Path) -> list:
    """Extract the indexed string table from an .sdb file.

    Per gist § "SDB String Database Format":
      - SDB is itself a Granny file (same magic, same 8-sector layout).
      - Sector 0 holds: a pointer array + the null-terminated string blob.
      - The sector-0 fixup table maps each pointer location to a string
        location elsewhere in sector 0.
      - Strings are sorted alphabetically and indexed by their position
        in the fixup table (so GPK entries reference strings by that index).

    Returns a list where index i is the i-th string referenced by GPK
    entries. Some early entries are empty strings (from the gist's worked
    example, indices 0 and 1 are empty).
    """
    raw = path.read_bytes()
    sectors = _parse_granny_sectors(raw)
    s0 = sectors[0]

    sector_0_data = _sector_data(raw, s0)
    fixups_raw = raw[s0.fixup_offset : s0.fixup_offset + s0.fixup_count * FIXUP_ENTRY_LEN]

    strings = []
    for i in range(s0.fixup_count):
        src_offset, dst_sector, dst_offset = struct.unpack_from(
            "<III", fixups_raw, i * FIXUP_ENTRY_LEN
        )
        # All SDB fixups should point into sector 0 (where the strings live).
        # Bail loudly if any point elsewhere — that'd suggest a different SDB layout.
        if dst_sector != 0:
            raise ValueError(
                f"sdb fixup {i} points to sector {dst_sector}, expected 0"
            )
        strings.append(_read_cstring(sector_0_data, dst_offset))

    return strings


def cmd_strings(args):
    sdb_path = Path(args.sdb)
    if not sdb_path.is_file():
        sys.stderr.write(f"error: {sdb_path}: not a file\n")
        return 1

    table = parse_sdb_string_table(sdb_path)
    print(f"{sdb_path.name}: {len(table)} string entries")

    if args.full:
        for i, s in enumerate(table):
            print(f"  [{i:5d}] {s!r}")
    else:
        # Show first 5 and last 5 — useful for sanity check.
        head_n, tail_n = 5, 5
        for i, s in enumerate(table[:head_n]):
            print(f"  [{i:5d}] {s!r}")
        if len(table) > head_n + tail_n:
            print(f"  ...   ({len(table) - head_n - tail_n} omitted)")
        for i in range(max(head_n, len(table) - tail_n), len(table)):
            print(f"  [{i:5d}] {table[i]!r}")
    return 0


def parse_gpk(path: Path):
    """Yield (name, decompressed_granny_bytes) for each entry in the GPK file.

    GPK header (gist § "Header"):
      offset 0x00  u32 LE  version  (observed 1)
      offset 0x04  u32 LE  entry_count

    Each entry:
      +0     u8         name_length
      +1     N bytes    name (ASCII, no null terminator)
      +1+N   u32 LE     compressed_size
      +5+N   bytes      LZ4 block-compressed Granny data (no size prefix)
    """
    raw = path.read_bytes()
    if len(raw) < 8:
        raise ValueError(f"{path}: too small to be a GPK file ({len(raw)} bytes)")

    version, entry_count = struct.unpack_from("<II", raw, 0)
    if version != 1:
        sys.stderr.write(
            f"warning: {path.name} header version is {version}, expected 1. "
            "Continuing — format may differ.\n"
        )

    print(f"  version={version}  entries={entry_count}")

    off = 8
    for i in range(entry_count):
        if off >= len(raw):
            raise ValueError(
                f"{path}: entry {i} starts past EOF "
                f"(file len {len(raw)}, offset {off})"
            )
        name_len = raw[off]
        off += 1
        name = raw[off : off + name_len].decode("ascii", errors="replace")
        off += name_len
        (compressed_size,) = struct.unpack_from("<I", raw, off)
        off += 4
        compressed = raw[off : off + compressed_size]
        off += compressed_size

        # LZ4 block decompress. The gist notes that GPK entries omit the
        # size prefix and recommends estimating output size (10× is "safe").
        # We try escalating estimates so very-large entries still succeed.
        decompressed = _lz4_decompress_unknown_size(compressed)
        yield name, decompressed


def _lz4_decompress_unknown_size(data: bytes) -> bytes:
    """LZ4 block decompress without knowing the output size.

    LZ4's max expansion ratio is ~255×, but ratios above ~10× are rare for
    structured data like Granny files. Try escalating ceilings; bail out
    once we've gone past 256× which would indicate either corruption or
    a different format.
    """
    last_err = None
    for multiplier in (10, 32, 128, 256):
        try:
            return lz4.block.decompress(
                data, uncompressed_size=len(data) * multiplier
            )
        except lz4.block.LZ4BlockError as e:
            last_err = e
            continue
    raise RuntimeError(f"LZ4 decompress failed at all size estimates: {last_err}")


def has_granny_magic(data: bytes) -> bool:
    return len(data) >= 16 and data[:16] == GRANNY_MAGIC_LE_64


def cmd_unpack(args):
    gpk_path = Path(args.gpk)
    if not gpk_path.is_file():
        sys.stderr.write(f"error: {gpk_path}: not a file\n")
        return 1

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Unpacking {gpk_path.name} -> {out_dir}/")
    entries_ok = 0
    entries_bad_magic = 0
    for name, payload in parse_gpk(gpk_path):
        magic_ok = has_granny_magic(payload)
        marker = "OK " if magic_ok else "?? "
        print(f"  {marker}{name}  ({len(payload):,} bytes)")
        if magic_ok:
            entries_ok += 1
        else:
            entries_bad_magic += 1

        # Sanitize filename — entry names can include path separators.
        safe = name.replace("/", "_").replace("\\", "_")
        out_path = out_dir / f"{safe}.gr2-raw"
        out_path.write_bytes(payload)

    print(
        f"\nDone. {entries_ok} entries with valid Granny magic, "
        f"{entries_bad_magic} with unexpected header."
    )
    if entries_bad_magic > 0:
        print(
            "  ^ unexpected headers may indicate a different format or "
            "LZ4 misconfiguration; inspect with `xxd <name>.gr2-raw | head`."
        )
    return 0


def main():
    p = argparse.ArgumentParser(
        description="Unpack Hades II GPK bundles into raw Granny .gr2 bytes "
        "(Phase 1: structural-only; not yet merged with SDB strings)."
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    unpack = sub.add_parser(
        "unpack",
        help="Extract entries from a .gpk to <output>/<entry>.gr2-raw files",
    )
    unpack.add_argument("gpk", help="Path to the .gpk file")
    unpack.add_argument(
        "-o", "--output", default="unpacked", help="Output directory"
    )
    unpack.set_defaults(func=cmd_unpack)

    strings = sub.add_parser(
        "strings",
        help="Dump the indexed string table from a .sdb file",
    )
    strings.add_argument("sdb", help="Path to the .sdb file")
    strings.add_argument(
        "--full", action="store_true",
        help="Print every entry (default: head + tail summary)",
    )
    strings.set_defaults(func=cmd_strings)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
