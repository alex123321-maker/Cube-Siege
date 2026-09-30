# Codex в автономном review loop

Watcher поддерживает два назначения: `antigravity` и `codex`. Старые записи без `agent_provider` и прежние строковые привязки веток считаются Antigravity. Для Codex используются точный UUID чата и команда установленного CLI `codex queue --thread <uuid> --message <text>`; модель, permissions и активный чат не подменяются. Проверено по `codex-cli 0.158.0-alpha.2.1` и локальной справке `codex queue --help`.

## Настройка и регистрация

1. Проверь `codex --version`, `codex queue --help` и `gh auth status`. Нужны Codex с поддержкой `queue`, доступ к существующему локальному чату/его app-server и авторизация GitHub. Браузерный ChatGPT этим backend не поддерживается.
2. Если watcher не находит CLI в PATH, задай `REVIEW_LOOP_CODEX_EXE` с абсолютным путём к нативному `codex.exe`/исполняемому файлу Codex в окружении watcher. Windows `.cmd`/`.bat` shims не исполняются через shell. Не переустанавливай или не перезапускай сам Codex ради доставки замечаний.
3. Создавай PR через `tools/review_loop/create_pr.py --agent codex --conversation-id <uuid> -- <аргументы gh pr create>`. Аргумент `--thread-id` — синоним `--conversation-id`. Явные значения приоритетны; без ID используется `CODEX_THREAD_ID`, затем сохранённая привязка **того же** провайдера. При отсутствии `--agent` учитывается среда текущего агента; если обе среды заданы и назначение неоднозначно, укажи провайдера явно.
4. Для существующего PR вызови `python tools/review_loop/register.py --agent codex --pr <number> --conversation-id <uuid>`.
5. В Windows запусти `python tools/review_loop/install.py ensure --agent codex`. При отсутствии задачи он установит постоянный запуск в Планировщике заданий, затем проверит PID за 20 секунд. Для обновления установленной конфигурации сначала выполни `install --agent codex`. Имена задач: `CubeSiegeReviewLoopWatcherCodex` и `AssetFactoryReviewLoopWatcherCodex`. Это задачи пользователя, а не службы Windows: они стартуют при входе пользователя после загрузки компьютера, когда доступна его сессия Codex/GitHub.
6. Задача запускает `pythonw.exe` без окна и работает без ограничения времени службы. Для восстановления заданы перезапуск через минуту после сбоя и независимый триггер каждую минуту; параллельные экземпляры запрещены. Независимый триггер действует и после ручного запуска задачи в текущей Windows-сессии. Сон/выключение компьютера приостанавливают работу. Сам Codex должен быть доступен для доставки в чат. Ограничения отдельных операций — [OPERATION_TIMEOUTS.md](OPERATION_TIMEOUTS.md).
7. Antigravity работает своим sidecar-процессом с `watcher.pid`; Codex — отдельным процессом с `watcher_codex.pid`. Оба используют общий транзакционный state, но каждый обрабатывает только своего провайдера. Остановка Codex не останавливает Antigravity. Старые sidecar продолжают использовать CLI по умолчанию `--agent antigravity`.
8. После обновления кода перезапусти watcher, убедившись, что нет активного исправления: `install.py stop --agent codex`, затем `install.py start --agent codex`. Остановка задачи временная: её триггеры остаются; для отключения автозапуска — `uninstall --agent codex`. Для foreground/другой ОС: `python tools/review_loop/watcher.py --agent codex`; остановка Ctrl+C. Установка постоянной службы через этот helper поддерживается на Windows.
9. При отдельном runtime checkout установи туда эту же версию review-loop кода, затем выполни installer из runtime с `ASSET_REVIEW_REPO_ROOT`, указывающим рабочий ассет-репозиторий. Обновление рабочего репозитория не обновляет другой checkout. Конфигурация задачи хранит source root, repo root и путь Codex в `.review_loop/codex_service.json`; после смены расположения CLI переустанови задачу.

Наличие сервера mentor/image в Antigravity не означает его подключение в Codex. Следуй [AGENTS.md](../AGENTS.md) и [MCP_BRIDGE.md](MCP_BRIDGE.md); watcher не меняет MCP-конфигурации.

## Доставка и завершение

- В `.review_loop/state.json` сохраняются PR, ветка, `agent_provider`, `conversation_id`, текущий run и события. Antigravity hook не перехватывает ветку, привязанную к Codex. Активное Codex-направление нельзя заменить другим чатом/провайдером до завершения run.
- Перед отправкой проверяется текущая ветка checkout. Полный Unicode-текст замечаний сохраняется без обрезки в `.review_loop/feedback/codex_pr_<N>_run_<R>_<sha256>.txt`. В очередь чата уходит короткая ссылка на файл с digest. Агент проверяет checkout/ветку и читает файл полностью.
- Успешный `queue` означает доставку, а не исправление. Новые отзывы сохраняются в pending до окончания текущего запуска, не создавая второй запрос на те же события.
- Агент подтверждает завершение после проверок и требуемых commit/push/вложений: `python tools/review_loop/complete_run.py <N> --run-id <R>`. Подтверждение нужно и для исправления без изменений. Оно записывается в том же state, а watcher атомарно закрывает только события указанного run.
- При дизайнерском блокере: та же команда с `--status awaiting_design_decision`. Замечания сохраняются; незавершённое не объявляется выполненным.
- Ошибка/тайм-аут доставки или отсутствие подтверждения в течение 30 минут переводит PR в `error`, сохраняя замечания. Автоматического повтора нет: сообщение могло остаться в очереди чата. Изменение HEAD само по себе не разрешает повторную отправку.
- После проверки чата и устранения причины можно явно вызвать `python tools/review_loop/register.py --reactivate <N>`. Старое подтверждение с прошлым run ID не завершит новый запуск. Не реактивируй ещё выполняющееся или стоящее в очереди задание.

## Диагностика

```powershell
python tools/review_loop/register.py --list
python tools/review_loop/install.py status --agent codex
python -m unittest discover -s tests/unit -p "test_review*.py"
```

Смотри provider и ID в списке, `.review_loop/watcher_codex.log`, `last_dispatch_error` в state, а при проблеме запуска — `.review_loop/watcher_codex_startup.log`. Не редактируй state вручную во время работы watcher.

Для проверки реального подключения используй отдельный согласованный тестовый PR/чат: замечание → одна доставка → чтение полного файла → исправление/проверка → run-scoped completion → переход в watching без повторной доставки. Unit/integration tests не доказывают фактическую доставку в GUI.

Инструкции Codex оформлены в `AGENTS.md` по [официальной документации](https://learn.chatgpt.com/docs/agent-configuration/agents-md). Здесь используется очередь существующего чата; альтернативный [неинтерактивный exec resume](https://learn.chatgpt.com/docs/non-interactive-mode#resume-a-non-interactive-session) автоматически не запускается, чтобы не исполнять одну задачу одновременно в двух процессах.
