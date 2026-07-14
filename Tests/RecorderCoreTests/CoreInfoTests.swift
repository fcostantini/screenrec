import Testing
@testable import RecorderCore

@Test func versionIsSemver() {
    let parts = CoreInfo.version.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
