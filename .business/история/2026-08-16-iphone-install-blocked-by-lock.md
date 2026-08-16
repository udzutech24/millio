# Установка Millio на iPhone

## Какая задача была поставлена

Установить текущую сборку Millio на подключённый iPhone.

## Как задача решалась

Проверены CLI-каналы CoreDevice/Xcode и резервный маршрут через UI Xcode. `devicectl` не смог инициализировать CoreDeviceService, а Computer Use определил, что Mac заблокирован.

## Решена ли задача

Да. После разблокировки Mac и iPhone текущий dirty-worktree собран в Debug для `iPhone A (2)` (iPhone 17 Pro Max). Первая обходная сборка с глобальным `CODE_SIGN_ENTITLEMENTS=''` падала в `CloudBackupStore`: crash-log показал `SIGTRAP` в `CloudKit` из-за отсутствующего iCloud entitlement. Сборка повторена с полными entitlements основного app (`iCloud.com.millio.app`, CloudKit, App Group), подпись проверена `codesign --verify --deep --strict`, bundle `com.millio.app` переустановлен и остался запущенным после контрольного ожидания. Данные приложения не удалялись.

## Эффективно ли решение

Частично: внешний блокер найден без destructive-действий, но первый build workaround был слишком широким и сломал runtime. После анализа crash-log применён корневой fix в маршруте сборки: entitlements основного app сохранены.

## Как было и как стало

Было: установка была заблокирована экранами блокировки. Стало: актуальная сборка установлена и открыта на iPhone 17 Pro Max.

## Идеи по улучшению

Перед physical install держать Mac и iPhone разблокированными до завершения подписи и запуска. Никогда не передавать `CODE_SIGN_ENTITLEMENTS=''` глобально в multi-target сборку: workaround для extension не должен снимать CloudKit/App Group с основного app.

## Дополнение: расхождение Unified Entry

16.08.2026 владелец сообщил, что видит на телефоне другой экран. Установленный `1.9 (10)` не доказывал актуальность: один build number использовался для нескольких локальных артефактов. Приложение заново собрано из текущего working tree в свежем DerivedData, entitlement проверены, bundle переустановлен без удаления app data. `devicectl` подтвердил запуск, процесс остался активен. Код и данные не менялись.

В следующих device-build нужен уникальный build identifier или записанный source revision; проверка только по `CFBundleVersion` хрупкая.
