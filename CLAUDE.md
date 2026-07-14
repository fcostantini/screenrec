# screenrec (Tier 2) — Agent Guide

Native macOS menu-bar screen recorder: screen + system audio + separate-track microphone,
crash-safe long recordings, pause/resume, instant replay. Apple frameworks only.

## Start here, in this order

1. **`STATUS.md`** — current milestone, next task, open questions. The single source of
   truth for "what do I do now". Update it every session (see contract below).
2. **`docs/03-milestones.md`** — the task you'll pick, its checklist and exit gate.
3. **`docs/02-technical-reference.md`** — REQUIRED reading before touching capture,
   writing, timing, or TCC code. It encodes bugs we already hit; do not rediscover them.
4. `docs/01-architecture.md` (module map, concurrency rules), `docs/05-decisions.md`
   (don't contradict ✅ ADRs), `docs/04-testing-verification.md` (gates),
   `docs/00-product-brief.md` (scope; check non-goals before adding anything).

Reference implementation: `~/code/screenrec-poc` (our working Tier-1; same author).

## Working contract

- Work milestone-order (M0→M6; M5 core may parallel M3/M4 — see dependency graph).
  One task (Mx-Ty) at a time; tick the checkbox in 03-milestones.md when done.
- A milestone is DONE only when its gate in 04-testing passes. Paste gate evidence
  (commands + output) into STATUS.md. Gates marked (human) — flag them in STATUS.md
  under "Needs Franco" instead of skipping silently.
- Update STATUS.md before ending any session: what changed, gate status, next task,
  anything surprising you learned (append to the "Field notes" section).
- `RecorderCore` never imports AppKit/SwiftUI. No external dependencies (ADR-010).
  Swift language mode v5 (see 02 §10). Read GPL reference repos for patterns only —
  never copy code.

## Quality pass (mandatory after every task, before its commit)

When the task's Verify passes, you are not done. Review the full diff (`git diff` plus
untracked files) as a critical senior Swift reviewer:

- **Architecture** — code lives in the right module per docs/01 (capture vs recording vs
  replay vs CLI vs app); no layering violations (RecorderCore importing UI, CLI reaching
  into another module's internals); new seams match the documented design instead of
  bypassing it (e.g. consumers go through SampleRouter, timing math through
  TimestampRebaser).
- **Swift practice** — Swift API Design Guidelines naming; value types where natural;
  access control as tight as possible (`public` only for genuine cross-module surface);
  no force-unwraps or `try!` outside tests (an invariant-based exception needs a comment
  stating the invariant); errors handled or propagated, never swallowed; guard-based
  early exits over nesting.
- **Concurrency** — docs/01 rules hold: sample-path code uses locks not actors, never
  blocks an SCK callback queue, no unbounded buffer retention; anything crossing threads
  is actually safe, not just quiet under language-mode v5.
- **Cleanliness** — no dead code, commented-out code, stray debug prints, or leftover
  TODO scaffolding; no duplication of an existing helper; comments state non-obvious
  constraints only; style matches the surrounding file.
- **Scope** — the diff contains this task only. Unrelated improvements you noticed go to
  STATUS.md field notes (or a separate `docs:`/follow-up commit), not smuggled in.

Fix what the review finds, re-run the task's Verify, then commit. If the harness offers
a /code-review or /simplify skill, run it on the diff as part of this pass — the
checklist above still applies on top. Genuine findings that are out of scope for the
task: record them in STATUS.md field notes rather than fixing silently.

## Version control

Commit after every completed task (its Verify must pass first), message prefixed with
the task ID: `M0-T2: devsign.sh finds stable identity`. Doc-only changes: prefix
`docs:`. Push to origin at session end. Never force-push main. The git history is the
per-task audit trail — one task, one commit.

## Session-end checklist (do this before your final message, every session)

1. Tick completed task checkboxes in `docs/03-milestones.md` (never tick a task whose
   verification you didn't run).
2. Update `STATUS.md` → "Now": current milestone, exact next task ID, blockers.
3. If a gate was attempted: record pass/fail + evidence in the gate table; add
   human-only leftovers to "Needs Franco".
4. Append anything surprising to "Field notes" — future agents only know what's written.

## Build & verify

```sh
swift build                      # debug
swift test                       # unit tests
swift build -c release           # before any capture timing/perf measurements
Scripts/bundle.sh                # assemble + sign dist/ScreenRec.app (M0+)
swift tools/probe.swift <file>   # inspect a recording's tracks
```

## Environment facts

- macOS 15.6.1, Apple Silicon, display captures at 4112×2570 (never hardcode), default
  mic is often AirPods Pro. Command Line Tools only — no Xcode, no xcodebuild.
- This dev terminal already holds Screen Recording + Microphone TCC grants → CLI capture
  tests run headlessly. GUI/onboarding tests need the human.
- Test recordings: use `~/Movies` or the session scratchpad. NEVER Desktop/Documents/
  Downloads (TCC → opaque "invalid parameter" failures — 02 §2). Clean up test files.
- Real capture runs take real wall-clock seconds; use `--duration` flags, run in
  foreground, and remember stdout buffering rules (02 §10).
