# screenrec — Tier 2

A native macOS (15+) menu-bar screen recorder: **screen video + system audio +
microphone (separate track)**, tuned HEVC encoding, crash-safe long recordings,
pause/resume, and ShadowPlay-style **instant replay** via a global hotkey.
Zero external dependencies — Apple frameworks only.

**Status:** planning complete, implementation not started. See `STATUS.md`.

This repo is documentation-first and built to be driven by coding agents:

| File | What it is |
|------|-----------|
| `CLAUDE.md` | Agent entry point: reading order, working contract, build commands |
| `STATUS.md` | Living state: current task, gate evidence, field notes |
| `docs/00-product-brief.md` | Vision, goals, non-goals, v1 acceptance criteria |
| `docs/01-architecture.md` | Module layout, dataflow, concurrency, state machine |
| `docs/02-technical-reference.md` | All API knowledge + every bug already hit. Read first. |
| `docs/03-milestones.md` | M0–M6 task breakdown with IDs, estimates, gates |
| `docs/04-testing-verification.md` | Concrete pass/fail checks per gate |
| `docs/05-decisions.md` | ADRs — the "why" behind every non-obvious choice |
| `tools/probe.swift` | Inspect any recording's tracks/codecs/duration |

Predecessor: `~/code/screenrec-poc` — the working Tier-1 proof of concept
(ScreenCaptureKit + SCRecordingOutput) that validated capture feasibility and whose
field bugs are baked into `docs/02`.

## Quick start (for humans)

Nothing to run yet. To kick off implementation, point an agent at this directory:

> Read CLAUDE.md and STATUS.md, then continue the work from the current task.
