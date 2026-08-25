import SwiftUI
import AVFoundation
import UIKit

/// A video view that uses the shared PlayerManager's AVPlayerLayer.
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

/// Custom UIView that holds the shared AVPlayerLayer.
class PlayerContainerView: UIView {
    weak var playerManager: PlayerManager?

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
        playerManager?.playerLayer?.frame = bounds
    }

    func attachLayer() {
        guard let layer = playerManager?.playerLayer else { return }
        if layer.superlayer != self.layer {
            layer.removeFromSuperlayer()
            layer.frame = bounds
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
        }
    }
}
