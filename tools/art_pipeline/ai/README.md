# Optional local AI layer

Status: **disabled on the verified workstation**. The production-approved path is `reference images -> manual Blender blockout -> cleanup -> GLB -> Godot`.

No AI repository, Python environment, model weight, or cache is installed by these scripts. `setup_ai.ps1` and `setup_ai.sh` intentionally preserve that decision. `generate_blockout.py` exits without writing geometry so automation cannot silently treat a missing AI backend as a successful mesh generation.

## Re-evaluation order

1. TRELLIS: official upstream requires Linux, an NVIDIA GPU with at least 16 GB VRAM, and CUDA 11.8/12.2. It can export a textured GLB mesh. Model repository data is about 3.07 GiB before dependency caches.
2. InstantMesh: official setup recommends Python 3.10+, PyTorch 2.1+, CUDA 12.1, and exports OBJ with vertex colors or a texture map. The complete model repository is about 6.77 GiB; a typical large mesh path downloads roughly 3 GiB of reconstruction and multiview weights.
3. TripoSR: official default inference uses about 6 GB VRAM and outputs a reconstructed mesh (OBJ in the upstream CLI). Its model repository is about 1.56 GiB.

Do not add an adapter until all of these are true:

- the target workstation has a supported upstream acceleration path;
- code and checkpoint revisions are pinned;
- code, checkpoint, and transitive dependency licenses are reviewed separately;
- hashes or safe upstream revision identifiers are recorded;
- a synthetic image-to-mesh run records wall time and peak VRAM/RAM;
- the result is imported into Blender and treated only as blockout/reference geometry.

Single-image reconstruction is never authoritative for hidden geometry. Every generated mesh must pass the cleanup checklist in `docs/art_pipeline/WORKFLOW.md`.
