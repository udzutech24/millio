# Handoff 2026-07-11 (ночь): Ф5c.7.4+5.5 — expand-фаза ВЫПОЛНЕНА, остался contract

## Коротко

Expand-фаза объединённого type-flip реализована полностью: 9 коммитов `a5169a7→f88abd2` поверх `7723d9d`, всё локально в `develop`, **НЕ запушено**. Конвейер: Александр (opus) кодит → независимый Fable-верификатор адверсариально проверяет каждый гейт → коммит только после CONFIRMED. Три гейта отклонялись с реальными дефектами — все закрыты фиксами в корне, ни один не «протолкнут». Полный журнал — в plan.md, секция 5c.7.4+5c.7.5, блок «Журнал expand-фазы».

## Состояние репо

- `develop`, HEAD `f88abd2`, дерево чистое. Не запушено, не смержено (develop сильно впереди origin — включая коммиты прошлых сессий).

```
f88abd2 test: Gate B — characterization-замок updateAccountAmount
0c23e0b fix:  Gate A — core-счета в валютной разбивке Динамики
6c31bd5 fix:  core-aware фильтр пустой Ungrouped в loadGroups
dd85c40 feat: №5 OverviewCard — снапшот + core-aware reloadToken
6855653 feat: №3 FinancesView.isGroupEmpty на снапшот
f20205f feat: №2 core-счета в FinanceGroupEditorView
2736945 feat: №1 FinanceRows на state.coreAccounts (+refresh-цепочка в корне)
a5169a7 feat: expand-шаг — state.coreGroups/coreAccounts рядом с легаси
```

## Что получил юзер (владелец) уже сейчас

- Редактор группы показывает core-счета (раньше — вообще нет).
- Валютная разбивка «Динамики» видит core-счета (раньше 0; двойник мигрированного счёта терялся полностью).
- Core-счета без группы не исчезают с карточки/списка (Ungrouped-фикс; вероятно закрыт и хвост «дубль Ungrouped» из 6b — **нужна визуальная проверка**).
- Дашборд-карточка реагирует на все core-мутации (баланс/архив/группа/rename).

## 🔴 Вопросы владельцу (блокируют части следующей сессии)

1. **Обход паволла:** free-лимит продуктов (`freeFinanceProductLimit=10`) считает только легаси-счета (`FinanceAddAccountView.swift:1288,1296-1298`), а создаются core-счета → free-юзер лимит обходит. Фикс прост (core+legacy count), но меняет gating free-юзеров → нужен sign-off (+решение про grandfathering).
2. **Роль `convertAccountToCore`/`unconvertAccountFromCore` (Track C, ~70 строк) после контрактного флипа** — в плане не определена: снести/оставить/переосмыслить?

## Что делать в следующей сессии (contract-шаг)

1. Прочитать plan.md секцию 5c.7.4+5c.7.5: «Журнал expand-фазы» (что уже сделано) + «Каталог flip-blocked» (полная карта сайтов) + Gate B parity-таблицу в `FinanceViewModelUpdateAccountAmountCharacterizationTests.swift` (шапка).
2. Contract-шаг = атомарный флип published-типов по каталогу: FVM published-поля, FDVM FetchDescriptor+кэши, FDV/Views сигнатуры, `FinanceGroupService`/`FinanceAccountService` API. Семантические узлы: `updateAccountAmount`→`adjustBalance` (по parity-карте Gate B — там знаковая инверсия долгов!), Ungrouped-сентинел для `visibleGroupsForList()→[AccountGroup]`, `FinanceRows`-подзаголовки, decoupling `InlineCreateForms`, rich-edit UI (перенос из 5c.7.0).
3. Граница: `getAccountsForCalculation`/`calculateBalanceAtDate` — сигнатуры legacy-typed НЕ трогать (Cashflow-потребители).
4. Гейт контракта — самый строгий в плане (см. план, «Гейт (объединённый)»): полный protected-кластер, characterization-числа те же, mixed-store, симулятор UI-flow, Fable-верификация особо строго.
5. После contract — 5c.7.6 (редизайн «Счета») и 5c.7.7 (финальный regression-гейт).

## PENDING (device, не блокер)

- Всё из прошлого handoff (5c.7.0/1/2) + новое: визуальная проверка Ungrouped-фикса и валютной разбивки на реальном бэкапе.

## Ментор-находки сессии

- **Мутационная проверка тестов** («закомментируй фикс — тест обязан упасть») вскрыла недостижимый dead code в собственном фиксе Gate A — рекомендуется как стандарт для data-critical гейтов.
- Верификатор трижды ловил реальные дефекты, которые сборка+тесты пропускали (refresh-gap, onDisappear-тайминг SwiftUI, недоказанный дедуп-слой) — паттерн «исполнитель+независимый адверсариальный верификатор на каждый гейт» окупился.
- Известное ограничение зафиксировано в коде: `coreAccountsForDynamics()` не уважает `selectedAccountIDs`/isSingleAccountMode (унаследовано, каскад — чинить при флипе).
- Sparkline на core-строках — feature gap (не regression): закрывать через `AccountDailySnapshot`-систему в 5c.7.6/account-detail, НЕ дублировать легаси-писателя.

## Артефакты

- План+журнал: `plans/2026-07-11__phase-5c7-finances-replatform.md` · Статус: `...status.json`
- Новые тест-файлы: `FinanceViewModelCoreEntitiesTests.swift`, `FinanceDynamicsCurrencyBreakdownTests.swift`, `FinanceViewModelUpdateAccountAmountCharacterizationTests.swift`
