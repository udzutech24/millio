# Dirty baseline ownership manifest for long autonomous sessions

## Problem

A one-time `git status` is insufficient when another local process can add changes during a long build. In this session the iOS dirty set expanded while tests/build were running, making attribution from the final status unsafe.

## Improvement

Record before-work `git status --porcelain=v1`, `git diff --stat`, and hashes of files intended for editing. Re-snapshot after every long gate and report newly appeared paths separately. Use narrow patch hunks and never claim the whole final diff as session-owned.

## Expected effect

Prevents accidental rollback or attribution of concurrent user work and reduces repeated full-diff inspection.
