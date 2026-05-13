"""
Unpacker for Hades II Granny asset bundles (GPK + SDB pairs).

Hades II ships character meshes and animations as paired files:
  <Name>.gpk  - LZ4-compressed bundle of Granny entries, with their type names
                and STRING-typed fields replaced by integer indices.
  <Name>.sdb  - String database. A normal Granny file whose sector 0 holds
                an indexed list of strings (~700 entries: type names, bone
                names, material paths, etc.) deduplicated across the bundle.

Eventually this tool will merge the two back into N standalone .gr2 files,
each loadable by Granny Viewer or arves100/opengr2 without further fixup.

Reverse engineering credit: alexpeattie's gist
  github.com/alexpeattie  (gist id: 12a644299a9f913c0514db9d628a2b39)
Saved locally at C:\\Users\\matte\\src\\granny-format-notes.md

Current state (2026-05-13 PM):
  Phase 1 (`unpack`):  COMPLETE.
    Verified on Test.gpk (1 entry) and Melinoe.gpk (855 entries, all
    valid Granny v7 64-bit LE magic).
  Phase 2 (`strings`): COMPLETE.
    Verified on Melinoe.sdb (1468 indexed strings, alphabetically sorted,
    first two entries empty — matches the gist's worked example).
  Phase 3 (`inspect`): PARTIAL.
    A type-tree walker is implemented and CORRECTLY enumerates the
    sector-6 type-name string indices for every entry. The sector-0
    STRING-field walker handles INLINE / REFERENCE / REFERENCETOARRAY /
    ARRAYOFREFERENCES / VARIANTREFERENCE / REFERENCETOVARIANTARRAY, but
    is under-counting badly in practice (Melinoe_Mesh: walker finds 1
    STRING field where brute u64-scanning identifies ~218 plausible
    indices). The likely culprit: the root REFERENCE at sector 0 offset
    0 resolves to a struct at 0x94, but fixups exist at 0x00..0x93 too,
    suggesting either a different root struct layout than the simple
    "single REFERENCE" interpretation, or a Granny convention not
    captured in the gist (e.g. an implicit table-of-contents block
    before the root struct). Need to either correlate against opengr2's
    parser or get a successful-merge reference file from alexpeattie
    to compare against.
  Phase 4 (CRC32 + finalize):  NOT STARTED.
  Phase 5 (verify with viewer): NOT STARTED.

Workable fallback if the walker can't be made complete: brute-force
scan sector 0 for 8-byte-aligned u64 values that look like valid string
indices (0 < v < len(sdb_strings)), treat each as a STRING-field
candidate, add fixup entries. False positives are possible but Granny
Viewer will tell us quickly if the substitutions are nonsense.
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


# ---------------------------------------------------------------------------
# Phase 3: type tree walker for finding string-index positions in a GPK entry.
# ---------------------------------------------------------------------------
#
# A GPK entry is a valid Granny file structurally, but with two semantic
# changes vs. standalone GR2:
#   - sector 6 type defs hold a string INDEX in their name_offset field
#     instead of a fixup-resolved pointer to a string.
#   - sector 0 STRING fields (type id 8) hold an integer INDEX instead of
#     a fixup-resolved pointer to a string.
# Pointer-type fields (REFERENCE, REFERENCETOARRAY, etc.) still use the
# normal fixup-table resolution — only string-pointer fixups are missing.
#
# To find every STRING field's sector-0 position, we walk the data tree:
# start at the root struct, follow children/references/arrays per the
# type def's `type_id`, and yield the offset whenever we hit a STRING leaf.

# Type ID constants from gist § "Type Definitions". Source of truth is
# arves100/opengr2's libopengrn/typeinfo.h.
T_NONE = 0
T_INLINE = 1
T_REFERENCE = 2
T_REFERENCETOARRAY = 3
T_ARRAYOFREFERENCES = 4
T_VARIANTREFERENCE = 5
T_REMOVED = 6
T_REFERENCETOVARIANTARRAY = 7
T_STRING = 8
T_TRANSFORM = 9
T_REAL32 = 10
T_INT8 = 11
T_UINT8 = 12
T_BINORMALINT8 = 13
T_NORMALUINT8 = 14
T_INT16 = 15
T_UINT16 = 16
T_BINORMALINT16 = 17
T_NORMALUINT16 = 18
T_INT32 = 19
T_UINT32 = 20
T_REAL16 = 21
T_EMPTYREFERENCE = 22

# Per-type field size in sector 0 (one element, ignoring array_size).
# INLINE has no fixed size — its size is the sum of its children. Reference
# types are 64-bit pointers (8 bytes on 64-bit Granny). REFERENCETOARRAY /
# ARRAYOFREFERENCES / VARIANTREFERENCE / REFERENCETOVARIANTARRAY are 16
# bytes: a u32 element count + 4 padding + u64 pointer (or two u64s for
# variants). TRANSFORM is 56 bytes (4×4 matrix + scale shear).
_TYPE_SIZE = {
    T_REFERENCE: 8,
    T_REFERENCETOARRAY: 16,
    T_ARRAYOFREFERENCES: 16,
    T_VARIANTREFERENCE: 16,
    T_REFERENCETOVARIANTARRAY: 16,
    T_STRING: 8,
    T_TRANSFORM: 56,
    T_REAL32: 4,
    T_INT8: 1,
    T_UINT8: 1,
    T_BINORMALINT8: 1,
    T_NORMALUINT8: 1,
    T_INT16: 2,
    T_UINT16: 2,
    T_BINORMALINT16: 2,
    T_NORMALUINT16: 2,
    T_INT32: 4,
    T_UINT32: 4,
    T_REAL16: 2,
    T_EMPTYREFERENCE: 8,
}

TYPE_DEF_LEN = 44  # 64-bit type definition struct size, per gist.


class TypeDef:
    __slots__ = ("type_id", "name_index", "children_index", "array_size", "_pos")

    def __init__(self, sector_6_pos: int, type_id: int, name_index: int,
                 children_index: int, array_size: int):
        self._pos = sector_6_pos
        self.type_id = type_id
        self.name_index = name_index
        self.children_index = children_index
        self.array_size = array_size


def _parse_type_def(sector_6: bytes, offset: int) -> TypeDef:
    """Parse a 44-byte type definition entry at sector_6[offset:].

    Field layout (gist § "Type Definitions"):
      0x00  u32  type_id
      0x04  u64  name_offset       <- in GPK, this is a string INDEX
      0x0C  u64  children_offset   <- 8-byte field; in GPK its value here
                                       is the GPK's existing fixup-resolvable
                                       pointer for sector 6 -> sector 6
                                       child-list references. We DON'T read
                                       the pointer here; we resolve via the
                                       fixup table at the caller.
      0x14  i32  array_size  (-1 dynamic, 0 none, >0 fixed)
      0x18  20 bytes padding
    """
    type_id, name_index, children_index, array_size = struct.unpack_from(
        "<IQQi", sector_6, offset
    )
    return TypeDef(offset, type_id, name_index, children_index, array_size)


def _walk_children(
    children_root_offset: int,
    sector_6: bytes,
):
    """Yield TypeDef objects from a NUL-terminated list starting at
    sector_6[children_root_offset:]. The list ends when type_id == NONE.
    """
    pos = children_root_offset
    while pos + TYPE_DEF_LEN <= len(sector_6):
        td = _parse_type_def(sector_6, pos)
        if td.type_id == T_NONE:
            return
        yield td
        pos += TYPE_DEF_LEN


def _field_size(td: TypeDef, sector_6: bytes, s6_fixups_by_src: dict) -> int:
    """Total size in sector 0 of one field described by td, accounting
    for array_size. INLINE fields walk their children to sum the size."""
    if td.type_id == T_INLINE:
        # Sum sizes of all children (one struct of children).
        children_off = _resolve_s6_fixup(td._pos + 0x0C, s6_fixups_by_src)
        if children_off is None:
            return 0
        elem_size = sum(
            _field_size(c, sector_6, s6_fixups_by_src)
            for c in _walk_children(children_off, sector_6)
        )
    else:
        elem_size = _TYPE_SIZE.get(td.type_id, 0)
        if elem_size == 0:
            # Unknown type id — bail with 0 to avoid runaway offsets.
            # If this fires in practice we need to look up the missing case.
            return 0
    n = td.array_size if td.array_size > 0 else 1
    return elem_size * n


def _resolve_s6_fixup(src_offset: int, s6_fixups_by_src: dict):
    """Look up a sector-6 fixup. Returns destination offset in the target
    sector if a fixup exists for this source offset, else None.

    The fixup map's value is (dst_sector, dst_offset). For sector 6 → 6
    fixups (children-pointer fixups) the caller cares about dst_offset.
    For sector 6 → 0 fixups (type-name pointers, absent in GPK) the same
    structure works.
    """
    entry = s6_fixups_by_src.get(src_offset)
    if entry is None:
        return None
    _dst_sector, dst_offset = entry
    return dst_offset


def _read_fixups(raw: bytes, sector: SectorInfo) -> list:
    """Decode this sector's fixup table into a list of (src, dst_sector, dst_off)."""
    out = []
    base = sector.fixup_offset
    for i in range(sector.fixup_count):
        entry = struct.unpack_from("<III", raw, base + i * FIXUP_ENTRY_LEN)
        out.append(entry)
    return out


def find_string_positions(raw_gr2: bytes) -> dict:
    """Walk a GPK-entry Granny file and locate every string-index field.

    Returns a dict with:
      'sector_0_strings'  -> list of (sector_0_offset, string_index)  for STRING fields
      'sector_6_typenames' -> list of (sector_6_offset, string_index) for type-name fields
      'sectors' -> the parsed [SectorInfo, ...]
      'fixups_by_sector' -> {sector_index: [(src, dst_sec, dst_off), ...]}

    The sector_6_typenames list is straightforward: every non-NONE type
    def has a name_index at sector_6_offset + 0x04. We collect those by
    walking sector 6 directly (it's a flat list — no recursion needed for
    that part).

    The sector_0_strings list requires walking the data structure rooted
    at (root_ref_sector, root_ref_offset) in the file info, using the
    type tree starting at (type_ref_sector, type_ref_offset).
    """
    sectors = _parse_granny_sectors(raw_gr2)
    sector_0 = _sector_data(raw_gr2, sectors[0])
    sector_6 = _sector_data(raw_gr2, sectors[6])

    fixups_by_sector = {i: _read_fixups(raw_gr2, sectors[i]) for i in range(SECTOR_COUNT)}
    s6_fixups_by_src = {f[0]: (f[1], f[2]) for f in fixups_by_sector[6]}

    # --- Collect all type-name (sector 6) string indices.
    # Sector 6 is a flat array of type defs starting at offset 0. Walk it
    # entry by entry, recording each non-NONE entry's name_index.
    sector_6_typenames = []
    pos = 0
    while pos + TYPE_DEF_LEN <= len(sector_6):
        td = _parse_type_def(sector_6, pos)
        if td.type_id != T_NONE:
            sector_6_typenames.append((pos + 0x04, td.name_index))
        pos += TYPE_DEF_LEN

    # --- Walk the data tree to find STRING field positions in sector 0.
    # File info gives us (type_ref_sector, type_ref_offset) for the root
    # type def, and (root_ref_sector, root_ref_offset) for the root data.
    # We parse those from offset 0x34 / 0x3C of the file (gist § "File Info").
    type_ref_sector, type_ref_offset = struct.unpack_from(
        "<II", raw_gr2, MAGIC_LEN + 0x14
    )
    root_ref_sector, root_ref_offset = struct.unpack_from(
        "<II", raw_gr2, MAGIC_LEN + 0x1C
    )
    if type_ref_sector != 6 or root_ref_sector != 0:
        # Unexpected layout; bail with what we have so far.
        return {
            "sector_0_strings": [],
            "sector_6_typenames": sector_6_typenames,
            "sectors": sectors,
            "fixups_by_sector": fixups_by_sector,
            "unexpected": (type_ref_sector, root_ref_sector),
        }

    s0_strings = []
    root_type = _parse_type_def(sector_6, type_ref_offset)
    s0_fixups_by_src = {f[0]: (f[1], f[2]) for f in fixups_by_sector[0]}
    _walk_struct(
        root_type, sector_6, sector_0, root_ref_offset,
        s6_fixups_by_src, s0_fixups_by_src, s0_strings, set()
    )

    return {
        "sector_0_strings": s0_strings,
        "sector_6_typenames": sector_6_typenames,
        "sectors": sectors,
        "fixups_by_sector": fixups_by_sector,
    }


def _walk_struct(
    type_def: TypeDef, sector_6: bytes, sector_0: bytes, data_offset: int,
    s6_fixups_by_src: dict, s0_fixups_by_src: dict,
    out_string_positions: list, visited: set,
):
    """Recursively walk one struct/value at data_offset, appending any
    STRING-field positions found to out_string_positions.

    `visited` tracks (type_def position, data_offset) pairs to short-circuit
    cycles that REFERENCE-typed fields could otherwise create.
    """
    if data_offset < 0 or data_offset >= len(sector_0):
        return

    type_id = type_def.type_id
    if type_id == T_STRING:
        out_string_positions.append((data_offset, struct.unpack_from(
            "<Q", sector_0, data_offset
        )[0]))
        return

    if type_id == T_INLINE or type_id == T_REFERENCE:
        # Both INLINE and REFERENCE have a children list describing the
        # struct's fields. INLINE places the struct inline at data_offset.
        # REFERENCE has an 8-byte pointer at data_offset whose target is
        # the struct's start. After resolving, both walk identically.
        if type_id == T_REFERENCE:
            target = s0_fixups_by_src.get(data_offset)
            if target is None:
                return
            dst_sector, dst_offset = target[0], target[1]
            if dst_sector != 0:
                return
            struct_start = dst_offset
        else:
            struct_start = data_offset

        children_off = _resolve_s6_fixup(type_def._pos + 0x0C, s6_fixups_by_src)
        if children_off is None:
            return
        key = (type_def._pos, struct_start)
        if key in visited:
            return
        visited.add(key)
        _walk_struct_fields(
            children_off, sector_6, sector_0, struct_start,
            s6_fixups_by_src, s0_fixups_by_src,
            out_string_positions, visited,
        )
        return

    if type_id in (T_REFERENCETOARRAY, T_ARRAYOFREFERENCES):
        # 16-byte field: u32 count, u32 pad, u64 pointer-or-array-base.
        count = struct.unpack_from("<I", sector_0, data_offset)[0]
        target = s0_fixups_by_src.get(data_offset + 8)
        if target is None or target[0] != 0 or count <= 0:
            return
        # Children list describes the element type's fields. For
        # ARRAYOFREFERENCES each element is itself a pointer (8 bytes);
        # for REFERENCETOARRAY each element is the struct inline. Both
        # collapse to "walk children at the element's start".
        children_off = _resolve_s6_fixup(type_def._pos + 0x0C, s6_fixups_by_src)
        if children_off is None:
            return
        # Compute element size by summing children sizes.
        elem_size = sum(
            _field_size(c, sector_6, s6_fixups_by_src)
            for c in _walk_children(children_off, sector_6)
        )
        if elem_size == 0:
            return
        for i in range(count):
            elem_off = target[1] + i * elem_size
            if type_id == T_ARRAYOFREFERENCES:
                # Each array slot holds a pointer; resolve and walk the
                # pointed-at struct.
                ref_target = s0_fixups_by_src.get(elem_off)
                if ref_target is None or ref_target[0] != 0:
                    continue
                _walk_struct_fields(
                    children_off, sector_6, sector_0, ref_target[1],
                    s6_fixups_by_src, s0_fixups_by_src,
                    out_string_positions, visited,
                )
            else:
                _walk_struct_fields(
                    children_off, sector_6, sector_0, elem_off,
                    s6_fixups_by_src, s0_fixups_by_src,
                    out_string_positions, visited,
                )
        return

    if type_id == T_VARIANTREFERENCE:
        # 16 bytes: u64 pointer to type def (sector 6), u64 pointer to
        # data (sector 0). Both fixups live in sector 0's fixup table.
        type_fx = s0_fixups_by_src.get(data_offset)
        data_fx = s0_fixups_by_src.get(data_offset + 8)
        if type_fx is None or data_fx is None:
            return
        if type_fx[0] != 6 or data_fx[0] != 0:
            return
        variant_type = _parse_type_def(sector_6, type_fx[1])
        _walk_struct(
            variant_type, sector_6, sector_0, data_fx[1],
            s6_fixups_by_src, s0_fixups_by_src,
            out_string_positions, visited,
        )
        return

    if type_id == T_REFERENCETOVARIANTARRAY:
        # 16 bytes: u32 count, u32 pad, u64 pointer to first variant.
        # Each variant in the array is itself 16 bytes (type ptr + data ptr).
        count = struct.unpack_from("<I", sector_0, data_offset)[0]
        array_fx = s0_fixups_by_src.get(data_offset + 8)
        if array_fx is None or array_fx[0] != 0 or count <= 0:
            return
        for i in range(count):
            elem_off = array_fx[1] + i * 16
            type_fx = s0_fixups_by_src.get(elem_off)
            data_fx = s0_fixups_by_src.get(elem_off + 8)
            if type_fx is None or data_fx is None:
                continue
            if type_fx[0] != 6 or data_fx[0] != 0:
                continue
            variant_type = _parse_type_def(sector_6, type_fx[1])
            _walk_struct(
                variant_type, sector_6, sector_0, data_fx[1],
                s6_fixups_by_src, s0_fixups_by_src,
                out_string_positions, visited,
            )
        return

    # Leaf or unsupported types: nothing more to walk.


def _walk_struct_fields(
    children_off: int, sector_6: bytes, sector_0: bytes, struct_start: int,
    s6_fixups_by_src: dict, s0_fixups_by_src: dict,
    out_string_positions: list, visited: set,
):
    """Walk the children list at sector_6[children_off:] as the fields of
    a struct that starts at sector_0[struct_start:]. Used by both INLINE
    (placed inline) and REFERENCE/REFERENCETOARRAY (after resolving the
    pointer to the struct's start)."""
    field_off = struct_start
    for child in _walk_children(children_off, sector_6):
        n = child.array_size if child.array_size > 0 else 1
        elem_size = _field_size_single(child, sector_6, s6_fixups_by_src)
        for i in range(n):
            _walk_struct(
                child, sector_6, sector_0, field_off + i * elem_size,
                s6_fixups_by_src, s0_fixups_by_src,
                out_string_positions, visited,
            )
        field_off += n * elem_size


def _field_size_single(td: TypeDef, sector_6: bytes, s6_fixups_by_src: dict) -> int:
    """Size of ONE element of this type (ignoring array_size)."""
    if td.type_id == T_INLINE:
        children_off = _resolve_s6_fixup(td._pos + 0x0C, s6_fixups_by_src)
        if children_off is None:
            return 0
        return sum(
            _field_size(c, sector_6, s6_fixups_by_src)
            for c in _walk_children(children_off, sector_6)
        )
    return _TYPE_SIZE.get(td.type_id, 0)


def cmd_inspect(args):
    """Diagnostic: load one extracted GPK entry, run the type walker, and
    report counts. Useful for verifying Phase 3 against the gist's expected
    numbers BEFORE building the merger.
    """
    path = Path(args.entry)
    if not path.is_file():
        sys.stderr.write(f"error: {path}: not a file\n")
        return 1
    raw = path.read_bytes()
    if not has_granny_magic(raw):
        sys.stderr.write(f"error: {path}: not a Granny v7 64-bit LE file\n")
        return 1

    info = find_string_positions(raw)
    sectors = info["sectors"]
    print(f"{path.name}")
    print(f"  sector 0  data={sectors[0].decompressed_length:,}B  fixups={sectors[0].fixup_count}")
    print(f"  sector 6  data={sectors[6].decompressed_length:,}B  fixups={sectors[6].fixup_count}")
    print(f"  type-name string indices (sector 6): {len(info['sector_6_typenames'])}")
    print(f"  STRING field positions (sector 0):    {len(info['sector_0_strings'])}")
    if args.show:
        for off, idx in info["sector_6_typenames"][: args.show]:
            print(f"    s6 0x{off:06x} -> str[{idx}]")
        for off, idx in info["sector_0_strings"][: args.show]:
            print(f"    s0 0x{off:06x} -> str[{idx}]")
    return 0


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

    inspect = sub.add_parser(
        "inspect",
        help="Walk one extracted GPK-entry .gr2-raw file's type tree and "
        "report how many string-index positions were found "
        "(diagnostic for Phase 3 before the merger is built).",
    )
    inspect.add_argument("entry", help="Path to a .gr2-raw entry file")
    inspect.add_argument(
        "--show", type=int, default=0,
        help="Print the first N string-index positions (default: 0)",
    )
    inspect.set_defaults(func=cmd_inspect)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
