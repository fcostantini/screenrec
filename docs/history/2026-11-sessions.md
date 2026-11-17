# 2026-11 sessions — closed logs

Rotated out of `STATUS.md` on 2026-11-17, when its "Now" section had reached 305 lines against the
~250-line bound the working contract sets. These are the per-task logs of M40-T1 to M40-T3
(2026-11-16 and 2026-11-17), M40's filing, and the note about the live install of 2026-11-11, moved
verbatim. M40's later tasks stay in STATUS.md until the milestone closes; per-task specs and their
tick boxes are in `docs/03-milestones.md`.

- **✅ M40-T3 DONE (2026-11-17) — the Trim window uploads the range to YouTube, after a sheet
  for the title, description and visibility.** `Upload to YouTube…` under `Export Audio & Copy`;
  a connect alert when there is no account, then the sheet by itself; the upload chained to
  `Export & Copy`'s own export; one notice with the link. **982 tests** (944 → 982); **30 breaks,
  30 red.** The deployed app at `/Users/Shared` is this commit's build, connected to his channel.
  ✅ **Live:** one unlisted upload of a 24 s synthetic clip — 14 s from the press to `uploaded`,
  oEmbed 200 with the typed title, watch page `"isUnlisted":true`.
  ✅ **Review:** ten findings, ruled "as proposed" — seven fixed and re-verified live on a
  temporary build with a fake sign-in (his real one untouched), one moved to T4, three to T5.
  **Next: M40-T4** — the menu row, the receipt with `Copy Link`, the clipboard rule, quitting
  mid-upload, `Upload to YouTube…` on exported `.mp4`s. ⏸ **Plan artifact published 2026-11-17,
  awaiting Franco's go:** `claude.ai/artifact/QKHR2hWzjpYGJTCiDPwXxA`. **Do not implement before
  he answers.** It asks four rulings, each with a recommendation: (1) a `Cancel Upload` row —
  include; (2) a click on the notice — open the video; (3) whole recordings — keep out, `.mp4`
  only; (4) the receipt's lifetime — one hour, like the others.
  ⚠️ **Test uploads are a budget:** one or two a day; one spent 2026-11-17.
  **Needs Franco:** delete the eight `ScreenRec test …` videos in Studio (seven from T1, one from
  T3), and say whether Studio flags them about audience ("made for kids"); whether the *Uploaded
  to YouTube* notice appeared at 09:24 on 2026-11-17; by eye, a dead-key accent (`´` then `a`)
  typed into the sheet's title lands as one letter.

- **✅ M40-T2 DONE (2026-11-16) — Settings connects a YouTube account, and a build carries the
  credentials to do it.** `UploadModel` + a **YouTube** section in Settings › Sharing; `bundle.sh`
  stamps the client. **944 tests** (905 → 944); **12 + 9 breaks, all red**. Live on the deployed
  build: connected, relaunched, **swapped to a build with another `CDHash` — still connected, no
  dialog**, disconnected, folder empty. **Next: M40-T3** — plan artifact published, awaiting Franco's
  go (`claude.ai/artifact/9ked9JDke2DStc8yGn8kL7`) — approved; see the entry above.
  🔴 **Ruled by Franco: the sign-in is a private file, not a Keychain item** (ADR-024 amended). The
  data-protection Keychain refuses a self-signed program outright (`-34018`).
  🔴 **Two defects only running it showed:** `plutil -extract` prints its failure on *stdout*, so
  `bundle.sh` first stamped an error sentence as the client ID; and a link dimmed into prose.
  ⚠️ **`/code-review medium`: ten found, eight fixed, one to T5, one rejected** (no Keychain
  migration — T1's item is gone).
  ⚠️ **The app can hold a sign-in and still cannot upload** — that is T3. The installed app at
  `/Users/Shared` is this development build, **connected** to Franco's channel since he published.
  ✅ **Franco's Google project is In production** (published 2026-11-16, after T2), so a new
  sign-in no longer ends after 7 days. The Settings line that says so appears only in Testing.

- **✅ M40-T1 DONE (2026-11-16) — the CLI signs in to YouTube and uploads a file.** New target
  `UploadCore` + `screenrec-cli youtube connect | upload | disconnect`. Live on Franco's own Google
  project: a **59.8 MB** clip cut at 40 % resumed from the **24.6 MB** YouTube held and landed in
  **19.7 s**; an unlisted one answered oEmbed `200` at once.
  🔴 **Its one "no" reshaped T2:** with a self-signed identity the Keychain binds an item to the
  build that made it — another build gets the password dialog and cannot delete it.
  ✅ **Measured, in docs/07:** the secret is required even with PKCE; the response names the channel;
  YouTube needs ~2 s after a break before it reports what it kept; uplink here is 2.6–3.8 MB/s.
  ⚠️ **Not exercised live:** the access-token refresh. **Seven test videos** sit on Franco's channel.

- **📋 M40 FILED from Franco's rulings (2026-11-16) — a trimmed clip can go to YouTube; five tasks.**
  Scoping artifact `claude.ai/artifact/1xC4iSiiCSRsaatL3A9qRP`; **MINOR → 1.23.0 at G40**. Rulings,
  ADR-024 and the task specs are in docs/03 and docs/05.
  ⚠️ **Not ruled, only not objected to:** `Cancel Upload`, a notification click that opens the video.
  🔴 **This Mac's `gcloud` has an unrelated account and project active** — never run it for M40
  without an explicit `--project`.

- **🔧 2026-11-11 — the live install was on v1.12.0; swapped to 1.22.0. No code change.** Franco
  reported the Trim window as small and unresizable. That was 1.12.0's fixed window:
  `/Users/Shared/ScreenRec.app` had not moved since Jul 31, and predates both the resize (M37-T2) and
  the update notice. Replaced with `dist`'s 1.22.0 — same designated requirement, pid 51936 → 53463,
  installed binary's sha equal to `dist`'s. Field note filed.
  ⚠️ **Not driven:** the Trim window has not been opened on the new install this session.
  **Needs Franco:** confirm it drags larger; re-arm Instant Replay if the swap left it off.
  **Open question:** should a release also update the live install (`release.sh` only publishes)?
  **Next:** nothing filed — new work comes from Franco or a review.
