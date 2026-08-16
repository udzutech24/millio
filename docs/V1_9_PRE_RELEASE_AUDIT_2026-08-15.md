# Millio 1.9 pre-release audit — 2026-08-15

## Verdict

**NO-GO.** Version 1.9 (10) must not be submitted. Backup/Restore has a green focused data-layer suite, but the mandatory real CloudKit round-trip was not performed. The full test gate and localization gate are red, physical-device scenarios and App Store Connect/TestFlight state are unverified.

## Baseline

| Item | Evidence | Result |
|---|---|---|
| Branch / commit | `develop`, `06733f0d019f04e9a74dddfca6e068dea6d11c3a` | PASS |
| Worktree | Pre-existing modified/deleted screenshot, Fastlane, seeder and plan-status files; preserved | DIRTY |
| Version | `MARKETING_VERSION=1.9`, `CURRENT_PROJECT_VERSION=10` | PASS |
| Deployment | iOS 18.6; iPhone/iPad target family | PASS |
| Simulator | iPhone 17 Pro Max, iOS 26.5 (plus listed phone/iPad simulators) | PASS |
| Physical device | iPhone 17 Pro Max connected | AVAILABLE, NOT TESTED |
| Identifiers | app `com.millio.app`; widget `com.millio.app.currencywidget` | PASS |
| Signing/export | Archive succeeded; IPA re-signed Apple Distribution, Production CloudKit, `get-task-allow=false` | PASS |
| App Store Connect | API credential variables unavailable | BLOCKED |
| TestFlight 1.9 (10) | Cannot query without App Store Connect access | BLOCKED |

## P0/P1 blockers

1. **P1 — no real Backup/Restore round-trip.** Required control dataset → backup → safe reset → restore → field/UUID/relationship comparison → repeat restore was not executed against the production-like CloudKit path. Mock/data-layer tests cannot prove this.
2. **P1 — full automated gate failed.** `.xcresult`: 1,897 passed, 362 failed, 5 expected failures; 91% of failures were signal traps, with additional real expectation failures. A cascade is still a broken gate until isolated and rerun cleanly.
3. **P1 — localization gate failed.** `scripts/l10n-audit.sh` reported four failed checks, including hardcoded Russian UI in Statement Review/Import and incomplete `en`/`zh-Hans` catalog coverage. Selectable languages can leak Russian.
4. **P1 — production external state unverified.** Production CloudKit schema, TestFlight build 1.9 (10), train state, duplicate build number, privacy labels and Apple validation were not queryable.
5. **P1 — physical iPhone critical flows unverified.** Installing the production bundle could overwrite/attach to existing app data; no destructive device action was authorized.
6. **P1 — screenshot set is incomplete in the current worktree.** Raw English screenshots are deleted and only Russian raw screenshots are present; these are pre-existing user changes and were not modified.

## P2/P3 findings

- **P2:** Release archive emits deprecated localized interpolation warning in `DebitCardDetailSection.swift`; displayed date/decimal may use an unlocalized debug description.
- **P2:** No app-owned `PrivacyInfo.xcprivacy` was found. Required-reason API coverage must be verified from the exported IPA and App Store validation; absence alone is not proof of violation.
- **P2:** Existing backup design documents acknowledge device-key backups may be unusable after reinstall or on another device. Product copy and default protection mode require explicit disaster-recovery validation.
- **P3:** Localization audit heuristics include false positives (search aliases/log text), but confirmed hardcoded UI strings remain sufficient to fail the gate.

## Scenario matrix

| Scenario | Environment | Result | Evidence | Residual risk |
|---|---|---|---|---|
| Backup data-layer round-trip | iPhone 17 Pro Max simulator, iOS 26.5 | PASS | Focused XCTest 72/72 | No real CloudKit/UI |
| AccountsCore all account kinds | Same | PASS | `AccountsCoreBackupTests` | Attachments/settings breadth not proven manually |
| Corrupt/checksum/incompatible input | Same | PASS | Envelope/import validation tests | UI error copy not visually verified |
| Legacy schema/self-heal | Same | PASS | Schema + legacy migration tests | Production historical backups not sampled |
| Dedup/repeated import primitives | Same | PASS | Integrity/dedup tests | Repeat explicit restore contract not verified end-to-end |
| Full unit/integration gate | Same | FAIL | 1,897 passed / 362 failed | Root causes unresolved |
| Onboarding/auth/account/Cashflow/Upcoming/import/Dashboard | Simulator | NOT RUN | Blocked after red full gate | Product regressions unknown |
| Offline/background/deep links/widget/purchases | Simulator/device | NOT RUN | No clean UI gate | Unknown |
| Localization | Static catalog/source audit | FAIL | Four audit failures | Visual truncation/accessibility also unknown |
| Release archive/export | Generic iOS | PASS | Archive + IPA export | Apple server validation not run |
| Physical iPhone | Connected iPhone 17 Pro Max | BLOCKED | Device inventory only | All physical behavior unknown |

## Backup/Restore matrix

| Check | Result | Evidence / gap |
|---|---|---|
| Local export/import | PASS (automated) | Data-layer round-trip tests |
| Cloud manual backup | BLOCKED | Real iCloud mutation not executed |
| Automatic backup | PASS (policy/mock only) | Unit tests; no real scheduled upload |
| Clean-store restore | PASS (isolated data layer) | Automated temporary stores |
| Restore over existing data | PARTIAL | Replacement/rollback tests; no UI scenario |
| Keychain encryption | PASS (unit) | Encryption/restore candidate tests |
| Passphrase + wrong password | PASS (unit) | Passphrase tests |
| Corrupt/empty/incompatible | PASS (unit) | Validation/envelope tests |
| Old schema migration | PASS (unit) | Schema and self-heal tests |
| AccountsCore/Cashflow/relations | PASS (focused subset) | Round-trip suites |
| Attachments/photos/settings | NOT PROVEN | No comprehensive manual comparison evidence |
| Ownership/scope/logout-login | FAIL/UNVERIFIED | Full suite includes scope failures; no real auth round-trip |
| Repeat restore/no duplicates | PARTIAL | Dedup primitives pass; explicit repeat restore not executed |
| Integrity before deletion | PASS (code tests), NOT PROVEN UI | Rollback/pre-restore tests; no manual destructive flow |
| PII/logs/Crashlytics | PARTIAL | Structured non-PII intent found; runtime payload not inspected |
| Localized errors | FAIL/UNVERIFIED | Global localization gate is red |

## Files changed by this audit

- `thoughts/research/2026-08-15-v1.9-pre-release-audit.md`
- `specs/2026-08-15-v1.9-pre-release-audit.md`
- `plans/2026-08-15__v1.9-pre-release-audit.md`
- `docs/V1_9_PRE_RELEASE_AUDIT_2026-08-15.md`
- `.business/история/2026-08-15-v1.9-pre-release-audit.md`
- Generated ignored build evidence under `.build/pre-release*` and IPA `.build/pre-release/export/millio.ipa`.

No application source, existing screenshot, Fastlane or user-modified file was changed.

## Required before App Store

1. Fix localization leaks and obtain a clean localization audit across every selectable locale.
2. Diagnose the full-suite signal traps and real assertions; rerun the complete test gate cleanly and add relevant UI tests.
3. Execute the exact real Backup/Restore control-dataset round-trip, including repeat restore, attachments/settings, logout/login and production CloudKit schema.
4. Run critical flows on the connected physical iPhone using an isolated safe test account/data plan.
5. Restore/generate complete App Store screenshots for required locales/sizes.
6. Query App Store Connect, confirm TestFlight 1.9 (10), next unique build number, train state, metadata/privacy labels, then run Apple validation.

## Can move to next release

Only P3 audit-noise cleanup and non-user-visible tooling improvements. The P1 items and localized interpolation warning must not be deferred.

## Next safe step

Authorize implementation with: **`Реализуй фазу 1 по плану`**. Phase 1 should first make the localization gate green and isolate the full-test signal-trap root cause without changing test expectations. After a clean automated gate, explicitly authorize a safe physical-device/CloudKit test account for the real round-trip.
