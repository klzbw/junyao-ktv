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
    @FocusState private var focusedButton: Int?

    enum VoiceMode {
        case original, accompaniment
        var label: String { self == .original ? "原唱" : "伴唱" }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SharedVideoView(playerManager: playerManager)
                .ignoresSafeArea()
                .onAppear { setup() }
                .onDisappear { cleanup() }

            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
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

                        // 6 control buttons
                        HStack(spacing: 12) {
                            controlButton(icon: "house", title: "主页", tag: 0) { onClose() }
                            controlButton(icon: "gobackward", title: "重唱", tag: 1) { playerManager.restart() }
                            controlButton(icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                                        title: playerManager.isPlaying ? "暂停" : "播放", tag: 2) {
                                playerManager.togglePlayPause()
                            }
                            controlButton(icon: "mic.fill", title: voiceMode.label, tag: 3) { toggleVoice() }
                            controlButton(icon: "forward.end.fill", title: "切歌", tag: 4) { onNext() }
                            controlButton(icon: "list.bullet", title: "队列", tag: 5) { onClose() }
                        }
                        .focusSection()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .padding(.top, 16)
                    .background(LinearGradient(colors: [.clear, Color.black.opacity(0.85)],
                                               startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .onTapGesture { toggleControls() }
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

    private func controlButton(icon: String, title: String, tag: Int, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            resetHideTimer()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(minWidth: 76)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(focusedButton == tag ? WebColors.ac.opacity(0.5) : Color.white.opacity(0.12))
            .cornerRadius(12)
            .scaleEffect(focusedButton == tag ? 1.1 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focusedButton)
        }
        .buttonStyle(.plain)
        .focused($focusedButton, equals: tag)
        .focusEffectDisabled()
    }

    private func setup() {
        showControls = true
        resetHideTimer()
    }

    private func cleanup() {
        hideTimer?.invalidate()
        hideTimer = nil
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
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
            DispatchQueue.main.async { showControls = false }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
