import Foundation
import Testing
@testable import RecorderCore

/// The rescue's pure rebind decision (docs/03 M8-T2: honor the pick) and the watchdog's
/// re-arm cycle; the stream mechanics are the live legs' job.
@Suite struct MicrophoneRescueTests {

    private static let airPods = AudioInputDevice(uniqueID: "airpods-uid", name: "AirPods Pro", isDefault: false)
    private static let builtIn = AudioInputDevice(uniqueID: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone", isDefault: true)

    @Test func aSpecificPickWaitsForItsOwnDevice() {
        // Only the built-in present: a `.sameDevice` pick must NOT substitute it.
        #expect(MicrophoneRescue.rebindTarget(
            policy: .sameDevice, lostDeviceID: "airpods-uid", devices: [Self.builtIn]) == nil)
    }

    @Test func aSpecificPickRebindsWhenItReturns() {
        #expect(MicrophoneRescue.rebindTarget(
            policy: .sameDevice, lostDeviceID: "airpods-uid",
            devices: [Self.builtIn, Self.airPods]) == "airpods-uid")
    }

    @Test func automaticFollowsTheCurrentDefault() {
        // The AirPods stay cased; Automatic recovers onto whatever is default NOW.
        #expect(MicrophoneRescue.rebindTarget(
            policy: .systemDefault, lostDeviceID: "airpods-uid",
            devices: [Self.builtIn]) == "BuiltInMicrophoneDevice")
    }

    @Test func noDevicesMeansKeepWaiting() {
        #expect(MicrophoneRescue.rebindTarget(
            policy: .systemDefault, lostDeviceID: "airpods-uid", devices: []) == nil)
        #expect(MicrophoneRescue.rebindTarget(
            policy: .sameDevice, lostDeviceID: "airpods-uid", devices: []) == nil)
    }

}
