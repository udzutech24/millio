# Backend startup probe — скрытый bottleneck cold start

**Дата:** 2026-05-11  
**Ось:** process (архитектурное наблюдение)

## Наблюдение

После оптимизации CloudKit-части холодного старта (`cloudkit-snapshot-cache`) выяснилось, что `initializeColdStart` всё равно 16 932 ms. Причина — `BackendStartupResolver.probe()` в `BackendRuntime.swift:313` с `timeoutInterval = 8`. Когда preferred endpoint недоступен (пользователь в AM, preferred = DE), probe тайм-аутится за 8s до перехода на fallback. Это происходит в `resolveBackendRuntimeIfNeeded()` — первом вызове внутри `initializeColdStart`, до lifecycle init.

## Почему важно

8s — это больше половины всего `initializeColdStart`. При нормальной сети этого нет. При любом региональном недоступном endpoint — это постоянная деградация. Это скрыто за `initializeColdStart`, который выглядел как CloudKit-проблема.

## Варианты решения

1. **Снизить таймаут** с 8s до 2–3s — минимальные правки, риск: на медленной сети (3G) preferred endpoint может отвечать дольше 3s и будет ложно считаться недоступным.
2. **Параллельный probe + lifecycle init** — запускать `BackendStartupResolver.resolve()` через `Task.detached`, lifecycle init начинать с предыдущим/кэшированным runtime, применять новый runtime по готовности. Более сложно, но устраняет блокировку.
3. **Кэш последнего успешного backend endpoint** — сохранять `selectedEndpoint` в UserDefaults, при следующем запуске использовать как hint. Probe в фоне, применять если изменился.

## Рекомендация

Вариант 1 (таймаут 3s) как быстрое улучшение. Потенциальный выигрыш: -5–6s от `initializeColdStart` при недоступном preferred endpoint.
