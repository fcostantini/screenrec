import AppCore
import AppKit
import RecorderCore

/// The status item and the menu hanging off it (docs/06 "Status item" / "Menu").
///
/// The icon is redrawn by timers, not by bindings: the pulse, the elapsed clock and the input meter
/// each have their own cadence, and `withObservationTracking` covers everything else that changes
/// it. All three run in `.common` mode — menu tracking runs its own run-loop mode, and a timer in
/// the default mode stops while the menu is open.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    /// Slow enough to read as breathing rather than as an alert (M4-T1, settled by taste).
    private static let pulseCycle: TimeInterval = 2
    private static let pulseFramesPerCycle: Double = 12
    /// The meter's poll: never per sample, which is the M6-T10 rule that also froze the in-menu
    /// clock. Writes only when the bar count changes, so a silent room costs no redraws.
    private static let meterFramesPerSecond: Double = 8

    private let state: AppState
    private let windows: WindowPresenter
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = MenuRow.menu()
    private let thumbnails = MenuThumbnails()

    /// The only timer that is started and stopped; the other two run for the app's life, and the
    /// run loop owns them.
    private var pulseTimer: Timer?
    private var pulsePhase = 0.0
    private var levelBars = 0
    private var menuIsOpen = false
    private var observingProgress = false

    init(state: AppState, windows: WindowPresenter) {
        self.state = state
        self.windows = windows
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityRole(.menuButton)
        // A frame that lands while the menu is open fills its own row in; only the view redraws,
        // so the menu is not rebuilt under the cursor (M6-T10, docs/07).
        thumbnails.onThumbnail = { [weak self] url in self?.showThumbnail(for: url) }

        repeating(every: 1, tolerance: 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.tickClock() }
        }
        repeating(every: 1 / Self.meterFramesPerSecond, tolerance: 0.02) { [weak self] in
            MainActor.assumeIsolated { self?.readMicrophoneLevel() }
        }
        observeIcon()
    }

    // MARK: - Menu

    /// Re-reads sources/recents/progress, then rebuilds every row. Rows are stamped here and hold
    /// while the menu is up (M6-T10).
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuData()
        menu.removeAllItems()
        let builder = MenuBuilder(state: state, windows: windows, thumbnails: thumbnails)
        for item in builder.rows() { menu.addItem(item) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        observeExportProgress()
    }

    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    /// Advances the export row in place while the menu is up — nothing else in the menu ticks
    /// (M28-T4).
    ///
    /// At most one registration exists at a time: tracking is one-shot and only *re-arms* while the
    /// menu is open, so without the flag every open would stack another one that outlives it.
    private func observeExportProgress() {
        guard StatusItemPolicy.registersObservation(
            menuIsOpen: menuIsOpen, alreadyObserving: observingProgress) else { return }
        observingProgress = true
        withObservationTracking {
            _ = state.exports.exportProgress
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observingProgress = false
                self.advanceExportRow()
                self.observeExportProgress()
            }
        }
    }

    private func advanceExportRow() {
        guard let fraction = state.exports.exportProgress,
              let name = state.exports.exportInProgress,
              let row = menu.items.first(where: { $0.view is ExportProgressRowView })
        else { return }
        // The title as well as the bar: it is what VoiceOver reads.
        row.title = MenuHeader.exporting(name, fraction: fraction)
        (row.view as? ExportProgressRowView)?.show(fraction)
    }

    /// Hands a just-decoded frame to the row showing that file, wherever it currently sits.
    private func showThumbnail(for url: URL) {
        guard let image = thumbnails.image(for: url) else { return }
        for view in Self.recentRows(in: menu) where view.url == url { view.show(image) }
    }

    private static func recentRows(in menu: NSMenu) -> [RecentRowView] {
        menu.items.flatMap { item -> [RecentRowView] in
            let here = (item.view as? RecentRowView).map { [$0] } ?? []
            return here + (item.submenu.map(recentRows(in:)) ?? [])
        }
    }

    /// Also run once at launch: the Source rows and the recents' details arrive from async reads,
    /// and a stamped menu can't wait for them — without priming, the first open after launch is the
    /// only one missing them.
    func refreshMenuData() {
        state.refreshRecentRecordings()
        state.refreshRecordingRoom()
        Task { await state.refreshRecentDetails() }
        state.exports.expireStaleReceipt()   // drop a receipt aged out since a prior session (M12-T3)
        state.expireStaleRecordingReceipt()  // …and the take receipt, on the same clock (M24-T3)
        if !state.session.isActive {
            state.refreshSources(displays: DisplayOption.liveScreens())
            // Async because SCShareableContent takes ~a second; on the first open the app rows land
            // a beat late, like the recents.
            Task { await state.refreshCapturableApps() }
            Task { await state.refreshCapturableWindows() }
        }
        state.session.refreshProgress()
        thumbnails.prime(state.recentRecordings + state.recentExports)
    }

    // MARK: - Icon

    /// Redraws on any change to the state the icon reads, and re-registers itself — observation is
    /// one-shot.
    private func observeIcon() {
        withObservationTracking {
            renderIcon()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeIcon() }
        }
    }

    private func renderIcon() {
        let icon = state.session.statusIcon
        let armed = state.isReplayArmed
        let exporting = state.exports.exportInProgress != nil
        let bars = state.showsMicrophoneLevel ? levelBars : nil

        let pulsing = StatusItemPolicy.pulses(
            icon: icon, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        syncPulseTimer(running: pulsing)

        let base = pulsing
            ? StatusIconImage.recordingImage(
                fadedTo: StatusIconImage.pulseAlpha(atPhase: pulsePhase),
                isReplayArmed: armed, isExporting: exporting, levelBars: bars)
            : StatusIconImage.image(
                for: icon, isReplayArmed: armed, isExporting: exporting, levelBars: bars)

        let button = statusItem.button
        button?.image = StatusIconImage.decorated(
            base, clock: clockText, showsSavedMark: state.replaySavedFlash)
        button?.setAccessibilityLabel(accessibilityLabel)
    }

    /// The elapsed clock drawn beside the glyph, or nil when it isn't shown. Drawn into the image
    /// rather than carried as a title, so it sits on the glyph's optical line (docs/07).
    private var clockText: String? {
        guard state.showsMenuBarTimer, let clock = state.session.recordingClock else { return nil }
        return Timecode.clock(clock.elapsed(now: Date()))
    }

    /// The whole item as one VoiceOver element: the icon state, plus elapsed time and a
    /// just-saved note when shown.
    private var accessibilityLabel: String {
        var label = StatusIconImage.label(
            for: state.session.statusIcon, isReplayArmed: state.isReplayArmed,
            isExporting: state.exports.exportInProgress != nil)
        if let clockText { label += ", " + clockText }
        if state.replaySavedFlash { label += ", saved" }
        return label
    }

    /// Advances the drawn clock, and only then: a still icon has nothing to redraw, and while the
    /// pulse runs it is already redrawing faster than this.
    private func tickClock() {
        guard StatusItemPolicy.redrawsOnClockTick(
            isPulsing: pulseTimer != nil, hasClock: clockText != nil) else { return }
        renderIcon()
    }

    private func readMicrophoneLevel() {
        guard state.showsMicrophoneLevel else { return }
        let lit = MicrophoneLevel.bars(forPeak: state.takeMicrophoneLevel())
        guard lit != levelBars else { return }
        levelBars = lit
        renderIcon()
    }

    /// Alive only while recording: the pulse is the one thing that redraws when nothing changed.
    private func syncPulseTimer(running: Bool) {
        guard running != (pulseTimer != nil) else { return }
        guard running else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulsePhase = 0
            return
        }
        pulseTimer = repeating(
            every: Self.pulseCycle / Self.pulseFramesPerCycle, tolerance: 0.05
        ) { [weak self] in
            MainActor.assumeIsolated { self?.advancePulse() }
        }
    }

    private func advancePulse() {
        pulsePhase = (pulsePhase + 1 / Self.pulseFramesPerCycle).truncatingRemainder(dividingBy: 1)
        renderIcon()
    }

    /// `.common` mode, so the tick survives menu tracking's own run-loop mode. The run loop retains
    /// the timer; only one of these needs holding onto.
    @discardableResult
    private func repeating(
        every interval: TimeInterval, tolerance: TimeInterval, _ tick: @escaping @Sendable () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in tick() }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
