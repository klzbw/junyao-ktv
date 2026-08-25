import AVFoundation
import UIKit

/// Shared player manager - holds a single AVPlayer and AVPlayerLayer.
/// The layer moves between small preview and fullscreen views via currentHostView.
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var currentSongId: Int?
    @Published var isOriginalVoice: Bool = true
    var onPlaybackEnd: (() -> Void)?

    private(set) var player: AVPlayer?
    private(set) var playerLayer: AVPlayerLayer?
    /// Current host view that displays the player layer
    weak var currentHostView: UIView?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private init() {}

    func setupPlayer(for url: URL) {
        if let existingURL = (player?.currentItem?.asset as? AVURLAsset)?.url,
           existingURL == url {
            attachLayerToCurrentHost()
            return
        }

        cleanup()

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.playerLayer = layer

        // Auto-attach to current host view
        attachLayerToCurrentHost()

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

        // Apply voice mode after tracks are loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyVoiceMode()
        }
    }

    /// Attach player layer to the current host view
    func attachLayerToCurrentHost() {
        guard let layer = playerLayer, let host = currentHostView else { return }
        if layer.superlayer != host.layer {
            layer.removeFromSuperlayer()
            host.layer.addSublayer(layer)
        }
        layer.frame = host.bounds
    }

    /// Update layer frame when host view layout changes
    func updateLayerFrame() {
        guard let layer = playerLayer, let host = currentHostView else { return }
        layer.frame = host.bounds
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

    // MARK: - Voice Toggle (Original / Accompaniment)
    var currentAudioTracks: Int = 1

    func toggleVoice() {
        isOriginalVoice.toggle()
        applyVoiceMode()
    }

    func setVoiceMode(_ original: Bool) {
        isOriginalVoice = original
        applyVoiceMode()
    }

    private func applyVoiceMode() {
        guard let playerItem = player?.currentItem else { return }

        // Try switching HLS audio tracks immediately
        if trySwitchAudioTracks(playerItem) { return }

        // HLS tracks may not be loaded yet, retry after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let item = self.player?.currentItem else { return }
            if !self.trySwitchAudioTracks(item) {
                // Fallback: reload HLS stream
                self.reloadHLSStream()
            }
        }
    }

    private func trySwitchAudioTracks(_ playerItem: AVPlayerItem) -> Bool {
        guard let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return false
        }
        let options = audioGroup.options
        guard options.count >= 2 else { return false }
        let targetIndex = isOriginalVoice ? 0 : min(1, options.count - 1)
        playerItem.select(options[targetIndex], in: audioGroup)
        return true
    }

    private func reloadHLSStream() {
        guard let player = player,
              let currentItem = player.currentItem,
              let asset = currentItem.asset as? AVURLAsset,
              currentSongId != nil else { return }

        let currentTime = player.currentTime()
        let wasPlaying = player.rate > 0

        // Use the same HLS URL - server will return correct audio track based on voice state
        let newItem = AVPlayerItem(url: asset.url)
        player.replaceCurrentItem(with: newItem)

        // Wait for item to be ready, then seek and play
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: newItem,
            queue: .main
        ) { _ in
            if wasPlaying {
                player.seek(to: currentTime) { _ in player.play() }
            }
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
        }

        // Fallback: after 2 seconds, seek and play anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if wasPlaying && player.rate == 0 {
                player.seek(to: currentTime) { _ in player.play() }
            }
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
        }
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
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
