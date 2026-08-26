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
    private var itemStatusObserver: NSKeyValueObservation?
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

        // Item status observer - start voice poll when item is ready to play
        itemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] _, _ in
            if playerItem.status == .readyToPlay {
                DispatchQueue.main.async {
                    self?.startVoicePoll()
                }
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

        // Start voice poll — will select target track once HLS audio group is ready
        startVoicePoll()
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
    // Strategy: HLS audio media selection group becomes available asynchronously
    // after the item starts playing. We poll until the group is ready, then call
    // select(_:in:) exactly ONCE — matching web's hls.audioTrack = want semantics.
    // Repeated select() calls cause AVPlayer to rebuffer audio = stutter, so we
    // never call it more than once per target.
    var currentAudioTracks: Int = 1
    private var loadedAudioTrackIndex: Int = 0
    private var voicePollTimer: Timer?
    private var voicePollAttempts = 0

    func toggleVoice() {
        isOriginalVoice.toggle()
        loadedAudioTrackIndex = -1  // force re-apply
        startVoicePoll()
    }

    func setVoiceMode(_ original: Bool) {
        isOriginalVoice = original
        loadedAudioTrackIndex = -1
        startVoicePoll()
    }

    /// Poll until audio group is available, then select target track once.
    private func startVoicePoll() {
        voicePollTimer?.invalidate()
        voicePollAttempts = 0
        // Try immediately first
        if trySelectIfReady() { return }
        // Poll every 0.4s for up to ~6s (15 attempts)
        voicePollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.voicePollAttempts += 1
            if self.trySelectIfReady() || self.voicePollAttempts >= 15 {
                self.voicePollTimer?.invalidate()
                self.voicePollTimer = nil
            }
        }
        RunLoop.main.add(voicePollTimer!, forMode: .common)
    }

    /// Returns true if selection was applied (or already on target), false if group not ready.
    @discardableResult
    private func trySelectIfReady() -> Bool {
        guard let playerItem = player?.currentItem else {
            voicePollTimer?.invalidate(); voicePollTimer = nil
            return true
        }
        let targetIndex = isOriginalVoice ? 0 : 1
        if loadedAudioTrackIndex == targetIndex {
            voicePollTimer?.invalidate(); voicePollTimer = nil
            return true
        }
        guard let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return false  // group not ready yet, keep polling
        }
        let options = audioGroup.options
        guard options.count > targetIndex else {
            return false  // tracks not loaded yet
        }
        let targetOption = options[targetIndex]
        let current = playerItem.selectedMediaOption(in: audioGroup)
        if current != targetOption {
            // Single select call — AVPlayer handles rendition switch smoothly
            playerItem.select(targetOption, in: audioGroup)
        }
        loadedAudioTrackIndex = targetIndex
        return true
    }

    func cleanup() {
        voicePollTimer?.invalidate()
        voicePollTimer = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
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
