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

## ADR-011 ✅ CLI-first development
Every capability lands in `screenrec-cli` before the app (M1–M3, M5 core). Agents can
run/verify CLI headlessly under the terminal's existing TCC grants; GUI verification
needs a human. The CLI ships in the repo forever as the debugging surface.
