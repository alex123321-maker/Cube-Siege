# 📊 Cube Siege — Фактический статус реализации систем

Документ отражает реальное состояние кодовой базы по результатам аудита существующих скриптов (`scripts/`), сцен (`scenes/`), C++ кода (`src/`) и тестов (`tests/`).

---

## 🟢 IMPLEMENTED (Полностью реализовано и проверено)

| Система / Компонент | Расположение | Описание и фактическая реализация |
| :--- | :--- | :--- |
| **EventBus (Шина событий)** | `scripts/event_bus.gd` | Autoload-синглтон. Передаёт сигналы ресурсов (`resources_changed`, `resource_gathered`), боя (`enemy_killed`, `damage_dealt`, `player_died`), построек (`building_placed`, `building_destroyed`), времени/волн (`day_started`, `night_started`, `wave_started`, `wave_cleared`), игрока (`player_health_changed`, `player_xp_changed`, `player_level_up`, `player_class_changed`), портала (`portal_repair_started`, `portal_repair_complete`, `portal_evacuation_started`) и боссов (`boss_spawned`, `boss_defeated`). |
| **MasteryManager (Мета-прогресс)** | `scripts/mastery_manager.gd` | Autoload-синглтон. Управляет боевым опытом, уровнями и 4 ветками талантов (Кровожадность, Выживаемость, Проворство, Ремесло). |
| **RosterManager (Ростер классов)** | `scripts/roster_manager.gd` | Autoload-синглтон. Хранит доступные классы (Воин, Лучник, Инженер), активного персонажа и историю забегов. |
| **SaveManager (Система сохранений)** | `scripts/save_manager.gd` | Класс `SaveManager`. Сохраняет мета-XP, число выживаний, ростер героев и разблокированные классы в текстовый JSON `user://cube_siege_save.json` (`SAVE_VERSION = 1`). |
| **Main Menu (Главное меню)** | `scenes/main_menu.tscn`<br>`scripts/main_menu.gd` | Стартовый экран, выбор персонажей ростера, просмотр/прокачка дерева талантов, запуск ран-сессии. |
| **Main Scene (Главный игровой цикл)** | `scenes/main.tscn`<br>`scripts/main.gd` | Корневой координатор игры: загрузка карты, инициализация игрока, портала, камеры и HUD. |
| **Player Controller (Прототип GDScript)** | `scenes/player.tscn`<br>`scripts/player_prototype.gd` | Игрок (`CharacterBody3D`): изометрическое движение (WASD), чтение активного класса из `RosterManager`, прицеливание (мышь / стрелки), рывок уклонения (Space), компас портала, инвентарь ресурсов, получение урона и пермадес. |
| **Class Mechanics (Воин / Лучник / Инженер)** | `scripts/player_prototype.gd` | В коде реализованы раздельные наборы атак, умений и ультимейтов для 3 классов:<br>• **Воин**: взмах мечом (`trigger_slash`), круговой спецвзмах, блок щитом [Q], ультимейт «Дуэль чести» [F] с цепью (`duel_tether.tscn`) и +20% урона.<br>• **Лучник**: выстрел стрелой (`trigger_arrow_shot`), пробивающая стрела, чучело-приманка [Q], ультимейт «Орлиный глаз» [F] (+50% дальности, отдаление камеры).<br>• **Инженер**: удар молотом (`trigger_hammer_smash`), установка турели [ПКМ], дистанционная мина [Q], ультимейт «Тактический ядерный удар» [F] (AoE 10м, 1.2с телеграф, 300 урона). |
| **Portal Controller & Extraction** | `scenes/portal.tscn`<br>`scripts/portal_controller.gd` | Центральный портал: зоны взаимодействия, 3 стадии починки ресурсами (дерево, камень), обратный отсчёт эвакуации (45 сек), триггер победы. |
| **Day/Night Cycle** | `scripts/day_night_cycle.gd` | Таймер смены дня и ночи, интерполяция направленного света (`DirectionalLight3D`), цвета тумана и сигналы `day_started`/`night_started`. |
| **Safe Zone Detector** | `scripts/safe_zone_detector.gd` | Отслеживание дистанции игрока до портала. Нанесение периодического урона ночной тьмы за пределами безопасного радиуса. |
| **Map Generator (Процедурная карта)** | `scenes/map_generator.tscn`<br>`scripts/map_generator.gd` | Генерация сетки 65x65 клеток (`map_radius = 32`, координаты от -32 до 32), процедурный спавн деревьев, камней и железа через FastNoiseLite с зоной клиринга портала (радиус 6.5м). |
| **Resource Nodes (Добыча ресурсов)** | `scenes/resource_tree.tscn` (`scripts/resource_tree.gd`)<br>`scenes/resource_stone.tscn` (`scripts/resource_rock.gd`)<br>`scenes/resource_iron.tscn` (`scripts/resource_rock.gd`) | Интерактивные объекты ресурсов с запасом прочности, отдачей при ударе, дропом ресурсов и плавающим текстом. |
| **Building System (Строительство)** | `scripts/building_system.gd`<br>`scripts/building_base.gd` | Размещение защитных построек по сетке с проверкой стоимости ресурсов, превью-сеткой и вызовом радиального меню. |
| **UI: Radial Menu** | `scenes/radial_menu.tscn`<br>`scripts/radial_menu.gd` | Круговое меню выбора категорий и типов построек. |
| **UI: Workbench Modal** | `scenes/workbench_modal.tscn`<br>`scripts/workbench_modal.gd` | Модальное окно крафта инструментов и боеприпасов на верстаке. |
| **UI: Card Draft Popup** | `scenes/card_draft_popup.tscn`<br>`scripts/card_draft_popup.gd` | Выбор 1 из 3 случайных карт усилений при повышении уровня или пережитой ночи. |
| **UI: Skills Action Bar** | `scenes/skills_action_bar.tscn`<br>`scripts/skills_action_bar.gd` | Нижняя панель способностей с иконками, кулдаунами и горячими клавишами. |
| **UI: HUD & Combat Text** | `scripts/hud.gd`<br>`scenes/floating_text.tscn`<br>`scenes/game_over_overlay.tscn` | Индикаторы HP/XP, компас портала, всплывающий урон (`floating_text.gd`), экран поражения (`game_over_overlay.gd`). |
| **GUT Testing Harness** | `addons/gut/`<br>`.gutconfig.json`<br>`tests/smoke/` | Фреймворк GUT 9.6.1, запуск через `.gutconfig.json` (smoke, unit, integration), набор тестов на загрузку ключевых сцен и автозагрузок. |
| **Godot MCP Native Server** | `addons/godot_mcp/`<br>`tools/gdmcp.py` | Сервер MCP для инспекции сцен, ресурсов, логов и вызова инструментов редактора Godot по HTTP (порт 9080) и CLI. |

---

## 🟡 PARTIAL (Частично реализовано)

| Система | Расположение | Что готово | Что предстоит доделать |
| :--- | :--- | :--- | :--- |
| **Player Controller (C++ Graybox)** | `src/player_controller.cpp`<br>`src/player_controller.h`<br>`bin/cube_siege.gdextension` | Нативный класс `PlayerController` скомпилирован в GDExtension DLL/.so для валидации сборки. | Не используется в активной сцене `player.tscn` (сцена подключена к `scripts/player_prototype.gd`). |
| **Enemy AI & Wave Director** | `scripts/wave_director.gd`<br>`scripts/enemy_base.gd`<br>`scenes/enemy_dummy.tscn`<br>`scenes/enemies/ranged_skirmisher.tscn`<br>`scenes/enemies/siege_breaker.tscn`<br>`scenes/enemies/boss_gorgon.tscn` | Директор волн ночи со спавном мобов по периметру. Созданы 4 типа врагов: Dummy (ближний бой), Skirmisher (стрелок), Siege Breaker (разрушитель стен), Boss Gorgon (3 фазы, окаменение, призыв миньонов). | Враги двигаются по прямой линии к цели `(target - pos).normalized()`, отсутствует алгоритм разделения толпы (crowd steering/boids). |
| **Defensive Buildings (Префабы)** | `scenes/prefabs/wood_wall.tscn`<br>`scenes/prefabs/iron_wall.tscn`<br>`scenes/prefabs/archer_tower.tscn`<br>`scenes/prefabs/ballista_tower.tscn`<br>`scenes/prefabs/floor_spikes.tscn`<br>`scenes/prefabs/remote_mine.tscn`<br>`scenes/prefabs/decoy_dummy.tscn`<br>`scenes/prefabs/temp_turret.tscn`<br>`scenes/prefabs/workbench.tscn` | Все 9 префабов созданы и функциональны: турели стреляют снарядами (`arrow_projectile.gd`), шипы и мины наносят урон, чучело агрит мобов. | Требуется балансировка параметров урона/прочности и визуальные стадии разрушения. |
| **Visual Models (3D Ассеты)** | `assets/models/` | Воин укомплектован уникальной воксельной моделью Blockbench (`hero_warrior.tscn`) с анимациями бега, атаки и блока. | Лучник и Инженер временно используют ту же воксельную модель; уникальные 3D-модели для них ещё не экспортированы. |

---

## ⚪ PLANNED (Запланировано в GDD / Backlog, код отсутствует)

| Система | Запланированный этап | Технический план реализации |
| :--- | :--- | :--- |
| **C++ 2D Flowfield Pathfinding** | Milestone 5 (`docs/BACKLOG.md` 3.1 & 5.7) | Расчёт векторного поля дистанций (волновой фронт Дейкстры) в C++ GDExtension для 500+ юнитов без индивидуального поиска пути. В текущем коде враги двигаются по прямой. |
| **MultiMesh Crowd Renderer** | Milestone 5 | Отрисовка больших толп через `MultiMeshInstance3D` с GPU-инстансингом трансформаций. Сейчас каждый враг — отдельный `CharacterBody3D`. |
| **Audio & SFX System** | Milestone 4 | Подключение звуковой шины (`AudioServer`), пространственных звуков шагов, ударов, разрушения построек, эмбиента дня/ночи и музыки. Аудиофайлы отсутствуют. |

---

## 🔴 DEPRECATED / OBSOLETE CLAIMS

> [!WARNING]
> В `README.md` ранее утверждалось, что Flowfield Pathfinding на C++ уже функционирует. Согласно ревизии исходного кода `src/` и `docs/BACKLOG.md`, Flowfield находится в статусе **PLANNED** и ожидает реализации в рамках отдельного Issue.
