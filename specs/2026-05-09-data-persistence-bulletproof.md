# Spec: Bulletproof Data Persistence

**Date:** 2026-05-09
**Stage:** 2 / Spec
**Priority:** CRITICAL — пользовательские данные теряются при обновлении билда

## Problem

Данные на устройстве/симуляторе исчезают после установки нового Xcode-билда. Подтверждённые два корневых кейса.

### Root Cause A — Schema Divergence (ПОДТВЕРЖДЕНО)

`Cashback.self` был зарегистрирован в `ModelTypeRegistry` (→ попадал в `AppSchema.create()`), но отсутствовал в `AppSchemaV1`, `AppSchemaV2` и `AppMigrationPlan.makeContainer`.

Цепочка отказа:
1. Store создан через `freshConfig` (путь для нового пользователя) — включал `ZCASHBACK` таблицу
2. При следующем запуске: `AppMigrationPlan.makeContainer` открывает стор без знания о `Cashback`
3. SwiftData детектирует рассогласование схемы → throws
4. В DEBUG: `rebuildStorePreservingData` → переименовывает стор в `.bak`, создаёт пустой новый
5. Данные потеряны

Uncommitted fix (`git diff`) добавляет `Cashback.self` в V1/V2/makeContainer — это правильное направление, но **архитектурная проблема остаётся**: два независимых списка моделей (`ModelTypeRegistry` и `AppMigrationPlan`) без механизма синхронизации.

### Root Cause B — Auth/Scope Mismatch (ВЕРОЯТЕН, требует верификации)

Если `authManager.restoreSession()` не восстанавливает сессию (истёк токен, сеть недоступна), `isAuthenticated = false` → scope = `.guest` → приложение открывает пустой `millio_guest.store`, а данные пользователя живут в `millio_user_<hash>.store`.

### Root Cause C — Отсутствие защитной сетки

- Нет compile-time / runtime гарантии, что `AppMigrationPlan` и `AppSchema.create()` содержат одни модели
- Нет теста, который открывает реальный SQLite-файл и проверяет миграцию
- `rebuildStorePreservingData` в DEBUG стирает данные молча, без предупреждения разработчика

## Goal

Данные пользователя **никогда** не теряются при установке нового билда. Любое рассогласование схемы обнаруживается на этапе разработки (тест / assertion), а не в продакшне.

## Scope

- Единый источник правды для списка моделей SwiftData
- Устойчивость `DataScope` к сбоям auth-restore при запуске
- Runtime assertion (DEBUG) при расхождении схем
- Unit-тест: V1→V2 lightweight migration с реальным SQLite-fixture
- Unit-тест: списки моделей в V_current == AppMigrationPlan == AppSchema

## Non-Goals

- Автоматический restore из iCloud при потере данных (это отдельная фича backup-hardening)
- Conflict-resolution при merge нескольких store-файлов
- CloudKit live-sync (не часть архитектуры)

## Acceptance Criteria

1. **AC-1:** Установка нового DEBUG-билда на устройство с данными — данные сохраняются
2. **AC-2:** Добавление нового `@Model` без обновления плана миграции → падает unit-тест `SchemaConsistencyTests`
3. **AC-3:** Auth-restore не возвращает пользователя → приложение использует последний известный scope, не сбрасывается в `.guest`
4. **AC-4:** `SchemaMigrationTests` открывает binary V1 fixture с записями и проверяет что все записи доступны после миграции на V2
5. **AC-5:** `rebuildStorePreservingData` в DEBUG логирует путь `.bak`-файла с уровнем WARNING в консоль (уже есть — верифицировать)
6. **AC-6:** `AppSchema.create()` и `AppMigrationPlan.makeContainer` дают одинаковый набор типов моделей (проверяется тестом)
