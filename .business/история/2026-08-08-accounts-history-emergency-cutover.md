# Рефлексия сессии: accounts history emergency cutover

**Дата:** 2026-08-08
**Автор:** Codex
**Ветка / PR:** current dirty worktree; no commit or PR

## 1. Задача

Реализовать экстренный cache-first historical cutover в рамках Phase 5, не объявляя
Phase 5 завершённой. Исходный production-скриншот показал ложное уменьшение
исторической суммы на `23 147 393 RUB`.

## 2. Как решалась

- Подтверждено, что `.shadow` вычислял structured series, но возвращал на экран старые
  compatibility pixels.
- Проверено, что structured boundary читает локальные `HistoricalRate`,
  `HistoricalAssetPrice` и V7 closes без сетевого lookup в presentation path.
- No-override default переключён на `.structured`; явные `.shadow` и `.compatibility`
  сохранены.
- Добавлены/обновлены tests на emergency default и compatibility rollback.
- Актуализированы plan, status sidecar и Phase 5 progress.

## 3. Решена ли

- [ ] Полностью
- [x] Частично — emergency reader activation реализована, но Phase 5 намеренно
  остаётся открытой до real-device diagnosis, observation window и rollback drill.
- [ ] Нет

## 4. Эффективно ли

- Drive-by правок не было; изменены reader default, его тесты и обязательные документы.
- Более простая смена enum default без rollback semantics была бы хрупкой.
- Focused gate зелёный. Expanded gate: 58/58, 0 failed, 0 skipped.
- AC-E2/E3 затронуты, но операционно не закрыты.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| Historical reader default | `.shadow`: на экране compatibility total | `.structured`: локальные evidence/V7 closes |
| Missing dependency | счёт мог молча исчезнуть из total | incomplete point не публикует numeric subtotal |
| Rollback | риск возврата к shadow pixels | явный `.compatibility`, остающийся structured |

## 6. Идеи по улучшению

### Агенты
- 0 наблюдений.

### Токены / контекст
- Первый clean build дал очень большой xcodebuild output; дальше использованы compact
  result summaries. Отдельная запись не нужна: паттерн уже зафиксирован в improvements.

### Процесс
- Production evidence writer не мог собрать поля, которые требовал gate.
- Зафиксировано в `improvements/process/2026-08-08-shadow-evidence-must-be-operationally-reachable.md`.

### Бизнес
- Продуктовый факт: длинное shadow-окно неприемлемо, если comparator уже известно
  публикует ложные финансовые цифры. Отдельную business-гипотезу не создавали.

## 7. Артефакты и коммиты

- Коммиты: не создавались.
- Result bundle: `/tmp/millio-emergency-cutover-expanded.xcresult`.
- План: `plans/2026-08-08__accounts-history-source-of-truth.md` — Phase 5 открыта.

## 8. Что для следующей сессии

Начать с real-device contribution-level diagnosis фактической дельты `23 147 393 RUB`,
затем довести production evidence writer до реально достижимого operational gate. Phase 6 не
начинать до завершения rollback window.
