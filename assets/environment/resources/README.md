# Resource node production exports

These Godot-ready GLB exports are copied from the sibling `game_assets` repository at commit `2e896cf314b89958189e273ac3491ddea71397d7`.

## Tree family

`tree_oak/tree_0_standard_oak.glb` through `tree_4_shrub_oak.glb` preserve the `ResourceTree.tree_variation` mapping 0–4.

## Rock family

The destructible stone family is exported to `rock_stage1/` through `rock_stage5/` using the progression 6 / 3 / 3 / 2 / 3. Files use zero-based runtime names (`rock_stageN_var_0.glb`, etc.) mapped from the asset package's one-based variant names.

`ResourceRock.variation_index` selects the intact Stage 1 silhouette. Its stable per-cell seed selects independent variants for Stages 2–5. Every imported model is anchored at its bottom center before display so stage swaps keep ground contact fixed.

The exported GLB files are the only runtime assets required by the game. Source voxel packages, build tools, review images, and the asset repository itself are not runtime dependencies.
