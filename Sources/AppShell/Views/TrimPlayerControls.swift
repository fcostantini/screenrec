import AVKit

/// Which transport the Trim preview draws (M37-T3).
///
/// `AVPlayerView`'s own controls sit *under* the crop overlay, which takes every click inside the
/// picture — so while cropping they are not drawn at all and the window's own Play/Pause is the
/// transport. A control that is visible and ignores the click is worse than one that isn't there.
enum TrimPlayerControls {

    static func style(cropping: Bool) -> AVPlayerViewControlsStyle {
        cropping ? .none : .inline
    }
}
