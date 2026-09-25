# Resource node production exports

These Godot-ready GLB exports are copied from the sibling `game_assets` repository at commit `2e896cf314b89958189e273ac3491ddea71397d7`.

## Tree family

`tree_oak/tree_0_standard_oak.glb` through `tree_4_shrub_oak.glb` preserve the `ResourceTree.tree_variation` mapping 0–4.

## Rock family

`rock_stage1/rock_stage1_var_0.glb` through `rock_stage1_var_5.glb` are the six intact Stage 1 variants. `ResourceRock.variation_index` selects one of these meshes.

The exported GLB files are the only runtime assets required by the game. Source voxel packages, build tools, review images, and the asset repository itself are not runtime dependencies.
