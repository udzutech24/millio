# Spec: смена типов финансовых продуктов

## Goal

Позволить исправлять ошибочно выбранный тип или переводить продукт в другой класс без ретроспективной порчи ledger, totals, valuation, Cashflow и backup.

## Acceptance criteria

- [x] **PT-C1** Exhaustive matrix covers every `AccountProductType × AccountProductType` pair and returns correction, conversion or blocked.
- [x] **PT-C2** In-place correction разрешена только при одинаковой replay/sign semantics и валидном target metadata tuple.
- [x] **PT-C3** Credit card, loan, debt-direction и cross-engine transitions никогда не выполняются простым field flip.
- [x] **PT-C4** Deposit ↔ cash-like in-place доступен только pristine account; generated/confirmed interest или Cashflow link запрещают correction.
- [x] **PT-C5** Market subtype correction требует согласованной `assetClass`, symbol и quote identity.
- [x] **PT-P1** Correction меняет `productType + kind + metadata + revisions` атомарно одним save.
- [x] **PT-P2** Conversion создаёт replacement graph и архивирует source одним disposable-context save.
- [x] **PT-P3** Stable operation ID делает retry/relaunch идемпотентным и конфликтует при другом target/payload.
- [x] **PT-P4** Любой injected stage/save failure оставляет source и target без изменений; unrelated save не воскрешает partial graph.
- [x] **PT-H1** История до effective date остаётся численно и семантически неизменной.
- [x] **PT-H2** Totals/group/dashboard до и после перехода не задваивают капитал.
- [x] **PT-B1** Backup/restore сохраняет source archive, replacement identity и operation links.
- [x] **PT-U1** Preview явно различает «исправить тип» и «создать новый продукт» и показывает необратимые ограничения.
- [x] **PT-U2** Неподдерживаемый переход показывает reason, а не молча выбирает близкий тип.

## Non-goals

- Универсальная конвертация market lots, кредитных графиков, валют и налоговой истории.
- Автоматическое угадывание target metadata.
- Переписывание исторических событий под новый engine.
