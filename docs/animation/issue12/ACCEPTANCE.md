# Критерии #12

Источник: https://github.com/alex123321-maker/Cube-Siege/issues/12 .

Архитектурные пункты проверены по diff; численные/lifecycle — GUT; визуальные — кадры и записи из README. Отметки относятся к текущим трём ригам.


## Architecture

- [x] Система работает поверх gameplay-контракта #11 и не дублирует его calculations.
- [x] `PlayerPresentation` или отдельный presentation-component остаётся владельцем animation logic.
- [x] Gameplay не читает bone transforms/animation pose для определения movement/combat state.
- [x] Все три класса используют общую animation architecture.
- [x] Классовые различия задаются профилем/конфигурацией, а не тремя копиями logic.
- [x] Bone/node references кэшируются, отсутствуют per-frame scene searches.

## Directional locomotion

- [x] Движение вперёд визуально отличается от движения назад.
- [x] Strafe left/right визуально отличается от forward/backward.
- [x] Промежуточные углы смешиваются непрерывно без snapping.
- [x] Переход forward → diagonal → strafe → backward не вызывает заметного phase jump ног.
- [x] Playback визуально соответствует фактической скорости без изменения gameplay velocity.
- [x] При движении под 180° относительно тела персонаж визуально действительно идёт/бежит назад, а не проигрывает forward-run задом наперёд.

## Aim / upper body

- [x] Корпус ограниченно следует `AimDirection` относительно `BodyFacingDirection`.
- [x] Голова может визуально следовать цели дальше корпуса, но имеет ограничение.
- [x] Нет невозможного поворота головы/корпуса на 150–180° при неподвижных ногах.
- [x] При превышении visual limit тело из #11 естественно догоняет aim, а visual offset уменьшается.
- [x] Procedural offsets изменяются плавно и не дёргаются при движении курсора.

## Turning

- [x] Поворот тела на месте визуально читается как перестройка персонажа, а не вращение статичной модели.
- [x] Разворот во время движения естественно меняет local locomotion blend.
- [x] Поворот на 180° не создаёт неправильного полного оборота или visual flip.
- [x] Turn animation/procedure не изменяет gameplay turn timing из #11.

## Combat integration

- [x] Warrior LMB/RMB/Q/F и block остаются читаемыми.
- [x] Archer LMB/RMB/Q/F сохраняют draw/release и направление выстрела.
- [x] Engineer LMB/RMB/Q/F сохраняют читаемые heavy/deploy poses.
- [x] Engineer turret placement сохраняет утверждённый gameplay placement moment.
- [x] Движение во время действия не приводит к постоянному sliding персонажа с полностью неподвижными ногами, где это визуально не оправдано.
- [x] Procedural aim не ломает authored attack key poses.
- [x] Включение/выключение procedural weights вокруг действий происходит без pose snapping.
- [x] Gameplay hit/projectile/ability timings не изменены.

## Cubic quality

- [x] Конечности сохраняют жёсткий cubic character и правильные pivot points.
- [x] Нет регулярного critical clipping оружия/щита/лука/powerpack через тело.
- [x] Силуэт остаётся читаемым с реальной gameplay camera.
- [x] Система не пытается имитировать реалистичную человеческую mocap-анатомию ценой стилистики.

## Foot placement

- [ ] На ровной поверхности отсутствует крупный distracting foot sliding. — записи приложены; остаточное скольжение быстрых боковых шагов требует playtest-оценки.
- [x] Foot IK/placement prototype протестирован на voxel-step/разнице высот.
- [x] Если IK оставлен в production, он имеет настраиваемый weight и не ломает таз/колени/силуэт.
- [x] Если IK после prototype исключён, в PR приложено визуальное сравнение и объяснение, почему обычная locomotion выглядит лучше.

## Lifecycle

- [x] Смена Warrior → Archer → Engineer и обратно корректно перепривязывает animation profile.
- [x] Старые modifiers не продолжают работать на скрытой модели.
- [x] Нет orphan helper nodes после class switch/death/scene exit.
- [x] Procedural system можно полностью отключить, и gameplay остаётся корректным.

## Tests

- [x] Unit tests проверяют world → body-local преобразование locomotion для forward/back/left/right.
- [x] Unit tests покрывают несколько diagonal angles.
- [x] Unit tests проверяют clamp torso/head offsets.
- [x] Unit tests проверяют shortest signed angle через ±180°.
- [x] Integration test подтверждает, что presentation читает #11 state, но не меняет gameplay orientation/velocity.
- [x] Integration/smoke tests проверяют binding всех трёх character animation profiles.
- [x] Missing optional modifier/bone не вызывает runtime crash.
- [x] `python tools/verify.py` проходит полностью.

---
