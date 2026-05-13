# Granny asset extraction (Hades II → Blender)

Tools for unpacking Hades II's Granny (`.gr2`) character meshes and
animations into a format Blender can import. Built for the Melinoë port
side of the co-op mod (see the `melinoe-port` branch).

## Pipeline

```
<Char>.gpk + <Char>.sdb  ─► granny_unpack.py  ─► 855 standalone .gr2
                                                       │
                                                       ▼
                          ┌──── convert_to_dae.ps1 (lslib Divine.exe)
                          │
                          ▼
                    855 .dae (Collada)  ──► Blender import
```

## granny_unpack.py — GPK/SDB → standalone .gr2

Reverse-engineering credit: alexpeattie's
[Granny Animated Mesh Formats gist](https://gist.github.com/alexpeattie/12a644299a9f913c0514db9d628a2b39),
cross-referenced against [arves100/opengr2](https://github.com/arves100/opengr2)
for the actual binary type sizes.

```bash
# 1. List entries in a GPK file
python granny_unpack.py list <Char>.gpk

# 2. Unpack one entry's raw Granny bytes (still GPK-style: strings are indices)
python granny_unpack.py unpack <Char>.gpk -o ./out

# 3. Dump the SDB string table
python granny_unpack.py strings <Char>.sdb

# 4. Walk one entry's type tree, count string-index positions
python granny_unpack.py inspect ./out/<entry>.gr2-raw

# 5. Merge a single GPK entry with its SDB into a standalone .gr2
python granny_unpack.py merge ./out/<entry>.gr2-raw <Char>.sdb -o <entry>.gr2

# 6. One-shot: extract + merge every entry in a GPK
python granny_unpack.py unpack-all <Char>.gpk <Char>.sdb -o ./melinoe-gr2
```

Requires `lz4` Python package: `pip install lz4`.

## convert_to_dae.ps1 — standalone .gr2 → Collada

Wraps [Norbyte/lslib](https://github.com/Norbyte/lslib)'s `Divine.exe`
(prebuilt at the latest release; bundled with `granny2.dll`).

```powershell
pwsh tools/granny/convert_to_dae.ps1
```

Downloads expected: `lslib` extracted to `C:\Users\matte\src\lslib\ExportTool\`.
Adjust `-DivinePath` parameter if installed elsewhere.

**Why DAE, not glTF**: lslib's glTF exporter throws a
`NullReferenceException` inside `ExportMeshExtensions` on Hades II files —
it looks up BG3-specific extension metadata that Hades II entries don't
carry. DAE export skips that code path and succeeds on ~99% of entries.

## Verified output

- `granny_unpack.py unpack-all` on `Melinoe.gpk` + `Melinoe.sdb`: 855/855
  entries merged in ~10 seconds, all open in `opengr2`'s `gr2nfo` tool
  with full structural integrity (ArtToolInfo, Skeleton, Bones with
  transforms, Materials, etc.).
- `convert_to_dae.ps1`: 846/855 → Collada in ~3 minutes. The 9 failures
  are edge-case animations (Aspect of Morrigan dagger executes, blur
  effects, run-stop transitions) that hit a different lslib export bug;
  the core mesh and standard movement animations all succeed.

## What's in `melinoe-dae/`

Naming convention from the GPK: `<Weapon|Tool>_<Variant>_<Action>_<Subtype>_<Number>.dae`

Major prefixes (counts approx.):

| Prefix     | Count | Notes                                           |
|------------|------:|-------------------------------------------------|
| `Melinoe_` | 463   | Per-weapon player character animations          |
| `Suit_`    | 141   | Default witch outfit poses                      |
| `Axe_`     |  56   | Axe weapon animations                           |
| `Staff_`   |  52   | Staff / Moonstone variants                      |
| `Lob_`     |  38   | Heavy attack ramp-ups                           |
| `TorchL_`/`TorchR_` | 21/21 | Torches (off-hand magic)                |
| `Tablet_`  |  12   | Bracer interactions                             |
| `Dagger_`  |  11   | Sister Blades                                   |
| `FishRod_` |  10   | Fishing                                         |
| `Torch_`   |   6   | Single-torch variants                           |
| meshes     |   3   | `Melinoe_Mesh`, `MelinoeOverlook_Mesh`, `Hat_Mesh` |

All Mel animations are weapon-bound — there's no "naked" walk/idle/run.
For mapping to Hades 1's `ZagreusXxx_Bink` slots, pick one of Mel's
weapon sets as canonical (Dagger reads closest to Zagreus's sword
stance).
