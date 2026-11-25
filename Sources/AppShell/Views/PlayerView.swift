import AVKit
import SwiftUI

/// AppKit's concrete `AVPlayerView`, wrapped — SwiftUI's generic `VideoPlayer` fatal-errors
/// instantiating its metadata in a Command-Line-Tools (no-Xcode) SPM build.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let controlsStyle: AVPlayerViewControlsStyle

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = controlsStyle
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        if view.controlsStyle != controlsStyle { view.controlsStyle = controlsStyle }
    }
}
