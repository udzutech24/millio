# Offline resilience — Phase 0 handoff

## Задача

Реализовать phased plan offline-resilience, начиная с гарантии локального UI не позднее T+5 при недоступном backend.

## Что сделано

- Прочитаны research, spec, plan и обязательные правила проекта.
- Зафиксированы несвязанные пользовательские изменения; они не редактировались.
- Добавлены независимые состояния доступности backend и root-level offline indicator.
- Убрано ожидание probe из runtime endpoint selection; повторный probe того же URL больше не выполняется последовательно.

## Статус

Частично. Фаза 0 не подписана: `AuthManager.restoreSession()` остаётся в cold-start пути и может ожидать backend. Это делает утверждение «local-ready к T+5» недоказанным. Переход к Phase 1 был бы слабым и небезопасным решением.

## Проверка

Focused xcodebuild был запущен, но не дошёл до компиляции: CoreSimulator сообщил об отказе `simdiskimaged`, затем Xcode не смог разрешить package dependencies.

## Эффективность и следующий шаг

Разделение endpoint selection и availability — правильное минимальное направление, но недостаточное без bounded auth-restore/local scope path. Следующая сессия должна сначала покрыть этот путь детерминированным lifecycle harness и повторно запустить focused tests; только затем можно начинать durable cache.
