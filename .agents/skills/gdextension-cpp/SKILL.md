---
name: gdextension-cpp
description: Activate only when working with native C++ code in src/, godot-cpp bindings, SConstruct, or bin/cube_siege.gdextension.
---

# GDExtension C++ Development Skill

Руководство по компиляции, разработке и интеграции нативных модулей C++ через GDExtension в Cube Siege.

## Структура нативной подсистемы
- `src/`: Исходные файлы C++ (`player_controller.cpp`, `register_types.cpp` и др.).
- `godot-cpp/`: Git-субмодуль с биндингами C++ для Godot Engine 4.x.
- `bin/cube_siege.gdextension`: Манифест расширения, связывающий скомпилированные библиотеки с Godot.
- `extension_api.json`: Корневой файл спецификации API движка Godot 4.6.
- `SConstruct`: Корневой сценарий сборки через SCons.

## Сборка модуля
После любого изменения исходников в `src/` или файла `cube_siege.gdextension` обязательна компиляция:

```bash
scons custom_api_file=extension_api.json platform=windows target=template_debug -j4
```

> [!NOTE]
> Параметр `custom_api_file=extension_api.json` обязателен для синхронизации с текущей версией `godot-cpp`.

## Регистрация новых классов в ClassDB
1. Наследовать класс от подходящего типа Godot (например, `godot::CharacterBody3D`, `godot::RefCounted`).
2. Объявить макрос `GDCLASS(MyClass, ParentClass)` в заголовочном файле.
3. Переопределить `static void _bind_methods()` для экспорта методов и свойств в Godot.
4. В `src/register_types.cpp`:
   - Добавить заголовочный файл `#include "my_class.h"`;
   - В функции `initialize_cube_siege_module`: вызвать `godot::ClassDB::register_class<MyClass>();`.
5. Собрать модуль и проверить, что класс распознаётся в Godot без ошибок загрузки библиотеки.
