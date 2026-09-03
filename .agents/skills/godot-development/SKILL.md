---
name: godot-development
description: Use this skill when modifying Godot scenes (.tscn), GDScript code, resources (.tres), project settings, InputMap, Autoloads, running the game, or inspecting the live Godot scene tree and editor.
---

# Godot Development Skill

Руководство по разработке, инспекции и модификации проектов на движке Godot 4.6.

## Ключевой цикл работы
**Inspect → Modify → Validate → Run → Observe → Verify**

1. **Inspect**:
   - Перед редактированием сцены (`.tscn`) изучить структуру дерева узлов, пути (`NodePath`), свойства и привязанные сигналы.
   - Предпочитать структурированные операции через Godot MCP / CLI (`tools/gdmcp.py`) или проверку сцены перед «слепым» редактированием текстового формата `.tscn`.
2. **Modify**:
   - Применять типизированный GDScript.
   - Менять минимально необходимую область в скриптах или сценах.
   - Сохранять согласованность `uid://` и путей зависимостей ресурсов.
3. **Validate**:
   - Проверить синтаксис скриптов и отсутствие битых ссылок:
     ```bash
     godot --headless --editor --quit
     ```
   - Убедиться, что нет предупреждений о missing resources или broken scripts.
4. **Run & Observe**:
   - Запустить сцену или проект:
     ```bash
     godot --headless --path . --quit-after 100
     ```
   - Читать runtime логи и вывод консоли. Убедиться в отсутствии stack trace ошибок.
5. **Verify**:
   - Запустить тесты GUT (`python tools/verify.py`).
   - Если изменение затрагивает UI или визуал — сделать скриншот и оценить результат.
