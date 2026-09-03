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

Файл плагина скачан в каталог плагинов Blockbench:
`%APPDATA%\Blockbench\plugins\mcp.js` (Windows) или `~/.config/Blockbench/plugins/mcp.js` (Linux).

> [!IMPORTANT]
> **Единственный ручной шаг в GUI Blockbench**:
> 1. Откройте приложение Blockbench.
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
1. Проверку компилятора, Python, SCons, Git и Godot.
2. Проверку инициализации субмодуля `godot-cpp`.
3. Сборку C++ GDExtension (`scons`).
4. Headless-импорт проекта и валидацию GDScript-классов.
5. Запуск набора дымовых тестов GUT (`res://tests/smoke/`).
6. Симуляцию 100 кадров игры в headless-режиме (`--quit-after 100`).

---

## 8. Шпаргалка инженера (Daily Commands)

| Действие | Команда |
| :--- | :--- |
| **Полная проверка проекта** | `python tools/verify.py` |
| **Запуск GUT тестов** | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/smoke/ -gexit` |
| **Сборка C++** | `scons custom_api_file=extension_api.json platform=windows target=template_debug` |
| **Проверка статуса MCP** | `python tools/gdmcp.py doctor` |
| **Инспекция дерева нод** | `python tools/gdmcp.py tree --depth 4` |
| **Запуск игры (Headless smoke)** | `godot --headless --path . --quit-after 100` |
