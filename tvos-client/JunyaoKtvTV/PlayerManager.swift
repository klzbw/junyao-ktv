import AVFoundation
import UIKit

/// Shared player manager - holds a single AVPlayer, AVPlayerLayer, and its container view.
/// The container view moves between small preview and fullscreen views.
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var currentSongId: Int?

    private(set) var player: AVPlayer?
    private(set) var playerLayer: AVPlayerLayer?
    /// Global container view that holds the player layer. Moves between parent views.
    private(set) var playerContainerView: UIView
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    private init() {
        playerContainerView = UIView()
        playerContainerView.backgroundColor = .black
        playerContainerView.clipsToBounds = true
    }

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
        layer.videoGravity = .resizeAspect
        self.playerLayer = layer

        // Attach layer to the global container view
        playerContainerView.layer.addSublayer(layer)
        layer.frame = playerContainerView.bounds

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

    /// Attach the global player container view to a given parent view
    func attachContainer(to parent: UIView) {
        if playerContainerView.superview != parent {
            playerContainerView.removeFromSuperview()
            parent.addSubview(playerContainerView)
        }
        playerContainerView.frame = parent.bounds
        playerLayer?.frame = parent.bounds
    }

    /// Detach the global player container view from its current superview
    func detachContainer() {
        playerContainerView.removeFromSuperview()
    }

    func updateContainerFrame(_ frame: CGRect) {
        playerContainerView.frame = frame
        playerLayer?.frame = frame
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
        playerContainerView.removeFromSuperview()
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
