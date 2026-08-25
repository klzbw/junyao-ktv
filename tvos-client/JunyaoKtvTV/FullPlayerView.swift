import SwiftUI
import AVFoundation

/// Fullscreen player using the shared PlayerManager.
/// The same AVPlayerLayer moves from small preview to here.
struct FullPlayerView: View {
    let song: QueueItem
    let onNext: () -> Void
    let onClose: () -> Void
    @ObservedObject var api: KTVAPIClient
    @ObservedObject private var playerManager = PlayerManager.shared

    @State private var showControls = true
    @State private var voiceMode: VoiceMode = .original
    @State private var hideTimer: Timer?
    @State private var nextUpSong: QueueItem?
    @State private var showQueue = false

    enum VoiceMode {
        case original, accompaniment
        var label: String { self == .original ? "原唱" : "伴唱" }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Shared video view - same player layer moves here
            SharedVideoView(playerManager: playerManager)
                .ignoresSafeArea()
                .onAppear { setup() }
                .onDisappear { cleanup() }

            // Controls overlay
            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        // Progress bar
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(LinearGradient(colors: [WebColors.ac, WebColors.ac2],
                                                             startPoint: .leading, endPoint: .trailing))
                                        .frame(width: playerManager.duration > 0 ? geo.size.width * CGFloat(playerManager.currentTime / playerManager.duration) : 0, height: 4)
                                }
                            }
                            .frame(height: 4)

                            HStack {
                                Text(formatTime(playerManager.currentTime))
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Spacer()
                                Text(formatTime(playerManager.duration))
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                        }

                        // Control buttons
                        HStack(spacing: 10) {
                            controlButton(icon: "house", title: "主页") { onClose() }
                            controlButton(icon: "gobackward", title: "重唱") { playerManager.restart() }
                            controlButton(icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                                        title: playerManager.isPlaying ? "暂停" : "播放", isCenter: true) {
                                playerManager.togglePlayPause()
                            }
                            controlButton(icon: "mic.fill", title: voiceMode.label) { toggleVoice() }
                            controlButton(icon: "forward.end.fill", title: "切歌") { onNext() }
                            controlButton(icon: "list.bullet", title: "队列") { showQueue.toggle() }
                        }
                        .focusSection()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                    .padding(.top, 14)
                    .background(LinearGradient(colors: [.clear, Color.black.opacity(0.8)],
                                               startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .focusable()
        .onPlayPauseCommand { playerManager.togglePlayPause(); resetHideTimer() }
        .onExitCommand {
            if showQueue { showQueue = false }
            else { onClose() }
        }
        .onMoveCommand { direction in
            if direction == .left { playerManager.seek(to: max(0, playerManager.currentTime - 10)) }
            else if direction == .right { playerManager.seek(to: playerManager.currentTime + 10) }
            resetHideTimer()
        }
    }

    private func setup() {
        if let playingIdx = api.queue.firstIndex(where: { $0.isPlaying }) {
            let nextIdx = api.queue.index(after: playingIdx)
            if nextIdx < api.queue.count {
                nextUpSong = api.queue[nextIdx]
            }
        }
        resetHideTimer()
    }

    private func cleanup() {
        hideTimer?.invalidate()
    }

    private func toggleVoice() {
        voiceMode = voiceMode == .original ? .accompaniment : .original
        api.toggleVoice()
    }

    private func toggleControls() {
        showControls.toggle()
        if showControls { resetHideTimer() }
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            DispatchQueue.main.async { showControls = false }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func controlButton(icon: String, title: String, isCenter: Bool = false, action: @escaping () -> Void) -> some View {
        @FocusState var focused: Bool
        return Button(action: { action(); resetHideTimer() }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: isCenter ? 30 : 26))
                    .foregroundColor(focused ? .white : Color.white.opacity(0.9))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(focused ? .white : Color.white.opacity(0.85))
            }
            .frame(minWidth: 72)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(focused ? WebColors.ac.opacity(0.35) : Color.white.opacity(0.1))
            .cornerRadius(11)
            .scaleEffect(focused ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.2), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
    }
}
