import Testing
@testable import RecorderCore

@Suite struct AudioInputDeviceTests {

    // The HAL provides UIDs; `select` keeps only those `AVCaptureDevice` resolves (a name), so a
    // device the recorder can't bind never reaches the picker. `phantom` sits on the unresolvable
    // side of that flag.
    private let uids = ["builtin", "airpods", "phantom"]
    private func resolveName(_ uid: String) -> String? {
        switch uid {
        case "builtin": return "MacBook Pro Microphone"
        case "airpods": return "AirPods Pro"
        default: return nil   // HAL listed it, but AVCaptureDevice can't resolve it
        }
    }

    @Test func dropsUnresolvableDevicesKeepingOrder() {
        let devices = AudioInputs.select(uniqueIDs: uids, defaultUID: "builtin", resolveName: resolveName)
        #expect(devices.map(\.uniqueID) == ["builtin", "airpods"])  // phantom dropped, order held
    }

    @Test func carriesResolvedName() {
        let device = AudioInputs.select(
            uniqueIDs: uids, defaultUID: "builtin", resolveName: resolveName).first
        #expect(device == AudioInputDevice(
            uniqueID: "builtin", name: "MacBook Pro Microphone", isDefault: true))
    }

    @Test func marksTheDefaultExactlyOnce() {
        let devices = AudioInputs.select(uniqueIDs: uids, defaultUID: "airpods", resolveName: resolveName)
        #expect(devices.filter(\.isDefault).map(\.uniqueID) == ["airpods"])
    }

    @Test func noDefaultWhenUnset() {
        let devices = AudioInputs.select(uniqueIDs: uids, defaultUID: nil, resolveName: resolveName)
        #expect(devices.allSatisfy { !$0.isDefault })
    }

    @Test func noDefaultWhenTheDefaultIsNotListed() {
        // The default UID vanished between the device read and the default read, or names a
        // device the resolver dropped — nothing is marked, rather than a phantom default.
        let devices = AudioInputs.select(uniqueIDs: uids, defaultUID: "ghost", resolveName: resolveName)
        #expect(devices.allSatisfy { !$0.isDefault })
    }
}
