# Plan: backend-probe-timeout

**Slug:** `backend-probe-timeout`
**Дата создания:** 2026-05-11
**Stage:** 1 / Design
**Размер:** S (1 файл: BackendRuntime.swift)
**Связан с:** `plans/2026-05-11__cloudkit-snapshot-cache.md` (обнаружен как следующий bottleneck после оптимизации CloudKit)

## Статус

`НЕ НАЧАТ`

## Контекст

После `cloudkit-snapshot-cache` CloudKit больше не является bottleneck холодного старта. Но `initializeColdStart = 16 932 ms` при `AppLifecycleUseCase.initialize = 6 558 ms` — разница ~10 s.

Причина: `BackendStartupResolver.resolve()` (вызывается первым в `initializeColdStart` через `resolveBackendRuntimeIfNeeded()`) делает HTTP probe к preferred endpoint с `timeoutInterval = 8`. Когда preferred endpoint недоступен (пользователь в AM, preferred = DE) — probe тайм-аутится за 8s, потом fallback probe проходит быстро.

```swift
// BackendRuntime.swift:313
private func probe(endpoint: BackendEndpoint, logPrefix: String) async -> Bool {
    var request = URLRequest(url: probeURL)
    request.timeoutInterval = 8   // ← блокирует initializeColdStart на 8s при недоступном endpoint
    ...
}
```

**Логи build 52 (устройство, AM):**
```
Backend preferred probe failed for https://api.iqdrop.ru/api/v1: The request timed out.
Selected backend region=DE baseURL=https://api.iqdrop.ru/api/v1 fallbackActive=true
AppLifecycleUseCase.initialize finished in 6558.780583 ms
initializeColdStart finished in 16932.337541 ms
```

Потенциальный выигрыш при снижении таймаута до 3s: `initializeColdStart` → ~6 558 + 3 000 + ~500 ≈ **~10 000 ms** вместо 16 932 ms. При нормальной сети с доступным preferred endpoint — без изменений.

## Решение

Три варианта, в порядке предпочтения:

### Вариант A: Снизить `timeoutInterval` (рекомендуется первым шагом)

`timeoutInterval = 8` → `timeoutInterval = 3` в `probe()`.

- Риск: на медленной 3G preferred endpoint может отвечать 3–5s и будет ложно считаться недоступным → fallback activation. Это некритично: fallback работает корректно, пользователь просто получит другой endpoint.
- Выигрыш: при недоступном endpoint (региональный сбой, плохая сеть) таймаут сокращается с 8s до 3s.

### Вариант B: Параллельный probe + lifecycle init

Запускать `BackendStartupResolver.resolve()` параллельно с lifecycle, а не до него. Lifecycle использует кэшированный runtime с прошлого запуска, применяет новый по завершении probe.

- Требует: кэш runtime в UserDefaults или Keychain (сохранять `selectedEndpoint.baseURL` между запусками).
- Сложнее: апдейт runtime может прийти в середине lifecycle init — нужно убедиться, что это безопасно.

### Вариант C: Кэш последнего endpoint

Сохранять `selectedEndpoint` в UserDefaults. При следующем запуске — сразу использовать, probe запускать в фоне (best-effort), применять если изменился.

## Acceptance Criteria

- [ ] AC1: При недоступном preferred endpoint (timeout) `initializeColdStart` ≤ 10 000 ms. (Device verification)
- [ ] AC2: При доступном preferred endpoint — поведение не меняется (endpoint выбирается корректно).
- [ ] AC3: Существующие тесты `BackendStartupResolverTests` — все passed.

## Фазы

### Фаза 1 — Снизить timeoutInterval [ ]

**Файл:** `millio/Core/Backend/BackendRuntime.swift`

1. `BackendStartupResolver.probe()` (line 313): изменить `timeoutInterval = 8` → `timeoutInterval = 3`.
2. Проверить `BackendStartupResolverTests` — убедиться, что тесты не hardcode 8s.

### Фаза 2 — Верификация на устройстве [ ]

1. Собрать, установить.
2. Проверить `initializeColdStart` при недоступном preferred endpoint.
3. Проверить, что при нормальной сети endpoint выбирается корректно.

## Вне скопа

- Параллельный probe (Вариант B) и кэш endpoint (Вариант C) — рассматривать только если Вариант A недостаточен.
- `iCloud status refresh` (~4.5s, третий `source=snapshotQuery` после `initializeColdStart`) — отдельная задача.

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-11 | Plan v1 создан. Обнаружен как следующий bottleneck в рамках device verification cloudkit-snapshot-cache. Наблюдение зафиксировано, план ждёт. |
