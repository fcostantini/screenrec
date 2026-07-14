import Testing
@testable import RecorderCore

@Suite struct SleepGuardTests {
    @Test func beginAndEndToggleActiveIdempotently() {
        let sleepGuard = SleepGuard()
        #expect(!sleepGuard.isActive)

        sleepGuard.begin(reason: "test")
        #expect(sleepGuard.isActive)

        sleepGuard.begin(reason: "test")  // second begin is a no-op
        #expect(sleepGuard.isActive)

        sleepGuard.end()
        #expect(!sleepGuard.isActive)

        sleepGuard.end()  // second end is a no-op
        #expect(!sleepGuard.isActive)
    }
}
