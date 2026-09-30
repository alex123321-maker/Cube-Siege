---
trigger: glob
globs: "scripts/vfx/**,assets/vfx/**,tools/vfx_*.py,tools/capture_*pilot.gd,tools/capture_cleave.gd"
description: "Gameplay VFX: production examples, true footprint, body anatomy and evidence."
---

Начни с `docs/vfx/START_HERE.md` и `python tools/vfx_workbench.py catalog`.
Бери ближайший production preset; новый art trial не меняет default до проверки.
Физическая способность требует различимой работы тела и двух pose видов без VFX.
Сначала проверь imported local forward/wrapper, затем плечо/руку/оружие в движении.
Footprint берётся из реальной damage geometry; contact — только из confirmed hit.
Preview PNG и fixed-fps movie не доказывают real-time performance или art approval.
Запиши fresh coverage, конкретные наблюдения и skipped условия; сравни с basic,
когда способность должна отличаться от него. Bridge `game_assets` копирует declared
data exports с исходным quality status, не меняет источник и не определяет gameplay.
