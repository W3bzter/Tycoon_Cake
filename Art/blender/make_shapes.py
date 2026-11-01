"""Builds the smooth low-poly base shapes the game uses (World/Style), exports
them as FBX for Roblox Studio's 3D Importer, and renders a before/after preview.

Run with Blender's Python module (pip install bpy):
    python Art/blender/make_shapes.py [out_dir]

Outputs (default out_dir = Art/Shapes):
    RoundedBox.fbx  unit cube with soft bevelled edges     (Style.RoundedBox / Trim)
    Cylinder.fbx    16-sided cylinder along X, bevelled rims (Style.Cylinder)
    Ball.fbx        faceted low-poly icosphere              (Style.Ball)
    preview.png     before (current primitives) vs after (these meshes)

Every mesh is 1 x 1 x 1 stud, centred on the origin; the game sets Size and
Color, so one mesh serves every box/cylinder/ball. Cylinder runs along X like a
Roblox cylinder part, so the game's existing CFrames work unchanged.
"""

import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "Shapes")
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def finish(obj, smooth_angle):
    """Applies modifiers and shading: smooth by angle (None = flat facets)."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth_angle is None:
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
    obj.select_set(False)
    return obj


def make_rounded_box(name="RoundedBox"):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    bevel = obj.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.12
    bevel.segments = 3
    bevel.limit_method = "NONE"
    return finish(obj, 40)


def make_cylinder(name="Cylinder"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.5, depth=1)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = (0, math.radians(90), 0)  # axis along X, like Roblox
    bpy.ops.object.transform_apply(rotation=True)
    bevel = obj.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.08
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(60)  # only the rims, not the side facets
    return finish(obj, 40)


def make_ball(name="Ball"):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5)
    obj = bpy.context.active_object
    obj.name = name
    return finish(obj, None)  # faceted: the low-poly look


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    loc = obj.location.copy()
    obj.location = (0, 0, 0)
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
    obj.location = loc


# ---------------------------------------------------------------- export
reset()
shapes = {
    "RoundedBox": make_rounded_box(),
    "Cylinder": make_cylinder(),
    "Ball": make_ball(),
}
for name, obj in shapes.items():
    export(obj, os.path.join(OUT, f"{name}.fbx"))
    print("exported", name, len(obj.data.polygons), "faces")

# ---------------------------------------------------------------- preview
# Roblox (x, y, z) -> Blender (x, -z, y). Sizes are Roblox studs.
COLORS = {
    "Peach": (1.0, 0.78, 0.62), "Cream": (1.0, 0.96, 0.86), "HotPink": (1.0, 0.36, 0.62),
    "Steel": (0.62, 0.66, 0.72), "White": (1, 1, 1), "Mint": (0.6, 0.92, 0.78),
    "Leaf": (0.45, 0.8, 0.4), "Grass": (0.35, 0.68, 0.32), "Cocoa": (0.5, 0.33, 0.24),
    "Door": (0.24, 0.16, 0.16), "Floor": (0.98, 0.9, 0.8),
}
materials = {}


def mat(color):
    if color not in materials:
        m = bpy.data.materials.new(color)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*COLORS[color], 1)
        bsdf.inputs["Roughness"].default_value = 0.55
        materials[color] = m
    return materials[color]


def place(template_or_kind, size, pos, color, offset_x):
    """size/pos in Roblox studs; offset_x shifts the whole set sideways."""
    x, y, z = pos
    if isinstance(template_or_kind, str):  # "before": plain primitives
        if template_or_kind == "box":
            bpy.ops.mesh.primitive_cube_add(size=1)
        elif template_or_kind == "cyl":
            bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.5, depth=1)
            bpy.context.active_object.rotation_euler = (0, math.radians(90), 0)
            bpy.ops.object.transform_apply(rotation=True)
            bpy.ops.object.shade_smooth()
        else:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.5)
            bpy.ops.object.shade_smooth()
        obj = bpy.context.active_object
    else:
        obj = template_or_kind.copy()
        obj.data = template_or_kind.data
        obj.hide_render = False
        bpy.context.collection.objects.link(obj)
    sx, sy, sz = size
    obj.scale = (sx, sz, sy)
    obj.location = (x + offset_x, -z, y)
    if len(obj.data.materials) == 0:
        obj.data.materials.append(None)
    obj.material_slots[0].link = "OBJECT"  # colour per object, mesh shared
    obj.material_slots[0].material = mat(color)
    return obj


def scene_set(kinds, offset_x):
    box, cyl, ball = kinds
    # Oven (as in World/ItemBuilders: body, door frame, door, knobs, chimney)
    place(box, (8, 7, 5), (0, 3.5, 0), "Peach", offset_x)
    place(box, (6.4, 4.4, 0.4), (0, 3.2, 2.6), "Cream", offset_x)
    place(box, (5.4, 3.4, 0.3), (0, 3.2, 2.8), "Door", offset_x)
    for i in (-1, 0, 1):
        place(ball, (0.7, 0.7, 0.7), (i * 1.6, 6.1, 2.6), "HotPink", offset_x)
    chim = place(cyl, (3, 1.2, 1.2), (2.5, 8.5, -1.5), "Steel", offset_x)
    chim.rotation_euler = (0, math.radians(90), 0)  # upright
    # Café table with two chairs
    top = place(cyl, (0.4, 4.4, 4.4), (8, 3, 4), "White", offset_x)
    top.rotation_euler = (0, math.radians(90), 0)
    leg = place(cyl, (2.8, 0.6, 0.6), (8, 1.4, 4), "HotPink", offset_x)
    leg.rotation_euler = (0, math.radians(90), 0)
    for dx in (-3, 3):
        place(box, (1.8, 1.8, 1.8), (8 + dx, 0.9, 4), "Mint", offset_x)
    # Tree
    trunk = place(cyl, (6, 1.4, 1.4), (-8, 3, 3), "Cocoa", offset_x)
    trunk.rotation_euler = (0, math.radians(90), 0)
    place(ball, (7, 7, 7), (-8, 7.5, 3), "Leaf", offset_x)
    place(ball, (5, 5, 5), (-6.2, 9.5, 3.6), "Grass", offset_x)
    place(ball, (4.5, 4.5, 4.5), (-9.6, 9, 2.2), "Grass", offset_x)


for obj in shapes.values():
    obj.hide_render = True
    obj.location = (0, 200, 0)
scene_set(("box", "cyl", "ball"), -15)  # before
scene_set((shapes["RoundedBox"], shapes["Cylinder"], shapes["Ball"]), 15)  # after

bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, 0))
bpy.context.active_object.data.materials.append(mat("Floor"))

cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 35
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = (0, -50, 24)
cam.rotation_euler = (math.radians(66), 0, 0)
bpy.context.scene.camera = cam

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 2.2
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
bpy.context.collection.objects.link(sun)
world = bpy.data.worlds.new("World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.85, 1.0, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
bpy.context.scene.world = world

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 48
scene.render.resolution_x = 1400
scene.render.resolution_y = 700
scene.view_settings.view_transform = "Standard"
scene.render.filepath = os.path.join(OUT, "preview.png")
bpy.ops.render.render(write_still=True)
print("preview", scene.render.filepath)
