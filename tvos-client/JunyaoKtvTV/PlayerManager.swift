import AVFoundation
import UIKit

/// Shared player manager - holds a single AVPlayer and AVPlayerLayer
/// that moves between small preview and fullscreen views.
/// This mirrors the web page's strategy of moving the same <video> element in DOM.
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var currentSongId: Int?

    private(set) var player: AVPlayer?
    private(set) var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    private init() {}

    func setupPlayer(for url: URL) {
        // If same song, keep existing player
        if let existingURL = (player?.currentItem?.asset as? AVURLAsset)?.url,
           existingURL == url {
            return
        }

        // Cleanup old player
        cleanup()

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.playerLayer = layer

        // Add time observer
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
            if let dur = player.currentItem?.duration.seconds, !dur.isNaN {
                self?.duration = dur
            }
        }

        // Observe rate changes to sync isPlaying
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }

        player.play()
        isPlaying = true
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    func restart() {
        seek(to: 0)
        play()
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    /// Attach player layer to a given view's layer
    func attachLayer(to view: UIView) {
        guard let layer = playerLayer else { return }
        layer.removeFromSuperlayer()
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
    }

    /// Detach player layer from its current superlayer
    func detachLayer() {
        playerLayer?.removeFromSuperlayer()
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
