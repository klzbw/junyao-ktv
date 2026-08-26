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
    var currentAudioTracks: Int = 1
    private var loadedAudioTrackIndex: Int = 0
    private var voiceSession: Int = 0
    /// Last diagnostic message from voice switching (for toast display)
    @Published var voiceDiagnostic: String = ""

    @discardableResult
    func toggleVoice() -> String {
        isOriginalVoice.toggle()
        loadedAudioTrackIndex = -1
        return applyVoiceMode()
    }

    @discardableResult
    func setVoiceMode(_ original: Bool) -> String {
        isOriginalVoice = original
        loadedAudioTrackIndex = -1
        return applyVoiceMode()
    }

    /// Returns a diagnostic string describing what happened.
    @discardableResult
    private func applyVoiceMode() -> String {
        guard let playerItem = player?.currentItem else {
            voiceDiagnostic = "无播放项"
            return voiceDiagnostic
        }
        let wantOriginal = isOriginalVoice
        let targetIndex = wantOriginal ? 0 : 1

        if loadedAudioTrackIndex == targetIndex {
            voiceDiagnostic = wantOriginal ? "已是原唱" : "已是伴唱"
            return voiceDiagnostic
        }

        voiceSession += 1
        let session = voiceSession

        // Prevent AVPlayer from auto-overriding our selection based on system language
        playerItem.appliesMediaSelectionCriteriaAutomatically = false

        // First try synchronous access (works if playlist already parsed)
        if let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            let msg = doSelectTrack(for: playerItem, group: group, targetIndex: targetIndex, wantOriginal: wantOriginal)
            if loadedAudioTrackIndex == targetIndex { return msg }
        }

        // Async load for HLS (master playlist may not be parsed yet)
        playerItem.asset.loadMediaSelectionGroup(for: .audible) { [weak self] audioGroup, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard session == self.voiceSession else { return }
                guard let item = self.player?.currentItem else { return }
                guard let audioGroup = audioGroup else {
                    self.voiceDiagnostic = "音轨组不可用"
                    return
                }
                _ = self.doSelectTrack(for: item, group: audioGroup, targetIndex: targetIndex, wantOriginal: wantOriginal)
            }
        }

        voiceDiagnostic = "切换中..."
        return voiceDiagnostic
    }

    private func doSelectTrack(for item: AVPlayerItem, group: AVMediaSelectionGroup, targetIndex: Int, wantOriginal: Bool) -> String {
        let options = group.options
        let targetName = wantOriginal ? "原唱" : "伴唱"

        // Match by name first (HLS declares NAME="原唱"/NAME="伴唱"), fall back to index
        var targetOption: AVMediaSelectionOption? = options.first { opt in
            opt.displayName.contains(targetName)
        }
        if targetOption == nil && options.count > targetIndex {
            targetOption = options[targetIndex]
        }
        guard let option = targetOption else {
            voiceDiagnostic = "音轨不足(\(options.count))"
            return voiceDiagnostic
        }

        let current = item.selectedMediaOption(in: group)
        if current != option {
            item.select(option, in: group)
        }

        // Verify selection took effect
        let after = item.selectedMediaOption(in: group)
        if after == option {
            loadedAudioTrackIndex = targetIndex
            voiceDiagnostic = targetName
        } else {
            voiceDiagnostic = "切换失败(\(options.count)轨)"
        }
        return voiceDiagnostic
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
