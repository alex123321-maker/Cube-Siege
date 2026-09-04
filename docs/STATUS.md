# 📊 Cube Siege — Фактический статус реализации систем

Документ отражает реальное состояние кодовой базы по результатам аудита существующих скриптов (`scripts/`), сцен (`scenes/`), C++ кода (`src/`) и тестов (`tests/`).

---

## 🟢 IMPLEMENTED (Полностью реализовано и проверено)

| Система / Компонент | Расположение | Описание и фактическая реализация |
| :--- | :--- | :--- |
| **EventBus (Шина событий)** | `scripts/event_bus.gd` | Autoload-синглтон. Передаёт сигналы ресурсов (`resources_changed`, `resource_gathered`), боя (`enemy_killed`, `damage_dealt`, `player_died`), построек (`building_placed`, `building_destroyed`), времени/волн (`day_started`, `night_started`, `wave_started`, `wave_cleared`), игрока (`player_health_changed`, `player_xp_changed`, `player_level_up`, `player_class_changed`), портала (`portal_repair_started`, `portal_repair_complete`, `portal_evacuation_started`) и боссов (`boss_spawned`, `boss_defeated`). |
| **SaveManager (Система сохранений)** | `scripts/save_manager.gd` | Autoload-синглтон. Консолидированное хранение схемы `SAVE_VERSION = 2` в `user://cube_siege_save.json` (`meta_xp`, `survived_runs`, `unlocked_classes`, `roster_slots`, `mastery`, `run_history`), автомиграция с v1 и сайдкар-файлов, изоляция через `@export var auto_load`. |
| **MasteryManager (Мета-прогресс)** | `scripts/mastery_manager.gd` | Autoload-синглтон. Доменный фасад талантов, делегирующий сохранение в `SaveManager`. |
| **RosterManager (Ростер классов)** | `scripts/roster_manager.gd` | Autoload-синглтон. Доменный фасад ростера героев, делегирующий сохранение в `SaveManager`. |
| **EntityRegistry (Реестр сущностей)** | `scripts/core/entity_registry.gd` | Autoload-синглтон. Высокопроизводительный трекинг активных построек, мобов и боссов без кадровых сканирований SceneTree. |
| **Main Menu (Главное меню)** | `scenes/main_menu.tscn`<br>`scripts/main_menu.gd` | Стартовый экран, выбор персонажей ростера, просмотр/прокачка дерева талантов, запуск ран-сессии. |
| **Main Scene (Главный игровой цикл)** | `scenes/main.tscn`<br>`scripts/main.gd` | Корневой координатор игры: загрузка карты, инициализация игрока, портала, камеры, HUD и обработка исходов (победа/поражение). |
| **Player Controller (Архитектура подсистем)** | `scenes/player.tscn`<br>`scripts/player_prototype.gd`<br>`scripts/player/` | Игрок (`CharacterBody3D`), декомпозированный на компоненты: `PlayerMovement`, `PlayerAim`, `PlayerHealth`, `PlayerProgression`, `PlayerInteraction`, `PlayerPresentation` и `InteractableTarget`. Сохраняет 100% обратную совместимость API. |
| **Class Mechanics (Воин / Лучник / Инженер)** | `scripts/player_prototype.gd` | В коде реализованы раздельные наборы атак, умений и ультимейтов для 3 классов:<br>• **Воин**: взмах мечом (`trigger_slash`), круговой спецвзмах [ПКМ], блок щитом [Q], ультимейт «Дуэль чести» [F] с привязкой цепью (`duel_tether.tscn`) и +20% урона.<br>• **Лучник**: выстрел стрелой (`trigger_arrow_shot`), пробивающая стрела сквозь 6 целей [ПКМ], приманка-чучело [Q], ультимейт «Орлиный глаз» [F] (отдаление камеры `camera.size = 34.0`; бонус к дальности в коде не подключен).<br>• **Инженер**: удар молотом (`trigger_hammer_smash`), установка турели [ПКМ], дистанционная мина [Q], ультимейт «Тактический ядерный удар» [F] (AoE 10м, 1.2с телеграф, 300 урона). |
| **Portal Controller & Extraction** | `scenes/portal.tscn`<br>`scripts/portal_controller.gd` | Центральный портал: зоны взаимодействия, 3 стадии починки ресурсами (дерево, камень), обратный отсчёт эвакуации (45 сек), триггер победы. |
| **Day/Night Cycle** | `scripts/day_night_cycle.gd` | Таймер смены дня и ночи, интерполяция направленного света (`DirectionalLight3D`), цвета тумана и запуск сигналов `day_started`/`night_started`. |
| **Safe Zone Detector (Замкнутый контур)** | `scripts/safe_zone_detector.gd`<br>`scripts/algorithms/safe_zone_calculator.gd` | Чистый алгоритм 8-связного внешнего flood-fill: находит замкнутые периметры стен (минимум 4 стены), диагональные зазоры считаются проницаемыми для утечки. Передаёт координаты в `WaveDirector.set_safe_zone_cells()`. |
| **Map Generator (Процедурная карта)** | `scenes/map_generator.tscn`<br>`scripts/map_generator.gd` | Генерация сетки 65x65 клеток (`map_radius = 32`, координаты от -32 до 32) с переиспользованием ресурсов BoxMesh/BoxShape3D, спавн деревьев, камней и железа через FastNoiseLite с зоной клиринга портала (радиус 6.5м). |
| **Resource Nodes (Добыча ресурсов)** | `scenes/resource_tree.tscn` (`scripts/resource_tree.gd`)<br>`scenes/resource_stone.tscn` (`scripts/resource_rock.gd`)<br>`scenes/resource_iron.tscn` (`scripts/resource_rock.gd`) | Интерактивные объекты ресурсов с запасом прочности, отдачей при ударе, дропом ресурсов и плавающим текстом. |
| **Building System & Economy** | `scripts/building_system.gd`<br>`scripts/economy/resource_wallet.gd`<br>`scripts/resources/building_definition.gd` | Строительство с проверкой стоимости через изолированный `ResourceWallet`, метаданные префабов в `BuildingDefinition`, превью-сетка и радиальное меню. |
| **UI: Radial Menu** | `scenes/radial_menu.tscn`<br>`scripts/radial_menu.gd` | Круговое меню выбора категорий и типов построек. |
| **UI: Workbench Modal** | `scenes/workbench_modal.tscn`<br>`scripts/workbench_modal.gd` | Модальное окно крафта инструментов и боеприпасов на верстаке. |
| **UI: Card Draft Popup** | `scenes/card_draft_popup.tscn`<br>`scripts/card_draft_popup.gd` | Выбор 1 из 3 случайных карт усилений при повышении уровня или пережитой ночи. |
| **UI: Skills Action Bar** | `scenes/skills_action_bar.tscn`<br>`scripts/skills_action_bar.gd` | Нижняя панель способностей с иконками, кулдаунами и горячими клавишами. |
| **UI: HUD & Combat Text** | `scripts/hud.gd`<br>`scenes/floating_text.tscn`<br>`scenes/game_over_overlay.tscn` | Индикаторы HP/XP, компас портала, всплывающий урон (`floating_text.gd`), экран поражения (`game_over_overlay.gd`). Полностью синхронизирован через EventBus. |
| **GDExtension Native Probe** | `src/native_probe.cpp`<br>`src/native_probe.h`<br>`bin/cube_siege.gdextension` | Нативный класс `NativeProbe` скомпилирован через SCons, валидирует работу тулчейна и вызов C++ методов (`is_native_loaded()`) из GDScript. |
| **GUT Testing Suite** | `addons/gut/`<br>`.gutconfig.json`<br>`tests/` | 42+ автоматических теста (smoke, unit, integration), полное покрытие безопасных зон, кошелька, персистентности, игрока, таранщика, директора волн и нативного пробника. |
| **Godot MCP Native Server** | `addons/godot_mcp/`<br>`tools/gdmcp.py` | Сервер MCP для инспекции сцен, ресурсов, логов и вызова инструментов редактора Godot по HTTP (порт 9080) и CLI. |

---

## 🟡 PARTIAL (Частично реализовано)

| Система | Расположение | Что готово | Что предстоит доделать |
| :--- | :--- | :--- | :--- |
| **Enemy AI & Wave Director** | `scripts/wave_director.gd`<br>`scripts/enemy_base.gd`<br>`scenes/enemy_dummy.tscn`<br>`scenes/enemies/ranged_skirmisher.tscn`<br>`scenes/enemies/siege_breaker.tscn`<br>`scenes/enemies/boss_gorgon.tscn` | Директор ночных волн: интервал спавна 1.6с, кольцо спавна 20..28м, отклонение внутри SafeZone, интеграция с EntityRegistry. Таранщик опрашивает цели по таймеру 0.8с с дистанцией в квадрате. | Отсутствует волновое поле (Flowfield) и алгоритмы разделения толпы (crowd steering/boids). |
| **Defensive Buildings (Префабы)** | `scenes/prefabs/wood_wall.tscn`<br>`scenes/prefabs/iron_wall.tscn`<br>`scenes/prefabs/archer_tower.tscn`<br>`scenes/prefabs/ballista_tower.tscn`<br>`scenes/prefabs/floor_spikes.tscn`<br>`scenes/prefabs/remote_mine.tscn`<br>`scenes/prefabs/decoy_dummy.tscn`<br>`scenes/prefabs/temp_turret.tscn`<br>`scenes/prefabs/workbench.tscn` | Все 9 префабов созданы и функциональны: турели стреляют снарядами (`arrow_projectile.gd`), шипы и мины наносят урон, чучело агрит мобов. | Требуется балансировка параметров урона/прочности и визуальные стадии разрушения. |
| **Visual Models (3D Ассеты)** | `assets/models/` | Воин укомплектован уникальной воксельной моделью Blockbench (`hero_warrior.tscn`) с анимациями бега, атаки и блока. | Лучник и Инженер временно используют ту же воксельную модель; уникальные 3D-модели для них ещё не созданы. |

---

## ⚪ PLANNED (Запланировано в GDD / Backlog, код отсутствует)

| Система | Запланированный этап | Технический план реализации |
| :--- | :--- | :--- |
| **C++ 2D Flowfield Pathfinding** | Milestone 5 (`docs/BACKLOG.md` 3.1 & 5.7) | Расчёт векторного поля дистанций (волновой фронт Дейкстры) в C++ GDExtension для 500+ юнитов без индивидуального поиска пути. В текущем коде враги двигаются по прямому вектору. |
| **MultiMesh Crowd Renderer** | Milestone 5 | Отрисовка больших толп через `MultiMeshInstance3D` с GPU-инстансингом трансформаций. Сейчас каждый враг — отдельный `CharacterBody3D`. |
| **Audio & SFX System** | Milestone 4 | Подключение звуковой шины (`AudioServer`), пространственных звуков шагов, ударов, разрушения построек, эмбиента дня/ночи и музыки. Аудиофайлы отсутствуют. |

---

## ⚠️ CURRENT TECH DEBT (Архитектурный долг текущей реализации)

1. **Несоответствие параметров ультимейта Лучника**:
   - `perform_archer_ultimate()` устанавливает `is_eagle_eye = true` и отдаляет камеру (`camera.size = 34.0`), но фактический бонус +50% к дальности стрел в коде `trigger_arrow_shot()` пока не применён.

2. **Логика лимитов WaveDirector при боссах**:
   - Формула `var effective_max: int = 4 if has_boss else max_concurrent_enemies` ограничивает число обычных врагов 4 мобами при живом боссе и 20 мобами в обычной волне. Запланированное расписание волн 10/20/30 в коде не реализовано.

