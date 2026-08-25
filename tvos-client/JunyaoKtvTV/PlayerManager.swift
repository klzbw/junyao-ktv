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

        // New song defaults to original voice (track 0), matching web _loadedTrack = 0
        loadedAudioTrackIndex = 0

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

        // Apply current voice mode after tracks load
        applyVoiceMode()

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
    private var loadedAudioTrackIndex: Int = 0

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
        // HLS multi-audio-track switching (same as web hls.audioTrack = want)
        // Try immediately, then retry as tracks load
        trySelectAudioTrack(for: playerItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, let item = self.player?.currentItem else { return }
            self.trySelectAudioTrack(for: item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let item = self.player?.currentItem else { return }
            self.trySelectAudioTrack(for: item)
        }
    }

    private func trySelectAudioTrack(for playerItem: AVPlayerItem) {
        guard let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        let options = audioGroup.options
        guard options.count >= 2 else { return }
        // track 0 = original, track 1 = accompaniment (matches web hls.audioTrack)
        let targetIndex = isOriginalVoice ? 0 : 1
        if playerItem.selectedMediaOption(in: audioGroup) != options[targetIndex] {
            playerItem.select(options[targetIndex], in: audioGroup)
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
