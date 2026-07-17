# screenrec — Tier 2

A native macOS (15+) menu-bar screen recorder: **screen video + system audio +
microphone (separate track)**, tuned HEVC encoding, crash-safe long recordings,
pause/resume, and ShadowPlay-style **instant replay** via a global hotkey.
Zero external dependencies — Apple frameworks only, no Xcode required.

**Status:** feature-complete through M6 (ship-quality pass). See `STATUS.md` for the
live gate table and what's left before v1.

## Build & run

Requirements: **macOS 15+**, Apple Silicon, and the Command Line Tools
(`xcode-select --install`). No Xcode, no package manager, no external dependencies.

```sh
swift build -c release      # compile
Scripts/bundle.sh           # assemble + code-sign → dist/ScreenRec.app
open dist/ScreenRec.app      # launch (menu-bar icon; no Dock icon — it's an accessory app)
```

`Scripts/bundle.sh` signs with a local identity so macOS remembers the permission
grants across rebuilds. It looks for, in order:

1. **`screenrec-dev`** — a self-signed identity you create once (below), or
2. any **Apple Development** identity you already have from Xcode.

If neither exists it prints the ~2-minute setup. To create `screenrec-dev` by hand:
open **Keychain Access → Certificate Assistant → Create a Certificate…**, name it
`screenrec-dev`, type **Code Signing**, then trust it:

```sh
security find-certificate -c screenrec-dev -p > /tmp/screenrec-dev.pem
security add-trusted-cert -r trustRoot -p codeSign /tmp/screenrec-dev.pem
```

## First launch

The app onboards itself — no manual permission-granting. On first run it opens a
setup window and requests, via the system prompts:

- **Screen & System Audio Recording** — required; the app relaunches itself once granted.
- **Microphone** — optional; needed only for the separate mic track.
- **Notifications** — optional; "Recording saved", "Replay saved", and failure notices.

The default output folder is `~/Movies` (no extra grant needed). Choosing Desktop,
Documents, or Downloads requires macOS's Files & Folders access; the folder picker
tells you if a folder isn't writable before you record.

## Use

Everything is in the menu-bar menu:

- **Start Recording / Stop & Save** — full-screen capture to a `.mov` in your output folder.
- **Pause / Resume** — mid-recording, with the timeline kept in sync.
- **Arm Instant Replay** + **⌥⌘R** — keeps the last 30 s / 60 s / 2 min buffered; the
  hotkey saves it to disk in under a second, whether or not you're also recording.
- **Settings (⌘,)** — output folder, quality (Efficient / Balanced / High), frame-rate
  cap, replay buffer length and shortcut, and **Launch at login**.

## Sharing this build

The build is signed with a **local** identity, so the assembled `dist/ScreenRec.app`
runs on **this machine only** — copied elsewhere it hits Gatekeeper as an unidentified
developer. To try it on another Mac, **share the repo and build there** (the steps above
are self-contained). Distributing the built `.app` needs Developer ID signing + Apple
notarization — tracked as M6-T4.

## Repository map

This repo is documentation-first and built to be driven by coding agents:

| File | What it is |
|------|-----------|
| `CLAUDE.md` | Agent entry point: reading order, working contract, build commands |
| `STATUS.md` | Living state: current task, gate evidence, field notes |
| `docs/00-product-brief.md` | Vision, goals, non-goals, v1 acceptance criteria |
| `docs/01-architecture.md` | Module layout, dataflow, concurrency, state machine |
| `docs/02-technical-reference.md` | All API knowledge + every bug already hit. Read first. |
| `docs/03-milestones.md` | M0–M7 task breakdown with IDs, estimates, gates |
| `docs/04-testing-verification.md` | Concrete pass/fail checks per gate |
| `docs/05-decisions.md` | ADRs — the "why" behind every non-obvious choice |
| `docs/06-ui-spec.md` | Menu-bar app UI spec: menu states, notifications, onboarding, settings |
| `tools/probe.swift` | Inspect any recording's tracks/codecs/duration |
| `tools/menudriver.swift` | Drive/inspect the menu-bar menu via Accessibility (testing) |

Predecessor: `~/code/screenrec-poc` — the working Tier-1 proof of concept
(ScreenCaptureKit + SCRecordingOutput) that validated capture feasibility and whose
field bugs are baked into `docs/02`.

## Contributing / development loop

There is no CI. This ordered loop is the gate — run it top to bottom after any change:

```sh
swift build            # debug build compiles
swift test             # all unit tests pass
swift build -c release # release build compiles
Scripts/bundle.sh      # assemble + sign dist/ScreenRec.app (must stay signable)
```

Then run the current task's Verify step (see `docs/03-milestones.md`). Agents: start
with `CLAUDE.md`, then `STATUS.md`.
