"""Detailed smooth low-poly item models for the game (World/Skins).

Run with Blender's Python module (pip install bpy):
    python Art/blender/make_models.py [out_dir] [--no-render]

For every item this builds a model in the item's own space (studs; Roblox
(x, y, z) = Blender (x, -z, y); origin = centre of its footprint on the floor;
front = Roblox +Z = Blender -Y), joins the pieces by colour role and exports
`<Id>.fbx` with one mesh per role (Body, Trim, Accent, Metal, Dark, Wood, ...).
The game colours each role from its palette (World/Skins.Defs), scales and
aligns the model to the item's footprint, so exact import scale doesn't matter.
Also renders `<Id>.png` and a `lineup.png` of everything.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
OUT = ARGS[0] if ARGS else os.path.join(ROOT, "Models")
RENDER = "--no-render" not in sys.argv
os.makedirs(OUT, exist_ok=True)

# Preview colours per role (the game uses its own palette, see World/Skins).
ROLE_COLORS = {
    "Body": (1.0, 0.78, 0.62), "Trim": (1.0, 0.95, 0.85), "Accent": (1.0, 0.36, 0.62),
    "Metal": (0.66, 0.7, 0.76), "Dark": (0.2, 0.15, 0.16), "Door": (0.24, 0.16, 0.16),
    "Wood": (0.72, 0.5, 0.34), "LightWood": (0.9, 0.74, 0.55), "Glass": (0.75, 0.9, 1.0),
    "Stripe": (1.0, 0.55, 0.75), "Top": (1.0, 0.97, 0.92), "Cushion": (0.6, 0.92, 0.78),
    "Leaf": (0.42, 0.78, 0.38), "LeafDark": (0.3, 0.62, 0.3), "Soil": (0.36, 0.25, 0.2),
    "Petal": (1.0, 0.5, 0.7), "PetalB": (1.0, 0.86, 0.4),
}


def rb(x, y, z):
    """Roblox position/size -> Blender."""
    return Vector((x, -z, y))


def new_obj(role):
    obj = bpy.context.active_object
    obj["role"] = role
    return obj


def finish(obj, bevel=0.0, segments=2, smooth=35, limit_angle=None):
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE" if limit_angle else "NONE"
        if limit_angle:
            mod.angle_limit = math.radians(limit_angle)
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth is None:
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth))
    obj.select_set(False)
    return obj


def box(role, size, pos, bevel=0.15, segments=2, rot=(0, 0, 0)):
    """Rounded box; size/pos in Roblox studs (x, y, z)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=rb(*pos))
    obj = new_obj(role)
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = rot
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return finish(obj, min(bevel, min(size) / 2 - 0.001), segments)


def cyl(role, diameter, height, pos, axis="Y", verts=20, bevel=0.06, r2=None):
    """Cylinder (or cone when r2 is set) along a Roblox axis."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=diameter / 2, depth=height, location=rb(*pos))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=diameter / 2, radius2=r2 / 2, depth=height, location=rb(*pos))
    obj = new_obj(role)
    if axis == "X":
        obj.rotation_euler = (0, math.radians(90), 0)
    elif axis == "Z":  # Roblox Z = Blender -Y
        obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(obj, bevel, 2, 40, limit_angle=50)


def ball(role, diameter, pos, subdivisions=2, flat=True, squash=1.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=diameter / 2, location=rb(*pos))
    obj = new_obj(role)
    obj.scale = (1, 1, squash)
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, 0, smooth=None if flat else 60)


def torus(role, major, minor, pos, axis="Y", major_seg=24, minor_seg=8, arc=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=major_seg, minor_segments=minor_seg, location=rb(*pos))
    obj = new_obj(role)
    if axis == "X":
        obj.rotation_euler = (0, math.radians(90), 0)
    elif axis == "Z":
        obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    return finish(obj, 0, smooth=40)


def cut(target, cutter):
    """Boolean difference; the cutter is deleted."""
    mod = target.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return target


def cutter_box(size, pos):
    bpy.ops.mesh.primitive_cube_add(size=1, location=rb(*pos))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True)
    return finish(obj, min(0.08, min(size) / 2 - 0.001), 2)


# ------------------------------------------------------------------ items


def oven():
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl("Metal", 0.55, 0.45, (sx * 3.3, 0.22, sz * 1.8), verts=12)
    body = box("Body", (8, 6.4, 5), (0, 3.65, 0), bevel=0.45, segments=3)
    for side in (-1, 1):  # side vents
        for i in range(3):
            cut(body, cutter_box((0.6, 0.22, 2.4), (side * 4.0, 5.1 + i * 0.45, -0.4)))
    box("Trim", (7.3, 0.2, 4.3), (0, 6.9, -0.1), bevel=0.1)  # cooktop plate
    for x in (-1.8, 1.8):  # burners
        torus("Metal", 0.75, 0.12, (x, 7.05, -0.7))
        cyl("Dark", 1.15, 0.1, (x, 7.02, -0.7), verts=16, bevel=0.02)
    box("Trim", (7.4, 1.1, 0.3), (0, 6.0, 2.55), bevel=0.12)  # control strip
    for i, x in enumerate((-2.6, -1.5, -0.4)):
        cyl("Accent", 0.72, 0.35, (x, 6.0, 2.8), axis="Z", verts=14)
        box("Dark", (0.08, 0.28, 0.06), (x, 6.12, 2.98), bevel=0.02)
    box("Dark", (1.9, 0.55, 0.1), (2.2, 6.0, 2.72), bevel=0.05)  # little display
    box("Accent", (0.35, 0.35, 0.06), (1.2, 6.0, 2.74), bevel=0.05)
    frame = box("Trim", (6.4, 4.4, 0.35), (0, 3.1, 2.6), bevel=0.2)
    cut(frame, cutter_box((5.3, 3.3, 1.0), (0, 3.1, 2.6)))
    box("Door", (5.4, 3.4, 0.25), (0, 3.1, 2.5), bevel=0.15)
    cyl("Metal", 0.3, 5.0, (0, 5.0, 3.1), axis="X", verts=12, bevel=0.03)  # handle
    for x in (-2.2, 2.2):
        cyl("Metal", 0.24, 0.45, (x, 5.0, 2.88), axis="Z", verts=10, bevel=0.02)
    cyl("Metal", 1.1, 3.0, (2.5, 8.4, -1.5), verts=16)  # chimney
    cyl("Metal", 1.5, 0.3, (2.5, 10.0, -1.5), verts=16)
    torus("Accent", 0.6, 0.1, (2.5, 8.9, -1.5))


def mixer():
    body = box("Body", (5, 1.6, 5), (0, 0.8, 0), bevel=0.5, segments=3)  # base
    box("Trim", (4.4, 0.15, 4.4), (0, 1.62, 0), bevel=0.05)
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl("Dark", 0.6, 0.2, (sx * 1.9, 0.1, sz * 1.9), verts=10, bevel=0.02)
    box("Body", (1.8, 7.0, 1.8), (0, 4.5, -2.0), bevel=0.6, segments=3)  # column
    cyl("Body", 2.0, 4.6, (0, 8.9, -0.6), axis="Z", verts=20, bevel=0.3)  # head
    ball("Body", 2.0, (0, 8.9, 1.7), subdivisions=2, flat=False)  # nose
    torus("Accent", 1.02, 0.12, (0, 8.9, 0.6), axis="Z")  # head band
    cyl("Accent", 0.8, 0.3, (1.1, 8.9, -1.4), axis="X", verts=12)  # speed dial
    cyl("Metal", 0.5, 0.6, (0, 7.6, 1.2), verts=12)  # beater shaft
    # Whisk: crossed wire loops
    for i in range(4):
        loop = torus("Metal", 0.55, 0.05, (0, 6.6, 1.2), axis="X", major_seg=16, minor_seg=6)
        loop.rotation_euler = (0, 0, math.radians(i * 45))
        bpy.context.view_layer.objects.active = loop
        loop.select_set(True)
        bpy.ops.object.transform_apply(rotation=True)
        loop.select_set(False)
    bowl = cyl("Metal", 4.2, 2.5, (0, 3.0, 1.0), verts=24, bevel=0.1, r2=4.6)
    cut(bowl, cyl("Metal", 3.8, 2.6, (0, 3.35, 1.0), verts=24, bevel=0, r2=4.3))
    torus("Metal", 2.3, 0.12, (0, 4.25, 1.0))
    cyl("Trim", 3.4, 0.3, (0, 1.85, 1.0), verts=20)  # bowl plate
    cyl("Accent", 0.7, 0.35, (1.9, 1.0, 2.45), axis="Z", verts=12)  # power knob
    del body


def pantry():
    # Open cabinet against the wall: back panel, sides, crown, plinth, 2 shelves.
    box("Wood", (13, 9, 0.5), (0, 4.8, -1.25), bevel=0.15)
    for x in (-6.25, 6.25):
        box("Wood", (0.5, 9.4, 4.4), (x, 4.7, 0.7), bevel=0.15)
    box("Trim", (13.8, 0.6, 4.8), (0, 9.6, 0.75), bevel=0.2, segments=3)  # crown
    box("Accent", (14.0, 0.25, 4.9), (0, 9.2, 0.75), bevel=0.08)
    box("Wood", (13.0, 0.6, 4.4), (0, 0.3, 0.7), bevel=0.15)  # plinth
    for y in (3.1, 6.0):
        box("LightWood", (12.2, 0.35, 3.8), (0, y, 0.95), bevel=0.1)
        box("Trim", (12.2, 0.12, 0.12), (0, y + 0.22, 2.85), bevel=0.04)  # shelf lip
    # Jars and a crate on top for character.
    for i, x in enumerate((-4.5, -3.2, -1.9)):
        cyl("Glass", 1.0, 1.2 + i * 0.2, (x, 10.5 + i * 0.1, 0.7), verts=12)
        cyl("Accent", 1.05, 0.25, (x, 11.15 + i * 0.2, 0.7), verts=12)
    box("LightWood", (2.6, 1.2, 1.8), (3.8, 10.5, 0.7), bevel=0.1)
    for x in (2.8, 3.8, 4.8):
        box("Wood", (0.15, 1.0, 1.85), (x, 10.5, 0.7), bevel=0.03)
    box("Trim", (4.0, 1.2, 0.15), (0, 8.4, -0.9), bevel=0.05)  # name plate
    box("Accent", (3.6, 0.9, 0.08), (0, 8.4, -0.82), bevel=0.04)


def counter():
    body = box("Body", (20, 3.3, 4), (0, 2.05, 0), bevel=0.3, segments=3)
    for i in range(5):  # inset front panels
        cut(body, cutter_box((3.4, 2.1, 0.5), (-8 + i * 4, 2.2, 2.0)))
        box("Stripe", (3.2, 1.9, 0.15), (-8 + i * 4, 2.2, 1.85), bevel=0.12)
        box("Trim", (1.2, 0.12, 0.1), (-8 + i * 4, 2.9, 1.95), bevel=0.04)  # label tag
    for x in (-9.9, 9.9):
        box("Trim", (0.5, 3.3, 4.2), (x, 2.05, 0), bevel=0.15)  # corner pilasters
    box("Accent", (20.4, 0.4, 4.3), (0, 0.2, 0.05), bevel=0.12)  # kick plate
    box("Top", (20.6, 0.5, 4.6), (0, 3.85, 0.1), bevel=0.2, segments=3)  # top slab (top at 4.1)
    box("Trim", (20.6, 0.15, 0.2), (0, 3.62, 2.35), bevel=0.05)  # edge band


def cafe_table():
    cyl("Top", 4.4, 0.35, (0, 3.0, 0), verts=28, bevel=0.12)
    torus("Accent", 2.2, 0.1, (0, 3.0, 0), major_seg=32)
    cyl("Accent", 0.5, 2.6, (0, 1.6, 0), verts=12)
    cyl("Accent", 2.0, 0.25, (0, 0.13, 0), verts=20, bevel=0.08, r2=1.4)
    for x in (-3, 3):  # bistro chairs facing the table
        cyl("Cushion", 1.8, 0.35, (x, 1.65, 0), verts=20, bevel=0.12)
        cyl("Metal", 1.75, 0.1, (x, 1.45, 0), verts=20, bevel=0.02)
        for a in range(4):
            ang = math.radians(45 + a * 90)
            cyl("Metal", 0.14, 1.45, (x + math.cos(ang) * 0.6, 0.72, math.sin(ang) * 0.6), verts=8, bevel=0.0)
        back = torus("Metal", 0.75, 0.07, (x + (0.8 if x > 0 else -0.8), 2.6, 0), axis="X", major_seg=20, minor_seg=6)
        cut(back, cutter_box((2, 2, 2), (x + (0.8 if x > 0 else -0.8), 1.5, 0)))  # keep the top arc
        for dz in (-0.7, 0.7):
            cyl("Metal", 0.1, 1.0, (x + (0.8 if x > 0 else -0.8), 2.2, dz), verts=8, bevel=0.0)


def potted_plant():
    pot = cyl("Body", 2.0, 2.0, (0, 1.0, 0), verts=14, bevel=0.1, r2=2.7)  # wider at the top
    cut(pot, cyl("Body", 2.3, 0.6, (0, 2.0, 0), verts=14, bevel=0, r2=2.45))
    torus("Accent", 1.33, 0.15, (0, 1.95, 0), major_seg=14)
    cyl("Soil", 2.3, 0.15, (0, 1.8, 0), verts=14, bevel=0)
    cyl("Trim", 2.1, 0.15, (0, 0.08, 0), verts=14, bevel=0.04)  # saucer
    # Leafy crown: faceted blobs...
    ball("Leaf", 2.2, (0, 3.0, 0), subdivisions=1)
    ball("LeafDark", 1.5, (0.7, 3.4, 0.3), subdivisions=1)
    ball("LeafDark", 1.4, (-0.6, 3.5, -0.4), subdivisions=1)
    ball("Leaf", 1.2, (0.1, 4.0, -0.2), subdivisions=1)
    # ...and long leaf blades fanning out of the pot, tips up.
    for i in range(7):
        ang = i * math.tau / 7 + 0.3
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.5)
        leaf = new_obj("Leaf" if i % 2 == 0 else "LeafDark")
        leaf.scale = (2.0, 0.7, 0.18)  # long, narrow, thin
        leaf.rotation_euler = (0, math.radians(-30), ang)  # tilt the tip up, then fan around
        leaf.location = rb(math.cos(ang) * 1.0, 2.55, -math.sin(ang) * 1.0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        finish(leaf, 0, smooth=None)
    for pos, role in (((0.8, 4.1, 0.5), "Petal"), ((-0.7, 4.0, -0.4), "PetalB"), ((0.2, 4.5, 0.6), "Petal")):
        ball(role, 0.8, pos, subdivisions=1)
        ball("PetalB" if role == "Petal" else "Petal", 0.35, (pos[0], pos[1] + 0.25, pos[2]), subdivisions=1)


ITEMS = {
    "Oven": oven,
    "Mixer": mixer,
    "IngredientCrate": pantry,
    "DisplayCounter": counter,
    "CafeTable": cafe_table,
    "PottedPlant": potted_plant,
}

# ------------------------------------------------------------------ pipeline


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def join_roles():
    """One mesh per colour role, named after the role."""
    by_role = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and "role" in obj:
            by_role.setdefault(obj["role"], []).append(obj)
    joined = []
    for role, objs in by_role.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.active_object
        obj.name = role
        obj.data.name = role
        joined.append(obj)
    return joined


def material(role):
    m = bpy.data.materials.get(role) or bpy.data.materials.new(role)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*ROLE_COLORS.get(role, (0.8, 0.8, 0.8)), 1)
    bsdf.inputs["Roughness"].default_value = 0.3 if role in ("Metal", "Glass") else 0.6
    bsdf.inputs["Metallic"].default_value = 0.7 if role == "Metal" else 0.0
    if role == "Glass":
        bsdf.inputs["Alpha"].default_value = 0.55
    return m


def render(path, objs, lineup=False):
    for obj in objs:
        obj.data.materials.clear()
        obj.data.materials.append(material(obj.name.split(".")[0]))
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objs:
        for v in obj.bound_box:
            w = obj.matrix_world @ Vector(v)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    centre = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new("Floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.98, 0.9, 0.82, 1)
    floor.data.materials.append(fm)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    direction = Vector((0.55, -1.0, 0.55)).normalized()
    cam.location = centre + direction * radius * (2.6 if not lineup else 2.9)
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 2.4
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(45), math.radians(15), math.radians(30))
    bpy.context.collection.objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.86, 1.0, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    scene = bpy.context.scene
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 1400 if lineup else 800
    scene.render.resolution_y = 600 if lineup else 640
    scene.render.film_transparent = False
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )


def bounds_roblox(objs):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objs:
        for v in obj.bound_box:
            w = obj.matrix_world @ Vector(v)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    # Blender (x, y, z) -> Roblox (x, z, -y)
    size = (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)
    centre = ((hi.x + lo.x) / 2, (hi.z + lo.z) / 2, -(hi.y + lo.y) / 2)
    return [round(v, 3) for v in size], [round(v, 3) for v in centre]


import json

bounds = {}
for item_id, build in ITEMS.items():
    reset()
    build()
    objs = join_roles()
    size, centre = bounds_roblox(objs)
    bounds[item_id] = {"Size": size, "Centre": centre, "Roles": sorted(o.name for o in objs)}
    export(os.path.join(OUT, f"{item_id}.fbx"), objs)
    faces = sum(len(o.data.polygons) for o in objs)
    print(f"exported {item_id}: {len(objs)} role meshes, {faces} faces")
    if RENDER:
        render(os.path.join(OUT, f"{item_id}.png"), objs)

with open(os.path.join(OUT, "models.json"), "w") as f:
    json.dump(bounds, f, indent=1)

if RENDER:
    reset()
    x = 0.0
    all_objs = []
    for item_id, build in ITEMS.items():
        before = set(bpy.context.scene.objects)
        build()
        new = [o for o in bpy.context.scene.objects if o not in before]
        lo = min((o.matrix_world @ Vector(v)).x for o in new for v in o.bound_box)
        hi = max((o.matrix_world @ Vector(v)).x for o in new for v in o.bound_box)
        for o in new:
            o.location.x += x - lo
        x += (hi - lo) + 2.5
        all_objs += new
    for o in all_objs:
        o.name = o["role"]
    render(os.path.join(OUT, "lineup.png"), all_objs, lineup=True)
