# Art

## Shapes (smooth low-poly look)

`Shapes/RoundedBox.fbx`, `Shapes/Cylinder.fbx`, `Shapes/Ball.fbx` are the three base
shapes almost everything in the game is built from (`World/Style`: rounded boxes,
cylinders, balls). Each is 1 x 1 x 1 stud; the game resizes and colours them, so
these three files restyle every machine, sign, plant, table and tree at once.
`Shapes/preview.png` shows before (left) and after (right).

### Import into Studio (once)

1. In Explorer, make sure `ServerStorage` has a folder `Assets`, and inside it a
   folder named `Shapes` (create them if missing).
2. File > Import 3D, pick `Art/Shapes/RoundedBox.fbx`. In the importer keep the
   defaults and click Import.
3. The import lands in Workspace. Rename it to exactly `RoundedBox` and drag it
   into `ServerStorage > Assets > Shapes`. (A Model holding the MeshPart is fine.)
4. Repeat for `Cylinder.fbx` (name it `Cylinder`) and `Ball.fbx` (name it `Ball`).
5. Press Ctrl+S to save the place, then start a playtest.

Missing shapes are fine: the game falls back to the plain shapes it used before.

### Regenerate or tweak

```
pip install bpy
python Art/blender/make_shapes.py
```

Bevel sizes, side counts and the faceted ball are at the top of
`blender/make_shapes.py` (`make_rounded_box`, `make_cylinder`, `make_ball`).
After regenerating, re-import the changed `.fbx` and replace the old one in
`ServerStorage > Assets > Shapes`.
