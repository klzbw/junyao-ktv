import SwiftUI
import AVFoundation

/// Fullscreen player using the shared PlayerManager.
struct FullPlayerView: View {
    let song: QueueItem
    let onNext: () -> Void
    let onClose: () -> Void
    @ObservedObject var api: KTVAPIClient
    @ObservedObject private var playerManager = PlayerManager.shared

    @State private var showControls = true
    @State private var voiceMode: VoiceMode = .original
    @State private var hideTimer: Timer?
    @State private var hasAutoExited = false

    enum VoiceMode {
        case original, accompaniment
        var label: String { self == .original ? "原唱" : "伴唱" }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SharedVideoView(playerManager: playerManager)
                .ignoresSafeArea()
                .id("fullscreen-video")
                .onAppear { setup() }
                .onDisappear { cleanup() }

            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 14) {
                        // Progress bar
                        VStack(spacing: 6) {
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

                        // 6 control buttons - standard tvOS focusable buttons
                        HStack(spacing: 20) {
                            Button(action: { onClose() }) {
                                controlContent(icon: "house", title: "主页")
                            }
                            Button(action: { playerManager.restart() }) {
                                controlContent(icon: "gobackward", title: "重唱")
                            }
                            Button(action: { playerManager.togglePlayPause() }) {
                                controlContent(
                                    icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                                    title: playerManager.isPlaying ? "暂停" : "播放"
                                )
                            }
                            Button(action: { toggleVoice() }) {
                                controlContent(icon: "mic.fill", title: voiceMode.label)
                            }
                            Button(action: { onNext() }) {
                                controlContent(icon: "forward.end.fill", title: "切歌")
                            }
                            Button(action: { onClose() }) {
                                controlContent(icon: "list.bullet", title: "队列")
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .padding(.top, 16)
                    .background(LinearGradient(colors: [.clear, Color.black.opacity(0.9)],
                                               startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Select button: toggle controls visibility
            withAnimation(.easeOut(duration: 0.2)) {
                showControls.toggle()
            }
            if showControls { resetHideTimer() }
        }
        .onPlayPauseCommand {
            playerManager.togglePlayPause()
            showControls = true
            resetHideTimer()
        }
        .onExitCommand {
            if showControls {
                showControls = false
            } else {
                onClose()
            }
        }
        .onMoveCommand { direction in
            showControls = true
            resetHideTimer()
            if direction == .left {
                playerManager.seek(to: max(0, playerManager.currentTime - 10))
            } else if direction == .right {
                playerManager.seek(to: playerManager.currentTime + 10)
            }
        }
    }

    private func controlContent(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 95, height: 95)
        .background(Color.white.opacity(0.15))
        .cornerRadius(16)
    }

    private func setup() {
        showControls = true
        resetHideTimer()
        hasAutoExit = false
        // Set playback end callback to auto-exit
        playerManager.onPlaybackEnd = {
            DispatchQueue.main.async {
                if !hasAutoExited {
                    hasAutoExited = true
                    onClose()
                }
            }
        }
    }

    private func cleanup() {
        hideTimer?.invalidate()
        hideTimer = nil
        playerManager.onPlaybackEnd = nil
    }

    private func toggleVoice() {
        voiceMode = voiceMode == .original ? .accompaniment : .original
        api.toggleVoice()
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
