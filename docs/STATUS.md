# 📊 Cube Siege — Фактический статус реализации систем

Документ отражает реальное состояние кодовой базы по результатам аудита существующих скриптов (`scripts/`), сцен (`scenes/`), C++ кода (`src/`) и тестов (`tests/`).

## Редакция первой версии Воина — 2026-10-03

Пользователь подтвердил Warrior-first scope и делегировал оставшийся баланс. Текущие числа/контракт: [`GDD.md`](GDD.md), [`in_run_progression_concept.md`](design/in_run_progression_concept.md), [`warrior_radial_talent_tree_concept.md`](design/warrior_radial_talent_tree_concept.md). Цели 2–3 часа на прохождение и 8–15 успешных эвакуаций на дерево пока не подтверждены длительным playtest.

**Общая проверка итоговой реализации:** `python tools/verify.py` — exit 0, 243,59 с. Нативная debug-сборка и импорт прошли; **500/500 GUT тестов в 71 script**, **148 Python-тестов**, **26/26 проверок мира**, smoke меню и **24/24 gameplay checks** существующих трёх классов. Проверка мира использует production WaveDirector в настоящем main: у 24 врагов проверено совпадение нижней границы фактической коллизии с воксельным рельефом. Журнал: `screenshots_debug/root/final-verify.log`. Завершение GUT проверено по фактическому exit 0 процесса; регрессии отмены таймеров способностей при удалении владельца и полного последнего шага выпада при физике 10 Гц входят в общий прогон.

**Свойства Ability Lab:** пять новых native-регрессий сверяют отображаемые значения с настоящим парированием/ответным уроном, защитой рывка, числом целей меча, released-геометрией Рассечения и лечением от фактической потери HP при overkill. Отдельный прогон `test_ability_viewer.gd` — **16/16**, 310 assertions, exit 0; журнал `screenshots_debug/progression/viewer-property-gut.log`. Каталог читает runtime и общий ресурс, без изменения игровых механик.

**Проверка прогрессии/сохранений/координации:** 5 выбранных GUT scripts, **32/32 тестов**, **1313 assertions**, exit 0. Включены `test_warrior_progression.gd`, `test_warrior_meta_progression.gd`, `test_persistence.gd`, `test_warrior_run_flow.gd`, `test_main_menu.gd`. Последний flow-тест использует контролируемый WaveDirector double; он проверяет расписание и транзакции, а не реальную длительность боссов. Локальные журналы: `screenshots_debug/progression/flow-gut.log`, `flow-import.log`. Проверенные ошибки записи и повреждённые файлы намеренно моделируются тестами и ожидаются через assertions. Регрессии восстановления проверяют приоритет durable backup перед temporary/legacy, tmp-only первой записи, сохранность некорректного backup и прежний отказ при повреждённом существующем primary.

**Визуальная проверка меню:** реальный Godot GPU render и просмотр трёх кадров — 1280×720 новый герой, 1920×1080 частично открытое дерево, 2560×1080 полное. Захват `tools/capture_warrior_menu.gd` использует события клика из главного меню и production unlock API в отдельном профиле. Свидетельства: `screenshots_debug/progression/menu/fresh_1280.png`, `partial_1920.png`, `complete_wide.png`, `screenshots_debug/progression/menu-capture.log` (exit 0). Размеры/расположение проверены без перекрытия и обрезания текста.

**Проверка настоящего main.tscn:** `python tools/warrior_run_smoke.py --immediate-teardown --verbose` — **95/95 проверок**, exit 0, без engine/script errors и с неизменным source fingerprint. В сценарии настоящий процедурный мир (49 чанков), production HUD/modal, все 30 переходов волн, шесть настоящих authored boss scenes и попадания production меча по контролируемым боссам. Проверены точный уровень за босса, предел шести талантов, один сохранённый исход, защита от поздней эвакуации, перезагрузка победившего героя и немедленное удаление владельца незавершённого удара. Журнал/manifest: `screenshots_debug/progression/run-smoke.log`, `run-smoke-manifest.json`.

**Обновлённые gameplay UI кадры:** `python tools/warrior_run_smoke.py --capture --immediate-teardown` — **99/99 проверок**, exit 0, неизменный source fingerprint. Четыре GPU-render кадра 1280×720 просмотрены: начальный выбор (реальные 00:30), специализации с полным описанием, ночь/имя босса, победа с корректно перенесённым текстом. Журнал/manifest: `screenshots_debug/progression/run-capture.log`, `run-capture-manifest.json`; PNG: `screenshots_debug/progression/run/{initial_draft,specializations,boss_night,victory}.png`.

Оба actual-main сценария используют отдельный профиль до загрузки autoload, ускоряют только часы драйвером, отключают случайный обычный спавн и удерживают настоящих боссов на 10 HP для реального попадания мечом. GPU сценарий ускоряет и переход освещения через production API. **Это интеграционная проверка, не доказательство длительности/баланса прохождения.** Watchdog 150 с, внешний timeout процесса 180 с; helper завершается сам.

Файлы `screenshots_debug/` являются локальными свидетельствами и не заменяют медиа-вложения PR после создания/обновления ревизии.

---

## 🟢 IMPLEMENTED (Реализованные системы; область проверки указана отдельно)

| Система / Компонент | Расположение | Описание и фактическая реализация |
| :--- | :--- | :--- |
| **EventBus (Шина событий)** | `scripts/event_bus.gd` | Autoload-синглтон. Передаёт сигналы ресурсов (`resources_changed`, `resource_gathered`), боя (`enemy_killed`, `damage_dealt`, `player_died`), построек (`building_placed`, `building_destroyed`), верстака (`workbench_opened`), времени/волн (`day_started`, `night_started`, `cycle_time_updated`, `wave_started`, `wave_cleared`), игрока (`player_health_changed`, `player_xp_changed`, `player_level_up`, `player_class_changed`), портала (`portal_repair_started`, `portal_repair_complete`, `portal_evacuation_started`, `portal_evacuated`) и боссов (`boss_spawned`, `boss_defeated`). |
| **SaveManager (Сохранения v3)** | `scripts/save_manager.gd` | Атомарная запись `cube_siege_save.json` через временный файл и резервную копию; при отсутствии primary восстанавливается проверенная `.bak`, затем допустимая `.tmp` первой записи. Повреждённые артефакты сохраняются для восстановления. Прогресс Воина (`talent_xp`, открытые/купленные ID, завершённые забеги, победы) принадлежит слоту. Идемпотентная миграция v1/v2, старые классы/история сохранены; сайдкар не перезаписывает существующий v3. Ошибка покупки/исхода откатывает память. |
| **MasteryManager (Совместимость)** | `scripts/mastery_manager.gd` | Старый фасад глобального мастерства сохранён для legacy-данных. В новом живом цикле Воина не используется и не складывается с его веточными бонусами. |
| **RosterManager (Персонаж и мета-пул)** | `scripts/roster_manager.gd` | Открывает таланты между забегами с проверками пути/XP/класса/повторной покупки. Все открытые таланты, включая стартовые, дают один веточный пассивный бонус. `record_run_end` — единый фасад атомарной транзакции исхода; смерть заменяет Воина, эвакуация/победа сохраняет дерево. |
| **EntityRegistry (Реестр сущностей)** | `scripts/core/entity_registry.gd` | Autoload-синглтон. Высокопроизводительный трекинг активных построек, мобов и боссов без кадровых сканирований SceneTree. |
| **Main Menu / Радиальное дерево Воина** | `scenes/main_menu.tscn`<br>`scripts/main_menu.gd`<br>`scripts/ui/warrior_talent_tree.gd` | Только Воин запускается из меню. Девять отдельных SVG-иконок, органические связи и открытые пути, покупка/описание/остаток XP. Изолированный модельный SubViewport без боевого контроллера и смены выбранного слота при осмотре. Старые слоты других классов остаются в сохранениях. |
| **Main Scene / Координатор забега** | `scenes/main.tscn`<br>`scripts/main.gd`<br>`scripts/run/warrior_run_coordinator.gd` | 30 волн, реальные шесть boss scenes каждые 5 волн, первый выбор после готовности HUD, выбор после волны 2 и боссов до лимита. Единственный владелец сохранения исхода. Повтор записи после ошибки сохраняет первоначальную победу/смерть и XP. Начальные тестовые враги и живой верстак удалены. |
| **Player Controller (Архитектура подсистем)** | `scenes/player.tscn`<br>`scripts/player_prototype.gd`<br>`scripts/player/` | Игрок (`CharacterBody3D`) использует 10 подсистем: `PlayerMovement`, `PlayerAim`, `PlayerHealth`, `PlayerProgression`, `PlayerInteraction`, `PlayerPresentation`, `PlayerCombat`, `PlayerAbilities`, `PlayerOrientation` и `WarriorTalentRuntime`. Взаимодействия используют типизированный контракт `InteractableTarget`; новые таланты исполняются через общий runtime. |
| **Class Mechanics (Воин, legacy-прототипы)** | `scripts/player/player_combat.gd`<br>`scripts/player/player_abilities.gd`<br>`scripts/player/warrior_talent_runtime.gd` | Воин: одиночная базовая атака без таланта, Рассечение, рывок без базовой неуязвимости, одноударное парирование, Дуэль. Девять талантов и три автоматические скрытые синергии используют общее production исполнение в игре и Ability Lab. Лучник/Инженер сохранены как прототипы, их игровые ветки отложены. |
| **Portal Controller & Extraction** | `scenes/portal.tscn`<br>`scripts/portal_controller.gd` | Портал не атакуется. Ремонт 25 дерева + 25 камня, ожидание 45 с, удержание E 2 с. Сигнал эвакуации сообщает намерение; портал сам не записывает исход. Награда рассчитывается координатором по уровню и фактически собранным ресурсам. |
| **Day/Night Cycle** | `scripts/day_night_cycle.gd` | День 30 с. Обычная ночь `min(120, 20 + 2 × wave)`; 22 с на первой волне. Ночи 5/10/15/20/25/30 заблокированы до победы над боссом. Рассвет очищает оставшихся врагов без XP. Цикл не сохраняет мета-прогресс посреди забега и остаётся независимым от UI. |
| **Safe Zone Detector (Замкнутый контур)** | `scripts/safe_zone_detector.gd`<br>`scripts/algorithms/safe_zone_calculator.gd` | Чистый алгоритм 8-связного внешнего flood-fill: находит замкнутые периметры стен (минимум 4 стены), диагональные зазоры считаются проницаемыми для утечки. Передаёт координаты в `WaveDirector.set_safe_zone_cells()`. |
| **Map Generator (Процедурный мир и биомы)** | `scenes/map_generator.tscn`<br>`scripts/map_generator.gd`<br>`scripts/world/` | Процедурный бесконечный мир с чанковым стримингом (16x16 вокселей на чанк, радиус загрузки 3..5 чанков), 3 макро-биома (`BiomeSystem`: Лес 0..+10, Равнина 0..+4, Горы с масштабированием высоты до 50+ и 100+ с плавным схождением к границам секторов), правило проходимости ступеней `\|Δheight\| <= 1`, вертикальная боевая система (`TerrainCombatRules`), ресурсы (`ResourceDistribution`: свободные пикапы 1-3 ед. на слое 4, полные месторождения дерева/камня/железа с визуальными тирами и стадиями разрушения, магический камень как ран-ресурс) и персистентное сохранение срубленных/собранных ресурсов при выгрузке чанков. |
| **Resource Nodes & Pickups (Зоны взаимодействия)** | `scenes/resource_tree.tscn`<br>`scenes/resource_stone.tscn`<br>`scenes/resource_iron.tscn`<br>`scripts/interaction/interaction_zone.gd`<br>`scripts/world/free_resource_pickup.gd` | Полнотелые интерактивные объекты ресурсов с запасом прочности, отдачей при ударе, стадиями разрушения, вариациями дубов и тирами камня/железа + свободные собираемые пикапы. Взаимодействие полностью отделено от боя и геометрии на физический слой 6 (`InteractionZone`, mask 32) со снимком `get_overlapping_areas()` — разрушенные ресурсы подбираются сразу на месте без отхода от точки. Безопасный сбор с предварительной проверкой `BuildingSystem` и защитой от дублирования. |
| **Building System & Economy** | `scripts/building_system.gd`<br>`scripts/economy/resource_wallet.gd`<br>`scripts/resources/building_definition.gd` | Строительство с проверкой стоимости через изолированный `ResourceWallet`, метаданные префабов в `BuildingDefinition`, превью-сетка и радиальное меню. |
| **UI: Radial Menu** | `scenes/radial_menu.tscn`<br>`scripts/radial_menu.gd` | Круговое меню выбора категорий и типов построек. |
| **UI: Workbench Modal (Legacy)** | `scenes/workbench_modal.tscn`<br>`scripts/workbench_modal.gd` | Прототип крафта/старого мастерства сохранён для совместимости. Живого верстака в первой версии Воина нет; вещи и атрибуты отложены. |
| **UI: Билд и talent checkpoints** | `scripts/ui/warrior_build_panel.gd`<br>`scripts/progression/warrior_run_build.gd` | До 6 талантов; до 3 уникальных открытых вариантов или Focus (+2 очка). Уровень даёт специализацию, не карточку. Бесплатный сброс, неограниченные ранги, раскрытие синергий после пары. Очередь reward ID защищена от дублирования и старых callback. Старый CardDraftPopup не участвует в live progression Воина. |
| **UI: Skills Action Bar** | `scenes/skills_action_bar.tscn`<br>`scripts/skills_action_bar.gd` | Нижняя панель способностей с иконками, кулдаунами и горячими клавишами. |
| **UI: HUD & Combat Text** | `scripts/hud.gd`<br>`scenes/floating_text.tscn`<br>`scenes/game_over_overlay.tscn` | Индикаторы HP/XP, компас портала, всплывающий урон (`floating_text.gd`), экран поражения (`game_over_overlay.gd`). Самостоятельно форматирует и отображает `DayNightLabel` через `EventBus.cycle_time_updated`, использует явную зависимость `DayNightCycle` для кнопки пропуска ночи. |
| **Навигация монстров / Issue #56** | `scripts/navigation/monster_flowfield.gd`<br>`src/monster_field_solver.cpp` | Общий бюджет построения полей раз в 0,25 с, точная цель и физические препятствия; нативный расчёт с reference parity. Свежая парная проверка настоящего baseline: 14/20 движущихся врагов P95 5,972/5,705 мс, P99 8,643/10,085 мс. 100/500 — диагностические нагрузки: P95 16,178/129,379 мс; 60 FPS для 500 и 120 FPS не заявлены. Подробности: [BENCHMARK_ISSUE_56.md](BENCHMARK_ISSUE_56.md). |
| **GDExtension Native Probe** | `src/native_probe.cpp`<br>`src/native_probe.h`<br>`bin/cube_siege.gdextension` | Нативный класс `NativeProbe` скомпилирован через SCons, валидирует работу тулчейна и вызов C++ методов (`is_native_loaded()`) из GDScript. |
| **GUT Testing Suite** | `addons/gut/`<br>`.gutconfig.json`<br>`tests/` | Автоматические smoke/unit/integration проверки. Добавлены отдельные тесты каталога/билда, мета-пула/миграции/отката и 30-волновой координации, включая повтор сохранения смерти и победы. Фактические результаты новой области приведены ниже; полная верификация не подменяется ими. |
| **Godot MCP Native Server** | `addons/godot_mcp/`<br>`tools/gdmcp.py` | Сервер MCP для инспекции сцен, ресурсов, логов и вызова инструментов редактора Godot по HTTP (порт 9080) и CLI. |

---

## 🟡 PARTIAL (Частично реализовано)

| Система | Расположение | Что готово | Что предстоит доделать |
| :--- | :--- | :--- | :--- |
| **Enemy AI & Wave Director** | `scripts/wave_director.gd`<br>`scripts/enemy_base.gd`<br>`scenes/enemies/`<br>`scenes/bosses/` | Растущий с волной состав/темп/лимит: интервал `max(1.35, 3.2 − wave × 0.06)`, лимит `min(42, 10 + wave)`, при боссе 4 обычных врага. Элиты после волны 5. Безопасный поиск позиции, SafeZone/EntityRegistry, удаление на рассвете без XP. Шесть боссов вызываются координатором каждые 5 волн. | Длительный playtest темпа/сложности; показатели массовой навигации проверяются отдельной задачей производительности. |
| **Defensive Buildings (Префабы)** | `scenes/prefabs/wood_wall.tscn`<br>`scenes/prefabs/iron_wall.tscn`<br>`scenes/prefabs/archer_tower.tscn`<br>`scenes/prefabs/ballista_tower.tscn`<br>`scenes/prefabs/floor_spikes.tscn`<br>`scenes/prefabs/remote_mine.tscn`<br>`scenes/prefabs/decoy_dummy.tscn`<br>`scenes/prefabs/temp_turret.tscn`<br>`scenes/prefabs/workbench.tscn` | Все 9 префабов созданы и функциональны: турели стреляют снарядами (`arrow_projectile.gd`), шипы и мины наносят урон, чучело агрит мобов. | Требуется балансировка параметров урона/прочности и визуальные стадии разрушения. |
| **Visual Models (3D Ассеты)** | `assets/models/` | Воин укомплектован уникальной воксельной моделью Blockbench (`hero_warrior.tscn`) с анимациями бега, атаки и блока. | Лучник и Инженер временно используют ту же воксельную модель; уникальные 3D-модели для них ещё не созданы. |

---

## ⚪ PLANNED (Запланировано в GDD / Backlog, код отсутствует)

| Система | Запланированный этап | Технический план реализации |
| :--- | :--- | :--- |

| **MultiMesh Crowd Renderer** | Milestone 5 | Отрисовка больших толп через `MultiMeshInstance3D` с GPU-инстансингом трансформаций. Сейчас каждый враг — отдельный `CharacterBody3D`. |
| **Audio & SFX System** | Milestone 4 | Подключение звуковой шины (`AudioServer`), пространственных звуков шагов, ударов, разрушения построек, эмбиента дня/ночи и музыки. Есть отдельный звук Рассечения; общая система музыки, окружения и звуков всех действий пока отсутствует. |

---

## ⚠️ CURRENT TECH DEBT & STABILIZATION

### 1. Ранее зафиксированные дефекты реализации (Unresolved Defects)

1. **Несоответствие параметров ультимейта Лучника**:
   - `perform_archer_ultimate()` устанавливает `is_eagle_eye = true` и отдаляет камеру (`camera.size = 34.0`), но фактический бонус +50% к дальности стрел в коде `trigger_arrow_shot()` пока не применён.

2. **Расписание боссов и лимиты WaveDirector — обновлено в первой версии**:
   - Боссы вызываются на 5/10/15/20/25/30, обычный лимит растёт с волной до 42, при боссе остаётся 4. Координация расписания покрыта новыми flow-тестами; сложность требует длительного playtest.

---

### 2. Исторический аудит вертикального среза (Issue #20)

Следующий список сохранён как история аудита, а не перечень открытых дефектов текущей редакции. Подробный анализ первопричин, реестр временных прототипов и дорожная карта стабилизации зафиксированы в **[`docs/AUDIT_VERTICAL_SLICE_STABILIZATION.md`](AUDIT_VERTICAL_SLICE_STABILIZATION.md)**.

1. **~~P0: Сломанный подбор срубленных ресурсов (`ResourceTree`, `ResourceRock`)~~ (РЕШЕНО — Issue #42)**:
   - Взаимодействие переведено на выделенный физический слой 6 (`InteractionZone`, mask 32) со снимком `sensor.get_overlapping_areas()`. Отключение твёрдых коллизий (слой 1) и хёртбоксов (слой 4) больше не теряет цель. Сбор защищён проверкой `BuildingSystem` и защитой от повторного входа. Полнотелые и свободные ресурсы подбираются сразу на месте разрушения без отхода от точки.
2. **P0: Инвертированное / Aim-relative WASD управление**:
   - Локомоция относительно вектора мыши дезориентирует при кайтинге. Требуется возврат к каноническому экранно-изометрическому WASD.
3. **P0: Зависание стрел над врагами при стрельбе с высоты**:
   - В `TerrainCombatRules.update_projectile_height` накопительный клиренс $\ge 2.0$ над пологим склоном со спуском шагами $-1$ преждевременно включает `currently_over_drop` и замораживает высоту стрелы, из-за чего она пролетает над головами врагов. Требуется исправление условия спуска с сохранением дискретного контракта высот Issue #18 ($0 / \pm 1 / \pm 2$).
4. **P1: Зебра-лестницы гор и хаос рельефа**:
   - Градиент 0.7 + высокочастотный симплекс-шум + квантование порождают ступенчатую зебру через каждый метр. Требуется террасированный профиль (параметры — DESIGN DECISION REQUIRED).
5. **P1: Полное отсутствие звука (гробовая тишина)**:
   - В проекте нет аудиофайлов. Требуется базовый пакет SFX (состав — DESIGN DECISION REQUIRED).
6. **P1: Микро-строб камеры при движении**:
   - Рассинхрон тиков физики игрока (60 Гц дискретно) и рендера камеры (120/144 Гц) без физической интерполяции. Требуется пост-физическая синхронизация или physics interpolation.
7. **P1: Гипотеза о перегрузке спавна чанков нодами (биномиальное среднее $\mu \approx 41$ на чанк)**:
   - Требуется обязательное инструментальное профилирование в Godot Profiler перед оптимизациями.




