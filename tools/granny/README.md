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

## convert_to_dae.ps1 / convert_to_glb.ps1 — standalone .gr2 → Blender-importable

Both wrap [Norbyte/lslib](https://github.com/Norbyte/lslib)'s `Divine.exe`.
Use whichever importer your Blender supports:

| Output | Coverage          | Blender importer            |
|--------|-------------------|-----------------------------|
| `.glb` | ~791/855 (~92.5%) | Built-in glTF 2.0 (always)  |
| `.dae` | ~846/855 (~99.0%) | Collada add-on (4.5+ may have dropped it) |

```powershell
pwsh tools/granny/convert_to_glb.ps1   # glTF binary  → File > Import > glTF 2.0
pwsh tools/granny/convert_to_dae.ps1   # Collada      → File > Import > Collada
```

Downloads expected: `lslib` v1.20.4 extracted to
`C:\Users\matte\src\lslib\ExportTool\`. Adjust `-DivinePath` if installed
elsewhere.

### glTF export requires a patched lslib

Stock lslib v1.20.4 crashes its glTF mesh export on Hades II files —
`GLTFExporter.ExportMeshExtensions` dereferences `mesh.ExtendedData.UserMeshProperties`
without a null check, and Hades II meshes don't carry that BG3-specific
metadata. The patch is a one-line `?.` guard with a fallback path that
still emits the `ExportOrder` + `ParentBone` extensions when meaningful.

Steps to reproduce the patched build (matches what's installed locally):

```bash
git clone https://github.com/Norbyte/lslib.git
cd lslib

# Download dependencies (the project's prebuild step needs gplex/gppg)
mkdir -p external && cd external
curl -sLo gppg.zip 'https://s3.eu-central-1.amazonaws.com/nb-stor/dos-legacy/ExportTool/gppg-distro-1_5_2.zip'
unzip -q gppg.zip && mkdir -p gppg/binaries
cp gppg-distro-1_5_2/binaries/* gppg/binaries/
cd ..

# Run gplex/gppg manually (the in-csproj PreBuildEvent uses $(SolutionDir) which
# doesn't resolve when building a .csproj outside a .sln; do it ourselves).
./external/gppg/binaries/Gplex.exe /out:LSLib/LS/Story/GoalParser/Goal.lex.cs   LSLib/LS/Story/GoalParser/Goal.lex
./external/gppg/binaries/Gppg.exe  /out:LSLib/LS/Story/GoalParser/Goal.yy.cs   LSLib/LS/Story/GoalParser/Goal.yy
./external/gppg/binaries/Gplex.exe /out:LSLib/LS/Story/HeaderParser/StoryHeader.lex.cs LSLib/LS/Story/HeaderParser/StoryHeader.lex
./external/gppg/binaries/Gppg.exe  /out:LSLib/LS/Story/HeaderParser/StoryHeader.yy.cs LSLib/LS/Story/HeaderParser/StoryHeader.yy

# Strip #line directives that reference relative paths the compiler can't find
# at build time. They're debug-only.
python -c "import re,sys,pathlib
for p in ['LSLib/LS/Story/GoalParser/Goal.lex.cs','LSLib/LS/Story/GoalParser/Goal.yy.cs','LSLib/LS/Story/HeaderParser/StoryHeader.lex.cs','LSLib/LS/Story/HeaderParser/StoryHeader.yy.cs']:
    p = pathlib.Path(p)
    s = p.read_text(encoding='utf-8', errors='replace')
    s = re.sub(r'^#line\s+\d+\s+\"[^\"]*\"\s*\$','',s,flags=re.MULTILINE)
    p.write_text(s, encoding='utf-8')"

# Edit LSLib/LSLib.csproj:
# - Clear the <PreBuildEvent>...</PreBuildEvent> block (we just ran it).
# - Replace <ProjectReference Include="..\LSLibNative\LSLibNative.vcxproj" />
#   with <Reference Include="LSLibNative"><HintPath>..\..\ExportTool\Packed\LSLibNative.dll</HintPath></Reference>
#   so we reuse the prebuilt native DLL instead of needing the C++ toolchain.

# Patch GLTFExporter.cs ExportMeshExtensions:
# - Change `var user = extd.UserMeshProperties;` to `var user = extd?.UserMeshProperties;`
# - Insert early-return when extd or user is null that still emits ExportOrder
#   and ParentBone (rigid-mesh attachment data) where applicable.

dotnet publish LSLib/LSLib.csproj -c Release -o LSLib/publish
cp LSLib/publish/*.dll C:/Users/matte/src/lslib/ExportTool/Packed/
cp LSLib/publish/*.dll C:/Users/matte/src/lslib/ExportTool/Packed/Tools/
```

### Failure modes

`.glb` path:
- "multiple track groups is not supported" — for Mel's compound run-stop
  animations (Axe special-upper return-to-idle etc.)
- "without skeleton data is not supported" — for short reaction clips
- For these, fall back to the `.dae` path.

`.dae` path:
- 9 entries hit a different lslib export bug (Aspect of Morrigan dagger
  executes, blur effects, Lob run-stop). Skip those clips.

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
