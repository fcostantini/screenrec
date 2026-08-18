import AppCore
import AppKit
import RecorderCore

/// The status item's menu (docs/06 "Menu — idle state" / "Menu — recording state").
///
/// Rebuilt from scratch on each open, which is when its state is refreshed. Rows are stamped and
/// never tick: a rebuild under an open menu garbles hover (M6-T10).
@MainActor
struct MenuBuilder {
    let state: AppState
    let windows: WindowPresenter
    let thumbnails: MenuThumbnails

    func rows() -> [NSMenuItem] {
        var items = state.session.isActive ? recordingItems() : idleItems()

        items.append(MenuRow.separator())
        // Only when there is something to say (M32-T3, ADR-020). Opens the Releases page rather than
        // downloading anything — the manual path ADR-014 documents. Read off state the launch check
        // left behind: the menu is stamped at open and must not wait on a network (M6-T10).
        if let update = MenuHeader.updateAvailable(state.availableUpdate) {
            items.append(MenuRow.link(update, url: UpdateCheck.releasesPageURL))
        }
        // docs/06 item 12: present in both menus. Settings are read at the next Start, so changing
        // them mid-recording is harmless. ⌘, is bound on the row as well as in the app menu, because
        // the app menu exists only while a window is open (ADR-023).
        let settings = MenuRow.action("Settings…") { windows.show(.settings) }
        settings.keyEquivalent = ","
        items.append(settings)
        let quit = MenuRow.action("Quit") { QuitFlow.run(state) }
        quit.keyEquivalent = "q"
        items.append(quit)
        return items
    }

    // MARK: - Idle (docs/06 items 1–10)

    private func idleItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // Always actionable, never inert: notifications never block, so `needsOnboarding` goes
        // false and a user who dismissed that prompt would have no route back to the setup window.
        items.append(MenuRow.action("ScreenRec — \(MenuHeader.idleStatus(state.readiness))") {
            windows.show(.onboarding)
        })
        items.append(MenuRow.separator())

        // docs/06 (M12-T3): Start is the first actionable row — the receipts sit below it, never
        // squatting above the primary action.
        items.append(MenuRow.action(
            "Start Recording", hotkey: state.recordHotkey, enabled: state.readiness == .ready
        ) { Task { await state.start() } })
        // A start that fails before a session exists lands back here, so the reason has to render
        // in the idle menu too, or Start looks like a no-op.
        if let failure = state.lastFailure { items.append(MenuRow.label(failure)) }
        items += replayControls()

        items.append(MenuRow.separator())
        items += receiptRows()

        items.append(sourceRow())
        // docs/06 item 5 (M21-T4): the exclusion takes the picture as well as the sound, and nobody
        // should discover that by watching the file.
        if let excluded = state.excludedAppName {
            items.append(MenuRow.label("\(excluded) won't be seen or heard"))
        }
        // The other half of that sentence (M27-T3); `mutedAppName` is nil when the exclusion above
        // already covers the app, so the stronger line stands alone.
        if let muted = state.mutedAppName {
            items.append(MenuRow.label("\(muted) will be seen but not heard"))
            // A tap carries apps SCK's own capture omits, so a muted take can hold *more* sound.
            items.append(MenuRow.label("Sound from apps with no window is captured too"))
        }

        items.append(microphoneRow())
        // ADR-019: the other half of the audio picture, beside the mic it pairs with.
        items.append(MenuRow.check("Capture System Audio", on: state.capturesSystemAudio) {
            state.capturesSystemAudio.toggle()
        })
        if let warning = state.silentRecordingWarning { items.append(MenuRow.label(warning)) }

        items.append(qualityRow())
        items.append(stopAfterRow())
        // Only when it is news: on a healthy disk this says nothing at all (M18-T4).
        if let room = RecordingRoom.phrase(
            seconds: state.recordingRoomSeconds, presetName: state.quality.menuTitle) {
            items.append(MenuRow.label(room))
        }

        items.append(MenuRow.separator())
        items.append(recordingsRow())
        return items
    }

    // MARK: - Recording / paused (docs/06 items 1–9)

    private func recordingItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        items.append(MenuRow.label(
            "\(Timecode.clock(state.session.elapsedSeconds)) — "
                + MenuHeader.recordingDetail(bytes: state.session.recordedBytes)))
        items.append(MenuRow.separator())
        items += receiptRows()

        // Pause/Resume advertise the opt-in pause shortcut (M12-T6), Stop the start/stop one.
        if state.session.isPaused {
            items.append(MenuRow.action("Resume", hotkey: state.pauseHotkey) {
                Task { await state.resume() }
            })
        } else {
            items.append(MenuRow.action("Pause", hotkey: state.pauseHotkey) {
                Task { await state.pause() }
            })
        }
        // The combo sits on whichever ending it actually has (M24-T2).
        items.append(MenuRow.action("Stop & Save", hotkey: state.stopAndSaveHotkey) {
            Task { await state.stop() }
        })
        items.append(MenuRow.action(state.stopAndCopyTitle, hotkey: state.stopAndCopyHotkey) {
            Task { await state.stopAndShare() }
        })

        items.append(MenuRow.separator())

        if let failure = state.lastFailure {
            items.append(MenuRow.label(failure))
        } else {
            // docs/06 recording item 5: a scoped recording names its subject.
            if let app = state.session.activeAppName {
                items.append(MenuRow.label("Recording \(app) only"))
            }
            if let region = state.session.activeRegion {
                items.append(MenuRow.label("Recording region \(SourcesModel.regionLabel(region))"))
            }
            if let microphone = state.session.activeMicrophoneName {
                items.append(MenuRow.label("\(microphone) · separate track"))
            }
        }

        items += replayControls()
        // The bound this take runs under, as an absolute time: a countdown would have to tick.
        if let stopsAt = state.stopsAt { items.append(MenuRow.label(MenuHeader.stopsAt(stopsAt))) }
        // docs/06: the pickers are hidden while recording, not disabled — this row says why.
        items.append(MenuRow.label("Sources locked while recording"))

        items.append(MenuRow.separator())
        // docs/06 recording item 9: subordinate to Stop & Save and set apart from it — the one
        // irreversible action must not sit under Stop's muscle memory.
        items.append(MenuRow.destructive("Discard Recording…") { discardRecording() })
        return items
    }

    // MARK: - Shared groups

    /// Arm toggle + save row, shared by both menus (docs/06 idle item 3 / recording item 5). The
    /// readiness gate also guards a permission revoked mid-recording.
    private func replayControls() -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            MenuRow.check(
                "Arm Instant Replay", on: state.isReplayArmed,
                enabled: state.readiness == .ready || state.isReplayArmed
            ) { state.isReplayArmed.toggle() }
        ]
        guard state.isReplayArmed else { return items }
        // What arming costs (M16-T2): the ring's memory, and ADR-018's deliberate wakefulness.
        items.append(MenuRow.label(state.replayBufferMenuLabel))
        // docs/06 §Notifications: macOS hides banners while the screen is captured, unless the user
        // allowed them when sharing. M35-T1 reads that setting, so this states the fact when it can
        // and stays silent when there is nothing to warn about; "may" survives only for a failed read.
        switch state.bannerVisibility() {
        case .hidden: items.append(MenuRow.label("Notification banners are hidden while armed"))
        case .unknown: items.append(MenuRow.label("Notification banners may be hidden while armed"))
        case .shown: break
        }
        items.append(MenuRow.action("Save Replay Now", hotkey: state.replayHotkey) {
            state.saveReplay()
        })
        return items
    }

    /// The take that just stopped (M24-T3), the export's progress or receipt (M10-T2/M12-T1), and
    /// the replay receipt (M9-T2) — each with its own trailing separator, present only when it is.
    private func receiptRows() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let last = state.lastRecording {
            items.append(MenuRow.submenu(last.menuTitle, fileActions(last.url)))
            items.append(MenuRow.separator())
        }
        if let name = state.exports.exportInProgress {
            let fraction = state.exports.exportProgress
            let row = MenuRow.label(
                MenuHeader.exporting(
                    name, fraction: fraction, waiting: state.exports.queuedExportCount))
            // Only the path that can report gets a bar; GIF and trim say what they are doing and
            // nothing they cannot know (M28-T4).
            if let fraction { row.view = ExportProgressRowView(fraction: fraction) }
            items.append(row)
            items.append(MenuRow.separator())
        } else if let last = state.exports.lastExport {
            items.append(MenuRow.submenu(last.menuTitle, fileActions(last.url)))
            items.append(MenuRow.separator())
        }
        if let last = state.lastReplay {
            items.append(MenuRow.submenu(last.menuTitle, fileActions(last.url)))
            items.append(MenuRow.separator())
        }
        return items
    }

    // MARK: - Source (docs/06 item 5)

    /// All three capture modes are entered from this one submenu (M12-T4). Screens above the
    /// divider, running apps below; a picked app that isn't running stays listed and checkmarked
    /// (its Start fails loud instead). The title carries the current pick (M12-T3).
    private func sourceRow() -> NSMenuItem {
        var items: [NSMenuItem] = [MenuRow.separator()]
        for screen in state.sources.displays {
            let title = state.sources.displays.count == 1
                ? "Entire Screen" : "Entire Screen (\(screen.name))"
            items.append(pick(title, .display(screen.id)))
        }
        items.append(MenuRow.separator())
        for app in state.sources.capturableApps {
            items.append(pick(app.name, .app(bundleID: app.bundleID)))
        }
        if let missing = state.sources.missingPickedApp {
            let row = pick("\(missing.name) (not running)", .app(bundleID: missing.bundleID))
            row.isEnabled = false
            items.append(row)
        }
        // The current region as a checkmarked, re-selectable row (M11-T2); redraw via Select Region…
        if let region = state.sources.selectedRegion {
            items.append(MenuRow.separator())
            items.append(pick(
                "Region \(SourcesModel.regionLabel(region.rect.size))",
                .region(display: region.displayID, rect: region.rect)))
        }

        items.append(MenuRow.separator())
        items.append(windowRow())
        items.append(everythingExceptRow())
        items.append(muteRow())
        // Opens the drag-to-select overlay (M11-T2) — an action, not a pick.
        items.append(MenuRow.action("Select Region…") { state.beginRegionSelection?() })

        return MenuRow.submenu("Source: \(state.sources.sourceMenuLabel)", items)
    }

    /// Windows nest one level down (M17-T2): there are routinely a dozen or more, and Source is
    /// already the longest submenu.
    private func windowRow() -> NSMenuItem {
        var items: [NSMenuItem] = [MenuRow.separator()]
        for window in state.sources.capturableWindows {
            items.append(pick(
                WindowSelection.label(appName: window.appName, title: window.title),
                .window(WindowSelection(id: window.id, bundleID: window.bundleID))))
        }
        // A picked window that is gone stays listed and checkmarked — the pick survives absence.
        if let missing = state.sources.missingPickedWindow {
            items.append(pick(
                WindowSelection.goneLabel(appName: state.sources.appName(for: missing.bundleID)),
                .window(missing)))
        }
        items.append(MenuRow.separator())
        return MenuRow.submenu("Window", items)
    }

    /// The whole screen minus one app (M21-T4). "Nothing" is how the exclusion is undone without
    /// leaving the submenu.
    private func everythingExceptRow() -> NSMenuItem {
        var items: [NSMenuItem] = [
            MenuRow.separator(),
            pick("Nothing", .display(state.sources.selectedDisplayID)),
            MenuRow.separator(),
        ]
        for app in state.sources.capturableApps {
            items.append(pick(app.name, .displayExcluding(bundleID: app.bundleID)))
        }
        // A picked app with nothing on screen can't be excluded at capture — the pick stays, and
        // the start says what didn't happen.
        if let missing = state.sources.missingExcludedApp {
            items.append(pick(
                "\(missing.name) (not on screen)", .displayExcluding(bundleID: missing.bundleID)))
        }
        items.append(MenuRow.separator())
        return MenuRow.submenu("Everything Except", items)
    }

    /// Heard no more, while its windows stay in frame (M27-T3). A separate list from Everything
    /// Except: only apps the audio system knows can be silenced at all (docs/07).
    private func muteRow() -> NSMenuItem {
        let silenceable = state.sources.silenceableApps()
        guard !silenceable.isEmpty else {
            return MenuRow.submenu("Mute", [MenuRow.label("Nothing is playing")])
        }
        var items: [NSMenuItem] = [
            MenuRow.action("Nothing") { state.sources.mutedAppBundleID = nil },
            MenuRow.separator(),
        ]
        for app in silenceable {
            items.append(MenuRow.check(
                app.name, on: state.sources.mutedAppBundleID == app.bundleID
            ) { state.sources.mutedAppBundleID = app.bundleID })
        }
        return MenuRow.submenu("Mute", items)
    }

    /// A Source row: checkmarked when it is the current pick, and choosing it makes it so.
    private func pick(_ title: String, _ choice: SourceChoice) -> NSMenuItem {
        MenuRow.check(title, on: state.sources.sourceChoice == choice) {
            state.sources.sourceChoice = choice
        }
    }

    // MARK: - The other pickers

    /// Reads through `presentMicrophonePreference`: the checkmark sits on None while a picked
    /// device is away, without forgetting the pick (docs/06 item 6).
    private func microphoneRow() -> NSMenuItem {
        let current = state.presentMicrophonePreference
        var items = [
            MenuRow.check("None", on: current == .none) { state.microphonePreference = .none },
            MenuRow.check("Automatic (System Default)", on: current == .automatic) {
                state.microphonePreference = .automatic
            },
            MenuRow.separator(),
        ]
        for device in state.microphones {
            items.append(MenuRow.check(
                device.name, on: current == .device(id: device.uniqueID)
            ) { state.microphonePreference = .device(id: device.uniqueID) })
        }
        return MenuRow.submenu("Microphone: \(state.microphoneMenuLabel)", items)
    }

    private func qualityRow() -> NSMenuItem {
        let items = QualityPreset.allCases.map { preset in
            MenuRow.check(preset.menuTitle, on: state.quality == preset) { state.quality = preset }
        }
        return MenuRow.submenu("Quality: \(state.quality.menuTitle)", items)
    }

    /// A bound for the next take (M18-T4): unattended captures, and a ceiling on the all-day
    /// recording nobody stopped.
    private func stopAfterRow() -> NSMenuItem {
        let items = Settings.allowedStopAfterMinutes.map { minutes in
            MenuRow.check(MenuHeader.stopAfter(minutes), on: state.stopAfterMinutes == minutes) {
                state.stopAfterMinutes = minutes
            }
        }
        return MenuRow.submenu("Stop After: \(MenuHeader.stopAfter(state.stopAfterMinutes))", items)
    }

    // MARK: - Files (docs/06 items 9–10)

    /// The whole file browser, one level down (M18-T3).
    private func recordingsRow() -> NSMenuItem {
        var items = [
            MenuRow.action("Open Folder — \(MenuHeader.recordingsFolder(state.outputDirectory))") {
                Finder.open(state.outputDirectory)
            }
        ]
        // Under the day each was made (M28-T5): ten near-identical timestamps are a wall without it.
        if !state.recentRecordings.isEmpty {
            items.append(MenuRow.separator())
            for group in RecentRecordings.grouped(
                state.recentRecordings, dates: state.recentRecordingDates, now: Date()) {
                if !group.label.isEmpty { items.append(MenuRow.label(group.label)) }
                items += fileRows(group.urls)
            }
        }
        // Recent Exports (M12-T2): derived files get their own group, and a smaller cap, so they
        // don't crowd out the recordings. No day headers — over five files they read as noise.
        if !state.recentExports.isEmpty {
            items.append(MenuRow.separator())
            items.append(MenuRow.label("Recent Exports"))
            items += fileRows(state.recentExports)
        }
        return MenuRow.submenu("Recordings", items)
    }

    /// Each row keeps its `title` — that is what leaves it identical to a plain row under
    /// `menudriver` — and gains a view carrying the frame (M28-T3).
    private func fileRows(_ urls: [URL]) -> [NSMenuItem] {
        urls.map { url in
            let title = state.rowTitle(for: url)
            let item = MenuRow.submenu(title, fileActions(url))
            item.view = RecentRowView(
                url: url, title: title, thumbnail: thumbnails.image(for: url))
            return item
        }
    }

    /// The per-file submenu shared by recents and every receipt: act on this file (M12-T1), then
    /// derive a new one — and only the derives this file can actually take (M24-T5).
    private func fileActions(_ url: URL) -> [NSMenuItem] {
        var items = [
            fileAction("Reveal in Finder", url, Finder.reveal),
            fileAction("Quick Look", url, ShareActions.quickLook),
            fileAction("Share…", url, ShareActions.share),
            fileAction("Copy", url, ShareActions.copy),
        ]

        let derives = DeriveOptions(for: url)
        if derives.hasAny {
            items.append(MenuRow.separator())
            if derives.canExportToMP4 {
                items.append(fileAction("Export as MP4", url) { state.exportToMP4($0) })
            }
            if derives.canSaveAsGIF {
                items.append(fileAction("Save as GIF", url) { state.exportToGIF($0) })
            }
            if derives.canTrim {
                items.append(fileAction("Trim…", url) { url in
                    state.exports.trimTarget = url
                    windows.show(.trim)
                })
            }
        }

        items.append(MenuRow.separator())
        // Trash is reversible, so no confirmation; red, because it is the destructive one.
        items.append(fileAction("Rename…", url) { url in
            ShareActions.rename(url) { state.rename(url, to: $0) }
        })
        items.append(MenuRow.destructive("Move to Trash") {
            guard state.fileStillExists(url) else { return }
            state.moveToTrash(url)
        })
        return items
    }

    /// A row action that first checks the file is still there; if it isn't, the state layer says so
    /// and refreshes the rows (M18-T4). Every file action is built through this, so one that
    /// forgets to check can't be written — rows are stamped at open, so the race is normal.
    private func fileAction(
        _ title: String, _ url: URL, enabled: Bool = true, _ act: @escaping (URL) -> Void
    ) -> NSMenuItem {
        MenuRow.action(title, enabled: enabled) {
            guard state.fileStillExists(url) else { return }
            act(url)
        }
    }

    // MARK: - Confirmations

    /// docs/06 recording item 9: discarding confirms first — the safe choice is the default, so a
    /// reflexive Return can't destroy a take — then drops the file and returns to Ready.
    private func discardRecording() {
        guard state.session.isActive else { return }
        guard !ConfirmAlert.ask(
            "Discard this recording?", "This take will be deleted and can't be recovered.",
            first: "Keep Recording", second: "Discard", secondIsDestructive: true)
        else { return }
        Task { await state.discard() }
    }
}

extension QualityPreset {
    /// docs/06 item 7 names these Efficient / Balanced / High; the raw values are the CLI's.
    var menuTitle: String {
        switch self {
        case .efficient: "Efficient"
        case .balanced: "Balanced"
        case .high: "High"
        }
    }
}
