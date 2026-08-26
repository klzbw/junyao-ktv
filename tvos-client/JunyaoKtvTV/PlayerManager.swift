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
    private var mediaGroupObserver: NSObjectProtocol?

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
        pendingVoiceSwitch = false

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
                    self?.applyVoiceModeIfNeeded()
                }
            }
        }

        // Listen for media selection group becoming available (HLS tracks load async).
        // This is the correct AVFoundation signal — equivalent to hls.js MANIFEST_PARSED
        // / AUDIO_TRACKS_UPDATED in the web VoiceManager.
        mediaGroupObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionGroupDidChangeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.applyVoiceModeIfNeeded()
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

        // Apply voice mode immediately (may no-op if tracks not loaded yet;
        // the notification observer above will apply when they become available)
        applyVoiceModeIfNeeded()
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
    // AVPlayerItem.select(_:in:) is the equivalent — it switches the audio rendition
    // without interrupting video. Calling it repeatedly causes rebuffering/stutter,
    // so we call it ONCE and rely on mediaSelectionGroupDidChangeNotification for
    // the async-loading case.
    var currentAudioTracks: Int = 1
    private var loadedAudioTrackIndex: Int = 0
    private var pendingVoiceSwitch: Bool = false

    func toggleVoice() {
        isOriginalVoice.toggle()
        // Force re-apply regardless of what we think is loaded
        loadedAudioTrackIndex = -1
        pendingVoiceSwitch = true
        applyVoiceModeIfNeeded()
    }

    func setVoiceMode(_ original: Bool) {
        isOriginalVoice = original
        loadedAudioTrackIndex = -1
        pendingVoiceSwitch = true
        applyVoiceModeIfNeeded()
    }

    /// Apply voice mode if we have a pending switch and tracks are available.
    /// Called from: setupPlayer, itemStatusObserver (readyToPlay),
    /// mediaSelectionGroupDidChangeNotification, and toggleVoice/setVoiceMode.
    private func applyVoiceModeIfNeeded() {
        guard let playerItem = player?.currentItem else { return }
        let targetIndex = isOriginalVoice ? 0 : 1

        // Already on the correct track — nothing to do (matches web: want === _loadedTrack)
        if loadedAudioTrackIndex == targetIndex && !pendingVoiceSwitch { return }

        // Try to select now. If the group isn't available yet, the notification
        // observer will call this again when it arrives.
        if selectAudioTrack(for: playerItem, targetIndex: targetIndex) {
            loadedAudioTrackIndex = targetIndex
            pendingVoiceSwitch = false
        }
        // If select failed (group not ready), leave pendingVoiceSwitch = true;
        // mediaSelectionGroupDidChangeNotification will retry — exactly ONCE.
    }

    /// Attempt to select the audio track. Returns true if selection was made.
    @discardableResult
    private func selectAudioTrack(for playerItem: AVPlayerItem, targetIndex: Int) -> Bool {
        guard let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return false
        }
        let options = audioGroup.options
        guard options.count > targetIndex else { return false }

        let targetOption = options[targetIndex]
        let current = playerItem.selectedMediaOption(in: audioGroup)
        if current != targetOption {
            // Single call — AVPlayer handles rendition switch smoothly,
            // just like hls.audioTrack = want in the web version.
            playerItem.select(targetOption, in: audioGroup)
        }
        return true
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let observer = mediaGroupObserver {
            NotificationCenter.default.removeObserver(observer)
            mediaGroupObserver = nil
        }
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
