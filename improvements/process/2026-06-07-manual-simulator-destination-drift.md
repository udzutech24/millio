# Manual Simulator Destination Drift

## Диагноз

Ручная проверка была сделана на booted `iPhone 17 Pro Max / iOS 26.2`, а автоматические тесты и предыдущие проверки шли на `iPhone 17 / iOS 26.5`.
Из-за этого легко принять старую установленную сборку или другой simulator runtime за регрессию текущего кода.

## Правило

Когда баг подтверждается скрином из Simulator, перед выводом о коде фиксировать:
- booted device UUID и OS через `xcrun simctl list devices booted`;
- destination тестов/сборки;
- установлен ли app на этом же UUID через `xcrun simctl get_app_container <uuid> <bundle-id> app`;
- время установленного бинаря, если подозревается stale build.

## Эффект

Меньше ложных фиксов и меньше риска чинить сервисный слой, когда проблема в destination drift или stale installed app.
