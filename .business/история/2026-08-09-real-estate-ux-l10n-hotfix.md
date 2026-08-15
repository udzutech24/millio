# Рефлексия: UX/l10n hotfix недвижимости

**Дата:** 2026-08-09

## 1. Задача

Исправить доказанные UX/l10n-дефекты real-estate slice после фаз 1–4, включая raw keys, тесную компоновку, selectors, photos и атомарность.

## 2. Как решалась

- Прочитаны plan/spec и текущие RealEstate/AccountDetail paths.
- Динамические l10n keys заменены typed presentation API.
- Создан отдельный editor с compact sheets и staged gallery; save boundary расширен до атомарной галереи.
- Добавлены unit/render tests, пройдены build/schema/migration/export gates и simulator QA.

## 3. Решена ли

- [x] Полностью. Все acceptance criteria hotfix покрыты кодом, тестами или simulator evidence.

## 4. Эффективно ли

Да. Drive-by refactoring нет; V8 schema не менялась. DEBUG QA-harness добавлен как малый детерминированный шов для реальных simulator screenshots.

## 5. Было → стало

| Область | Было | Стало |
|---|---|---|
| L10n | Raw `real_estate.type.*` | Typed static localized titles |
| Editor | Generic Form/Menu/Stepper | Product editor + compact sheets |
| Photos | Detail-only immediate writes | Staged edit gallery, atomic Save |
| Narrow/Dynamic Type | Smoke missed truncation | Matrix + inspected simulator shots |
| Ввод переоценки | Слитные цифры в обычном `TextField` | Живая группировка разрядов через общий `AmountTextField` |

## 6. Идеи по улучшению

- Агенты: первый smoke-test был слабым и не ловил реальную toolbar-компоновку; исправлено матрицей и manual simulator review.
- Токены/контекст: большой dirty baseline затрудняет ownership; уже зафиксировано в `improvements/process/2026-08-09-dirty-baseline-ownership-manifest.md`.
- Процесс: render smoke без точных device widths недостаточен; теперь 375/390 и accessibility size — явный gate.
- Бизнес: 0 новых наблюдений.
