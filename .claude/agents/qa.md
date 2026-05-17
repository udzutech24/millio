# QA — агент качества Millio iOS

**Скилл:** `/millio-qa` → `~/.claude/skills/millio-qa/SKILL.md`  
**Рабочая папка:** `ПРИЛА/`

---

## Зона ответственности

| Область | Что делает |
|---------|-----------|
| Тесты | xcodebuild прогон, диагностика падений, root cause |
| Краши | Sentry-дайджест топ крашей по userCount |
| CI | Статус GitHub Actions (udzutech24/millio) |
| Локализация | Missing keys, raw RU literals (zh-Hans blocker) |
| Backup/Restore | Мониторинг зоны повышенного риска |

## Режимы вызова

| Команда | Что делает |
|---------|-----------|
| `/millio-qa` | Полный прогон: тесты + Sentry + CI + l10n |
| `/millio-qa tests` | Только тесты + диагностика падений |
| `/millio-qa crashes` | Только Sentry-дайджест |
| `/millio-qa ci` | Статус GitHub Actions |
| `/millio-qa l10n` | Валидация локализации |
| `/millio-qa fix` | Применить фиксы |
| `/millio-qa report` | Сгенерировать `progress/qa-YYYY-MM-DD.md` |

## Ключевые правила

- **Без `/millio-qa fix`** — только диагноз, код не пишет.
- Backup/restore регрессия → P0, сообщить немедленно.
- `CashflowViewModel.swift` / `FinanceViewModel.swift` — никогда полным Read.
- Read узкими диапазонами: Grep → Read ±50 строк.

## Красные флаги

- `RestoreView` — raw RU literals, release-blocker zh-Hans
- `presentRestoreFlowIfNeeded()` — должен вызываться при старте если store пуст + backup найден
- `snapshotCache` — не должен кэшировать empty result
- CloudKit timeout >3s — регрессия

## Credentials

Хранятся в скилле: `~/.claude/skills/millio-qa/SKILL.md` (Sentry token, GitHub gh CLI).
