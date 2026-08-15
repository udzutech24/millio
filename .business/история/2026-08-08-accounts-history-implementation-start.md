# Accounts history source of truth — старт реализации

## Какая задача была поставлена

Полностью реализовать фазовый план Accounts history source of truth, начав с
контрактной сверки и red baseline.

## Как задача решалась

Прочитаны все нормативные документы и `$millio-bulletproof`. Три независимых
read-only аудита проверили valuation, product creation/persistence и consumer lineage.
Спека сверена с финальным планом. Добавлены точная night-jump fixture и snapshot
equivalence test. Начата 1V: structured result, frozen timezone и фикс same-day cache.

## Решена ли задача

Частично. Phase 0 закрыта; Phase 1V начата, но её exit gate ещё открыт. Фазы
2V–6 не реализованы; выдавать это за complete было бы ложью.

## Эффективно ли решение

Да для закрытого scope: production-изменение snapshot минимально, контрактные
типы изолированы, drive-by рефакторинга нет. Неэффективно было бы пытаться
втиснуть все восемь фаз без честных gates.

## Как было до и как стало

До: spec противоречила плану, точная дельта не была тестом, snapshot менял replay.
Стало: контракты согласованы, дефект 22 507 974 воспроизводится, snapshot-backed
same-day query равен direct replay, incomplete result не имеет public total.

## Идеи по улучшению

Нужно вынести typed fetch/rebuild seams до попытки тестировать failure semantics;
иначе тесты будут хрупкими и не управляемыми.
