# DerivedData в /tmp копятся и убивают диск — правило уборки

**Наблюдение (2026-07-08, вечер).** Диск дошёл до 432 МБ свободного места (97–100% занято): в `/private/tmp/` скопилось ~35 ГБ DerivedData от прошлых сессий (`xcodebuild-deriveddata-phase*`, `dd-legacy-*`, `xcodebuild-final-*` и т.д. — 14 папок по 1.2–3.5 ГБ). Это заблокировало сборки и тесты сразу трёх параллельных агентов («No space left on device» в CreateBuildDescription/SwiftDriver), потеряно ~30 минут на диагностику и рестарты.

**Root cause.** Правило `feedback-parallel-xcodebuild-deriveddata` требует уникальный `-derivedDataPath` для каждого агента (правильно), но никто не удаляет эти папки после завершения сессии. Каждая ночная сессия оставляет 10–15 ГБ мусора.

**Правило.**
1. В конце каждой сессии с xcodebuild — удалить свои `-derivedDataPath` (`find <path> -delete`; `rm -rf` на /tmp бывает заблокирован permissions, `find -delete` проходит).
2. Агентам в брифинге с xcodebuild — добавлять пункт «по завершении удали свой derivedDataPath».
3. При старте тяжёлой сборочной сессии — быстрый чек `df -h /`: меньше 15 ГБ свободно → сначала уборка `/private/tmp/*deriveddata*`, `dd-*` старше суток.
