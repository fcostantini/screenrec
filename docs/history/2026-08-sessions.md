# 2026-08 sessions — closed logs

Rotated out of `STATUS.md` when its "Now" section passed the ~250-line bound the working contract
sets. Gate evidence for G26, G27 and G28 stays in STATUS.md's gate table; per-task specs and their
tick boxes are in `docs/03-milestones.md`.

## M27 — audio-only per-app exclusion, and the v1.14.0 cut

- **🚢 v1.14.0 CUT (2026-08-03) — M27 ships: an app can be left out of a recording's audio while it
  stays in the picture.** `Mute ▸` in the menu, `--mute-app` in the CLI, a Core Audio process tap
  behind both. **695 tests**, release and signed bundle green, tagged and deployed.
  ✅ **What it does that SCK cannot:** silence an app with **no window at all** — the case
  `SCShareableContent` never lists, while its audio plays on at full level.
  ⚠️ **The bump also carries M25's deferred patch**, as ruled on 2026-07-31.
  ⚠️ **Known, recorded rather than fixed:** the pre-existing unused-value warning at
  `AppState.swift:753`; G26's letterbox calibration still rests on one clip; and the tap-silent
  notice's *positive* path can't be exercised without revoking a TCC grant.

- **✅ M27 WORKS IN THE APP (2026-08-03) — one plist key was the whole blocker.**
  `NSAudioCaptureUsageDescription` + the grant Franco clicked: a **menu-driven** take now carries
  full-length audio (697 344 samples / 14.5 s, continuous) with the muted app at **−67.7 dBFS** and
  the rest of the mix at −12.2. **No notarization and no entitlement needed** — the feasibility
  question is closed. ⚠️ The plist change is committed; **the menu path is now verified end to end**,
  which the CLI legs never covered.
  ⚠️ **A late-clicked prompt mimics a delivery bug:** the first run granted mid-take gave 1.3 s of
  audio in a 24 s file. Check for an unanswered prompt before chasing a stall.
  ✅ **Helpers now collapse onto their app (Franco's catch, 2026-08-03):** the menu shows **Discord**
  and muting it silences `com.hnc.Discord.helper.Renderer`, where the call audio actually is. ⚠️ The
  earlier framing was wrong twice over — the helper row was not noise to hide, and the plain Discord
  row would have silenced **nothing** (docs/07).
  ✅ **Armed replay does receive tap audio** (440 Hz at −22.1 dBFS in a saved clip) — the question
  M27-T2 left open.
  ✅ **The long take passed (5 min):** ~5.7% of one core, RSS 185 MB, **0 dropped frames**, 48 kHz
  throughout — closing both deferred questions (T2's IOProc allocation, T5's resampling).
  🔴 **It also caught a false positive no unit test could:** the silence notice fired because the
  **only app playing was the muted one**, so the tap was rightly silent while the cross-check said
  otherwise. `isAnythingPlaying` now excludes the silenced family; reproduced and confirmed fixed.
  ✅ **M27-T5 SHIPPED: the tap is normalised to 48 kHz stereo** through the mic path's own converter,
  now with an injectable target (the mic's default is untouched by construction). **694 tests.**
  ✅ **The leg with teeth passed (Franco, 2026-08-03):** AirPods disconnected mid-arm → the saved
  clip is 91.7 s with an **89 s audio track at 48000 Hz**, holding audio from *before* the switch.
  The ring kept its window; a format change would have emptied it. ✅ It also explains the
  "newest seconds are silent" anomaly logged twice: the **40 s tone fixture ending**, not a stall.
  ⚠️ The 24 kHz→48 kHz conversion itself stays unit-pinned — the device was back at 48 kHz by then.
  ⚠️ **Background: a tap's sample rate follows the output device (24 kHz measured, 48 kHz in T1) —
  SCK's is always 48 kHz.** So a muted take's audio quality now depends on the hardware. **Not the
  half-speed bug it was first written up as** — the track is correctly labelled and plays correctly;
  the retraction and the reasoning are in docs/07. **Open design question:** resample the tap to
  48 kHz (the `ResampledMicInput` precedent) or accept the device's rate — Franco's call.
  🔴 **Also still open:** a long take (T2's deferred real-time allocation). ⚠️ **Don't run one while
  Franco is on a call** — it captures the call.

- **🔴 (superseded) M27 DID NOT WORK IN THE APP (2026-08-03) — G27's pass covers the CLI only.** Measured at one
  moment, Spotify playing, mute set: **the app records −∞ dBFS** (silence) while **the CLI records
  −6.8 dBFS** with just the muted tone gone. **The tap needs a TCC grant the bundle doesn't have.**
  ⚠️ **M27-T1's Q5 answer was wrong and is retracted:** the probe ran the bundle's executable **from
  the Terminal**, and TCC attributes access to the **responsible process** — so it re-tested
  Terminal's grants. Launching a bundle's binary from a granted parent never tests that bundle.
  ✅ **`TapSilenceWatchdog` caught it unprompted, in the wild**, with a true sentence — the failure
  it was designed for, found by a human running the feature normally. Without T4 this ships as
  silent audio.
  ✅ **Feasibility is likely, and does not hinge on notarization:** TCC keys on a stable code
  identity, not on Gatekeeper — **this app already holds Screen Recording, Microphone and
  Notifications while self-signed** (M0-T3's stable designated requirement). The ladder, cheapest
  first: ① add **`NSAudioCaptureUsageDescription`** to the bundle plist, re-sign, **launch it as an
  app** (never from Terminal — that is what invalidated T1's probe) and create a tap; a missing usage
  string is the commonest cause of exactly this silent-zeros shape. ② If not, test whether an
  **entitlement** is needed — most audio entitlements are unrestricted and a self-signed build can
  carry them. ③ Only if both fail is "not without notarization" a real answer rather than a guess.
  ⚠️ **No TCC denial appears in the log**, consistent with silent zeros rather than a refusal.
  🔴 **Next: find what the app needs** (`NSAudioCaptureUsageDescription`? an entitlement? a grant
  that only a notarised build can hold?) — and if it can't have it, **M27 does not ship** and that is
  a product decision, not a bug fix. **No 1.14.0 cut until then.**

- **✅ G27 PASSED (2026-08-03) — M27's four tasks and its gate are in.** Evidence in the gate table.
  **Audio-only per-app exclusion ships:** a hidden app's tone fell **−18.3 → −70.8 dBFS** while a real
  windowed app survived. 🔴 **Two things stand between this and a release cut:** a muted take on a
  quiet Mac has **no audio track at all** (Franco's ruling pending), and the **aggregate device
  disappearing is unmeasured** (AirPods mid-take). ⚠️ **The first attempt at this gate was discarded**
  — both sound sources were silent, and a silent control proves nothing (the G21 trap).
  ⚠️ **`VERSION` is still 1.13.0**: M27 is a MINOR and wants 1.14.0, but not before those two close.

- **✅ M27-T4 SHIPPED (2026-08-03) — M27's four tasks are in. Next: G27.** `TapSilenceWatchdog`
  (6 tests) plus `audioTapSilent`. **687 tests**, dev loop clean. Plan artifact:
  `claude.ai/code/artifact/e15862e9-71c5-4af2-9ea8-b6338e74fd0f`.
  🔴 **Silence cannot be the signal:** an ungranted tap streams zeros with `OSStatus 0`, and so does
  a quiet Mac. The check is **something is playing AND the tap is silent for 5 s** — and the control
  that matters passed: **a genuinely quiet recording raises nothing**.
  ✅ **Ruled: no fallback to SCK audio** — it would restart the stream mid-take *and* silently undo
  the mute, since that path is the very filter which can't drop audio without dropping windows.
  ⚠️ **Two honest gaps:** the notice's positive path can't be exercised end to end without revoking
  Franco's TCC grants (decision unit-tested both ways instead), and **the aggregate device
  disappearing — AirPods connecting mid-take — is still unmeasured**. Both are G27's to weigh.

- **✅ M27-T2 and T3 SHIPPED (2026-08-03) — an app can be muted from the menu. Next: M27-T4.**
  `SystemAudioTap` routes tapped audio as `.systemAudio` through `PCMSampleBuffer` (its third
  caller), host-clock stamped so `TimestampRebaser` needs no special case — **no consumer changed**.
  `Mute ▸` sits beside `Everything Except ▸`, and the dimmed rows are one grammar: **`… won't be
  seen or heard`** against **`… will be seen but not heard`**. **681 tests.** Plan artifacts:
  `.../384bd51c-72d2-4f86-820a-2250378605b2` (T2), `.../55c6bd3a-d758-4e8c-9205-50c6eb429950` (T3).
  ✅ **Measured:** silencing QuickTime by bundle ID took its tone **−18.5 → −102.4 dBFS** while the
  rest of the mix held at −18.1; the no-exclusion control kept both; an ordinary take still lands
  **3 tracks**, because nothing muted means the SCK path is untouched code.
  🔴 **Two wrong assumptions, both caught by building:** the process object list is *every process
  the audio system knows* (`caphost`, `audiomxd`, accessibility daemons) — `IsRunningOutput` plus a
  resolvable-name filter took the menu from six daemons to one real app; and **one app owns several
  audio objects**, so T2's "silence the object" left a browser's other helpers audible.
  ⚠️ **T2's unplanned finding, which T4's copy must carry:** the tap *also* captures windowless
  processes SCK omits, so muting one app can make a take hold **more** sound, not less (docs/07).

- **✅ M27-T1 DONE (2026-08-03) — the premise holds; a tap does what SCK cannot. Next: M27-T2.**
  A spike, no shipped code, all five questions answered in docs/07. Plan artifact:
  `claude.ai/code/artifact/1af9516f-d319-482b-8493-0aeed7e2c18b`.
  ✅ **The one the milestone rested on:** a tap **excludes a windowless process**. Two `afplay` tones,
  the exclusion swapped between them as the control — the excluded one drops to **−106 / −97.8 dBFS**
  while the other holds at −18.2. That is the case SCK structurally cannot reach.
  ✅ **Format is SCK's own** (48 kHz, 2 ch, 32-bit float), 512-frame callbacks, and **tap and SCK run
  together without conflict**. Cost **~0.4% of one core**, 27.6 MB.
  🔴 **The finding that shapes T3/T4:** excluding a process with **no audio object** is a **silent
  no-op** — that app's audio lands in full. The excludable list is *processes the audio system
  knows*, not *running apps*. An excluded process quitting mid-take is graceful.
  ✅ **The permission question is closed, and M27 needs nothing new:** the deployed bundle's own
  identity read a tone through a tap at **−18.2 dBFS**. No new TCC grant, no new `Info.plist` key —
  Screen Recording and Microphone already carry it.
  🔴 **But an ungranted tap is SILENT, not an error.** A freshly signed `.app` with no grants
  reported `OSStatus 0`, a valid tap UID and **374 callbacks of pure zeros**. **A health check that
  reads status codes would pass a tap capturing nothing** — T4's failure modes must measure level.


- **✅ G26 PASSED (2026-08-03) — M26 is complete and v1.13.0 is tagged.** Crop on export ships:
  a rect from the CLI, a band drawn in the Trim window, a `Find bars` button that finds a real
  letterbox by itself, and a precise trim that crops while keeping HEVC and both audio tracks.
  Evidence in the gate table. **Next: Franco's call.** M27 (Core Audio process taps) is the proposed
  one, and its T1 is explicitly *measure before designing anything else*; M28 (`NSMenu`) is the other.
  ⚠️ **Two things left on the floor, both recorded rather than done:** the pre-existing unused-value
  warning at `AppState.swift:753`, and the fact that G26's calibration rests on **one** letterboxed
  clip — a second, from a different source, would be worth more than any amount of tuning.
