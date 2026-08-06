# Changelog

What changed in each release, written for the people who use ScreenRec. Newest first.
`Scripts/release.sh` publishes the section matching `VERSION` as the release's notes, so this is the
one file in the repo whose audience is not us.

Only versions published as releases appear here; several were tagged during development and never
published. The commit history is in the repository, where it belongs.

## 1.18.0

**You can tell when a replay has been saved.** The menu bar now says **Saved** for three seconds
instead of showing a small tick. That matters more than it sounds: macOS hides notification banners
while Instant Replay is armed, so this is often the only confirmation you get.

**And ScreenRec stops guessing about those hidden banners.** It can now tell whether you've allowed
notifications while sharing the display, so the menu and the setup window say what will actually
happen rather than what might. Turn the setting on and the setup window confirms it, with no restart.

## 1.17.1

**The update notice now takes you somewhere.** When a newer version exists, clicking the row in the
menu opens the releases page — before, it named a version and left you to find it yourself.

## 1.17.0

**ScreenRec can tell you when a newer build exists.** When there is one, the menu shows its version
just above **Settings…**.

It looks once a day, and it sends nothing about you, your Mac or your recordings — it reads the list
of releases and nothing else. To stop it making any network request at all, turn off **Check for new
versions** in Settings.

Versions before 1.17.0 have no check in them, so this is the last release their holders hear about by
hand.

## 1.16.0

**Share several clips without waiting for each one.** Asking for a second export while one was
running used to be refused outright; now it waits its turn, and the menu says how many are queued.

**Leave your narration out of a shared clip.** Turn off **Include the microphone** in Settings and an
export carries the system audio only. Your voice stays in the saved recording — it just doesn't go
into the copy you share.

**Stop & Copy** always gives you a copy now, instead of skipping it when another export was already
running.

## 1.15.1

Fixes only, no new features.

- A recording that ends unexpectedly — a captured window closing, for instance — no longer leaves a
  system-audio tap running behind it. This only affected recordings made with **Mute ▸** set.
- Only one copy of ScreenRec runs at a time, so launching it again no longer leaves two icons in the
  menu bar.
- The Trim window's filmstrip could hang while its thumbnails loaded. It can't now.

## 1.15.0

**The menu was rebuilt, and it does things it couldn't before.**

- Every recording under **Recordings ▸** carries a thumbnail of what's in it.
- An export in progress shows a percentage that advances while you watch it, rather than a row that
  looks frozen.
- The last ten recordings are grouped under the day they were made — Today, Yesterday, then the
  weekday or the date.

## 1.12.0

**The share loop is finished.**

- **Export & Copy** (⌘↩) writes the trimmed clip and puts it on the clipboard in one step.
- The start/stop shortcut can stop a recording and copy a shareable clip in a single press.
- The Trim window has a player, so you can find the moment instead of scrubbing blind.
- Trimming an `.mp4` gives you an `.mp4`. It used to hand back a `.mov`.
- A saved replay gets its own row in the menu, and files that no longer exist stop being offered.

## 1.11.0

**One step from "it happened" to "here it is."**

- **Stop & Copy MP4** stops the recording and puts a shareable clip on the clipboard.
- **Source ▸ Everything Except ▸** records the screen with one app left out — out of the picture and
  out of the sound.
- **Export as MP4** in the Trim window writes the trimmed clip itself.
- Name a take the moment it stops, if you want to: Settings → Recording, off by default.

## 1.10.2

No user-facing changes — internal restructuring only.

## 1.10.1

Fixes only.

- The low-disk guard can see a disk actually filling, so a long recording is stopped safely instead
  of running until the write fails.
- MP4 size options are named by what they're for rather than by their pixel count.
- A window you picked to record is remembered by identity, so renaming it — or having a second window
  with the same title — no longer records the wrong one.
