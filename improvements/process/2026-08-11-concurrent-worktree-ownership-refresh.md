# Refresh ownership before cross-cutting gates

**Date:** 2026-08-11
**Category:** process
**Status:** OPEN
**Priority:** HIGH
**Author:** Codex

## Что произошло

Во время cashflow L-задачи в том же worktree параллельно появились debit-card production/test файлы. Первая visual-сборка сформировала source list до появления `DebitCardDetailSection.swift` и упала на missing symbol; повтор уже был зелёным. Более важно: новые coordinator paths выявили обход closure policy.

## На какой стадии

- [x] Implementation
- [x] Review / Security scan
- [x] Handoff

## Что именно не сработало

Одноразовый ownership manifest в начале не защищает от параллельных изменений в cross-cutting domain-задаче.

## Предложение

- [x] Добавить gate: перед миграцией, широким build и final review повторно снимать `git status --short` и сравнивать с manifest.
- [x] При новых concurrent files перезапускать repository-wide bypass search до exposure доменного UI-статуса.

## Как измерим что помогло

Ни один final review не закрывает cross-cutting acceptance criterion на основе устаревшего source inventory; concurrent build failures отличаются от product regression.

## Ссылки

- Сессия: `.business/история/2026-08-11-cashflow-month-workspace.md`
- План: `plans/2026-08-11__cashflow-month-workspace-redesign.md`
