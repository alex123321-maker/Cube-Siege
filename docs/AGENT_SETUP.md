# 🛠️ Руководство по развёртыванию окружения Cube Siege

Данное руководство описывает воспроизведение рабочего окружения разработчика и агента (Gemini / Antigravity) на чистой машине с нуля.

---

## 1. Системные требования

* **ОС**: Windows 10/11 (64-bit) или Ubuntu 22.04+ (Linux x86_64).
* **Godot Engine**: **4.6.1-stable** (официальный бинарник Godot).
* **Python**: 3.10+ (с установленным pip).
* **SCons**: 4.x+ (`pip install scons`).
* **C++ компилятор**: MinGW-w64 (GCC 13+) / Clang / MSVC для Windows, GCC 11+ для Linux.
* **Git**: 2.30+ с поддержкой submodule.
* **GitHub CLI (`gh`)**: 2.30+ (**Обязательно для Issue-Driven Development** — чтение задач, создание PR).
* **Blockbench** *(опционально для работы с 3D вокселями)*: 4.10+.

---

## 2. Первоначальное клонирование и настройка

```bash
# 1. Клонирование репозитория вместе с субмодулями (godot-cpp)
git clone --recursive <repository_url> cube-siege
cd cube-siege

# Если субмодули не были инициализированы при clone:
git submodule update --init --recursive

# 2. Установка зависимостей сборки
python -m pip install --upgrade pip
python -m pip install scons

# 3. Установка и авторизация GitHub CLI (gh)
# Windows:
winget install --id GitHub.cli
# Linux (Ubuntu/Debian):
sudo apt update && sudo apt install gh
# macOS:
brew install gh

# Авторизация в GitHub (необходима для работы команды 'Implement issue #N'):
gh auth login
# Проверка статуса авторизации:
gh auth status
```

---

## 3. Настройка пути к исполняемому файлу Godot

Для работы скриптов верификации (`tools/verify.py`) и тестового раннера укажите путь к Godot одним из двух способов:

### Вариант А: Переменная окружения (Рекомендуется)
* **Windows (PowerShell)**:
  ```powershell
  [Environment]::SetEnvironmentVariable("GODOT_BIN", "C:\Path\To\godot.exe", "User")
  ```
* **Linux (bash/zsh)**:
  ```bash
  export GODOT_BIN="/usr/local/bin/godot"
  ```

### Вариант Б: Локальный файл конфигурации (Игнорируется в Git)
Создайте в корне репозитория файл `.godot_path` и запишите в него полный путь к исполняемому файлу Godot:
```text
C:\Godot\Godot_v4.6.1-stable_win64_console.exe
```

---

## 4. Сборка C++ GDExtension

Для компиляции нативной библиотеки контроллера и систем оптимизации:

```bash
# Сборка под Windows (Debug)
scons custom_api_file=extension_api.json platform=windows target=template_debug

# Сборка под Linux (Debug)
scons custom_api_file=extension_api.json platform=linux target=template_debug -j$(nproc)
```

---

## 5. Подключение Godot MCP Native

Плагин Godot MCP Native предустановлен в `addons/godot_mcp` и зарегистрирован в `project.godot`.

### Запуск Godot с сервером MCP
Чтобы Antigravity / Gemini могли напрямую инспектировать сцены и вызывать инструменты редактора, запустите Godot с флагом `--mcp-server`:

```bash
# Headless-режим (для агентов в фоне):
godot --headless --editor --path . -- --mcp-server --mcp-port=9080

# Режим редактора с GUI:
godot --editor --path . -- --mcp-server --mcp-port=9080
```

### Проверка работоспособности моста
С помощью companion CLI проверьте состояние сервера:
```bash
python tools/gdmcp.py doctor
python tools/gdmcp.py project-info
python tools/gdmcp.py tree
```

---

## 6. Подключение Blockbench MCP

Конфигурация MCP для Blockbench находится в `.agents/mcp_config.json` (`http://localhost:3000/bb-mcp`).

### Шаг 1: Автоматическая установка плагина
Для загрузки плагина `mcp.js` в каталог плагинов Blockbench запустите скрипт установки:
```bash
python tools/install_blockbench_mcp.py
```
Скрипт автоматически определит директорию плагинов для Windows (`%APPDATA%\Blockbench\plugins`), Linux (`~/.config/Blockbench/plugins`) или macOS и скачает актуальный файл `mcp.js`.

### Шаг 2: Активация в GUI Blockbench
> [!IMPORTANT]
> **Единственный ручной шаг в GUI Blockbench**:
> 1. Запустите настольное приложение Blockbench.
> 2. Перейдите в меню: **File → Plugins → Installed** (Файл → Плагины → Установленные).
> 3. Нажмите **Load Plugin from File** (Загрузить плагин из файла) и выберите файл `mcp.js` из папки плагинов (или включите тумблер плагина «Blockbench MCP Server», если он отобразился в списке).
> 4. Убедитесь, что сервер сообщает о прослушивании порта `3000`.

---

## 7. Полная автоматическая верификация

Перед началом и по завершении любой задачи выполните единую команду проверки:

```bash
python tools/verify.py
```

Скрипт автоматически выполнит:
1. Проверку инструментов: компилятора, Python, SCons, Git, GitHub CLI (`gh`) и Godot.
2. Проверку инициализации субмодуля `godot-cpp`.
3. Сборку C++ GDExtension (`scons`).
4. Headless-импорт проекта и валидацию GDScript-классов.
5. Запуск полного набора автотестов GUT (`res://tests/smoke/`, `res://tests/unit/`, `res://tests/integration/`) через `.gutconfig.json`.
6. Симуляцию 100 кадров игры в headless-режиме (`--quit-after 100`).

---

## 8. Шпаргалка инженера (Daily Commands)

| Действие | Команда |
| :--- | :--- |
| **Полная проверка проекта** | `python tools/verify.py` |
| **Запуск всех тестов GUT** | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json` |
| **Сборка C++** | `scons custom_api_file=extension_api.json platform=windows target=template_debug` |
| **Проверка статуса MCP** | `python tools/gdmcp.py doctor` |
| **Инспекция дерева нод** | `python tools/gdmcp.py tree --depth 4` |
| **Запуск игры (Headless smoke)** | `godot --headless --path . --quit-after 100` |
| **Просмотр задачи GitHub** | `gh issue view <N>` |
| **Регистрация PR в review loop** | `python tools/review_loop/register.py` |
| **Статус review watcher** | `python tools/review_loop/install.py status` |
| **Запуск watcher (run-once)** | `python tools/review_loop/watcher.py --run-once` |

---

## 9. Автономный цикл обработки ревью (Autonomous PR Review Feedback Loop)

Система автономного ревью замыкает цикл `implementation → PR review → fixes → re-review` без необходимости вручную копировать комментарии рецензента из GitHub в Gemini/Antigravity.

### 9.1. Принцип работы

```text
GitHub Issue
  ↓
Gemini / Antigravity реализует фичу
  ↓
Создание ветки + тесты + верификация
  ↓
Создание Pull Request (`gh pr create`)
  ↓
Регистрация PR в review loop (`python tools/review_loop/register.py`)
  ↓
Фоновый watcher отслеживает новые замечания
  ↓
При обнаружении REQUEST_CHANGES / комментариев / тредов:
автоматически возобновляет ту же сессию Antigravity (через agentapi send-message)
  ↓
Агент исправляет замечания, прогоняет `python tools/verify.py` и пушит в ту же ветку
  ↓
Watcher снимает блокировку и ожидает APPROVE или повторного ревью
```

### 9.2. Регистрация PR в цикле

После создания PR в ветке задачи выполните в терминале агента (где установлена переменная `$ANTIGRAVITY_CONVERSATION_ID`):

```bash
# Автоматически определяет текущую ветку, открытый PR и conversation ID
python tools/review_loop/register.py

# Просмотр списка зарегистрированных PR и списка доверенных рецензентов
python tools/review_loop/register.py --list

# Добавление дополнительного рецензента в allowlist (по умолчанию автор репозитория)
python tools/review_loop/register.py --allow-user <username>

# Отмена отслеживания PR
python tools/review_loop/register.py --unregister <pr_number>
```

### 9.3. Управление фоновой службой (Lifecycle)

Скрипт `tools/review_loop/install.py` управляет фоновым процессом без требования прав администратора / root:
* **Windows**: Создаёт пользовательскую задачу в Windows Task Scheduler (`schtasks`) с запуском при входе в систему (`onlogon`), а также поддерживает прямой запуск фонового процесса.
* **Linux**: Создаёт пользовательский systemd-юнит (`~/.config/systemd/user/cube-siege-review-watcher.service`).

```bash
# Установка службы автозапуска
python tools/review_loop/install.py install

# Запуск фонового вотчера
python tools/review_loop/install.py start

# Проверка статуса (процесс, задача в планировщике, последние строки лога)
python tools/review_loop/install.py status

# Остановка фонового вотчера
python tools/review_loop/install.py stop

# Удаление службы из автозапуска
python tools/review_loop/install.py uninstall
```

### 9.4. Логи и состояние

* **Лог работы**: `.review_loop/watcher.log` (добавляется в `.gitignore`, не содержит токенов и секретов).
* **Файл состояния**: `.review_loop/state.json` (хранит маппинг PR ↔ conversation ID, идентификаторы обработанных событий, блокировки от параллельных запусков).
