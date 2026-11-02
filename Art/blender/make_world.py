"""Detailed smooth low-poly WORLD models: vehicles, trees, mountains, street and
drive-thru props. Shared helpers: lowpoly.py.

Run with Blender's Python module (pip install bpy):
    python Art/blender/make_world.py [out_dir] [--no-render] [--only Name,Name]

Outputs (default Art/World): <Name>.fbx, <Name>.png, lineup_*.png and
world.json (each model's size/centre in Roblox studs, its front direction, its
colour roles and its moving parts).

Moving parts are separate meshes with fixed names so the game can animate them:
    Wheel*/Hub*   spin around their own X axis (vehicles)
    RearDoor      rolls up (truck)
    Leaves*       sway gently (trees, bushes)
    Window        slides sideways (drive-thru kiosk)
    Bulb          glows at night (street lamp, kiosk, menu board)
    SignBoard     blank board the game writes text on (SurfaceGui)
Vehicles face Roblox -Z (like World/Vehicles); everything else faces +Z (street).
"""

import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly as lp  # noqa: E402
from lowpoly import ball, box, cut, cutter_box, cyl, torus  # noqa: E402

import bpy  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ONLY = None
if "--only" in sys.argv:
    ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(","))
ARGS = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] != "--only"]
OUT = ARGS[0] if ARGS else os.path.join(ROOT, "World")
RENDER = "--no-render" not in sys.argv
os.makedirs(OUT, exist_ok=True)

lp.ROLE_COLORS.update({
    "Tire": (0.16, 0.15, 0.17), "Hub": (0.85, 0.87, 0.9), "Light": (1.0, 0.95, 0.7),
    "TailLight": (1.0, 0.25, 0.25), "Cargo": (1.0, 0.72, 0.82), "Rock": (0.55, 0.53, 0.6),
    "RockDark": (0.42, 0.4, 0.48), "Snow": (0.97, 0.98, 1.0), "Grass": (0.45, 0.78, 0.36),
    "Trunk": (0.55, 0.36, 0.24), "Pine": (0.2, 0.55, 0.38), "PineDark": (0.14, 0.45, 0.3),
    "Cardboard": (0.85, 0.65, 0.45), "Ribbon": (1.0, 0.36, 0.62), "Cone": (1.0, 0.5, 0.15),
    "Window": (0.75, 0.9, 1.0), "Bulb": (1.0, 0.92, 0.6), "SignBoard": (1.0, 1.0, 1.0),
    "Leaves": (0.42, 0.78, 0.38), "LeavesDark": (0.3, 0.62, 0.3), "Flower": (1.0, 0.5, 0.7),
})


def solo(obj, name):
    obj["solo"] = name
    return obj


def tilt(obj, rx=0.0, ry=0.0, rz=0.0):
    """Rotate an already-built object about its own centre (degrees, Roblox axes:
    X, Y up, Z). Pieces are built with their origin at the world origin, so move
    the origin to the piece first, or it would swing round the world centre."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.rotation_euler = (math.radians(rx), math.radians(rz), math.radians(ry))
    bpy.ops.object.transform_apply(rotation=True)
    obj.select_set(False)
    return obj


def wheel(prefix, d, w, pos):
    cyl("Tire", d, w, pos, axis="X", verts=16, bevel=0.12)
    tire = bpy.context.active_object
    solo(tire, f"Wheel{prefix}")
    hub = cyl("Hub", d * 0.5, w + 0.06, pos, axis="X", verts=10, bevel=0.04)
    solo(hub, f"Hub{prefix}")
    # hub cap star: 4 spokes, part of the hub so they spin with it
    for a in range(4):
        spoke = box("Hub", (w + 0.08, d * 0.08, d * 0.42), pos, bevel=0.01)
        tilt(spoke, rx=a * 45)
        solo(spoke, f"Hub{prefix}")


# ------------------------------------------------------------------ vehicles (front -Z)


def car():
    box("Body", (4.2, 1.4, 7.4), (0, 1.25, 0), bevel=0.6, segments=3)
    box("Body", (3.9, 0.5, 2.3), (0, 2.0, -2.4), bevel=0.25)  # hood
    box("Body", (3.9, 0.5, 1.6), (0, 2.0, 2.85), bevel=0.25)  # trunk lid
    # Cabin with real window openings; the glass sits just inside them.
    cabin = box("Body", (3.7, 1.55, 3.6), (0, 2.9, 0.4), bevel=0.45, segments=3)
    cut(cabin, cutter_box((4.0, 0.95, 1.45), (0, 2.95, -0.35)))  # front side windows (through both sides)
    cut(cabin, cutter_box((4.0, 0.95, 1.2), (0, 2.95, 1.25)))  # rear side windows
    cut(cabin, cutter_box((3.0, 0.95, 4.2), (0, 2.95, 0.4)))  # windscreen + back window
    box("Glass", (3.5, 0.98, 3.3), (0, 2.95, 0.4), bevel=0.1)  # one glass block inside the openings
    box("Body", (3.7, 0.18, 0.3), (0, 2.95, 0.48), bevel=0.05)  # B-pillar band across the roof line
    for x in (-1.86, 1.86):
        box("Trim", (0.12, 0.08, 6.6), (x * 1.13, 1.55, 0), bevel=0.02)  # side trim line
        box("Body", (0.35, 0.25, 0.5), (x * 1.13, 2.65, -1.25), bevel=0.08)  # mirror
        box("Dark", (0.08, 0.12, 0.45), (x * 1.13, 1.9, 0.4), bevel=0.02)  # door handle
    for z, role in ((-3.66, "Trim"), (3.66, "Trim")):
        box(role, (4.3, 0.5, 0.45), (0, 0.85, z), bevel=0.2)  # bumpers
    box("Dark", (2.2, 0.55, 0.08), (0, 1.45, -3.72), bevel=0.04)  # grille
    for i in range(4):
        box("Metal", (2.0, 0.05, 0.1), (0, 1.25 + i * 0.13, -3.75), bevel=0.0)
    for x in (-1.4, 1.4):
        ball("Light", 0.6, (x, 1.6, -3.62), subdivisions=2, flat=False, squash=0.8)
        box("TailLight", (0.7, 0.35, 0.1), (x, 1.65, 3.72), bevel=0.05)
    box("Trim", (1.2, 0.4, 0.05), (0, 1.15, 3.92), bevel=0.02)  # number plate
    for x in (-1.95, 1.95):
        for z, tag in ((-2.4, "F"), (2.4, "B")):
            wheel(("L" if x < 0 else "R") + tag, 1.5, 0.7, (x, 0.75, z))


def delivery_truck():
    box("Dark", (5.2, 0.8, 13.0), (0, 1.55, 0), bevel=0.2)  # chassis
    cab = box("Body", (5.4, 3.8, 4.0), (0, 3.85, -4.65), bevel=0.75, segments=3)
    del cab
    box("Body", (5.0, 0.6, 3.2), (0, 5.95, -4.4), bevel=0.3)  # cab roof cap
    ws = box("Glass", (4.6, 1.7, 0.12), (0, 4.75, -6.6), bevel=0.06)
    tilt(ws, rx=-12)
    for x in (-2.72, 2.72):
        box("Glass", (0.12, 1.5, 1.9), (x, 4.8, -5.0), bevel=0.05)
        box("Dark", (0.06, 2.6, 0.06), (x, 3.6, -3.75), bevel=0.0)  # door seam
        box("Body", (0.4, 0.9, 0.3), (x * 1.12, 4.6, -6.1), bevel=0.1)  # mirror
        box("Metal", (0.8, 0.15, 0.9), (x * 0.95, 1.9, -4.6), bevel=0.04)  # step
        cyl("Metal", 0.9, 2.2, (x * 0.85, 1.6, -1.2), axis="Z", verts=12)  # fuel tank
    grille = box("Metal", (3.8, 1.2, 0.2), (0, 2.75, -6.72), bevel=0.1)
    del grille
    for i in range(5):
        box("Dark", (3.4, 0.08, 0.08), (0, 2.3 + i * 0.22, -6.84), bevel=0.0)
    box("Trim", (5.6, 0.55, 0.5), (0, 1.65, -6.85), bevel=0.2)  # front bumper
    for x in (-2.0, 2.0):
        ball("Light", 0.75, (x, 2.9, -6.78), subdivisions=2, flat=False, squash=0.7)
    # Cargo box with a bakery livery
    box("Cargo", (5.8, 5.8, 8.8), (0, 5.2, 2.1), bevel=0.45, segments=3)
    box("Trim", (5.95, 0.3, 8.95), (0, 8.05, 2.1), bevel=0.12)  # roof rim
    box("Accent", (5.95, 0.55, 8.6), (0, 3.15, 2.1), bevel=0.15)  # stripe
    for side in (-1, 1):
        x = side * 2.93
        box("Trim", (0.08, 3.0, 5.6), (x, 5.6, 2.1), bevel=0.06)  # logo panel
        # cake emblem: three tiers and a cherry
        for i, w in enumerate((2.4, 1.8, 1.2)):  # flat tiles: a three-tier cake
            box("Accent", (0.12, 0.5, w), (x + side * 0.1, 4.6 + i * 0.6, 2.1), bevel=0.05)
            box("Trim", (0.13, 0.12, w * 0.9), (x + side * 0.11, 4.82 + i * 0.6, 2.1), bevel=0.02)  # icing line
        ball("TailLight", 0.45, (x + side * 0.2, 6.35, 2.1), subdivisions=2, flat=False)
    door = box("Door", (5.0, 5.2, 0.2), (0, 5.1, 6.55), bevel=0.08)
    for i in range(6):
        cut(door, cutter_box((4.9, 0.08, 0.1), (0, 2.85 + i * 0.85, 6.66)))
    solo(door, "RearDoor")
    box("Metal", (5.4, 0.3, 0.6), (0, 2.25, 6.75), bevel=0.08)  # rear bumper
    for x in (-2.3, 2.3):
        box("TailLight", (0.6, 0.6, 0.15), (x, 2.75, 6.72), bevel=0.06)
        box("Dark", (0.9, 0.9, 0.08), (x * 0.95, 1.05, 5.9), bevel=0.02)  # mud flaps
    wheel("LF", 1.9, 0.9, (-2.4, 0.95, -4.4))
    wheel("RF", 1.9, 0.9, (2.4, 0.95, -4.4))
    for z, tag in ((3.0, "B1"), (4.75, "B2")):
        wheel("L" + tag, 1.9, 0.9, (-2.4, 0.95, z))
        wheel("R" + tag, 1.9, 0.9, (2.4, 0.95, z))


# ------------------------------------------------------------------ nature (front +Z)


def round_tree(seed=1):
    rng = random.Random(seed)
    cyl("Trunk", 1.9, 6.5, (0, 3.25, 0), verts=8, bevel=0.12, r2=1.2)
    for a in (40, 200, 300):  # short branches reaching into the canopy
        b = cyl("Trunk", 0.7, 2.6, (0, 0, 0), verts=6, bevel=0.0, r2=0.45)
        tilt(b, rx=45)
        tilt(b, ry=a)
        b.location = lp.rb(math.sin(math.radians(a)) * 0.9, 6.4, math.cos(math.radians(a)) * 0.9)
    for i in range(5):
        ang = i * math.tau / 5 + rng.random()
        r = 1.6 + rng.random()
        leaf = ball("Leaves" if i % 2 == 0 else "LeavesDark", 3.6 + rng.random() * 1.6, (math.cos(ang) * r, 7.4 + rng.random() * 1.5, math.sin(ang) * r), subdivisions=1)
        solo(leaf, "Leaves" if i % 2 == 0 else "LeavesDark")
    top = ball("Leaves", 4.6, (0, 9.3, 0), subdivisions=1)
    solo(top, "Leaves")
    for i in range(3):  # roots
        root = box("Trunk", (0.5, 0.4, 1.4), (math.cos(i * 2.1) * 0.8, 0.2, math.sin(i * 2.1) * 0.8), bevel=0.15)
        tilt(root, ry=math.degrees(-i * 2.1) + 90)


def pine_tree():
    cyl("Trunk", 1.0, 3.0, (0, 1.5, 0), verts=7, bevel=0.08, r2=0.7)
    tiers = ((5.6, 3.4, 3.2), (4.6, 3.0, 5.3), (3.5, 2.7, 7.2), (2.3, 2.4, 9.0))
    for i, (d, h, y) in enumerate(tiers):
        role = "Leaves" if i % 2 == 0 else "LeavesDark"
        tier = cyl(role, d, h, (0, y, 0), verts=8, bevel=0.0, r2=0.15)
        tilt(tier, ry=i * 22)
        solo(tier, role)
    star = ball("Light", 0.5, (0, 10.4, 0), subdivisions=1)
    star["role"] = "Leaves"
    solo(star, "Leaves")


def bush():
    for i, (x, y, z, d) in enumerate(((0, 1.0, 0, 2.6), (1.1, 0.8, 0.4, 1.9), (-1.0, 0.85, -0.3, 2.0), (0.2, 1.6, -0.6, 1.6))):
        b = ball("Leaves" if i % 2 == 0 else "LeavesDark", d, (x, y, z), subdivisions=1)
        solo(b, "Leaves" if i % 2 == 0 else "LeavesDark")
    for x, y, z in ((0.6, 2.0, 0.8), (-0.8, 1.7, 0.6), (1.4, 1.4, -0.2)):
        f = ball("Flower", 0.4, (x, y, z), subdivisions=1)
        solo(f, "Flowers")  # sway with the bush


def mountain(peaks, seed):
    """Faceted low-poly mountain: rock cones with snow caps on a grassy skirt."""
    rng = random.Random(seed)
    cyl("Grass", 150, 8, (0, 4, 0), verts=9, bevel=0.0, r2=128)
    for (x, z, r, h) in peaks:
        rock = cyl("Rock", r * 2, h, (x, h / 2 + 6, z), verts=7, bevel=0.0, r2=0.1)
        tilt(rock, ry=rng.random() * 50)
        # darker ridge faces: a slightly rotated, slightly smaller twin
        ridge = cyl("RockDark", r * 1.9, h * 0.97, (x + 1, h / 2 + 6, z - 1), verts=5, bevel=0.0, r2=0.1)
        tilt(ridge, ry=rng.random() * 70 + 15)
        cap_h = h * 0.32
        snow = cyl("Snow", r * 2 * 0.34 * 1.07, cap_h, (x, 6 + h - cap_h / 2 - 0.4, z), verts=7, bevel=0.0, r2=0.1)
        tilt(snow, ry=rng.random() * 50)
    for _ in range(10):  # boulders on the skirt
        ang = rng.random() * math.tau
        dist = 55 + rng.random() * 12
        ball("RockDark", 5 + rng.random() * 6, (math.cos(ang) * dist, 7, math.sin(ang) * dist), subdivisions=1)


def mountain_a():
    mountain(((0, 0, 50, 95),), 3)


def mountain_b():
    mountain(((-18, 5, 40, 80), (22, -6, 34, 64)), 8)


def hill():
    h = ball("Grass", 60, (0, 0, 0), subdivisions=2, squash=0.35)
    del h
    for i in range(6):
        ang = i * math.tau / 6
        b = ball("LeavesDark", 5, (math.cos(ang) * 18, 6 + (i % 2) * 2, math.sin(ang) * 18), subdivisions=1)
        b["role"] = "LeavesDark"


# ------------------------------------------------------------------ street & drive-thru (front +Z)


def street_lamp():
    cyl("Dark", 1.4, 0.6, (0, 0.3, 0), verts=10, bevel=0.15, r2=1.0)
    cyl("Dark", 0.45, 10.0, (0, 5.4, 0), verts=10, bevel=0.0)
    torus("Dark", 0.25, 0.12, (0, 10.6, 0.25), axis="X", major_seg=16, minor_seg=6)
    arm = cyl("Dark", 0.3, 2.6, (0, 10.9, 1.4), axis="Z", verts=8, bevel=0.0)
    del arm
    cyl("Accent", 1.6, 0.5, (0, 10.75, 2.6), verts=12, bevel=0.15, r2=0.9)  # shade
    bulb = ball("Bulb", 0.8, (0, 10.35, 2.6), subdivisions=2, flat=False)
    solo(bulb, "Bulb")
    for y in (3.0, 3.6):  # decorative rings
        torus("Accent", 0.3, 0.08, (0, y, 0), major_seg=12, minor_seg=6)
    box("Trim", (1.6, 0.9, 0.1), (0, 6.5, 0.28), bevel=0.05)  # little banner
    box("Accent", (1.4, 0.7, 0.12), (0, 6.5, 0.3), bevel=0.04)


def drive_thru_kiosk():
    # Booth facing +X (the lane side), like ItemBuilders.DriveThru's kiosk.
    box("Body", (3.0, 6.4, 7.4), (0, 3.2, 0), bevel=0.5, segments=3)
    frame = box("Trim", (0.3, 3.0, 4.2), (1.5, 3.7, 0), bevel=0.12)
    cut(frame, cutter_box((1.0, 2.4, 3.6), (1.5, 3.7, 0)))
    win = box("Window", (0.12, 2.3, 1.75), (1.45, 3.7, -0.85), bevel=0.04)
    solo(win, "Window")
    box("Glass", (0.1, 2.3, 1.75), (1.4, 3.7, 0.85), bevel=0.04)
    box("Accent", (1.4, 0.25, 4.3), (2.0, 2.4, 0), bevel=0.08)  # serving ledge
    for i in range(7):  # striped canopy over the window
        role = "Accent" if i % 2 == 0 else "Trim"
        stripe = box(role, (2.6, 0.18, 0.62), (2.3, 5.75, -1.86 + i * 0.62), bevel=0.04)
        tilt(stripe, rz=-14)
    for i in range(7):
        ball("Accent" if i % 2 == 0 else "Trim", 0.62, (3.55, 5.38, -1.86 + i * 0.62), subdivisions=1)
    box("Trim", (3.4, 0.45, 7.8), (0, 6.6, 0), bevel=0.2)  # roof
    sign = box("SignBoard", (0.2, 1.1, 5.0), (1.6, 6.0, 0), bevel=0.08)
    solo(sign, "SignBoard")
    # Giant cupcake on the roof
    cyl("Cargo", 2.0, 1.4, (0, 7.6, 0), verts=12, bevel=0.1, r2=2.6)
    for i, (d, y) in enumerate(((2.8, 8.6), (2.2, 9.2), (1.5, 9.75))):
        ball("Trim" if i % 2 == 0 else "Cargo", d, (0, y, 0), subdivisions=2, flat=False, squash=0.6)
    ball("TailLight", 0.55, (0, 10.25, 0), subdivisions=2, flat=False)
    bulb = ball("Bulb", 0.5, (1.7, 5.2, 2.2), subdivisions=1)
    solo(bulb, "Bulb")


def menu_board():
    for z in (-1.8, 1.8):
        cyl("Dark", 0.3, 4.5, (0, 2.25, z), verts=8, bevel=0.0)
    box("Dark", (0.5, 3.4, 4.6), (0, 4.2, 0), bevel=0.2)
    board = box("SignBoard", (0.15, 2.9, 4.1), (0.27, 4.2, 0), bevel=0.06)
    solo(board, "SignBoard")
    roof = box("Accent", (1.6, 0.25, 5.2), (0.35, 6.05, 0), bevel=0.08)
    tilt(roof, rz=-10)
    # Order speaker on its own post in front
    cyl("Dark", 0.25, 3.0, (1.6, 1.5, 3.4), verts=8, bevel=0.0)
    box("Accent", (0.8, 1.1, 0.8), (1.6, 3.3, 3.4), bevel=0.25)
    grill = box("Dark", (0.06, 0.6, 0.6), (2.02, 3.35, 3.4), bevel=0.02)
    del grill
    bulb = ball("Bulb", 0.3, (2.02, 3.85, 3.4), subdivisions=1)
    solo(bulb, "Bulb")


def pallet_of_cakes():
    box("LightWood", (4.0, 0.2, 4.0), (0, 0.75, 0), bevel=0.04)
    for x in (-1.7, 0, 1.7):
        box("Wood", (0.6, 0.5, 4.0), (x, 0.35, 0), bevel=0.05)
    for x in (-1.6, 1.6):
        box("LightWood", (0.6, 0.15, 4.0), (x, 0.07, 0), bevel=0.03)
    rng = random.Random(4)
    for layer in range(2):
        for ix in range(2):
            for iz in range(2):
                y = 1.45 + layer * 1.3
                x, z = -0.95 + ix * 1.9, -0.95 + iz * 1.9
                box("Cardboard", (1.8, 1.25, 1.8), (x, y, z), bevel=0.06)
                box("Ribbon", (1.84, 1.27, 0.22), (x, y, z), bevel=0.02)
                box("Ribbon", (0.22, 1.27, 1.84), (x, y, z), bevel=0.02)
                ball("Ribbon", 0.35 + rng.random() * 0.1, (x, y + 0.7, z), subdivisions=1)


def traffic_cone():
    box("Dark", (1.6, 0.2, 1.6), (0, 0.1, 0), bevel=0.06)
    cyl("Cone", 1.3, 2.4, (0, 1.4, 0), verts=14, bevel=0.0, r2=0.25)
    for y, d in ((1.0, 1.06), (1.7, 0.75)):
        cyl("Trim", d, 0.3, (0, y, 0), verts=14, bevel=0.0, r2=d - 0.12)


def fire_hydrant():
    cyl("TailLight", 1.0, 2.2, (0, 1.1, 0), verts=12, bevel=0.1)
    cyl("TailLight", 1.3, 0.3, (0, 0.15, 0), verts=12, bevel=0.06)
    ball("TailLight", 1.0, (0, 2.25, 0), subdivisions=2, flat=False, squash=0.7)
    cyl("Metal", 0.3, 0.3, (0, 2.75, 0), verts=8, bevel=0.03)
    for x in (-0.65, 0.65):
        cyl("Metal", 0.45, 0.4, (x, 1.5, 0), axis="X", verts=10, bevel=0.05)
    cyl("Metal", 0.55, 0.4, (0, 1.4, 0.6), axis="Z", verts=10, bevel=0.05)


def bench():
    for i in range(3):
        box("Wood", (6.0, 0.2, 0.55), (0, 1.6, -0.7 + i * 0.65), bevel=0.06)
    back = box("Wood", (6.0, 0.55, 0.2), (0, 2.6, -1.05), bevel=0.06)
    del back
    box("Wood", (6.0, 0.55, 0.2), (0, 3.25, -1.05), bevel=0.06)
    for x in (-2.6, 2.6):
        box("Dark", (0.25, 1.6, 1.8), (x, 0.8, -0.2), bevel=0.08)
        box("Dark", (0.25, 2.0, 0.25), (x, 2.6, -1.15), bevel=0.06)
        arm = box("Dark", (0.3, 0.2, 1.7), (x, 2.2, -0.25), bevel=0.06)
        del arm


def trash_can():
    can = cyl("Accent", 1.7, 2.6, (0, 1.3, 0), verts=14, bevel=0.1, r2=1.9)
    cut(can, cyl("Accent", 1.5, 2.0, (0, 2.2, 0), verts=14, bevel=0.0, r2=1.7))
    for y in (0.6, 1.9):
        torus("Trim", 0.92, 0.08, (0, y, 0), major_seg=14, minor_seg=6)
    lid = cyl("Dark", 2.0, 0.25, (0, 2.7, 0), verts=14, bevel=0.06)
    del lid
    ball("Dark", 0.45, (0, 2.95, 0), subdivisions=1)


def mailbox():
    cyl("Dark", 0.35, 3.0, (0, 1.5, 0), verts=8, bevel=0.0)
    body = box("Sky" if False else "Accent", (1.3, 1.1, 2.0), (0, 3.3, 0), bevel=0.4, segments=3)
    del body
    flag = box("TailLight", (0.08, 0.6, 0.25), (0.7, 3.6, -0.4), bevel=0.02)
    solo(flag, "Flag")


MODELS = {
    # name: (builder, front, moving parts)
    "Car": (car, "-Z", ["Wheel*", "Hub*"]),
    "DeliveryTruck": (delivery_truck, "-Z", ["Wheel*", "Hub*", "RearDoor"]),
    "RoundTree": (round_tree, "+Z", ["Leaves", "LeavesDark"]),
    "PineTree": (pine_tree, "+Z", ["Leaves", "LeavesDark"]),
    "Bush": (bush, "+Z", ["Leaves", "LeavesDark", "Flowers"]),
    "MountainA": (mountain_a, "+Z", []),
    "MountainB": (mountain_b, "+Z", []),
    "Hill": (hill, "+Z", []),
    "StreetLamp": (street_lamp, "+Z", ["Bulb"]),
    "DriveThruKiosk": (drive_thru_kiosk, "+X", ["Window", "Bulb", "SignBoard"]),
    "MenuBoard": (menu_board, "+X", ["Bulb", "SignBoard"]),
    "PalletOfCakes": (pallet_of_cakes, "+Z", []),
    "TrafficCone": (traffic_cone, "+Z", []),
    "FireHydrant": (fire_hydrant, "+Z", []),
    "Bench": (bench, "+Z", []),
    "TrashCan": (trash_can, "+Z", []),
    "Mailbox": (mailbox, "+Z", ["Flag"]),
}

LINEUPS = {
    "vehicles": ["Car", "DeliveryTruck"],
    "nature": ["RoundTree", "PineTree", "Bush"],
    "mountains": ["MountainA", "MountainB", "Hill"],
    "street": ["StreetLamp", "DriveThruKiosk", "MenuBoard", "PalletOfCakes", "TrafficCone", "FireHydrant", "Bench", "TrashCan", "Mailbox"],
}

info = {}
info_path = os.path.join(OUT, "world.json")
if os.path.exists(info_path):
    with open(info_path) as f:
        info = json.load(f)

for name, (build, front, moving) in MODELS.items():
    if ONLY and name not in ONLY:
        continue
    lp.reset()
    build()
    objs = lp.join_roles()
    size, centre = lp.bounds_roblox(objs)
    info[name] = {
        "Size": size,
        "Centre": centre,
        "Front": front,
        "Roles": sorted({o.get("role", o.name) for o in objs}),
        "Moving": moving,
        "Faces": sum(len(o.data.polygons) for o in objs),
    }
    lp.export(os.path.join(OUT, f"{name}.fbx"), objs)
    print(f"exported {name}: {len(objs)} meshes, {info[name]['Faces']} faces")
    if RENDER:
        lp.render(os.path.join(OUT, f"{name}.png"), objs, from_front=(front == "-Z"))

with open(info_path, "w") as f:
    json.dump(info, f, indent=1)

if RENDER and not ONLY:
    from mathutils import Vector

    for sheet, names in LINEUPS.items():
        lp.reset()
        x = 0.0
        objs = []
        for name in names:
            before = set(bpy.context.scene.objects)
            MODELS[name][0]()
            new = [o for o in bpy.context.scene.objects if o not in before]
            lo = min((o.matrix_world @ Vector(v)).x for o in new for v in o.bound_box)
            hi = max((o.matrix_world @ Vector(v)).x for o in new for v in o.bound_box)
            for o in new:
                o.location.x += x - lo
            x += (hi - lo) * 1.15 + 2
            objs += new
        for o in objs:
            o.name = o.get("role", o.name)
        lp.render(os.path.join(OUT, f"lineup_{sheet}.png"), objs, lineup=True, from_front=(sheet == "vehicles"), distance={"vehicles": 2.4, "nature": 3.6}.get(sheet))
