import Foundation
import Testing
@testable import AppCore

/// M16-T5. The meter's scale is set by the levels measured in M16-T4 (docs/07): the load-bearing
/// assertion is that **real room tone lights nothing**, because "no bars" has to mean "nothing is
/// reaching this microphone" or the meter is decoration.
@Suite struct MicrophoneLevelTests {

    private func amplitude(dBFS: Float) -> Float { pow(10, dBFS / 20) }

    @Test(arguments: [Float(-78.9), -65.5, -52.9, -45.5, -42.7, -36])
    func measuredRoomToneLightsNothing(dBFS: Float) {
        // -78.9/-65.5 AirPods (quietest/median), -45.5/-42.7 the built-in — all in a quiet room.
        #expect(MicrophoneLevel.bars(forPeak: amplitude(dBFS: dBFS)) == 0)
    }

    @Test func silenceAndSubZeroAreZeroBars() {
        #expect(MicrophoneLevel.bars(forPeak: 0) == 0)
        #expect(MicrophoneLevel.bars(forPeak: -1) == 0)     // a peak is never negative; be total
    }

    @Test func theScaleRisesWithLevel() {
        #expect(MicrophoneLevel.bars(forPeak: amplitude(dBFS: -30)) == 1)   // quiet speech
        #expect(MicrophoneLevel.bars(forPeak: amplitude(dBFS: -18)) == 2)   // normal speech
        #expect(MicrophoneLevel.bars(forPeak: amplitude(dBFS: -6)) == 3)    // loud, close
        #expect(MicrophoneLevel.bars(forPeak: 1) == 3)                      // full scale clamps
    }

    @Test func eachThresholdIsItsOwnBoundary() {
        for (index, threshold) in MicrophoneLevel.barThresholdsDBFS.enumerated() {
            let expected = MicrophoneLevel.barCount - index
            #expect(MicrophoneLevel.bars(forPeak: amplitude(dBFS: threshold)) == expected)
            #expect(MicrophoneLevel.bars(forPeak: amplitude(dBFS: threshold - 0.1)) < expected)
        }
    }

    @Test func thresholdsSitAboveEveryMeasuredRoomTone() {
        // The invariant the whole scale rests on: the first bar must be louder than the loudest
        // quiet-room reading measured (-42.7 dBFS, the built-in mic).
        let firstBar = MicrophoneLevel.barThresholdsDBFS.last ?? 0
        #expect(firstBar > -42.7)
        let descending = MicrophoneLevel.barThresholdsDBFS.sorted().reversed()
        #expect(MicrophoneLevel.barThresholdsDBFS == Array(descending))
    }
}

/// When the label draws the meter at all (M16-T5): a stream with a mic has to exist, so an idle
/// app or a `None` mic shows nothing rather than three dead bars.
@MainActor
@Suite struct MicrophoneLevelVisibilityTests {
    private func makeState() -> AppState {
        AppState(defaults: UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!)
    }

    @Test func armedWithAMicShowsIt() {
        let state = makeState()
        state.microphonePreference = .automatic
        state.isReplayArmed = true
        #expect(state.showsMicrophoneLevel)
    }

    @Test func nothingToMeterMeansNoMeter() {
        let state = makeState()
        state.microphonePreference = .automatic
        #expect(!state.showsMicrophoneLevel)          // idle: no stream, so no level

        state.isReplayArmed = true
        state.microphonePreference = .none
        #expect(!state.showsMicrophoneLevel)          // armed, but nothing is being captured

        state.microphonePreference = .automatic
        state.showsMenuBarLevel = false
        #expect(!state.showsMicrophoneLevel)          // opted out
    }
}
