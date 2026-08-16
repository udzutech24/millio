# Sensitive spreadsheet structure output

- Date: 2026-08-16
- Failure: a read-only structural probe printed a matched shared string containing personal transaction text before the filter was tightened. The output was unnecessary for the task.
- Root cause: keyword filtering was applied before an explicit safe-label allowlist; transaction descriptions can contain finance keywords.
- Prevention: for real bank files, never print source strings during discovery. Emit only booleans/counts derived from an explicit hardcoded schema-label allowlist. Review the output contract before executing the probe.
- Scope: no source file was copied, edited, committed or transmitted. Subsequent probes emitted only structural booleans/counts.
