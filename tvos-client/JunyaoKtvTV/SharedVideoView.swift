import SwiftUI
import AVFoundation
import UIKit

/// A video view that hosts the shared PlayerManager's playerContainerView.
struct SharedVideoView: UIViewRepresentable {
    let playerManager: PlayerManager

    func makeUIView(context: Context) -> VideoHostView {
        let view = VideoHostView()
        view.playerManager = playerManager
        view.attachPlayer()
        return view
    }

    func updateUIView(_ uiView: VideoHostView, context: Context) {
        uiView.playerManager = playerManager
        uiView.attachPlayer()
    }
}

/// Host view that adds the shared playerContainerView as subview.
class VideoHostView: UIView {
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            attachPlayer()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerManager?.updateContainerFrame(bounds)
    }

    func attachPlayer() {
        guard let playerManager = playerManager else { return }
        playerManager.attachContainer(to: self)
    }
}
