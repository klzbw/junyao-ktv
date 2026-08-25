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

        // Method 1: Try switching HLS audio tracks
        if let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            let options = audioGroup.options
            if options.count >= 2 {
                // Typically option 0 = original, option 1 = accompaniment
                let targetIndex = isOriginalVoice ? 0 : min(1, options.count - 1)
                playerItem.selectMediaOption(options[targetIndex], inMediaSelectionGroup: audioGroup)
                return
            }
        }

        // Method 2: For single audio track, try audio mix for channel balance
        applyChannelBalance()
    }

    private func applyChannelBalance() {
        guard let player = player,
              let playerItem = player.currentItem,
              let assetTrack = playerItem.asset.tracks(withMediaType: .audio).first else {
            return
        }

        let mix = AVMutableAudioMix()
        let params = AVMutableAudioMixInputParameters(track: assetTrack)

        // Set volume ramp for the entire duration
        let duration = playerItem.duration
        if duration.seconds > 0 {
            let volume: Float = isOriginalVoice ? 1.0 : 0.8
            params.setVolumeRamp(fromStartVolume: volume, toEndVolume: volume,
                                 timeRange: CMTimeRange(start: .zero, duration: duration))
        }

        mix.inputParameters = [params]
        playerItem.audioMix = mix
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
