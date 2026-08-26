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
                    self?.applyVoiceMode()
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

        // Apply voice mode — async loader fires when HLS tracks are available
        applyVoiceMode()
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
    // Mirrors web VoiceManager.applyTracks(): hls.audioTrack = want is called exactly once.
    // Key fix: use AVAsset.loadMediaSelectionGroup(for:completionHandler:) — the
    // synchronous mediaSelectionGroup(forMediaCharacteristic:) returns nil for HLS
    // streams until the master playlist is parsed, which is why select() silently
    // failed on previous attempts. The async loader invokes our callback exactly
    // when tracks become available; no retry loops, no repeated select() calls.
    var currentAudioTracks: Int = 1
    private var loadedAudioTrackIndex: Int = 0
    private var voiceSession: Int = 0

    func toggleVoice() {
        isOriginalVoice.toggle()
        loadedAudioTrackIndex = -1
        applyVoiceMode()
    }

    func setVoiceMode(_ original: Bool) {
        isOriginalVoice = original
        loadedAudioTrackIndex = -1
        applyVoiceMode()
    }

    private func applyVoiceMode() {
        guard let playerItem = player?.currentItem else { return }
        let targetIndex = isOriginalVoice ? 0 : 1
        if loadedAudioTrackIndex == targetIndex { return }

        // Bump session so stale callbacks from previous songs are ignored
        voiceSession += 1
        let session = voiceSession

        // Async-load the audible media selection group. For HLS this fires when
        // the master playlist has been parsed and audio renditions are available.
        playerItem.asset.loadMediaSelectionGroup(for: .audible) { [weak self] audioGroup, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Ignore stale callbacks (song changed while loading)
                guard session == self.voiceSession else { return }
                guard let item = self.player?.currentItem else { return }
                guard let audioGroup = audioGroup else { return }
                let options = audioGroup.options
                guard options.count > targetIndex else { return }
                let targetOption = options[targetIndex]
                let current = item.selectedMediaOption(in: audioGroup)
                if current != targetOption {
                    // Single call — AVPlayer switches rendition without interrupting video,
                    // equivalent to hls.audioTrack = want in the web version.
                    item.select(targetOption, in: audioGroup)
                }
                self.loadedAudioTrackIndex = targetIndex
            }
        }
    }

    func cleanup() {
        // Invalidate any pending async voice-load callback
        voiceSession += 1
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
