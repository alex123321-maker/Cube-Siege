# 📊 Cube Siege — Фактический статус реализации систем

Документ отражает реальное состояние кодовой базы по результатам аудита существующих скриптов (`scripts/`), сцен (`scenes/`), C++ кода (`src/`) и тестов (`tests/`).

---

## 🟢 IMPLEMENTED (Полностью реализовано и проверено)

| Система / Компонент | Расположение | Описание и фактическая реализация |
| :--- | :--- | :--- |
| **EventBus (Шина событий)** | `scripts/event_bus.gd` | Autoload-синглтон. Передаёт сигналы боевой системы, экономики, дня/ночи, талантов и эвакуации (`resource_changed`, `night_started`, `enemy_killed`, `player_damaged`, `extraction_completed`). |
| **MasteryManager (Мета-прогресс)** | `scripts/mastery_manager.gd` | Autoload-синглтон. Управляет боевым опытом, уровнями и 4 ветками талантов (Кровожадность, Выживаемость, Проворство, Ремесло). |
| **RosterManager (Ростер классов)** | `scripts/roster_manager.gd` | Autoload-синглтон. Хранит доступные классы (Воин, Лучник, Инженер) и активного персонажа. |
| **SaveManager (Система сохранений)** | `scripts/save_manager.gd` | Класс `SaveManager`. Сохраняет мета-XP, число выживаний, ростер героев и разблокированные классы в `user://cube_siege_save.json`. |
| **Main Menu (Главное меню)** | `scenes/main_menu.tscn`<br>`scripts/main_menu.gd` | Стартовый экран, выбор персонажей ростера, просмотр/прокачка дерева талантов, запуск ран-сессии. |
| **Main Scene (Главный игровой цикл)** | `scenes/main.tscn`<br>`scripts/main.gd` | Корневой координатор игры: загрузка карты, инициализация игрока, портала, камеры и HUD. |
| **Player Controller (Прототип)** | `scenes/player.tscn`<br>`scripts/player_prototype.gd` | Персонаж (`CharacterBody3D`): изометрическое движение (WASD), комбо-атака мечом (`hitbox_area.gd`), блок щитом, рывок уклонения, стрелка компаса к порталу, инвентарь ресурсов. |
| **Player Controller (C++ Graybox)** | `src/player_controller.cpp`<br>`src/player_controller.h` | Нативный C++ класс `PlayerController` для hot path перемещения. Скомпилирован в GDExtension (`bin/cube_siege.gdextension`). |
| **Portal Controller & Extraction** | `scenes/portal.tscn`<br>`scripts/portal_controller.gd` | Центральный портал: зоны взаимодействия, 3 стадии починки ресурсами (дерево, камень), обратный отсчёт эвакуации, триггер победы. |
| **Day/Night Cycle** | `scripts/day_night_cycle.gd` | Таймер смены дня и ночи, интерполяция солнечного света (`DirectionalLight3D`), цвета тумана и запуск сигналов шины. |
| **Safe Zone Detector** | `scripts/safe_zone_detector.gd` | Отслеживание дистанции игрока до портала. Нанесение периодического урона тьмы за пределами безопасной зоны ночью. |
| **Map Generator (Процедурная карта)** | `scenes/map_generator.tscn`<br>`scripts/map_generator.gd` | Генерация поверхности 80x80 и процедурный спавн деревьев, камней и железа с защитным радиусом вокруг портала. |
| **Resource Nodes (Добыча ресурсов)** | `scenes/resource_tree.tscn` (`scripts/resource_tree.gd`)<br>`scenes/resource_stone.tscn` (`scripts/resource_rock.gd`)<br>`scenes/resource_iron.tscn` (`scripts/resource_rock.gd`) | Интерактивные объекты ресурсов с запасом прочности, анимацией удара, выпадением лута и звуко-визуальной отдачей. |
| **Building System (Строительство)** | `scripts/building_system.gd`<br>`scripts/building_base.gd` | Размещение защитных построек по сетке с проверкой стоимости ресурсов, подсветкой превью и вызовом радиального меню. |
| **UI: Radial Menu** | `scenes/radial_menu.tscn`<br>`scripts/radial_menu.gd` | Круговое меню выбора категорий и типов построек. |
| **UI: Workbench Modal** | `scenes/workbench_modal.tscn`<br>`scripts/workbench_modal.gd` | Модальное окно крафта инструментов и боеприпасов на верстаке. |
| **UI: Card Draft Popup** | `scenes/card_draft_popup.tscn`<br>`scripts/card_draft_popup.gd` | Выбор 1 из 3 случайных карт перков/усилений при повышении уровня или пережитой ночи. |
| **UI: Skills Action Bar** | `scenes/skills_action_bar.tscn`<br>`scripts/skills_action_bar.gd` | Нижняя панель способностей с иконками, кулдаунами и горячими клавишами. |
| **UI: HUD & Combat Text** | `scripts/hud.gd`<br>`scenes/floating_text.tscn`<br>`scenes/game_over_overlay.tscn` | Полосы здоровья/опыта, компас портала, всплывающие цифры урона (`floating_text.gd`), экран поражения (`game_over_overlay.gd`). |
| **GUT Testing Harness** | `addons/gut/`<br>`.gutconfig.json`<br>`tests/smoke/` | Фреймворк GUT 9.6.1, полный запуск через `.gutconfig.json`, набор smoke-тестов на загрузку всех ключевых сцен и автозагрузок. |
| **Godot MCP Native Server** | `addons/godot_mcp/`<br>`tools/gdmcp.py` | Встроенный MCP-сервер для инспекции сцен, ресурсов, логов и вызова инструментов редактора Godot по HTTP (порт 9080) и CLI. |

---

## 🟡 PARTIAL (Частично реализовано)

| Система | Расположение | Что готово | Что предстоит доделать |
| :--- | :--- | :--- | :--- |
| **Enemy AI & Wave Director** | `scripts/wave_director.gd`<br>`scripts/enemy_base.gd`<br>`scenes/enemy_dummy.tscn`<br>`scenes/enemies/ranged_skirmisher.tscn`<br>`scenes/enemies/siege_breaker.tscn`<br>`scenes/enemies/boss_gorgon.tscn` | Директор волн ночи со спавном мобов по периметру. Реализованы 4 типа врагов: Dummy (ближний бой), Skirmisher (стрелок), Siege Breaker (разрушитель стен), Boss Gorgon (3 фазы, окаменение, призыв миньонов). | Прямое векторное перемещение (`(target - pos).normalized()`), отсутствует разделение и выравнивание толпы (boids/crowd steering). |
| **Defensive Buildings (Префабы)** | `scenes/prefabs/wood_wall.tscn`<br>`scenes/prefabs/iron_wall.tscn`<br>`scenes/prefabs/archer_tower.tscn`<br>`scenes/prefabs/ballista_tower.tscn`<br>`scenes/prefabs/floor_spikes.tscn`<br>`scenes/prefabs/remote_mine.tscn`<br>`scenes/prefabs/decoy_dummy.tscn`<br>`scenes/prefabs/temp_turret.tscn`<br>`scenes/prefabs/workbench.tscn` | Все 9 префабов созданы и функциональны: турели стреляют снарядами (`arrow_projectile.gd`), шипы и мины наносят урон, чучело агрит мобов. | Требуется балансировка параметров урона/прочности и визуальные стадии разрушения. |
| **Class Unique Gameplay** | `scripts/player_prototype.gd`<br>`scripts/roster_manager.gd` | Воин полностью укомплектован (3D Blockbench воксельная модель `hero_warrior.tscn`, анимации атаки/блока). Классы Лучник и Инженер доступны в меню. | В игровом прототипе персонаж всегда использует контроллер Воина. Уникальные механики оружия Лучника (лук/стрелы) и Инженера (гаечный ключ/мобильная турель) в `player_prototype.gd` не разделены. |

---

## ⚪ PLANNED (Запланировано в GDD / Backlog, код отсутствует)

| Система | Запланированный этап | Технический план реализации |
| :--- | :--- | :--- |
| **C++ 2D Flowfield Pathfinding** | Milestone 5 (`docs/BACKLOG.md` 3.1 & 5.7) | Расчёт векторного поля дистанций (Dijkstra + integration field) в C++ GDExtension для 500+ юнитов без индивидуального поиска пути. В текущем коде враги двигаются по прямой. |
| **MultiMesh Crowd Renderer** | Milestone 5 | Отрисовка больших толп через `MultiMeshInstance3D` с GPU-инстансингом трансформаций. Сейчас каждый враг — отдельный `CharacterBody3D`. |
| **Audio & SFX System** | Milestone 4 | Подключение звуковой шины (`AudioServer`), пространственных звуков шагов, ударов, разрушения построек, эмбиента дня/ночи и музыки. Аудиофайлы отсутствуют. |

---

## 🔴 DEPRECATED / OBSOLETE CLAIMS

> [!WARNING]
> В `README.md` содержится утверждение о том, что Flowfield Pathfinding на C++ уже функционирует. Согласно ревизии исходного кода `src/` и `docs/BACKLOG.md`, Flowfield находится в статусе **PLANNED** и ожидает реализации в рамках отдельного Issue.
