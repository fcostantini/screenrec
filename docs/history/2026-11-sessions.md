# 2026-11 sessions — closed logs

Rotated out of `STATUS.md` on 2026-11-17, when its "Now" section had reached 305 lines against the
~250-line bound the working contract sets. These are the per-task logs of M40-T1 to M40-T3
(2026-11-16 and 2026-11-17), M40's filing, and the note about the live install of 2026-11-11, moved
verbatim. M40-T4's and M40-T5's logs followed the same day, when "Now" was back at 263 lines.
M40-T6's followed on 2026-11-18, when the gate passed and the milestone closed; per-task specs and
their tick boxes are in `docs/03-milestones.md`.

- **✅ M40-T6 DONE (2026-11-17) — a failed upload can be tried again, and finishes the same one.**
  The menu keeps `Couldn't upload · ‹title›` for a day, with the reason, `Try Again`, the clip,
  Studio and `Dismiss`. `Try Again` continues the **same** upload while YouTube still has it
  and the sign-in it began under still stands, and starts over when not; the notices say which,
  and name an entry only when it will not be finished. Plan
  `claude.ai/artifact/AuVodjvViyFqv38r8pJEpZ`; `/code-review medium`'s nine findings ruled *"as
  proposed"* and applied (docs/03). **1097 tests** (1061 → 1097); **96 breaks, 96 red.**
  **Live:** the row, `Try Again`, `Cancel Upload` and `Dismiss` on a fail-on-purpose build; then
  for real — a 64 MB clip cut at 40%, `Try Again` picking up at 46% and landing one unlisted
  video nine seconds later, link copied, no "earlier entry" sentence. **(human) Franco, in
  Studio: one video, no leftover.** Installed: the clean T6 build (no scaffold in `strings`).
  ⚠️ **Left as designed:** `Dismiss`, or the row's day running out, drops a kept session and no
  notice says so (docs/07) — put to Franco in the session's report.
  **Next: gate G40** (docs/03): the gate's own checks on the deployed build, the README's
  "arriving in 1.23" note, `CHANGELOG.md` 1.23.0, `VERSION` 1.23.0, tag. **Not started — a
  checkpoint with Franco comes first.**

- **✅ M40-T5 DONE (2026-11-17) — every failed upload says why, and what to do next.**
  `UploadFailure`: one list, worded by the app and the CLI. The uploader resumes while bytes
  arrive and for about 5 minutes after, renews a lapsed token once, and opens a session a second
  time only when the first try cannot have reached YouTube. A sign-in Google refuses to renew
  drops the account where it is found; one YouTube refuses although Google renewed it is kept.
  The notice is the reason plus two sentences said only when true. The row says `· waiting for
  the connection`. **1061 tests** (1027 → 1061); **48 breaks, 48 red.** The deployed app at
  `/Users/Shared` **is** this commit's build.
  ✅ **Measured against YouTube** (docs/07): a title's 100 is counted in **code points** — the
  sheet now counts the same; `DELETE` on an unfinished session closes it (`499`).
  ✅ **Live:** the waiting row and four notices on a fail-on-purpose build; and **the real dead
  sign-in** — Franco removed ScreenRec's access at Google, the next upload said *needs
  reconnecting*, Settings went to `Not connected`, the saved sign-in was deleted.
  ✅ He reconnected the same afternoon (the saved sign-in is back; Settings reads `Connected`).
  ✅ **His look in Studio (2026-11-17):** the three measurement entries are **still listed**, so
  `DELETE` does not remove an entry; *test 10* was gone because he deleted it. The *delete it in
  Studio* wording stands, and T6 is `Try Again` only.
  **Next: M40-T6 — see the entry above this one.**
  **Needs Franco:** reconnect in Settings (`Connect…`); delete the test videos, the three
  measurement entries among them; click an *Uploaded to YouTube* notice once; the audience
  question from T1.

- **✅ M40-T4 DONE (2026-11-17) — the menu shows an upload, keeps its link, and can start one.**
  `Uploading to YouTube… n%` with `Cancel Upload`; the `Uploaded to YouTube · ‹title›` receipt
  (`Copy Link` · `Open on YouTube` · `Edit in YouTube Studio` · `Reveal File in Finder`); the
  clipboard rule; `Upload to YouTube…` on `.mp4` rows; a quit question that counts uploads.
  **1027 tests** (985 → 1027); **72 breaks, 72 red.** The deployed app at `/Users/Shared` **is**
  this commit's build, connected to his channel.
  ✅ **Rulings, all Franco's:** *"let's go"* (taken as the four plan rulings as recommended); the
  review's ten findings *"as proposed"* — a quit nobody chose to wait through **abandons
  uploads**, the *link is in the menu* notice **spells the link out**; *"Tell me each time"*.
  🔴 **What his Studio showed:** YouTube keeps an unfinished entry (*Processing will begin
  shortly*) for any upload it had opened and that then stops, and the app cannot delete it. A
  stop after that point posts *Upload to YouTube stopped* (click → Studio); the quit question
  says so first.
  ✅ **Live:** six fake-uploader scenarios, one real unlisted upload from a Recent Exports row,
  one real upload cancelled at 31%; then, after the fixes, the stopped notice on `Cancel Upload`,
  on `Quit Anyway`, and on a quit sent from outside (gone in 0.4 s).
  **Next: M40-T5 — see the entry above this one.**
  **Needs Franco:** delete *ScreenRec test 10 (cancelled on purpose)* and the nine other
  `ScreenRec test …` videos in Studio; say whether the test-10 entry went by itself; click an
  *Uploaded to YouTube* notice once to see the video open; the audience question (T1).
  ⚠️ **Test uploads on 2026-11-17: two landed, one cancelled.** He was on a Zoom call from
  ~11:00: ask before any desktop driving.

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
