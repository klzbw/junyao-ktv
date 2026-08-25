import SwiftUI
import AVFoundation
import UIKit

/// A video view that uses the shared PlayerManager's AVPlayerLayer.
/// This view attaches/detaches the shared layer as it appears/disappears.
struct SharedVideoView: UIViewRepresentable {
    let playerManager: PlayerManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Attach the shared player layer to this view
        playerManager.attachLayer(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Detach when view is dismantled
        PlayerManager.shared.detachLayer()
    }
}
