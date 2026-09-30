# Библиотека и безопасные начальные варианты

Сначала используй рабочие production-компоненты. Они содержат больше полезного
контекста, чем изолированный shader из интернета. `catalog` указывает реальные
profile/effect/harness/test/evidence и проверяет их наличие через `doctor`.

| Нужна часть эффекта | Образец и способ использования |
| --- | --- |
| Full-body melee ability, footprint, local hit cuts | `cleave`: `CleaveVFX`, `CleaveVFXProfile`, `WarriorCleaveSpec`; события в PlayerCombat, анимация в PlayerPresentation. |
| След по настоящему лезвию | `SwordBladeTrail`: resolved SwordGuard/SwordTip, world history, emission window и reset; нельзя заменять произвольным arc tween. |
| Обычный меч | `sword`: art trial меняет параметры painting/edge/shards/contact; тайминг и damage не задаёт. |
| Взрыв с дымом/почвой | `mine`: `MineExplosionVFX.setup(profile, actual_radius)`; radius приходит от gameplay. |
| Снаряд попал в врага или terrain | `archer`: `ArrowImpactVFX`, incoming direction и confirmed surface event. |
| Маленький тёплый contact accent | `scenes/vfx/library/warm_contact.tscn`: ready one-shot prefab, прозрачный flare с умеренным emission. |
| Короткий supporting dust | `scenes/vfx/library/soft_dust.tscn`: one-shot sprite с rise/expansion/drift, без light и collision. |

Последние два prefab — **начальные подчинённые акценты для настройки в production**,
не готовая способность и не проверенные во всех игровых условиях presets. Они не
меняют production cleave. Preview: `python tools/vfx_workbench.py capture stamps`.
Он показывает isolated компоненты и cleanup, а не gameplay-quality certification.
Создай новую Resource/scene для варианта; shared `.tres` не изменяй во время effect.
`VFXStamp3D` имеет per-instance material и один delta clock; wall timer не нужен.
Billboard сохраняет depth test: перенос внутрь меша target может скрыть акцент.
Позицию выбирает вызывающий код по contact/bounds и направлению; не называй
приближённое surface placement точным физическим контактом.

Пример **в уже подтверждённом hit callback**, не при каждом cast:

```gdscript
const CONTACT: PackedScene = preload("res://scenes/vfx/library/warm_contact.tscn")

func show_confirmed_contact(effect_parent: Node3D, target: Node3D, surface: Vector3) -> void:
    var accent: VFXStamp3D = CONTACT.instantiate() as VFXStamp3D
    effect_parent.add_child(accent)
    accent.global_position = surface
    accent.bind_target(target)
```

Если нужен общий счётчик нагрузки, зарегистрируй effect существующим
`VFXManager.register_effect(accent)`; stamp сам завершает lifecycle. Не добавляй
второй timeout и не делай библиотеку владельцем damage. Camera shake и recoil
подключай по задаче, не ко всем particle sprites автоматически.

## Локальные bitmap masks

Шесть PNG из [Kenney Particle Pack](https://kenney.nl/assets/particle-pack)
сохранены **без изменений** в `assets/vfx/library/kenney/`. Авторская лицензия
CC0 находится в `License.txt`; `PROVENANCE.json` хранит download URL, дату и
SHA256 архива/файлов. Runtime не требует интернет-доступа. Их смысл:

| Файл | Для чего пробовать |
| --- | --- |
| flare_01.png | Короткий contact, основная световая точка; не заливать им весь target. |
| smoke_01.png | Непрозрачность умеренная, supporting dust/smoke tail. |
| slash_02.png | Мягкий crescent mask; full-ability shape и body animation всё равно нужны. |
| circle_05.png | Soft glow mask, не точный damage radius/telegraph. |
| muzzle_01.png | Направленный всплеск: правильно повернуть UV/mesh относительно источника. |
| spark_06.png | Lightning mask, не metal spark; применять только при подходящем утверждённом языке материала. |

Текстуры имеют белые значения и alpha. Цветовая tint-модуляция — отдельное art
решение. При импорте нужны mipmaps и smooth alpha; не использовать чёрный фон как
alpha. Не смешивай sRGB художественного цвета с linear data maps. Geometry/depth,
texture coverage, размер с обычной камеры и material response проверяются в игре.

## Полка первичных референсов

- [Riot: Visual Effects](https://www.riotgames.com/en/artedu/visual-effects): читаемость,
  тема и ограничения яркости; assets Riot не включены в библиотеку.
- [Cyanilux: Sword Slash](https://www.cyanilux.com/tutorials/sword-slash-shader-breakdown/):
  prepared mesh + moving masks, Unity пример; способ материала не решает анатомию.
- [Godot 4.6 Movie Maker](https://docs.godotengine.org/en/4.6/tutorials/animation/creating_movies.html):
  offline запись/форматы; fixed-fps клип не используется для оценки FPS.

Ссылки и лицензия Kenney проверены 2026-09-30. Полка — адресные источники для
конкретного вопроса, не большой список, который слабая модель должна прочитать целиком.
Для собственного raster source используй доступный imagegen/bridge по его контракту
и сохрани prompt/provenance, как у `assets/vfx/cleave/PROMPT.md`.
