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

## Detailed item models

`Models/<Id>.fbx` are detailed models for placeable items, made by
`blender/make_models.py`: **Oven, Mixer, IngredientCrate (pantry), DisplayCounter,
CafeTable, PottedPlant**. Previews: `Models/<Id>.png` and `Models/lineup.png`.

Each file holds one mesh per colour role (Body, Trim, Accent, Metal, ...); the game
colours them from its palette, rescales them to the right size and lines them up
with the item (`World/Skins`), so import settings don't matter. The item's old
block model stays underneath, invisible, so gameplay is unchanged.

### Import into Studio (once per model)

1. In `ServerStorage > Assets`, create a folder named `Models`.
2. File > Import 3D, pick e.g. `Art/Models/Oven.fbx`, click Import.
3. Rename the imported Model to exactly the file name without `.fbx`
   (`Oven`, `Mixer`, `IngredientCrate`, `DisplayCounter`, `CafeTable`, `PottedPlant`)
   and drag it into `ServerStorage > Assets > Models`.
4. Ctrl+S, then playtest. Items placed from now on use the new model (place or
   re-place existing ones, or rejoin, to see them).

Studio's importer turns these models around; `Config.Skins.ImportYaw = 180` in
`ReplicatedStorage/Shared/ConfigParts/Build.luau` turns them back (confirmed in Studio).

### Regenerate or tweak

```
python Art/blender/make_models.py            # exports + renders
python Art/blender/make_models.py --no-render
```

Each item is one function in the script (`oven()`, `mixer()`, ...). After changing
sizes, copy the new numbers from `Models/models.json` into `World/Skins.Defs`
(`Size`, `Centre`), then re-import that `.fbx`.
