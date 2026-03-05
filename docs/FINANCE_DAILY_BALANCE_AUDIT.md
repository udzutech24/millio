# Finance Daily Balance Audit

## Что добавлено

Экран `FinanceBalanceAuditSheet` открывается как `sheet` из `FinanceDynamicsView` по кнопке `list.clipboard` в верхней панели.

Экран решает MVP-задачи:
- аудит дневного среза балансов по выбранной дате;
- ручная корректировка значения на дату с немедленной записью (`setValue`);
- удаление значения только на выбранную дату;
- удаление счёта навсегда (из ежедневных срезов + currency mapping + удаление сущности из SwiftData);
- правка валюты счёта;
- агрегаты по группам и валютам;
- поиск по названию/группе/валюте;
- пустой state для даты без записей;
- review mode с последовательным фокусом, `frequency` и `lastReviewDate` через `AppStorage`.

## Архитектура

Новые файлы:
- `millio/UI/Services/Finances/Audit/FinanceBalanceAuditModels.swift`
- `millio/UI/Services/Finances/Audit/FinanceBalanceAuditStore.swift`
- `millio/UI/Services/Finances/Audit/FinanceBalanceAuditViewModel.swift`
- `millio/UI/Services/Finances/Audit/FinanceBalanceAuditSheet.swift`

Ключевые решения:
- один режим редактирования: автосохранение на `onChange` без буферов;
- без reflection для валюты: только явные поля моделей;
- ключ дня `yyyy-MM-dd` через единый `Calendar` в `FinanceBalanceDayKey` для предсказуемости day-boundary;
- destructive операции подтверждаются через `confirmationDialog`.

## Нормализация знака

`FinanceBalanceAuditRow.normalizedValue` применяет правила:
- `accountTypeRaw == "credit"` отображается как отрицательное значение;
- если `effectSign < 0` и значение положительное, знак инвертируется в минус.

## Ограничения

Текущая версия не включает FX-конвертацию агрегатов в единую отчётную валюту. Это оставлено на Phase 2.
