# 📊 Cube Siege — Фактический статус реализации систем

Документ отражает реальное состояние кодовой базы по результатам аудита исполняемого кода, ресурсов и тестов.

---

## 🟢 IMPLEMENTED (Полностью реализовано и проверено)

| Система / Компонент | Расположение | Описание и проверка |
| :--- | :--- | :--- |
| **EventBus (Шина событий)** | `scripts/event_bus.gd` | Централизованная шина сигналов (`combat`, `economy`, `safe_zone`, `talents`, `day_night`). Проверена автотестом `test_project_loads.gd`. |
| **Mastery & Talent Progression** | `scripts/mastery_manager.gd` | Опыт, уровни, прокачка 4 веток талантов (Кровожадность, Выживаемость, Проворство, Ремесло). Сохранение и сброс очков. |
| **Roster & Characters** | `scripts/roster_manager.gd` | Конфигурация 3 классов: Воин (Warrior), Лучник (Archer), Инженер (Engineer). |
| **Save & Persistence** | `scripts/save_manager.gd` | Сохранение и загрузка состояния в `user://save_game.json` с проверкой целостности. |
| **Main Menu & Meta UI** | `scenes/main_menu.tscn`<br>`scripts/main_menu.gd` | Выбор персонажей, дерево талантов, запуск игры. Проверено в `test_main_menu.gd`. |
| **Main Gameplay Scene** | `scenes/main.tscn`<br>`scripts/main.gd` | Оркестрация игрового цикла, изометрическая камера, HUD ресурсов и волн. Проверено в `test_main_scene.gd`. |
| **Player Controller (GDScript)** | `scenes/player.tscn`<br>`scripts/player.gd` | Изометрическое движение (WASD), прицеливание, атака, получение урона, анимация. Проверено в `test_player_scene.gd`. |
| **Player Controller (C++ Graybox)** | `src/player_controller.cpp`<br>`src/player_controller.h` | Нативный контроллер перемещения для hot path. Скомпилирован в debug GDExtension DLL. |
| **Day / Night Director** | `scripts/day_night_director.gd` | Таймер фазы дня (сбор, строительство) и ночи (осада). Освещение и туман. |
| **Safe Zone & Dynamic Barrier** | `scenes/safe_zone.tscn`<br>`scripts/safe_zone.gd` | Безопасный радиус, защищающий от ночного урона, динамическое расширение при апгрейде. |
| **Portal & Extraction** | `scenes/portal.tscn`<br>`scripts/portal.gd` | Починка портала (ресурсы: дерево, камень, время), запуск эвакуации. |
| **Radial Build Menu** | `scenes/radial_menu.tscn`<br>`scripts/radial_menu.gd` | Круговое меню выбора построек (стены, турели, ловушки). |
| **Workbench Crafting Modal** | `scenes/workbench_modal.tscn`<br>`scripts/workbench_modal.gd` | Крафт инструментов и боеприпасов на верстаке. |
| **Card Draft Popup** | `scenes/card_draft_popup.tscn`<br>`scripts/card_draft_popup.gd` | Выбор 1 из 3 карточек усилений при повышении уровня / пережитой ночи. |
| **Automated Testing Harness** | `addons/gut/`<br>`tests/smoke/` | Фреймворк GUT 9.6.1, набор smoke-тестов, headless запуск. |
| **Godot MCP Native Server** | `addons/godot_mcp/`<br>`tools/gdmcp.py` | Полнофункциональный двусторонний мост MCP (HTTP 9080 + CLI wrapper). |

---

## 🟡 PARTIAL (Частично реализовано)

| Система | Расположение | Что готово | Что предстоит доделать |
| :--- | :--- | :--- | :--- |
| **Enemy AI & Spawning** | `scripts/spawner.gd`<br>`scripts/enemy.gd` | Базовый спавн врагов по периметру ночью, движение к игроку и порталу. | Нет кластеризации толпы, нет специфических архетипов врагов (танки, стрелки, камикадзе). |
| **Defensive Buildings** | `scripts/building.gd` | Базовая сетка размещения и получение урона стенами. | Стрельба турелей, замедляющие эффекты ловушек, визуальные стадии разрушения. |
| **Class Unique Skills** | `scripts/skills/` | У Воина есть базовая атака мечом и блок щитом. | Активные скиллы Лучника (веер стрел, ловушка) и Инженера (мобильная турель, генератор щита). |
| **Blockbench Voxel Assets** | `assets/models/` | Воин смоделирован и анимирован в Blockbench. | Модели мобов, лучника, инженера и построек находятся в graybox-состоянии. |

---

## ⚪ PLANNED (Запланировано в GDD / Backlog, код отсутствует)

| Система | Запланированный milestone | Технический план реализации |
| :--- | :--- | :--- |
| **C++ 2D Flowfield Pathfinding** | Milestone 5 (`docs/BACKLOG.md` 3.1 & 5.7) | Расчёт векторного поля дистанций (Dijkstra + integration field) в C++ GDExtension для 500+ юнитов без поиска путей каждым мобом. |
| **Night Boss Encounters** | Milestone 4 | Уникальные боссы ночей 3, 5, 7 с фазами, спецспособностями и призывом миньонов. |
| **MultiMesh Crowd Renderer** | Milestone 5 | Отрисовка больших толп через `MultiMeshInstance3D` с инстансингом трансформаций. |
| **Audio & SFX System** | Milestone 4 | Подключение звуковой шины (`AudioServer`), звуков ударов, окружения дня/ночи и музыки. |

---

## 🔴 DEPRECATED / OBSOLETE CLAIMS

> [!WARNING]
> В `README.md` содержится устаревшее маркетинговое утверждение о том, что Flowfield Pathfinding уже работает на C++. Согласно аудиту кодовой базы и `docs/BACKLOG.md` (пункты 3.1 и 5.7), Flowfield находится в статусе **PLANNED** и будет разработан в рамках отдельного Issue.
