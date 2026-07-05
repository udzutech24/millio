# Автоматизация UI-проверок на симуляторе без XCUITest (опыт 2026-07-04)

Контекст: сим-проверка accounts-core (сид → 4 экрана → скриншоты) руками агента.

## Что работает
- **Тапы**: `cliclick c:X,Y` (нужно разрешение Accessibility для процесса Claude/VS Code).
  Маппинг координат окна Simulator: `screen = (70.5 + pt_x*1.048, 99 + pt_y*1.048)` для окна
  456×972 @ (53,43), iPhone 17 Pro (402×874pt); титлбар ≈56px, контент вписан по высоте с полями.
  Калибровать эмпирически: клик → `simctl io screenshot` → проверка реакции. Верх экрана —
  зона максимальной ошибки.
- **Скриншоты**: `xcrun simctl io <UDID> screenshot` — работает всегда, даже при lock screen.
- **Скроллы**: `cliclick dd/dm/du` — драг; стартовать с НЕкликабельной зоны, иначе засчитается тап.
- **Debug-меню без 4 тапов+пароля**: писать `debugMenuUnlocked=true` НАПРЯМУЮ в контейнерный
  plist (`<app container>/Library/Preferences/com.millio.app.plist` через PlistBuddy при убитом
  приложении). `simctl spawn defaults write` пишет в ГЛОБАЛЬНЫЙ домен сима — приложение его НЕ видит.
- **Верификация данных**: sqlite3 read-only прямо по `SwiftDataScopes/*.store` — быстрее и
  надёжнее, чем разглядывать UI (ZACCOUNT/ZACCOUNTEVENT/Z_PRIMARYKEY).

## Грабли
- Несколько окон Simulator → клики уходят в верхнее окно. Лишние симы выключать
  (`simctl shutdown`), временные удалять.
- Клик в y<40 глобального экрана = menu bar macOS.
- **Lock screen (loginwindow layer>2000) молча съедает все клики** — проверять
  CGWindowList перед длинной серией; скриншоты сима при этом работают, что маскирует проблему.
- xcodebuild по умолчанию собирает Release-конфиг схемы → `#if DEBUG` код (сид-кнопка)
  отсутствует; явно указывать `-configuration Debug`.
- `simctl launch --console-pty` не ловит print() надёжно; unified log не содержит print.

## Идея на будущее
Для повторяемых проверок дешевле один XCUITest-сценарий (сид + скриншоты 4 экранов через
accessibilityIdentifier), чем координатные клики: идентификаторы уже расставлены
(`profile.adminStats.seedAccountsCoreButton` и др.).
