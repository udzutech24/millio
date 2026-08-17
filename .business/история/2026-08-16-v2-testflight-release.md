# Millio 2.0 (1): TestFlight release

## Какая задача была поставлена

Подготовить текущий working tree как Millio `2.0 (1)`, сделать commit/push в `develop` и загрузить новую сборку в TestFlight.

## Как задача решалась

- Версия app, Currency Widget и Statement Share Extension синхронизирована на `2.0 (1)`.
- Выполнен focused release gate для Unified Entry и statement onboarding: 33/33 теста прошли.
- Полный historical unit suite запущен серийно, но не является green gate: есть stale/characterization assertions в Accounts totals, credit-card mapping и group deletion, а также simulator test-host restart. Прогон остановлен после того, как красный gate был доказан.
- Localization audit остаётся красным: есть hardcoded Cyrillic и неполное покрытие xcstrings. Это известный риск TestFlight, а не зелёный production gate.
- Release archive и App Store IPA успешно собраны. Все три bundle имеют `2.0 (1)`, deep code-sign verification проходит.

## Решена ли задача

Да для internal TestFlight. Release commit `7ac7d57` отправлен в `origin/develop`. Xcode/App Store Connect провёл server-side analysis, принял IPA и вернул `Upload succeeded`; сборка `2.0 (1)` перешла в processing.

## Эффективно ли решение

Да для internal TestFlight: артефакт проверен и focused gate зелёный. Нет для production release: красные full-suite и localization gates запрещают выдавать эту сборку за App Store-ready.

## Как было и как стало

Было: dirty working tree с версией `1.9 (10)` и неформальным device build. Стало: версионированный, подписанный и проверенный App Store IPA `2.0 (1)`.

## Идеи по улучшению

Релизный lane должен fail-fast проверять одинаковую версию всех embedded bundle, наличие signing profile для каждого extension и отделять internal TestFlight gate от production gate.
