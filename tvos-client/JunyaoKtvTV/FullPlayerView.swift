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
    @FocusState private var focusedButton: Int?

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

                        // Control buttons - 6 buttons with proper focus
                        HStack(spacing: 12) {
                            controlButton(icon: "house", title: "主页", tag: 0) { onClose() }
                            controlButton(icon: "gobackward", title: "重唱", tag: 1) { playerManager.restart() }
                            controlButton(icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                                        title: playerManager.isPlaying ? "暂停" : "播放", tag: 2, isCenter: true) {
                                playerManager.togglePlayPause()
                            }
                            controlButton(icon: "mic.fill", title: voiceMode.label, tag: 3) { toggleVoice() }
                            controlButton(icon: "forward.end.fill", title: "切歌", tag: 4) { onNext() }
                            controlButton(icon: "list.bullet", title: "队列", tag: 5) { showQueue.toggle() }
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

            // Queue side panel
            if showQueue {
                queueSidePanel
                    .transition(.move(edge: .trailing))
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
            if showQueue {
                showQueue = false
            } else if showControls {
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
        .onLongPressGesture {
            toggleControls()
        }
    }

    // MARK: - Queue Side Panel
    private var queueSidePanel: some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                HStack {
                    Text("♪ 已点队列")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(api.queue.count)首")
                        .font(.system(size: 14))
                        .foregroundColor(WebColors.sub)
                        .padding(.leading, 8)
                    Spacer()
                    Button(action: { showQueue = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(WebColors.topbarBg)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(api.queue.enumerated()), id: \.element.id) { idx, item in
                            HStack(spacing: 8) {
                                if item.isPlaying {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundColor(WebColors.ac2)
                                        .font(.system(size: 16))
                                } else {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 13))
                                        .foregroundColor(WebColors.sub)
                                        .frame(width: 20)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayTitle)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(item.displayArtist)
                                        .font(.system(size: 11))
                                        .foregroundColor(WebColors.sub)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(item.isPlaying ? WebColors.ac.opacity(0.15) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 320)
            .background(WebColors.panelBg)
            .cornerRadius(16, corners: [.topLeft, .bottomLeft])
            .focusSection()
        }
        .ignoresSafeArea()
    }

    // MARK: - Control Button with proper focus
    private func controlButton(icon: String, title: String, tag: Int, isCenter: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            resetHideTimer()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isCenter ? 32 : 26, weight: .medium))
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

    // MARK: - Logic
    private func setup() {
        if let playingIdx = api.queue.firstIndex(where: { $0.isPlaying }) {
            let nextIdx = api.queue.index(after: playingIdx)
            if nextIdx < api.queue.count {
                nextUpSong = api.queue[nextIdx]
            }
        }
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
        if showControls {
            resetHideTimer()
        }
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
            DispatchQueue.main.async {
                showControls = false
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

// Helper for corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
