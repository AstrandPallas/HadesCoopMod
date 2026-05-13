"""
Headless Blender render driver for Mel sprite generation.

Loads a mesh .glb (skeleton + geometry) and an animation .glb (skeletal
action data), assigns the action to the mesh's armature, orbits an
orthographic camera through N angles around the character, and emits
PNG sequences ready to be Bink-encoded as a Hades-1-style sprite sheet.

Usage (Blender installed):
    blender --background --python render_mel.py -- \\
        --mesh   tools/granny/melinoe-glb/Melinoe_Mesh.glb \\
        --anim   tools/granny/melinoe-glb/Dagger_Weapon_Base_DaggerEquipIdleR_C_00.glb \\
        --out    tools/granny/render/Dagger_Idle

Usage (bpy installed via `pip install bpy`):
    python render_mel.py \\
        --mesh   tools/granny/melinoe-glb/Melinoe_Mesh.glb \\
        --anim   tools/granny/melinoe-glb/Dagger_Weapon_Base_DaggerEquipIdleR_C_00.glb \\
        --out    tools/granny/render/Dagger_Idle

Output layout (per (angle, frame) pair):
    <out>/angle_00/frame_0001.png
    <out>/angle_00/frame_0002.png
    ...
    <out>/angle_31/frame_NNNN.png

The first pass is intentionally easy to inspect: each angle gets its own
subdirectory so you can scrub through one angle's PNGs as a sanity check
before committing to a Bink encoding layout.

Tuning workflow:
  1. Run with defaults on a single animation
  2. Compare frame_0001 of a known angle against vanilla Zagreus's
     equivalent pose (extract with `bink2ForUnreal` -> first PNG frame)
  3. Adjust --pitch / --ortho-scale / --target-z / lighting until silhouettes
     line up
  4. Once one animation looks right, batch over all 791 Mel glbs.

Known camera tuning starting points (subject to revision after eyeball
comparison against vanilla Zagreus Bink frames):
  pitch:        45°  (Hades's actual 3/4 top-down is closer to 30-35°,
                      but 45° is a clean starting point)
  ortho-scale:  2.5  (smaller = zoomed in)
  target-z:     1.0  (height of "look at" point above floor; should be
                      roughly center-of-mass of the character)
  distance:     5.0  (orbit radius; ortho scale matters more than this)
"""

import argparse
import math
import os
import sys
from pathlib import Path


def _parse_args():
    # Blender's `--background --python script.py -- arg1 arg2` passes args
    # after `--` to the script. The bpy-pip path just uses argv normally.
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = argv[1:]

    p = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    p.add_argument("--mesh", required=True, help="Path to mesh .glb")
    p.add_argument("--anim", required=True, help="Path to animation .glb")
    p.add_argument("--out", required=True, help="Output directory for PNG sequences")
    p.add_argument("--angles", type=int, default=32,
                   help="Number of orbital camera angles (default: 32, matches vanilla Zag)")
    p.add_argument("--pitch", type=float, default=45.0,
                   help="Camera pitch in degrees below horizontal")
    p.add_argument("--ortho-scale", type=float, default=2.5,
                   help="Orthographic camera scale (smaller = closer)")
    p.add_argument("--target-z", type=float, default=1.0,
                   help="Z-coordinate the camera looks at (character mid-height)")
    p.add_argument("--distance", type=float, default=5.0,
                   help="Camera orbit radius from target")
    p.add_argument("--res", default="128x224",
                   help="Output resolution WxH (default: 128x224 matches Zag's Bink dims)")
    p.add_argument("--engine", default="EEVEE",
                   help="Render engine: EEVEE (fast) or CYCLES (slow, CPU/GPU)")
    p.add_argument("--frame-step", type=int, default=1,
                   help="Render every Nth frame (1 = every frame)")
    p.add_argument("--max-frames", type=int, default=0,
                   help="If >0, cap total frames per angle (debug)")
    return p.parse_args(argv)


def _set_render_engine(scene, engine_name: str):
    """EEVEE name varies across Blender versions; pick the one that exists."""
    candidates = {
        "EEVEE": ["BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"],
        "CYCLES": ["CYCLES"],
    }
    for name in candidates.get(engine_name.upper(), [engine_name]):
        try:
            scene.render.engine = name
            return name
        except (TypeError, AttributeError):
            continue
    raise RuntimeError(f"Could not set render engine to {engine_name}")


def _import_glb(path: str):
    """Wrap the glTF importer call so it tolerates both old and new Blender APIs."""
    import bpy
    bpy.ops.import_scene.gltf(filepath=path)


def _find_armatures(bpy):
    return [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']


def _reparent_mesh_to(target_armature, source_armature):
    """Move all mesh children of source_armature to target_armature, and
    rewire any Armature modifiers on them to point at target_armature.

    Why this instead of transferring the action: Blender 5.0 restructured
    Action data with layers + slots, where each slot is bound to a specific
    data ID (the armature it was loaded against). Reassigning
    `animation_data.action` doesn't rebind the slot to the new armature,
    so f-curves don't drive bones. Reparenting the mesh to the armature
    that already owns the action sidesteps the slot-rebinding problem
    entirely — the mesh's vertex groups resolve against the new armature
    by bone name (already verified ~97% overlap for Melinoe).

    Returns the action name on success, or None if the source had no action.
    """
    import bpy

    # Collect mesh objects parented to source_armature.
    mesh_children = [
        obj for obj in list(source_armature.children) if obj.type == 'MESH'
    ]

    # Re-parent each, preserve world transforms.
    for mesh_obj in mesh_children:
        mat = mesh_obj.matrix_world.copy()
        mesh_obj.parent = target_armature
        mesh_obj.matrix_world = mat
        # Rewire armature modifiers (vertex groups still resolve by name).
        for mod in mesh_obj.modifiers:
            if mod.type == 'ARMATURE':
                mod.object = target_armature

    # The action lives on target_armature (the animation glb's armature),
    # not source_armature (mesh glb has no action). Capture the name from
    # the right side.
    action_name = None
    if target_armature.animation_data and target_armature.animation_data.action:
        action_name = target_armature.animation_data.action.name

    # Delete the source armature (now orphaned).
    source_name = source_armature.name
    bpy.data.objects.remove(source_armature, do_unlink=True)

    return action_name, source_name, len(mesh_children)


def _disable_noisy_addons():
    """Disable third-party addons that throw spurious errors on factory-
    reset scenes (e.g. Valve Source Tools' depsgraph handler tries to
    touch scene.vs which doesn't exist on an empty scene)."""
    import bpy
    for addon_name in ("io_scene_valvesource",):
        try:
            bpy.ops.preferences.addon_disable(module=addon_name)
        except Exception:
            pass


def main():
    args = _parse_args()

    # Resolve to absolute paths so the script doesn't depend on Blender's
    # cwd (it typically starts in C:\ on Windows, not the user's repo).
    args.mesh = str(Path(args.mesh).resolve())
    args.anim = str(Path(args.anim).resolve())
    args.out = str(Path(args.out).resolve())

    import bpy  # imported here so argparse failures don't blame bpy
    import mathutils  # noqa: F401

    # Disable problematic third-party addons (Valve Source Tools' depsgraph
    # handler crashes on factory-reset scenes). Best-effort.
    _disable_noisy_addons()

    # Clean slate. Removes ALL default objects/cameras/lights/etc.
    bpy.ops.wm.read_factory_settings(use_empty=True)

    print(f"Loading mesh: {args.mesh}")
    _import_glb(args.mesh)

    # Hide outline shell meshes. Hades characters have a Maya cel-shading
    # rig where a slightly-enlarged duplicate of the body mesh, with
    # flipped normals + solid-black material, gets rendered first to draw
    # the cartoon outline. The glTF import strips that special material
    # treatment but keeps the geometry, so the outline shell ends up as a
    # solid black layer that occludes everything from camera POV. Names
    # like Melinoe_Rig_MelinoeOutline_MeshShape are the signal. Hiding
    # them gives us the actual body to look at; recreating the outline
    # effect properly is a separate styling pass.
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'MESH' and 'Outline' in obj.name:
            print(f"  hiding outline shell: {obj.name}")
            obj.hide_render = True
            obj.hide_viewport = True

    # Also remove any leftover default objects (the factory-empty preset
    # sometimes leaves an Icosphere or Cube placeholder).
    for placeholder in ("Cube", "Icosphere", "Sphere"):
        obj = bpy.data.objects.get(placeholder)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)

    # lslib's glTF export drops texture references (Granny stores them as
    # artist-machine paths like X:/Raw/3D/... which never resolve), so
    # imported materials have only a "Dummy" white Base Color and render
    # without surface variation. Patch all materials with a tunable gray
    # so EEVEE has something to shade. Real textures live in BiomeHub.pkg's
    # GR2\Melinoe_Color etc. and would need a separate extraction pass.
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is None:
            continue
        bsdf.inputs["Base Color"].default_value = (0.7, 0.7, 0.7, 1.0)
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.6
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
    mesh_armatures = _find_armatures(bpy)
    if not mesh_armatures:
        print(f"ERROR: no armature in mesh glb {args.mesh}", file=sys.stderr)
        return 1
    mesh_armature = mesh_armatures[0]
    print(f"  mesh armature: {mesh_armature.name}  bones={len(mesh_armature.data.bones)}")

    # Compute mesh bounding box so the camera setup can frame it. Granny
    # files don't normalize world units; Hades II's Mel is at roughly
    # 100-180 units tall ("100" in the GR2 unit-meter field would mean
    # the mesh thinks it's 100 cm = 1 m, but Blender treats it as meters
    # which makes it tiny). Auto-frame compensates.
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if mesh_objs:
        from mathutils import Vector
        min_v = Vector((float('inf'),) * 3)
        max_v = Vector((float('-inf'),) * 3)
        for obj in mesh_objs:
            for corner in obj.bound_box:
                world = obj.matrix_world @ Vector(corner)
                min_v.x = min(min_v.x, world.x); max_v.x = max(max_v.x, world.x)
                min_v.y = min(min_v.y, world.y); max_v.y = max(max_v.y, world.y)
                min_v.z = min(min_v.z, world.z); max_v.z = max(max_v.z, world.z)
        bbox_size = max_v - min_v
        bbox_center = (min_v + max_v) * 0.5
        print(f"  mesh bbox: min={tuple(round(v,2) for v in min_v)} max={tuple(round(v,2) for v in max_v)}")
        print(f"  bbox size={tuple(round(v,2) for v in bbox_size)} center={tuple(round(v,2) for v in bbox_center)}")

        # If the user left the default ortho-scale and target-z, auto-size
        # to fit the mesh height with 10% margin.
        if args.ortho_scale == 2.5 and args.target_z == 1.0:
            args.ortho_scale = max(bbox_size.x, bbox_size.z) * 1.1
            args.target_z = bbox_center.z
            args.distance = max(args.distance, max(bbox_size.x, bbox_size.y, bbox_size.z) * 2.0)
            print(f"  auto-framed: ortho-scale={args.ortho_scale:.2f}  target-z={args.target_z:.2f}  distance={args.distance:.2f}")

    print(f"Loading animation: {args.anim}")
    _import_glb(args.anim)
    all_armatures = _find_armatures(bpy)
    new_armatures = [a for a in all_armatures if a is not mesh_armature]
    if new_armatures:
        anim_armature = new_armatures[-1]
        anim_armature_name = anim_armature.name
        # Move the mesh to the animation's armature (instead of moving the
        # action onto the mesh's armature) so we don't have to rebind the
        # action's slot to a new data ID. After this, mesh_armature is
        # gone and anim_armature is the one we render against.
        action_name, mesh_arm_name, num_meshes = _reparent_mesh_to(anim_armature, mesh_armature)
        print(f"  reparented {num_meshes} mesh(es) from {mesh_arm_name} -> {anim_armature_name}")
        print(f"  active action on anim armature: {action_name}")
        # The render code below references `mesh_armature` to fetch the
        # active action's frame range. Point that at anim_armature now.
        mesh_armature = anim_armature
    else:
        # No new armature created — the importer might have merged the
        # action onto the existing armature already, or this glb has no
        # skeletal data. Either way, check what's on the mesh armature.
        if mesh_armature.animation_data and mesh_armature.animation_data.action:
            print(f"  action already on mesh armature: {mesh_armature.animation_data.action.name}")
        else:
            print(f"  warning: no animation action found anywhere; will render a static pose")

    # Configure scene render settings.
    scene = bpy.context.scene
    res_w, res_h = (int(x) for x in args.res.split("x"))
    scene.render.resolution_x = res_w
    scene.render.resolution_y = res_h
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    actual_engine = _set_render_engine(scene, args.engine)
    print(f"render engine: {actual_engine}  resolution: {res_w}x{res_h}")

    # Determine animation frame range from the action.
    action = (mesh_armature.animation_data and
              mesh_armature.animation_data.action)
    if action is not None:
        fr_start, fr_end = action.frame_range
        scene.frame_start = max(1, int(fr_start))
        scene.frame_end = int(fr_end)
    else:
        scene.frame_start = 1
        scene.frame_end = 1
    print(f"frame range: {scene.frame_start} to {scene.frame_end}")

    # Add a sun key light + sun fill light. Energy values are starting
    # points; tune against reference for the Hades-style look.
    key_data = bpy.data.lights.new(name="Key", type='SUN')
    key_data.energy = 5.0
    key = bpy.data.objects.new("Key", key_data)
    scene.collection.objects.link(key)
    key.rotation_euler = (math.radians(60), 0, math.radians(45))

    fill_data = bpy.data.lights.new(name="Fill", type='SUN')
    fill_data.energy = 1.5
    fill = bpy.data.objects.new("Fill", fill_data)
    scene.collection.objects.link(fill)
    fill.rotation_euler = (math.radians(60), 0, math.radians(-135))

    # Orthographic camera that orbits a target empty.
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = args.ortho_scale
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    target = bpy.data.objects.new("OrbitTarget", None)
    scene.collection.objects.link(target)
    target.location = (0.0, 0.0, args.target_z)

    track = cam.constraints.new(type='TRACK_TO')
    track.target = target
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'

    pitch_rad = math.radians(args.pitch)
    radius = args.distance

    Path(args.out).mkdir(parents=True, exist_ok=True)
    total_frames_per_angle = max(
        1,
        (scene.frame_end - scene.frame_start) // max(1, args.frame_step) + 1,
    )
    if args.max_frames > 0:
        total_frames_per_angle = min(total_frames_per_angle, args.max_frames)
    total = args.angles * total_frames_per_angle
    print(f"rendering {args.angles} angles × {total_frames_per_angle} frames = {total} images")

    rendered = 0
    for angle_idx in range(args.angles):
        theta = 2.0 * math.pi * angle_idx / args.angles
        cam.location = (
            radius * math.cos(pitch_rad) * math.sin(theta),
            -radius * math.cos(pitch_rad) * math.cos(theta),
            target.location.z + radius * math.sin(pitch_rad),
        )
        angle_dir = Path(args.out) / f"angle_{angle_idx:02d}"
        angle_dir.mkdir(exist_ok=True)

        frame_indices = list(range(scene.frame_start, scene.frame_end + 1, args.frame_step))
        if args.max_frames > 0:
            frame_indices = frame_indices[:args.max_frames]

        for frame in frame_indices:
            scene.frame_set(frame)
            scene.render.filepath = str(angle_dir / f"frame_{frame:04d}.png")
            bpy.ops.render.render(write_still=True)
            rendered += 1
            if rendered % 20 == 0:
                print(f"  {rendered}/{total}  (angle {angle_idx}, frame {frame})")

    print(f"\nDone. {rendered} renders in {args.out}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
