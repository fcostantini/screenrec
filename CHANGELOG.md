# Changelog

What changed in each release, written for the people who use ScreenRec. Newest first.
`Scripts/release.sh` publishes the section matching `VERSION` as the release's notes, so this is the
one file in the repo whose audience is not us.

Only versions published as releases appear here; several were tagged during development and never
published. The commit history is in the repository, where it belongs.

## 1.23.1

**A Quick Look preview can't get lost behind another app any more.** While a preview is open,
ScreenRec is in the Dock and in ⌘-Tab, as it is for Settings and Trim, so you can switch away and
come back to the video. Before, the preview dropped behind the other app's windows and nothing led
back to it.

**About ScreenRec stays reachable too.** Closing the last window under it used to leave it on screen
with no Dock icon.

**Select, copy, paste and undo work wherever you type a name.** ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z and ⇧⌘Z now
work in **Rename…**, in the naming prompt after a recording, and in the YouTube upload sheet when no
ScreenRec window is open. They used to do nothing there.

## 1.23.0

**A trimmed clip can go straight to YouTube.** The Trim window has a new button, **Upload to
YouTube…**, and so does every exported `.mp4` in the menu. It asks for a title, a description and who
can watch — unlisted unless you choose otherwise — then exports the range, uploads it, and leaves the
link on the clipboard, so the next keystroke is ⌘V. If you copied something else while it was
uploading, your clipboard is left alone and the link waits in the menu under **Copy Link**.

**Connect once, in Settings › Sharing.** Your browser opens on Google's sign-in. Google will warn that
it hasn't verified ScreenRec — expected for a personal tool that hasn't been through Google's review —
and you continue past it. **Disconnect** in the same place withdraws the sign-in.

**You can watch it go, and stop it.** The menu shows the export and then the upload with a
percentage, and **Cancel Upload** stops it. Quitting while one is under way asks first.

**A failed upload says why, and can be finished.** A dropped connection is waited out for five
minutes before ScreenRec gives up. When it does, the notice says what happened in plain words and what
to do next, and the menu keeps a **Couldn't upload** row for a day with **Try Again**, which picks the
same upload up where it stopped instead of starting a second one.

**What it can't do, on purpose.** ScreenRec asks Google for one permission: adding videos. It cannot
see, edit or delete anything on your channel. That also means an upload you cancel, or one that fails
for good, can leave an unfinished entry that only you can remove, in YouTube Studio — ScreenRec tells
you each time. Nothing is uploaded unless you press the button, one clip at a time, and only that clip
and what you typed go to Google. The README's *What ScreenRec sends* has the whole list.

## 1.22.0

**Audio from the Trim window lands on the clipboard.** The Trim window's audio button is now
**Export Audio & Copy**: it writes the trimmed range's sound as an `.m4a`, as before, and also puts
the file on the clipboard, so ⌘V drops it straight into Slack, Messages or Finder — the same way
**Export & Copy** already does with video. The menu's **Export Audio** still just saves the file.

## 1.21.0

**Export just the audio.** A recording's sound can now leave on its own as an `.m4a` — the whole take
from the menu (`Export Audio`, beside `Export as MP4` and `Save as GIF`), or only the part you have
trimmed, from the Trim window. No video is read or encoded, so a five-minute, 1.2 GB take becomes a
5.6 MB file in under two seconds. It follows the same microphone setting as the MP4 export, and a take
recorded with no sound at all tells you so instead of handing back an empty file. It is AAC rather than
MP3 because macOS decodes MP3 everywhere and encodes it nowhere, and ScreenRec ships no third-party
code.

**The preview keeps playing while you move around in it.** ←/→, ⇧←/⇧→ and clicks on the filmstrip used
to stop playback dead; they leave it running now, and leave a paused clip paused. A click during
`Play Range` takes over rather than stopping later at an out-point you have already moved away from.

**The windows behave like windows.** While a ScreenRec window is open the app now appears in the Dock
and in ⌘-Tab, with a Window menu that lists what's open. Minimizing the Trim window used to put it
somewhere you couldn't get it back from — no Dock icon, no ⌘-Tab entry, nothing to click. It's in
**Window ▸** now, and ⌘C and ⌘V work in the rename box for the first time.

**The Trim window resizes, and the picture grows with it.** Drag it larger and the preview follows.
That matters most when you're drawing a crop on a wide recording, where the preview used to spend a
third of itself on black bars. The size you choose is remembered.

**Play and pause work while you're cropping.** They didn't: the crop overlay covered the player's
controls and swallowed every click, while still drawing them, so the button was there and did nothing.
The Trim window now has its own **Play / Pause** and a clock, and the player's own controls step aside
while a crop is being drawn rather than sitting there dead.

## 1.19.0

**The menu tells you how much replay you actually have.** While the buffer is still filling — which
happens every time it restarts, including after your screen has slept — the armed row now reads
`0:12 of 2 min held` instead of promising the whole window. *Save Replay Now* can no longer hand you
four seconds while the menu claims two minutes.

**A long window title no longer stretches the menu.** Picking a window whose title ran to 170
characters used to widen every row in the menu; titles are shortened to fit now.

**And the last place the app still guessed about hidden notification banners now checks.** Settings'
Instant Replay pane says whether banners will really appear, and keeps itself current if you change the
setting while it is open.

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
