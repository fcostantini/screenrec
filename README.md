# screenrec

A native macOS (15+) menu-bar screen recorder: **screen video + system audio +
microphone (separate track)**, tuned HEVC encoding, crash-safe long recordings,
pause/resume, and ShadowPlay-style **instant replay** via a global hotkey.
Zero external dependencies — Apple frameworks only, no Xcode required.

![The ScreenRec menu opening in the macOS menu bar: Instant Replay is armed and shows its buffer cost,
a recording starts and the elapsed clock ticks in the menu bar beside a red dot, and Stop & Save ends
with a "Recording saved" confirmation.](docs/assets/demo.gif)

<sub>Recorded with ScreenRec's own region capture and encoded by its GIF exporter — v1.19.0.</sub>

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

### YouTube credentials

Signing in to YouTube needs a Google OAuth client, and the repository does not contain one.
Release builds carry the author's. A build you make yourself has none, and its Settings will read
**Not available in this build** — everything else works. To give your own build one:

1. In the [Google Cloud console](https://console.cloud.google.com), create a project and enable
   **YouTube Data API v3**. It needs no billing account.
2. Under **Google Auth Platform**, set up the consent screen (audience **External**), add yourself
   as a test user, and add the scope `https://www.googleapis.com/auth/youtube.upload`.
3. Create a client of type **Desktop app** and download its JSON straight away — the secret is
   shown only once.
4. Save it as `~/.config/screenrec/youtube-client.json`.

`Scripts/bundle.sh` stamps the client ID and secret from that file into the bundle and says so
(`YouTube credentials: stamped`). The file lives outside the repository on purpose: don't commit it.

**If Settings says the sign-in ends on a date:** the Google project is still in *Testing*, where
Google ends every sign-in after seven days and only the test users you listed can connect. Open
**Google Auth Platform › Audience** in the console and press **Publish app** — no verification is
needed for personal use — then disconnect and connect again, because a sign-in made while testing
keeps its seven days.

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

- **Start Recording / Stop & Save** — capture to a `.mov` in your output folder. An optional
  **global start/stop shortcut** works from any app.
- **Source ▸** — the whole screen, a **chosen app** (its windows + its audio only), a single
  **window**, a **drag-selected region** (`Select Region…`), or the whole screen **except one app**
  (`Everything Except ▸` — that app is neither seen nor heard).
- **Capture System Audio** — on or off; a recording may carry two, one or no audio tracks.
- **Pause / Resume · Discard** — mid-recording, with the timeline kept in sync.
- **Arm Instant Replay** + **⌥⌘R** — keeps a rolling buffer (5 s → 15 min); the hotkey saves the
  last N seconds to disk in under a second, whether or not you're also recording.
- **Stop & Copy MP4** — stops, transcodes to the message-safe profile and leaves the `.mp4` on the
  clipboard, so the next keystroke is ⌘V.
- **Recent recordings** — from each: **export a shareable MP4 or GIF**, **trim** it (losslessly, or
  re-encoded to hold only the kept range), rename, reveal, Quick Look. The original is never touched,
  and the Trim window can write the shareable `.mp4` of a range directly.
- **Settings (⌘,)** — output folder, quality (Efficient / Balanced / High), frame-rate cap,
  microphone (None / Automatic / a device), replay buffer length and shortcut, MP4/GIF export sizes,
  a 3-2-1 count-in, a name prompt when a take stops, an automatic **Stop After** bound, and
  **Launch at login**.

## Installing a release

**⚠️ macOS will refuse to open this app the first time.** That is expected, and it is a deliberate
choice rather than an oversight.

Builds are signed with a **local** identity and are **not notarized by Apple** (ADR-014, ADR-021).
Two ways in:

- **Build it yourself** — clone and run the four commands above. No Gatekeeper prompt at all, and
  nothing to trust but your own machine. This is the recommended path.
- **Download a release** from [Releases](https://github.com/fcostantini/screenrec/releases), unzip,
  and move **ScreenRec.app** to `/Applications`. On first launch macOS blocks it as an unidentified
  developer: open **System Settings → Privacy & Security**, find the ScreenRec message and click
  **Open Anyway** (macOS 15 removed the old right-click → Open shortcut). After that it launches
  normally, and screen-recording and microphone grants **persist across every future build**, because
  the stable code-signing identity keys the grant to the app rather than to Apple's trust chain.

## What ScreenRec sends

ScreenRec has no server and no analytics. Your recordings stay on your Mac unless you send one
somewhere yourself. It talks to the network in two cases:

- **Checking for a newer version.** At launch and once a day it reads the public list of releases
  from GitHub, which tells GitHub your IP address and nothing else. Turn it off in
  **Settings › General › Check for new versions**.
- **YouTube** *(arriving in 1.23; development builds already have the sign-in)*. Only if you connect
  an account in **Settings › Sharing**, and then only when you ask for an upload, one clip at a time:
  - **What goes to Google:** the clip you chose, and the title, description and visibility you gave it.
  - **What ScreenRec may do with your account:** add videos. It asks Google for that one permission
    and cannot see, edit or delete anything already on your channel.
  - **What is kept on your Mac:** the sign-in, in
    `~/Library/Application Support/ScreenRec/youtube-sign-in.json`, readable only by your user.
  - **How to end it:** **Disconnect** in Settings withdraws the sign-in with Google and deletes that
    file. You can also remove ScreenRec's access at any time from your Google account's
    [third-party access page](https://security.google.com/settings/security/permissions).

  ScreenRec uses YouTube API Services. Uploading through it is subject to the
  [YouTube Terms of Service](https://www.youtube.com/t/terms), and Google's handling of what you
  upload to the [Google Privacy Policy](https://policies.google.com/privacy). Questions about any of
  this: open an issue on this repository.

## Repository map

This repo is documentation-first and built to be driven by coding agents:

| File | What it is |
|------|-----------|
| `CLAUDE.md` | Agent entry point: reading order, working contract, build commands |
| `STATUS.md` | Living state: current task, gate evidence, field notes |
| `docs/00-product-brief.md` | Vision, goals, non-goals, v1 acceptance criteria |
| `docs/01-architecture.md` | Module layout, dataflow, concurrency, state machine |
| `docs/02-technical-reference.md` | All API knowledge + every bug already hit. Read first. |
| `docs/03-milestones.md` | Milestone task breakdown with IDs, estimates, gates |
| `docs/04-testing-verification.md` | Concrete pass/fail checks per gate |
| `docs/05-decisions.md` | ADRs — the "why" behind every non-obvious choice |
| `docs/06-ui-spec.md` | Menu-bar app UI spec: menu states, notifications, onboarding, settings |
| `docs/07-field-notes.md` | What SCK/VideoToolbox/AVFoundation actually do, measured and dated |
| `docs/history/` | Closed session logs, rotated out of STATUS.md. Not maintained |
| `tools/probe.swift` | Inspect any recording's tracks/codecs/duration |
| `tools/menudriver.swift` | Drive/inspect the menu-bar menu via Accessibility (testing) |

## Contributing / development loop

This ordered loop is the gate — run it top to bottom after any change:

```sh
swift build            # debug build compiles
swift test             # all unit tests pass
swift build -c release # release build compiles
Scripts/bundle.sh      # assemble + sign dist/ScreenRec.app (must stay signable)
```

Then run the current task's Verify step (see `docs/03-milestones.md`). Agents: start
with `CLAUDE.md`, then `STATUS.md`.

**Automated gate (install once per clone):** a versioned pre-push hook runs the loop —
`swift build` · `swift test` · the hardware-encode tests a default `swift test` skips
(`SCREENREC_HW_ENCODE_TESTS=1`) · `swift build -c release` — and blocks the push if any step
fails:

```sh
git config core.hooksPath Scripts/hooks   # points git at Scripts/hooks/pre-push
```

Signing (`bundle.sh`) is left out of the hook (it belongs to the release path); bypass in a
genuine emergency with `git push --no-verify`.
