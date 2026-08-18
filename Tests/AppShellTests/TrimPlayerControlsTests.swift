import AVKit
import Testing

@testable import AppShell

/// Which transport the Trim preview draws (M37-T3).
///
/// 🔴 Measured on the deployed v1.19.0 before the fix: the same click on the ▶ button played the clip
/// with the crop off (00:00 → 00:02) and moved the timeline by **nothing at all** with it on — it read
/// `20.421912393162` before and after. The overlay takes every click in the picture, and the player
/// kept drawing the controls underneath it anyway.
@Suite struct TrimPlayerControlsTests {

    @Test func croppingStopsThePlayerDrawingControlsItCannotReceive() {
        #expect(TrimPlayerControls.style(cropping: true) == .none)
    }

    @Test func withNoCropBeingDrawnTheInlineTransportIsBack() {
        #expect(TrimPlayerControls.style(cropping: false) == .inline)
    }
}
