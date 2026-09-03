# /create-asset

Workflow for creating and exporting 3D assets:

1. **Art Rules**: Inspect style guide in `blockbench-asset`.
2. **References**: Inspect existing models in `assets/models/characters/`.
3. **Blockbench Authoring**: Edit or create `.bbmodel` preserving canonical source, origin, and scale.
4. **Multi-Angle Screenshots**: Capture isometric, front, and profile views.
5. **Export**: Export game-ready asset.
6. **Import Godot**: Run headless import `godot --headless --editor --quit`.
7. **In-Game Check**: Validate materials, lighting, and animations in Godot scene.
