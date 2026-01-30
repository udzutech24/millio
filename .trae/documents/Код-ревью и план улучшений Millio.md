## С чего начнем (приоритет)
### Шаг 1 — P0: убрать возможные крэши (быстро, высокий эффект)
- Заменить `try!` в [millioApp.swift](file:///Users/sidorkin/xcode/millio/millio/millioApp.swift#L105-L107) на безопасный fallback без принудительного unwrap.
- Убрать `first!` в [FinanceDynamicsViewModel.swift](file:///Users/sidorkin/xcode/millio/millio/UI/Services/Finances/FinanceDynamicsViewModel.swift#L353-L398) (guard/if + fallback в `.aggregated`).

### Шаг 2 — P0: убрать `asyncAfter` в финанcах (устойчивость UI)
- Заменить `DispatchQueue.main.asyncAfter(...)` в [FinancesView.swift](file:///Users/sidorkin/xcode/millio/millio/UI/Services/Finances/FinancesView.swift#L1537-L1622) на детерминированный сигнал “модель создана”:
  - либо сделать в Card/Credit/Investment ViewModel метод создания, который возвращает созданный `uniqueID`,
  - либо публиковать событие через [EventBus.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Events/EventBus.swift) и ловить его в FinancesView.

### Шаг 3 — P1: сделать backup/restore надежным
- Ввести `BackupEnvelope` (Codable) и хранить флаги `compressed/encrypted` + `originalSize`.
- Переделать `decompress` в [BackupManager.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Backup/BackupManager.swift#L146-L170), чтобы не было эвристики `*10`.
- Принять решение по шифрованию (device-key vs passphrase), чтобы restore после переустановки не оказался невозможным.

### Шаг 4 — P2: убрать знание Core о бизнес-моделях
- Перевести экспорт/импорт/clear из [DataRepository.swift](file:///Users/sidorkin/xcode/millio/millio/Core/Repository/DataRepository.swift) на зарегистрированные feature-handlers.

## Верификация
- Прогнать unit-тесты и добавить тесты на envelope/шифрование/большие архивы.

Если следовать KISS, то стартуем с Шага 1, затем Шаг 2 — это самое быстрое и сразу снижает риск падений и “хрупких” сценариев UI.