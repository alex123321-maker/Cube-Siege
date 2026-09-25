# Environment Dressing Pack Family

This package contains 19 canonical, reusable stylized voxel dressing props authored for Cube Siege (Issue #7).

## Subfamilies
1. **Grass Tufts (6 variants)**:
   - `grass_tuft_small_01`: Compact 2-blade sprig
   - `grass_tuft_small_02`: Asymmetric 3-blade fan
   - `grass_tuft_small_03`: Tight 4-blade clump
   - `grass_tuft_med_01`: Tiered 5-blade clump
   - `grass_tuft_med_02`: Wind-swept 6-blade spread
   - `grass_tuft_tall_01`: Tall accent focal clump
2. **Flowers (4 variants / color groups)**:
   - `flower_white_cluster`: White meadow daisies
   - `flower_yellow_cluster`: Sunny golden buttercups (compact dome)
   - `flower_red_cluster`: Crimson poppies (flared cup crown)
   - `flower_mixed_accent`: Rare lilac-blue bellflower (arching stalk)
3. **Moss / Low Vegetation (3 variants)**:
   - `moss_tree_base`: Curved trunk wrap collar
   - `moss_rock_shelf`: Rock crevice shelf
   - `moss_cliff_ledge`: Cascading terrace overhang
4. **Stone Debris (6 variants, Independent Darker Palette)**:
   - `stone_debris_single`: Faceted rectangular keystone shard
   - `stone_debris_trio`: Balanced 3-stone group
   - `stone_debris_flat_patch`: Interlocking slab patch
   - `stone_debris_angular_chip`: Sharp diagonal triangular cleave
   - `stone_debris_fine_scatter`: Gravel & grit spread
   - `stone_debris_mountain_cluster`: Stepped crag pile

## Shared Technical & Performance Features
- **Voxel Scale**: Uniform `voxel_size = 0.10`m.
- **Pivot / Origin**: 18 ground props strictly use `bottom_center` at ground level (z=0). `moss_cliff_ledge` is an intentional architectural exception using `edge_anchor` on the ledge surface plane (z=0), allowing negative vertical extent (down to -0.26m) for 3D hanging tendrils dripping over cliff rims.
- **Shared Production Material**: Unified 1-material export (`mat_dressing_atlas`) referencing `dressing_palette_atlas.png` and `dressing_roughness_atlas.png`.
- **MultiMesh Ready**: Exactly 1 mesh object and 1 material per prop, triangle counts 84-408 tris (average 226.2 tris, budget <= 500), no collisions, no scripts. Instanced via Godot MultiMesh without material switches.
- **Unified Palette**: `source/palette.json` and `textures/dressing_palette_atlas.png`.
