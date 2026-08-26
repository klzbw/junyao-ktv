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

        // Item status observer - apply voice mode when item is ready to play
        itemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] _, _ in
            if playerItem.status == .readyToPlay {
                DispatchQueue.main.async {
                    self?.applyVoiceModeAsync()
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

        // Apply voice mode — async load handles HLS audio group availability
        applyVoiceModeAsync()
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
    // Mirrors web VoiceManager: hls.audioTrack = want is called exactly once.
    // For HLS, AVAsset.mediaSelectionGroup(for:) must be loaded ASYNCHRONOUSLY —
    // the synchronous variant often returns nil for HLS streams on tvOS.
    var currentAudioTracks: Int = 1
    private var loadedAudioTrackIndex: Int = 0
    private var voiceSwitchTask: Task<Void, Never>?

    func toggleVoice() {
        isOriginalVoice.toggle()
        loadedAudioTrackIndex = -1  // force re-apply
        applyVoiceModeAsync()
    }

    func setVoiceMode(_ original: Bool) {
        isOriginalVoice = original
        loadedAudioTrackIndex = -1
        applyVoiceModeAsync()
    }

    private func applyVoiceModeAsync() {
        voiceSwitchTask?.cancel()
        voiceSwitchTask = Task { [weak self] in
            guard let self = self else { return }
            let targetIndex = self.isOriginalVoice ? 0 : 1

            // Try up to 4 times with increasing delays (0s, 0.5s, 1.5s, 3s)
            // Each attempt uses async load — select() is called at most once.
            let delays: [UInt64] = [0, 500_000_000, 1_500_000_000, 3_000_000_000]
            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                if Task.isCancelled { return }
                if self.loadedAudioTrackIndex == targetIndex { return }

                guard let playerItem = self.player?.currentItem else { return }

                // Async load is required for HLS streams on tvOS
                if let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible) {
                    if Task.isCancelled { return }
                    let options = group.options
                    if options.count > targetIndex {
                        let targetOption = options[targetIndex]
                        await MainActor.run {
                            let current = playerItem.selectedMediaOption(in: group)
                            if current != targetOption {
                                playerItem.select(targetOption, in: group)
                            }
                            self.loadedAudioTrackIndex = targetIndex
                        }
                        return
                    }
                }

                // Fallback: synchronous method (works for non-HLS / already-loaded assets)
                await MainActor.run {
                    self.trySelectSynchronous(playerItem: playerItem, targetIndex: targetIndex)
                }
                if self.loadedAudioTrackIndex == targetIndex { return }
            }
        }
    }

    private func trySelectSynchronous(playerItem: AVPlayerItem, targetIndex: Int) {
        guard let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        let options = audioGroup.options
        guard options.count > targetIndex else { return }
        let targetOption = options[targetIndex]
        let current = playerItem.selectedMediaOption(in: audioGroup)
        if current != targetOption {
            playerItem.select(targetOption, in: audioGroup)
        }
        loadedAudioTrackIndex = targetIndex
    }

    func cleanup() {
        voiceSwitchTask?.cancel()
        voiceSwitchTask = nil
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
