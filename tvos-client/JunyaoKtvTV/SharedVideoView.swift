import SwiftUI
import AVFoundation
import UIKit

/// A video view that uses the shared PlayerManager's AVPlayerLayer.
/// Uses a custom UIView subclass that properly manages layer frame on layout changes.
struct SharedVideoView: UIViewRepresentable {
    let playerManager: PlayerManager

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerManager = playerManager
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerManager = playerManager
        uiView.attachLayer()
    }
}

/// Custom UIView that holds the shared AVPlayerLayer and updates its frame on layout.
class PlayerContainerView: UIView {
    weak var playerManager: PlayerManager? {
        didSet { attachLayer() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        clipsToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update player layer frame whenever view bounds change
        if let layer = playerManager?.playerLayer {
            layer.frame = bounds
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Re-attach when view moves to a new window (e.g., returning from fullscreen)
        if window != nil {
            attachLayer()
        }
    }

    func attachLayer() {
        guard let playerManager = playerManager,
              let layer = playerManager.playerLayer else { return }

        // Always re-attach to ensure layer is on this view
        if layer.superlayer != self.layer {
            layer.removeFromSuperlayer()
            layer.frame = bounds
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
        } else {
            // Already attached, just update frame
            layer.frame = bounds
        }
        self.layer.masksToBounds = true
    }
}
