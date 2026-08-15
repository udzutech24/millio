# Shadow evidence gate must be operationally reachable

**Date:** 2026-08-08
**Category:** process
**Status:** OPEN
**Priority:** HIGH
**Author:** Codex

## Что произошло

Phase 5 was described as blocked only by real observation, but production observation writes never
supplied `transitionID`, `wasOffline` or compatibility contribution count. A non-zero correction was
also always submitted with `hasExpectedResolverCorrection == false`. The documented production gate
therefore could not reach approval from production evidence.

## На какой стадии

- [ ] Research
- [ ] Spec
- [x] Plan
- [x] Implementation
- [x] Review / Security scan
- [ ] Handoff
- [ ] Рефлексия

## Что именно не сработало

Unit tests constructed valid transition/offline evidence directly, but no production writer could
construct the same data. The test proved pure gate logic, not operational reachability. In addition,
distinct days were based on valuation `dayKey`, so one multi-day chart query could imitate a
multi-day observation window.

## Предложение

- [ ] Add an end-to-end test from production observation writer to `approveStructuredCutover`.
- [ ] Persist observation civil date separately from valuation day.
- [ ] Add explicit, non-PII device-transition and offline-operation recording APIs.
- [ ] Deduplicate repeated renders of the same observation identity.
- [ ] Require every operational gate field to have at least one production writer before a phase is
  described as waiting only for external evidence.

## Как измерим что помогло

A production-composition test creates a seven-real-day window with two explicit transitions and one
offline transition, while a single multi-day chart render cannot increment those operational axes.

## Ссылки

- Сессия: [2026-08-08 accounts history emergency cutover](../../.business/история/2026-08-08-accounts-history-emergency-cutover.md)
- Связанный план: [accounts history source of truth](../../plans/2026-08-08__accounts-history-source-of-truth.md)
