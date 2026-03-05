# Launch Splash

Дата: 2026-03-05

## Что реализовано

- Runtime-экран загрузки (`LaunchingView`) заменен на анимированный splash:
  - фон `LaunchImage` с плавным дрейфом (offset + scale),
  - появление `Millio` через spring-анимацию,
  - короткий shimmer-проход по логотипу,
  - появление индикатора загрузки.
- Добавлена минимальная длительность показа splash: 2.2 секунды перед сменой `lifecycle` с `.launching`.
- Добавлен пользовательский режим показа splash в профиле:
  - `Всегда`,
  - `Раз в день`,
  - `Выключен`.
- Добавлен тактильный сценарий:
  - обычный режим: `soft impact` -> `success notification`,
  - `Reduce Motion`: только `soft impact`.
- `LaunchScreen.storyboard` очищен от старого слогана `ваш лучший помощник` для более чистого перехода в runtime splash.

## Технические детали

- План haptic вынесен в `UI/Launching/LaunchSplashHapticsPlan.swift`.
- Минимальная длительность splash задается в `Core/UseCases/AppLifecycleUseCase.swift` (по умолчанию 2.2s, в тестах отключается автоматически).
- Политика показа splash (режим и дата последнего показа) хранится в `SettingsManager`.
- План покрыт юнит-тестами в `millioTests/UI/Launching/LaunchSplashHapticsPlanTests.swift`.
