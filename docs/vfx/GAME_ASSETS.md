# game_assets → game: передача VFX-исходников и exports

`game_assets` — отдельный authoring проект. Здесь остаются gameplay, timings,
attachment, shaders/presentation и реальная камера. Не связывай игру symlink с
чужой рабочей копией; runtime получает зафиксированную копию declared exports.

```powershell
python tools/vfx_workbench.py assets list --repo ../game_assets
```

Команда читает реальные `manifest.json`, выбирает `type: "vfx"` и показывает
наличие quality/evidence/review без приписывания approval. На 2026-09-30 в
проверенном `D:/Repository/game_assets` таких пакетов **пока нет**. Старые UI/
3D exports не переименованы в VFX и не объявлены прошедшими новым gate.

## Задание для authoring-проекта

Работающий там агент сначала читает его AGENTS/GEMINI и docs/QUALITY_GATE.md.
Создать пакет можно его существующей командой:

```powershell
# Выполняется ИЗ game_assets, не из game.
python tools/new_asset.py vfx my_effect_masks --type vfx
```

В `request.md` передай intended sensation, material language, silhouette,
required textures/mesh, alpha/UV direction/scale/pivot и ссылку на одобренный
brief игры. В `quality.json` замени voxel starter recipe на реальный VFX build;
укажи все source/dependencies, exports и фактические review media. Заполни
конкретные criteria и исходное происхождение/лицензии. `manifest.outputs` —
объект путей **относительно package**, например:

```json
{"paint": "output/slash.png", "smoke": "output/smoke.png", "mesh": "output/ribbon.glb"}
```

Не копируй шаблонные значения, утверждённые references и art verdicts на новый
ассет автоматически. Source изменяет authoring; build читает source. В фабрике:

```powershell
python tools/quality_gate.py build assets/vfx/my_effect_masks
python tools/quality_gate.py check assets/vfx/my_effect_masks --require-review
python tools/quality_gate.py verify-clean assets/vfx/my_effect_masks
```

Записанный visual review связан с current evidence digest. Он не заменяет
gameplay review. Если в фабрике есть только mockup, это должно оставаться
`mockup_only`, а не автоматически `checked`.

## Копирование в игру

Для свежей сборки, **ещё без записанного visual review**, доступны локальные trials:

```powershell
python tools/vfx_workbench.py assets import assets/vfx/my_effect_masks --candidate --license-note "Source authored for Cube Siege; rights documented in upstream request.md"
```

Candidate идёт только в `screenshots_debug/vfx_workbench/assets/`; его статус
`CANDIDATE_ONLY`. Build receipt обязан быть текущим даже у candidate.
Для пакета с актуальным записанным visual review убери `--candidate`:
копия появится в `assets/vfx/imported/<name>/` со статусом
`UPSTREAM_REVIEW_RECORDED; NEEDS_GAME_VALIDATION`. Это не художественный approved.
Заметка о правах должна отражать реальный источник; пример не подходит внешним
ассетам автоматически. `--repo` принимает другой явный checkout, `--name` —
новое имя delivery. Existing destination никогда не перезаписывается.

Bridge дважды запускает существующий upstream `quality_gate.py check`
(для runtime delivery с `--require-review`), копирует **только manifest outputs**
и сохраняет SHA256 receipt, quality/manifest/request/evidence/visual-review snapshots.
Он не выполняет authoring/build и не меняет соседний репозиторий. Никакие source
scripts, binaries или произвольные Godot resources не импортируются: `.tres`/
`.gdshader` требуют явного решения dependencies/res://paths. Поддерживаются
PNG/JPEG/WebP, WAV/OGG, GLB, JSON/TXT data. GLB с внешними зависимостями требует
переэкспорта в self-contained delivery. Лицензии фиксируются автором в источнике
и импортёром в `license_note`; bridge не устанавливает юридическое право сам.

Затем импорт Godot, привязка через новый local art profile, actual entry-point
capture и сравнение с baseline. Default gameplay не меняется от одного импорта.
Повторный export получает новый delivery name; локально изменённый файл не
будет затёрт обновлением фабрики. Изменения dirty entrypoints/review loop чужого
проекта остаются вне этой задачи.
