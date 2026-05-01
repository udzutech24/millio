---
name: bulletproof
description: Use when building a feature, refactoring, fixing a complex bug, changing architecture, or starting any non-trivial coding task. 12-stage verified dev workflow from research to deploy.
---

# Bulletproof — Adaptive Development Workflow

> **Based on:** Bulletproof v5.0 by Artemiy Miller
> **Adapted for:** Millio iOS project (Swift, SwiftUI, SwiftData)

## Core Principle

**Code to solve problems, not code for code's sake.**

Before EVERY change ask: "Does this actually solve our problem? Is this the most efficient solution?"
If the answer isn't clear — stop, research alternatives, pick the best one.

---

## Pick Your Mode

Not every task needs the full pipeline.

| Size | Examples | Mode | Stages |
|------|----------|------|--------|
| **S** | Bug fix, small edit, 1-2 files | Lightweight | 1 → 4 → 5 → 6 → 7 → Gates (skip spec/plan) |
| **M** | New feature, module refactor, 3-10 files | Standard | Stages 1-10 |
| **L** | Architecture change, new service, 10+ files | Full | Stages 1-12 (all) |

**How stages relate:** Stages 5-6-7 (Self-Audit, Verification, Impact) run **inside each implementation phase** as an inner loop. Stages 8-12 run **once after all phases complete** as an outer loop.

---

## Context Management (ALWAYS applies)

### The 40% Rule
Code quality degrades when context fills beyond 40% ("Dumb Zone"). Rules:
- Stay within 40-60% of the context window
- Manual `/compact` at 50% — don't wait for auto
- If overloaded: save progress → `/clear` → fresh start

### Fresh Context Between Stages
Every major stage = clean context window:
1. Save stage artifact (research / spec / plan / handoff)
2. `/clear`
3. Start new stage pointing the agent to the artifact path

### Handoff Protocol
Before `/clear` always create `progress/<task>-handoff.md`.
See `templates/handoff.md` for format.

### Progressive Disclosure
Don't dump the entire codebase into context:
- Research: sub-agents → compact summary
- Planning: summary + key interfaces only
- Implementation: only files for current phase
- In CLAUDE.md: `"For details, see path/to/docs.md"` (not @file)

---

## Stage 1: Deep Research

**Mode: Read-Only. No code. No changes.**

- Launch parallel Explore agents (1 per area: structure, patterns, deps, tests)
- **WebSearch: Who has already solved this problem? How did they solve it? What is the most efficient known solution?**
- **Analyze all findings and make a conclusion: which solution is the BEST and why.**
- Save to `thoughts/research/YYYY-MM-DD-<task>.md`
  (see `templates/research.md` for format)

**→ `/clear`**

---

## Stage 2: Spec / PRD

**Mode: Read + Write only in specs/. No code.**

**Spec = WHAT and WHY. Not how. Spec = contract.**

- Read Research Artifact from `thoughts/research/`
- Create `specs/YYYY-MM-DD-<name>.md`
  (see `templates/spec.md` for format)
- Key sections: Problem, Goal, Scope, Acceptance Criteria, Constraints, Non-Goals

**Skip for size S tasks.**
**→ `/clear`**

---

## Stage 3: Planning + Questions

**Mode: Read + Write only in plans/. No code yet.**

- Read **both** Spec (`specs/`) and Research (`thoughts/research/`)
- Launch Plan agents to check the approach
- Find gaps: what's unthought? What edge cases? What could break?
- **Be creative and proactive: anticipate ALL possible problems BEFORE writing code.**
- **WebSearch: How have others solved this exact problem? What libraries/patterns exist?**

### Challenge Loop (mandatory before finalizing plan)

```
Before finalizing the plan, answer 3 questions:

1. DOES THIS SOLVE THE PROBLEM?
   Compare every plan item against acceptance criteria from spec.

2. IS THIS THE MOST EFFICIENT SOLUTION?
   Name 2-3 alternative approaches. Justify the chosen one.

3. IS THERE "CODE FOR CODE'S SAKE"?
   Every change must directly serve acceptance criteria.
```

### Questions for User
- Only for real forks where there's a genuine decision to make
- Use AskUserQuestion with options
- For each question: **recommend which option you think is best and why**

### Final Plan
Create plan in `../plans/YYYY-MM-DD-<name>.md` (shared plans directory)
(see `templates/plan.md` for full template)

**→ `/clear`**

---

## Stage 4: Phased Implementation

**Each phase = separate session, fresh context, feature branch.**

Order within each phase:
1. Create/switch to feature branch: `feature/<task>`
2. Update status → `in_progress`
3. **Implement** (TDD where applicable — Swift tests)
4. **Self-Audit** (Stage 5)
5. **Verification** (Stage 6)
6. **Impact Analysis** (Stage 7)
7. **Gates** (see Gates section)
8. **Commit** (checkpoint)
9. Status → `completed`, write to Changelog
10. **Handoff** → `/clear`

---

## Stage 5: Self-Audit (after each phase)

**Mandatory BEFORE marking `completed`:**

```
1. SPEC COMPLIANCE
   Open spec. Walk through every acceptance criterion.
   For each: implemented? Where exactly in code?

2. CHALLENGE THE SOLUTION
   Does this actually solve the problem from spec?
   Is there a simpler/more efficient way?
   Any "code for code's sake"?
```

---

## Stage 6: Verification — Deep Bug Hunt

### Step 1: Find errors
```
Check ALL code from this phase for:
- Logic errors (wrong conditions, off-by-one, race conditions)
- Data handling (nil, type mismatches, optional unwrapping)
- Security (exposed secrets, unvalidated input)
- Performance (N+1 fetches, unnecessary re-renders, memory leaks)
- SwiftData: correct model relationships, proper @Query usage
```

### Step 2: Verify bugs are REAL
```
For EACH found bug:
1. Is this a REAL bug or a false positive?
2. Can you prove this bug is reproducible?
3. If you can't prove it — it's NOT a bug. Don't touch it.

RULE: Don't fix code "for beauty" or "just in case".
```

---

## Stage 7: Impact Analysis

```
MANDATORY CHECK BEFORE MERGE:

1. REGRESSION — What other modules depend on changed files?
2. SIDE EFFECTS — Did any contracts/interfaces change?
3. THINK AHEAD — Edge cases? Zero data? Concurrent access?
4. COMPATIBILITY — Backward compat? Data migrations?
```

---

## Stage 8: Integration Check

- All phases `completed` → run gates across entire project
- Every acceptance criterion → fulfilled?

---

## Stage 9: Code Review (fresh context)

- Launch `@code-reviewer` agent (see `agents/code-reviewer.md`)
- Checklist: edge cases, race conditions, backward compat, security, performance

---

## Stage 10: Security Scan (for M and L)

```bash
/security-review    # built into Claude Code
```

---

## Stage 11: Fixes + Re-verification

If review/scan found issues: fix → re-run gates → re-verify impact.

---

## Stage 12: Cleanup + Deploy

- Archive plan: `mv ../plans/<file> ../plans/archive/`
- Keep spec as documentation
- Merge → develop
- **Deploy — ONLY on explicit user request**

---

## Deterministic Gates

A phase CANNOT be `completed` without passing ALL required gates.

### Tier 1: Required (block the phase)
```bash
# Swift — сборка проекта
xcodebuild build -project millio.xcodeproj -scheme millio -destination 'platform=iOS Simulator,name=iPhone 16' -quiet

# Swift — тесты
xcodebuild test -project millio.xcodeproj -scheme millio -destination 'platform=iOS Simulator,name=iPhone 16' -quiet

# SwiftLint (если установлен)
swiftlint lint --quiet 2>/dev/null || true
```

### Tier 2: Recommended (for M and L)
```bash
# Проверка на TODO/FIXME
grep -rn "TODO\|FIXME\|HACK" millio/ --include="*.swift" | head -20
```

### Tier 3: Deep Security (for Security Scan stage)
```bash
/security-review
```

If a gate fails — fix and re-run. Never skip.

---

## Git Discipline

- Each task = `feature/<task>` branch
- Commit after each passed gate (checkpoint for rollback)
- NEVER push to main/master directly
- Merge to develop, then develop → master via PR

---

## Project Structure

```
ПРИЛА/
├── .claude/
│   ├── skills/
│   │   └── bulletproof/
│   │       ├── SKILL.md        # ← this file
│   │       ├── templates/
│   │       │   ├── research.md
│   │       │   ├── spec.md
│   │       │   ├── plan.md
│   │       │   └── handoff.md
│   │       └── agents/
│   │           └── code-reviewer.md
├── CLAUDE.md                   # project brain
├── docs/                       # tech docs
├── specs/                      # WHAT and WHY
├── thoughts/research/          # research artifacts
└── progress/                   # handoff files

millio/ (root)
├── .business/                  # business context
├── plans/                      # shared plans (HOW)
│   └── archive/                # completed plans
```
