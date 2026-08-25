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
        uiView.attachLayerIfNeeded()
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.detachLayer()
    }
}

/// Custom UIView that holds the shared AVPlayerLayer and updates its frame on layout.
class PlayerContainerView: UIView {
    weak var playerManager: PlayerManager?
    private var isLayerAttached = false

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update player layer frame whenever view bounds change
        if let layer = playerManager?.playerLayer {
            layer.frame = bounds
        }
    }

    func attachLayerIfNeeded() {
        guard let playerManager = playerManager,
              let layer = playerManager.playerLayer,
              !isLayerAttached else { return }

        layer.removeFromSuperlayer()
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.layer.masksToBounds = true
        isLayerAttached = true
    }

    func detachLayer() {
        playerManager?.playerLayer?.removeFromSuperlayer()
        isLayerAttached = false
    }
}
