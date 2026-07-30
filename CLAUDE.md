# screenrec (Tier 2) — Agent Guide

Native macOS menu-bar screen recorder: screen + system audio + separate-track microphone,
crash-safe long recordings, pause/resume, instant replay. Apple frameworks only.

## Start here, in this order

1. **`STATUS.md`** — current milestone, next task, open questions. The single source of
   truth for "what do I do now". Update it every session (see contract below).
2. **`docs/03-milestones.md`** — the task you'll pick, its checklist and exit gate.
3. **`docs/02-technical-reference.md`** — REQUIRED reading before touching capture,
   writing, timing, or TCC code. It encodes bugs we already hit; do not rediscover them.
   §1a/§1a-ii are the ones a "the API surely does X" assumption keeps breaking on.
4. **`docs/07-field-notes.md`** — what SCK/VideoToolbox/AVFoundation *actually* do, measured.
   Skim before any capture/encode/test-harness work; most entries cost hours to learn.
5. `docs/01-architecture.md` (module map, concurrency rules), `docs/05-decisions.md`
   (don't contradict ✅ ADRs), `docs/04-testing-verification.md` (gates),
   `docs/00-product-brief.md` (scope; check non-goals before adding anything),
   `docs/06-ui-spec.md` (required before any M4/M5 UI work).
6. `docs/history/` — closed session logs. Not maintained; read only to answer "why did we".

Reference implementation: `~/code/screenrec-poc` (our working Tier-1; same author).

## Working contract

- **M0–M22 are shipped** (v1.11.0). New work comes from a review or from Franco: add the milestone
  to 03-milestones.md, then work it one task (Mx-Ty) at a time, ticking each box as it lands.
- A milestone is DONE only when its gate in 04-testing passes. Paste gate evidence
  (commands + output) into STATUS.md. Gates marked (human) — flag them in STATUS.md
  under "Needs Franco" instead of skipping silently.
- Update STATUS.md before ending any session: what changed, gate status, next task.
  Anything surprising you learned goes to `docs/07-field-notes.md` (newest first, dated,
  attributed to the task) — STATUS.md's "Now" stays short.
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
  TODO scaffolding; no duplication of an existing helper; style matches the surrounding file.
- **Comments — minimum information, and no storytelling.** A comment earns its place only by
  stating a non-obvious constraint the code can't. Two lines is the norm; four on a complex
  public type is the ceiling. Specifically, do NOT write:
  - **history** ("this used to…", "the first pass did X", "shipped for an afternoon",
    "deferred from M4-T2") — git has it;
  - **attribution** ("/code-review found", "Franco caught", "the live run caught it");
  - **your mistakes**, lessons learned, or war stories — those go to `docs/07-field-notes.md`,
    which is what that file is for;
  - **essays**. If a rationale needs a paragraph, it needs one *line* here and the paragraph
    in docs/ or field notes.
  Keep: platform facts and gotchas stated flatly, doc pointers (`02 §4`, `ADR-007`),
  invariants behind a force-unwrap, concurrency constraints, and one line on why a
  non-obvious approach beat the obvious one. Delete anything that only restates the code.
- **Scope** — the diff contains this task only. Unrelated improvements you noticed go to
  `docs/07-field-notes.md` (or a separate `docs:`/follow-up commit), not smuggled in.

Fix what the review finds, re-run the task's Verify, then commit. If the harness offers
a /code-review or /simplify skill, run it on the diff as part of this pass — the
checklist above still applies on top. Genuine findings that are out of scope for the
task: record them in `docs/07-field-notes.md` rather than fixing silently.

## Plan artifact (mandatory — BEFORE implementing any task)

Before writing code for a task, publish a **visual Artifact** laying out what you intend to
do, then stop and wait. This is a review gate, not a summary: it proves you understood the
task and lets Franco correct the plan while it's still cheap. Do not start implementing
until he's seen it.

- **Show the UI/UX the task will produce**, don't just describe it. Sketch the states,
  layout and copy you intend to build — enough for Franco to say "not that" before the work
  exists. Ground every element in a docs/06 line; where the spec is silent and you had to
  choose, say so out loud and give your reasoning. Where you're proposing to *change* an
  existing screen, show what's there now (real screenshot, see below) next to the proposal.
- **Also state:** the files/targets you'll add or touch, the seams you'll reuse (never
  reinvent one — e.g. `stop(reason:)`, SampleRouter, TimestampRebaser), what you're
  deliberately leaving out and to which task, how you'll Verify, and anything you'll need
  from Franco (a human gate, a TCC grant, a taste call).
- **Screenshotting the app headlessly** (for before/after shots, and for the evidence you
  hand back once the work is done): `screencapture -x -R <x>,<y>,<w>,<h>` against the
  running `dist/ScreenRec.app`, foreground only — the TCC rule in Environment facts applies.
  `NSScreen.main.frame` gives the point size to aim at; this display is 2×. To reach a state
  the UI can't drive yet, patch the app *temporarily* to enter it, capture, then revert —
  never ship the scaffolding. **Don't eyeball an animation; measure it** (M4-T1 field note).
- **Artifacts block external hosts**: embed images as `data:` URIs, inline all CSS/JS.
- Never present a mockup as a screenshot, or a plan as a finished result. If you don't yet
  know something the plan turns on, that's a question for Franco, not a guess to render.

## Version control

Commit after every completed task (its Verify must pass first), message prefixed with
the task ID: `M0-T2: devsign.sh finds stable identity`. Doc-only changes: prefix
`docs:`. Push to origin at session end. Never force-push main. The git history is the
per-task audit trail — one task, one commit.

**Versioning (semver, ADR-013):** bump the `VERSION` file in the same commit as the change that
warrants it — MINOR for a new user-facing feature (a milestone like M7/M8), PATCH for fixes with no
new feature, MAJOR for a breaking user-facing change. Tag releases (`git tag v1.2.0`). `1.0.0` = v1.

## Session-end checklist (do this before your final message, every session)

1. Tick completed task checkboxes in `docs/03-milestones.md` (never tick a task whose
   verification you didn't run).
2. Update `STATUS.md` → "Now": current milestone, exact next task ID, blockers.
3. If a gate was attempted: record pass/fail + evidence in the gate table; add
   human-only leftovers to "Needs Franco".
4. Append anything surprising to `docs/07-field-notes.md` — future agents only know what's
   written. If STATUS.md's "Now" has grown past ~250 lines, rotate the closed entries into
   `docs/history/` (M15-T5 did this once; it is meant to stay that size).

## Dev loop (the CI-less verify loop — run after every change)

There is no CI. This ordered loop IS the gate; run it top to bottom after any change,
and a task is not done until it passes clean:

```sh
swift build            # 1. debug build compiles
swift test             # 2. all unit tests pass
swift build -c release # 3. release build compiles
Scripts/bundle.sh      # 4. assemble + sign dist/ScreenRec.app (must stay signable)
```

Then run the current task's **Verify** step (docs/03) on top of this loop.

Other tools:
```sh
swift tools/probe.swift <file>          # inspect a recording's tracks/codecs/durations
swift tools/frames.swift <f> 1 3 1 out  # PNG frames at timestamps (clip *content*, vs probe's metadata)
swift tools/menudriver.swift dump       # the menu-bar app's open menu, as assertable text
swift tools/menudriver.swift click "Pause"
swift tools/settingsdriver.swift toggle # drive the Settings *window* via AX (menudriver does the menu)
swift tools/alertdriver.swift press "Quit Anyway"  # click a modal NSAlert (a keystroke can't — 07)
swift tools/hoverprobe.swift "Settings…" 5 out  # screenshot the open menu per-tick (caught M6-T10)
swift tools/axdump.swift                # dump the app's Accessibility tree (find a control's real role)
swift tools/itemframe.swift --rect      # the status item's real frame, for `screencapture -R`
swift tools/pixdiff.swift a.png b.png   # compare DECODED pixels (md5 of two PNGs is not a diff)
.build/debug/screenrec-cli --help
```

## Environment facts

- macOS 15.6.1, Apple Silicon, display captures at 4112×2570 (never hardcode), default
  mic is often AirPods Pro. Command Line Tools only — no Xcode, no xcodebuild.
- This dev terminal already holds Screen Recording + Microphone TCC grants → CLI capture
  tests run headlessly. GUI/onboarding tests need the human.
- **Terminal holds an Accessibility grant** (Franco, 2026-07-15) → `tools/menudriver.swift`
  can open, read and click the menu-bar app's menu, so most docs/03 M4/M5 verifies marked
  "(human)" for "menus can't be clicked headlessly" no longer are. Note the grant is on
  **Terminal**, not a "Claude Code" entry — Claude Code here is a CLI hosted by Terminal.app,
  so it never appears in the Accessibility list on its own. Taste calls and first-run TCC
  grant dances still need the human.
- Test recordings: use `~/Movies` or the session scratchpad. NEVER Desktop/Documents/
  Downloads (TCC → opaque "invalid parameter" failures — 02 §2). Clean up test files.
- Real capture runs take real wall-clock seconds; use `--duration` flags, run in
  foreground, and remember stdout buffering rules (02 §10).
