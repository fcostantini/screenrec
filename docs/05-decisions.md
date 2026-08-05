# 05 — Decision Log (ADRs)

Short-form architecture decision records. Status: ✅ decided · 🅿 parked (revisit
post-v1). Do not silently contradict a ✅ decision — add a new ADR superseding it.

## ADR-001 ✅ macOS 15+ only
SCK's `.microphone` output (15.0) puts all three sources on one delivery path with
host-clock PTS, eliminating the mic clock-drift problem that plagues pre-15 recorders,
and dev machine runs 15.6. Supporting 13/14 would force a second mic pipeline
(AVCaptureSession) + drift handling — the single biggest complexity source in prior art.
Cost: excludes older-OS users. Accepted.

## ADR-002 ✅ SPM + bundle script, no Xcode project
Only Command Line Tools are installed; agents iterate far better on SPM + scripts than
`.xcodeproj`. `Scripts/bundle.sh` assembles/signs the `.app`. Cost: no asset catalogs /
storyboards (fine — menu-bar app), manual Info.plist. Revisit only if notarization
tooling demands Xcode (it doesn't: `codesign`/`notarytool` are CLT).

## ADR-003 ✅ Own AVAssetWriter, not SCRecordingOutput
The point of Tier 2: separate mic track (SCRecordingOutput mixes on macOS 15 —
verified), bitrate control, pause, fragments. Tier-1 PoC remains the SCRecordingOutput
reference.

## ADR-004 ✅ HEVC default; `.mov` container; two AAC audio tracks
HEVC: H.264 writer cap (4096×2304) < dev display; Media Engine encodes HEVC for free.
`.mov`: required for `movieFragmentInterval` crash safety. Two tracks: the product
requirement; DTS confirms separate inputs are mandatory anyway. H.264 export/compat is
a post-v1 transcode feature if ever needed.

## ADR-005 ✅ Hand-rolled replay ring (VTCompressionSession) behind a narrow interface
Apple's `SCClipBufferingOutput` is macOS-27-beta only. We build our own now, but
`ReplayBuffer` protocol keeps the swap cheap when the OS API ships. No B-frames
(`AllowFrameReordering=false`) to keep ring trimming and passthrough muxing simple —
worth the ~5-10% bitrate efficiency loss.

## ADR-006 ✅ No App Sandbox; Developer-ID-style direct distribution (if ever)
Sandbox complicates user-chosen output dirs (security-scoped bookmarks) and buys nothing
for a personal tool not aimed at the App Store. Revisit if distribution plans change.

## ADR-007 ✅ Fail-stop, never fail-weird
Any mid-recording environment change we can't handle transparently (mic format change /
device loss, display unplug, sleep, disk floor) ⇒ finalize a playable file + notify with
cause. No hot-reconfiguration attempts in v1. Rationale: 02 §4/§7; corrupted or silently
degraded recordings are the unforgivable failure.
**Amended by ADR-012** for mic *device loss* only (that trigger now notifies and keeps
recording). **Amended M8-T1 (2026-07-20) for mic *format change*:** every mic buffer is
normalized to one fixed format (`ResampledMicInput`, 48 kHz mono) before any consumer, so a
device/codec flip is absorbed transparently — that trigger no longer exists
(`EndReason.microphoneChanged` was retired, then deleted in M15-T4). Every other trigger here still stands.

## ADR-008 🅿 Cursor-as-data (Screen Studio-style) deferred
v1 burns the cursor in (`showsCursor = true`). The editor-grade alternative (record
cursor positions/clicks as a sidecar, render at export) requires an export/render stage
we don't have. Architecture keeps the door open: a 4th SampleRouter consumer writing an
events sidecar file. Ship v1 first.

## ADR-009 🅿 Echo cancellation deferred
See 02 §8. UI copy recommends headphones. VPIO interferes with SCK system-audio capture;
third-party AEC adds deps and risk. Revisit with real user pain.

## ADR-010 ✅ Zero external dependencies for v1
Apple frameworks only (SCK, AVFoundation, VideoToolbox, CoreAudio, Carbon hotkey,
UserNotifications, SwiftUI). Keeps agent builds hermetic and licensing clean (avoids
GPL contamination risk from reference repos — read, don't copy).

## ADR-012 ✅ Mic device loss ⇒ notify and keep recording (amends ADR-007)
ADR-007 listed "mic device loss" as a fail-stop trigger ⇒ finalize the whole recording. G3
§4.2 (2026-07-15) disproved its premise: a lost mic doesn't hand over to another device, its
buffers just stop (02 §4), and the screen + system-audio capture stays perfectly healthy.
Ending a 90-minute screen recording because a headphone battery died is a worse outcome than
a mic track that stops early. So for this trigger only: emit `microphoneLost` (docs/01) and
**keep recording** — the mic track ends at the disconnect, the file stays playable.
ADR-007's principle is untouched: the result is neither corrupted nor silently degraded, and
"silently" is the operative word — today's behavior (mic dies, nothing is said, you narrate
into a void for 37 s) is exactly what ADR-007 forbids. The notification is what satisfies it,
not the stop. Other ADR-007 triggers (display unplug, sleep, disk floor, and a *same-device*
mic FORMAT change — M3-T2) still fail-stop.
Cost: the user gets a partial mic track rather than a hard stop; acceptable, since the stop
loses strictly more. UI copy for the notification lands with M4 (docs/06).
**Revisited 2026-07-15 once M3-T7 landed — decision unchanged for v1.** The spike answered the
open question: mic recovery IS possible (two verified routes, 02 §4), so this is now a real
choice rather than a limitation. Keeping notify-and-continue for v1 anyway:
- Both routes need a fixed-format (resampled) mic input first — the input's format is welded to
  the first buffer's — so it is ~2 tasks touching the sample path, for a case where the user is
  already told what happened and keeps their screen capture.
- The cheaper-looking route (re-point to a live device) is **one-way**: a died device can never
  be re-bound, so once AirPods drop you are on the built-in for the rest of the recording even
  after they reconnect. The route that *does* handle reconnect (rebuild a mic-only second
  stream) still carries an unverified PTS-coherence assumption — ADR-001's core concern.
- v1's job is a dependable recorder; "your mic died, we said so, the capture continued" is a
  defensible answer for it.
Scheduled as an explicit decision point in **M6-T4**, not left to memory — both routes are
verified and costed in 02 §4, so that call is a product judgement (does it bite in real use?),
not a research question.
**Superseded by M8 (2026-07-20): recovery is BUILT.** It bit in real use (armed replay +
AirPods, measured), so Route 2 shipped: M8-T1's fixed-format input + M8-T2's
`MicrophoneRescue` (HAL return listener → mic-only stream → splice; policy honors the pick,
02 §4). Notify-and-continue remains the floor when the device never returns; the loss and
recovery notifications carry the state either way.

## ADR-011 ✅ CLI-first development
Every capability lands in `screenrec-cli` before the app (M1–M3, M5 core). Agents can
run/verify CLI headlessly under the terminal's existing TCC grants; GUI verification
needs a human. The CLI ships in the repo forever as the debugging surface.

## ADR-013 ✅ Semantic versioning (Franco, 2026-07-20)
Adopted at v1. The `VERSION` file is the single source (ADR from M4-T6's stamping). Read semver for
an **end-user app**, not a library: "breaking" is user-facing. MAJOR = a settings/recording-format
migration, dropped OS support, or a UX overhaul; MINOR = a new backward-compatible feature (M7, M8);
PATCH = fixes with no new feature. `1.0.0` = v1 (M0–M6). Bump `VERSION` in the commit that warrants
it and tag the release. Chosen over date-based or build-number-only schemes because the milestone
structure already maps cleanly onto MINOR bumps, and a human-readable `defaults read`/Finder version
was the point of M4-T6's stamping.

## ADR-014 ✅ Distribution: self-signed, privately shared, no notarization (Franco, 2026-07-21)
⚠️ **Amended by ADR-021 (2026-08-05): the repository is now PUBLIC.** Signing and distribution
are unchanged by that; the "never public" clause below is superseded, and this ADR's own
widened-audience trigger has fired — see ADR-021.
Resolves the review's "personal tool or product?" fork. screenrec is a **personal tool Franco may
hand to a small number of people directly — never public, never commercial.** So the Apple Developer
Program ($99/yr) and `notarytool` are **not** worth it; M6-T4's notarization item is closed as "won't
do" (not merely deferred). The sharing path uses the existing self-signed `screenrec-dev` build:
- **On any Mac that can build**, clone and build (README's four commands) — zero caveats.
- **Others** get the signed `.app` and clear Gatekeeper once via **System Settings → Privacy &
  Security → Open Anyway** (macOS 15 removed the old right-click→Open shortcut for this).
- TCC grants (Screen Recording, Microphone) then **persist across every future build** Franco sends,
  because the stable designated requirement (M0-T3) keys the grant to the reused cert, not to
  Apple's trust chain — the same property G4 §5.2 proved for local rebuilds.
Refines ADR-006 (no sandbox; direct distribution "if ever") with the concrete decision. If the
audience ever widens beyond a handful of direct recipients, revisit — Developer ID + notarization is the only
part missing, and it's purely a Gatekeeper-friction removal, not a capability.

## ADR-015 ✅ Product direction: a recorder that may gain *basic* editing, not a demo studio (Franco, 2026-07-21)
Resolves the review's "recorder or studio?" fork, and supersedes the brief's blanket non-goal
"Editing of any kind." The identity stays **a dependable, native, private capture tool.** Two
consequences:
- **Basic editing is now in-scope as a future** — specifically the *cheap* kind that reuses existing
  machinery: **lossless trim** (passthrough via `ReplayMuxer`'s keyframe logic) and **format export**
  (transcode to a shareable `.mp4`/GIF). These are format/trim operations, not a timeline editor.
  Scheduled as M10.
- **The frame render/compositing stage stays OUT.** Screen-Studio-style *polish-at-export* — automatic
  click-zoom, cursor smoothing, padded backgrounds — needs a Metal/CoreImage render stage screenrec
  deliberately does not have (video goes SCK → encoder untouched). That XL path is **parked**, and
  crossing into it is a separate, explicit future decision, not something to drift into one
  convenience feature at a time. ADR-008's cursor-as-data sidecar remains parked with it.
The line: **trim and transcode = yes (M10); render/composite/animate = no, pending a deliberate
future ADR.** The brief's non-goals list is amended to point here.

**AMENDED 2026-07-31 (Franco): crop on export is on the "yes" side — scheduled as M26.** Crop was
neither trim nor transcode, so this ADR did not settle it and the parked list carried it as
🔴 *needs a ruling*. It goes in on the mechanism, not the appetite: the export path **already scales
every frame**, so a source rectangle is an argument to work that happens anyway, not a new pipeline.
**The line itself does not move** — composite, animate, auto-zoom, cursor emphasis and padded
backgrounds all stay out, and ADR-008's cursor-as-data sidecar stays parked with them (Franco
deferred both again on the same day). ⚠️ The test for anything asking to follow crop through this
door: does it reuse a stage the app already runs, or does it need the Metal/CoreImage render stage
screenrec deliberately does not have? Crop is the first; the rest of that list is the second.

## ADR-016 ✅ H.264/MP4 "share" export (demand-driven, realizes ADR-004's parked note)
ADR-004 kept HEVC + `.mov` the capture default and named H.264 export "a post-v1 transcode feature if
ever needed." The need is real and measured: clips are re-encoded by hand today (an ffmpeg recipe) to
be WhatsApp/web-compatible. So M10-T1 adds a **"Share…" export** to H.264 High + AAC `.mp4`
(`yuv420p`, `+faststart`), zero-dep (AVFoundation, ADR-010). It is an **export path, not a default
change** — recordings are still captured HEVC `.mov`; the `.mp4` is derived on demand for sharing.
GIF export (M10-T3) rides the same read side.

## ADR-017 ✅ No webcam / talking-head capture — screenrec stays a screen recorder (Franco, 2026-07-22)
The v1.6.0 product review surfaced a webcam overlay as the one lever that would change the product's
*category* — toward Loom/demo-narration. **Decided against.** screenrec's identity is a dependable,
private **screen** recorder (ADR-014/015); a webcam is a different product's job. This **tightens** the
brief's "webcam capture/overlay" non-goal from "architecture leaves room" to a **settled no** — the
"leaves room" note is an architecture *fact* (it would be a 4th `SampleRouter` source), not an
intention. Recorded as an ADR so it isn't re-litigated one convenience feature at a time; a future
reversal is a deliberate new ADR, and the ADR-consistent path if it ever happened is a **separate
webcam track** (no compositing), never PiP (which needs the parked render stage, ADR-015). The review's
"webcam fork" is closed; click/cursor-emphasis remains parked behind ADR-015's render-stage decision.

## ADR-019 ✅ System audio is optional (amends ADR-004; Franco, 2026-07-27)
ADR-004 made "two AAC audio tracks" a product requirement — written when the only live question was
whether to **mix** them. The requirement that survives is **never mixed**: whatever audio is captured
lands on its own track, because separate inputs are mandatory anyway (DTS). *Which* sources are
captured is the user's choice. The mic always was; M16-T3 makes system audio one too, because "just my
voice over the screen" is routine for demos, bug reports and meeting notes, and the answer before this
was to mute the Mac. So a recording may carry **two, one, or no** audio tracks — and a track is never
present-but-empty: system audio off means `MovieRecorder` never adds the input, since an input that
receives no buffer still writes an empty AAC track. Default on (`capturesSystemAudio` absent ⇒ on), so
existing installs are unchanged. A silent recording (both sources off) is legitimate, and the menu says
so before you start rather than after.
**Still true after M21-T4:** system audio remains all-or-nothing *per source*. `Everything Except ▸`
drops one app from the capture entirely — picture and sound together, because `SCContentFilter` governs
content — which is not the same thing as scoping audio, and it cannot reach an app with nothing on
screen (docs/02 §1a-ii). Audio-only exclusion would need a Core Audio process tap: a new ADR when it
happens, not an extension of this one.

## ADR-020 ✅ The app may read the release list to say it is out of date (Franco, 2026-08-05)
The brief's non-goals say **"Streaming, cloud anything"**, which left M32 blocked: does checking for a
newer version cross that line? **Decided: no, and the check is allowed** — as a background read on
launch that surfaces a dimmed menu row when a newer release exists, and says nothing otherwise.

**Why this is not the thing the non-goal forbids.** That non-goal is about **recordings** — uploading,
hosting, streaming what the app captures. ADR-014's whole distribution model is a signed `.app` handed
to people directly, and it has produced **22 releases**; a recipient on an old build currently has no
signal of any kind, which is a real defect in the distribution model rather than a missing feature.
Reading a public list of tags sends nothing about the user and nothing about their recordings.

**Bounds — this ADR authorises exactly one request and nothing more:**
- **Reads, never writes.** No telemetry, no analytics, no identifier, no crash reporting, no
  usage counts. Nothing about the machine, the user, or any recording leaves it.
- **Never downloads or installs.** The app only ever *says* a newer version exists; getting it stays
  the manual path ADR-014 describes.
- **Never blocks anything.** Launch, recording, replay and export must be unaffected by a check that
  is slow, refused, or offline — a failed check is silent, not an error.
- **Silent when current.** The surface exists only when there is something to say.

⚠️ **The cost, stated rather than buried:** a launch-time request tells `github.com` this machine's IP
address. That is the whole privacy cost, it is not zero, and for a deliberately private tool it is
worth a way to turn the check off — a ruling left to M32-T3, not assumed here.

🔴 **The bootstrap this cannot solve, recorded so it is not rediscovered:** a version check **can
never announce the release that introduced it**. Every build at or before **1.16.0** has no check in
it, so nobody holding one will be told about 1.17.0 or anything after — they will go on believing they
are current forever. The feature works **from 1.17.0 forward only**, and the existing cohort has to be
told once, by hand, exactly as before. That is not a defect and there is no version of this feature
that avoids it; it is the reason the first upgrade is always the owner's job.

**A reversal is a new ADR.** The line this draws is *reading public metadata about the software
itself*; anything that sends information about the user, the machine, or a recording is on the other
side of it and is not authorised by this.

## ADR-021 ✅ The repository is public; distribution and signing are unchanged (Franco, 2026-08-05)
ADR-014 said screenrec is **"never public"**, and M32 ran straight into the consequence: the update
check it needed could not read a private repo's releases, and — the part that reshaped the milestone
— **recipients of a handed-over `.app` have no GitHub access at all**, so even a link to the releases
page 404s for them. The options were ship a token (a leaked credential, never), publish a separate
version manifest, drop the feature, or make the repo public. **Franco made it public.**

**What this changes:** the source, the history and the release assets are readable by anyone, and
`api.github.com/.../releases` now answers unauthenticated — which is what unblocks M32-T2 within
ADR-020's existing bounds.

**What it does NOT change.** ADR-014's *distribution* posture stands: builds are **self-signed**
(`screenrec-dev`), **not notarized**, and the intended path is still a build handed to someone
directly, or cloned and built from source (README's four commands). Nothing about the app, its
signing, or its TCC behaviour moves because the repo moved.

✅ **The question this fired is settled: the friction is accepted, not paid for** (Franco,
2026-08-05). ADR-014 closed notarization "won't do" *on audience size* and wrote its own trigger —
*"if the audience ever widens beyond a handful of direct recipients, revisit"* — which a public repo
fires, since release zips are now downloadable by anyone and macOS blocks an unnotarized app until
the user goes to System Settings → **Open Anyway**. **Reviewed and kept:** screenrec is a personal
tool published in the open, not a product with users to onboard, so $99/yr buys convenience for
strangers rather than capability for anyone. The obligation this creates is **saying so plainly**:
the README leads its install section with the block rather than burying it, and every release's notes
carry the steps (`release.sh`). Revisit if it ever acquires an audience it owes a smooth first run.

⚠️ **Checked before the switch, and worth recording so nobody re-checks in a panic:** the tree and the
full history carry **no credentials, keys or tokens**; no window titles or channel names ever reached
the docs (M19-T5's discipline held in the prose, not only in the plist); the one email is Franco's own
in docs/00, deliberately. The ~61 `claude.ai/code/artifact/…` links throughout the docs are public but
**unreadable to anyone else** — dead links, not leaks.

## ADR-018 ✅ Armed replay keeps the Mac awake, deliberately — and the assertion says so (Franco, 2026-07-27)
The 2026-07-24 review filed armed replay's sleep assertion as a bug (M16-T1): arm once and the machine
never idle-sleeps again, while `pmset` blames a recording that isn't happening. Two things settled it.
**Measured:** releasing our assertion would not have let an armed Mac sleep anyway — any SCK stream
capturing audio also carries a `PreventUserIdleSystemSleep` held by `coreaudiod` for
`/usr/libexec/replayd`, released only at stream teardown (02 §7). Only tearing the armed stream down
after N idle minutes would have delivered sleep, and that trades away the feature's whole promise: a
buffer that is there when you reach for it. **Decided:** an armed stream holds the assertion on purpose
— the honest fix is the reason string, not the behaviour. `CaptureEngine.Purpose` gives each stream its
own (`Recording the screen` / `Instant replay is armed` / `Capturing the screen`), and the cost is
stated where the user chooses it (M16-T2's caption). This is M16's thesis applied to itself: the state
stops lying without the product quietly doing less than the user asked for. A future reversal is a new
ADR, and it needs a stream teardown, not just `SleepGuard`.
