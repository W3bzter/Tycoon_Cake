"""Shared helpers for the smooth low-poly Blender models (make_world.py).

Positions/sizes are Roblox studs (x, y, z); Roblox (x, y, z) = Blender (x, -z, y).
Objects get a colour "role" (custom property) and are joined into one mesh per
role on export. An object with obj["solo"] = "<Name>" is kept as its own mesh
with that name (moving parts the game animates: wheels, doors, leaves).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

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


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def join_roles():
    """One mesh per colour role, named after the role."""
    by_role = {}
    by_solo = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and "solo" in obj:
            by_solo.setdefault(obj["solo"], []).append(obj)
        elif obj.type == "MESH" and "role" in obj:
            by_role.setdefault(obj["role"], []).append(obj)
    solos = []
    for name, objs in by_solo.items():  # pieces sharing a solo name move together
        role = objs[0]["role"]
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.active_object
        obj.name = name
        obj.data.name = name
        obj["role"] = role
        solos.append(obj)
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
    return joined + solos


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


def render(path, objs, lineup=False, from_front=False, distance=None):
    for obj in objs:
        obj.data.materials.clear()
        obj.data.materials.append(material(obj.get("role", obj.name.split(".")[0])))
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
    # Default camera: front-right of a +Z-facing model; from_front: of a -Z-facing one.
    direction = Vector((0.55, 1.0 if from_front else -1.0, 0.55)).normalized()
    cam.location = centre + direction * radius * (distance or (2.6 if not lineup else 2.9))
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


