import AVFoundation
import UIKit

/// Shared player manager - holds a single AVPlayer, AVPlayerLayer, and its container view.
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var currentSongId: Int?
    /// Called when current item finishes playing
    var onPlaybackEnd: (() -> Void)?

    private(set) var player: AVPlayer?
    private(set) var playerLayer: AVPlayerLayer?
    private(set) var playerContainerView: UIView
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private init() {
        playerContainerView = UIView()
        playerContainerView.backgroundColor = .black
        playerContainerView.clipsToBounds = true
    }

    func setupPlayer(for url: URL) {
        if let existingURL = (player?.currentItem?.asset as? AVURLAsset)?.url,
           existingURL == url {
            // Same song, just ensure layer frame is correct
            refreshLayerFrame()
            return
        }

        cleanup()

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.playerLayer = layer

        playerContainerView.layer.addSublayer(layer)
        refreshLayerFrame()

        // Time observer
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
            if let dur = player.currentItem?.duration.seconds, !dur.isNaN {
                self?.duration = dur
            }
        }

        // Rate observer
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }

        // Playback end observer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.onPlaybackEnd?()
        }

        player.play()
        isPlaying = true
    }

    func refreshLayerFrame() {
        if let superview = playerContainerView.superview {
            playerContainerView.frame = superview.bounds
        }
        playerLayer?.frame = playerContainerView.bounds
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

    func attachContainer(to parent: UIView) {
        if playerContainerView.superview != parent {
            playerContainerView.removeFromSuperview()
            parent.addSubview(playerContainerView)
        }
        playerContainerView.frame = parent.bounds
        playerLayer?.frame = parent.bounds
    }

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
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
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
