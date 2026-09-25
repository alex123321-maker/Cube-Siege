# Art pipeline dependency and model licensing

This inventory separates code licenses from model/checkpoint licenses. “Open-source code” never implies that every model weight, training dataset, add-on, or input image has the same terms. This is an engineering inventory, not legal advice.

## Approved dependencies

| Component | Upstream | Code license | Model/checkpoint license | Commercial game use / obligations | Status |
| --- | --- | --- | --- | --- | --- |
| Blender 5.2.1 LTS | https://www.blender.org/ and https://projects.blender.org/blender/blender | GPL-3.0-or-later for Blender | None | Art authored with Blender is not automatically GPL. If Blender itself is redistributed, comply with GPL source/license obligations. | Required, approved |
| Blender glTF 2.0 exporter | Bundled with Blender; https://docs.blender.org/manual/en/5.2/addons/import_export/scene_gltf2.html | Included in Blender distribution | None | GLB output is usable in the game; retain relevant notices only when redistributing the software. | Required, built-in |
| Godot 4.6.1 stable | https://github.com/godotengine/godot | MIT | None | Commercial use allowed; include the Godot copyright/license notice when distributing the engine in a game. | Existing required runtime |
| Cube Siege pipeline scripts | This repository | Repository license | None | Follow the repository license. | Approved |

No third-party Blender add-on is required. Modeling, UV editing, Texture Paint, Shader Editor, rigging, weight painting, Python scripting, and GLB export are built into Blender.

## Evaluated, not installed or approved on this workstation

| Candidate | Official source | Code license | Checkpoint/model license | Size and format | Commercial/output assessment | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| TRELLIS | https://github.com/microsoft/TRELLIS | MIT for the majority of code; bundled submodules carry separate licenses that must also be retained/reviewed | `microsoft/TRELLIS-image-large` model card declares MIT | Model repository approximately 3.07 GiB; outputs textured GLB meshes and PLY splats | MIT itself permits commercial use. Input/reference rights and separately licensed submodules still apply; no automatic claim that generated geometry is infringement-free. | Not installed: upstream requires Linux-tested NVIDIA GPU with at least 16 GB VRAM and CUDA |
| InstantMesh | https://github.com/TencentARC/InstantMesh | Apache-2.0 | `TencentARC/InstantMesh` model card declares Apache-2.0 | Full model repository approximately 6.77 GiB; typical large path roughly 3 GiB; outputs OBJ with vertex colors or texture map | Apache-2.0 permits commercial software use subject to license/notice terms. Upstream does not provide a warranty or clear title guarantee for generated content; input rights remain the user's responsibility. | Not installed: official environment uses CUDA 12.1/PyTorch CUDA |
| TripoSR | https://github.com/VAST-AI-Research/TripoSR | MIT | `stabilityai/TripoSR` model card declares MIT | Model repository approximately 1.56 GiB; upstream CLI outputs OBJ and reports about 6 GB VRAM at defaults | MIT permits commercial use; keep license notices when redistributing code/model. Generated output still requires input/IP review. | Not installed: no supported CUDA GPU; unofficial acceleration ports are out of scope |

Recorded model sizes were queried from the official Hugging Face model repository metadata on 2026-09-05 and exclude Python packages and some transitive caches. A future integration must pin exact repository/model revisions and record actual downloaded bytes.

## Required attribution and recordkeeping

- Blender/Godot/tool code: keep upstream copyright and license text when redistributing the software components.
- MIT or Apache model/code packages: retain their notices/license as required when distributing those packages or modified versions.
- Generated game assets: none of the reviewed tool licenses alone imposes a blanket credit line on every output, but this does not waive rights in input concepts, trademarks, training-derived content, or third-party materials.
- References: record creator, source URL/file, granted rights, and approval Issue next to each externally sourced concept sheet.

## Approval rule for future AI integration

An AI backend is not a production dependency until code license, every required checkpoint license, and relevant transitive/native dependency licenses are clear and compatible with commercial distribution. Unknown or missing terms mean **not approved**. Download models only from the author-designated repository/model host; prefer `safetensors` and never load untrusted pickle checkpoints from mirrors.

## Primary sources consulted

- Blender LTS/download: https://www.blender.org/download/lts/ and https://www.blender.org/download/
- Blender license: https://www.blender.org/about/license/
- Godot license: https://godotengine.org/license/
- Godot 4.6 asset orientation/export guidance: https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html
- TRELLIS requirements/code: https://github.com/microsoft/TRELLIS
- TRELLIS model card: https://huggingface.co/microsoft/TRELLIS-image-large
- InstantMesh code/requirements: https://github.com/TencentARC/InstantMesh
- InstantMesh model card: https://huggingface.co/TencentARC/InstantMesh
- TripoSR code/requirements: https://github.com/VAST-AI-Research/TripoSR
- TripoSR model card: https://huggingface.co/stabilityai/TripoSR
