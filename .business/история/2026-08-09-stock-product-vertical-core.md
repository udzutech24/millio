# Итог: продуктовая вертикаль «Акции»

## Какая задача была поставлена

Исследовать, спроектировать и реализовать полную stock-вертикаль: лоты, P&L, сделки, Cashflow, котировки, FX, графики, UX, localization/accessibility и release audit.

## Как задача решалась

По workflow `$millio-bulletproof` зафиксирован baseline, контракт FIFO и девятифазный план. Реализован чистый lot engine, комиссии buy/sell, hard oversell guard и перевод detail P&L с UI-формулы на реплей ядра. Схема не менялась.

## Решена ли задача

Частично. Финансовое ядро получило первый безопасный срез; большая часть UX, historical/FX, Cashflow, corporate actions и render/release audit остаётся.

## Эффективно ли решение

Да для этапа: аддитивный pure engine, без миграции и drive-by рефакторинга. Параллельный прогон неэффективен из-за неизолированных SwiftData tests; финальный gate запущен последовательно.

## Как было до и как стало

До: oversell создавал отрицательную quantity; realized/unrealized P&L смешивались; комиссии сделок не хранились. Стало: FIFO лоты и cost basis выводятся детерминированно; fee учитывается один раз; oversell не попадает даже в SwiftData inverse relationship.

Stock detail получил контрастный hero и смысловые цвета действий. Buy/sell формы обновляют и подставляют текущую котировку, показывают live total и не дают сохранить oversell.

## Идеи по улучшению

Выделить серийный SwiftData test fixture или убрать shared global state, чтобы AccountsCoreService suite был детерминирован и при parallel testing.

Release-сборка выявила compiler-budget failure в `InlineCardCreateForm`: одна SwiftUI generic-цепочка объединяла секции, 15 observers, sheet и alert. Цепочка разделена на именованные compiler boundaries без изменения UX; Release simulator build после этого прошёл.

Аудит реального 375-pt скриншота выявил overflow действий, дубль ticker/name, неверный freshness badge, нулевой opening event в history и неполную финансовую сводку. Все пять дефектов устранены; current quote теперь считается свежей только при exact today cache evidence.
