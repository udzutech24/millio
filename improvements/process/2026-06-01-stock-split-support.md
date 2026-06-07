---
date: 2026-06-01
axis: process
priority: medium
---

# Поддержка stock splits в инвестиционных позициях

## Проблема

При reverse/forward stock split биржа меняет количество акций и цену пропорционально — итоговая сумма вложений не меняется. Millio хранит `marketQuantity` и `totalPurchaseCost` на момент ввода и не корректирует их при сплитах. Результат: P&L считается неверно (пример: PALL -82% вместо -13%, PPLT -90% вместо -9%).

## Причина

В `Investment.swift` нет механизма применения split-корректировки. `applyBuy()` / `applySell()` пишут данные один раз, дальше данные не меняются.

## Предлагаемое решение

1. **Ручная корректировка позиции** (минимальный MVP) — в `InvestmentEditorView` разрешить напрямую редактировать `marketQuantity` и `averagePurchaseUnitPrice` / `totalPurchaseCost`. Сейчас эти поля не редактируются отдельно.

2. **Split-действие** (полноценно) — новая операция `applySplit(ratio: Double)` в `Investment.swift`:
   ```swift
   func applySplit(ratio: Double) {
       // ratio = 10 → forward split (кол-во ×10, цена ÷10)
       // ratio = 0.1 → reverse split (кол-во ÷10, цена ×10)
       guard let qty = marketQuantity, ratio > 0 else { return }
       marketQuantity = qty * ratio
       if let avg = averagePurchaseUnitPrice {
           averagePurchaseUnitPrice = avg / ratio
       }
       // totalPurchaseCost не меняется — сумма вложений та же
       recalculateAmountFromPosition()
   }
   ```
   UI: кнопка «Применить сплит» в редакторе позиции с вводом коэффициента.

## Размер задачи

S–M: 2–4 файла (`Investment.swift`, `InvestmentEditorView.swift`, `FinanceInvestmentOrderService.swift`, тесты).

## Затронутые файлы

- `millio/UI/Services/Investments/Investment.swift`
- `millio/UI/Services/Finances/InvestmentEditorView.swift`
- `millio/UI/Services/Finances/FinanceInvestmentOrderService.swift`
