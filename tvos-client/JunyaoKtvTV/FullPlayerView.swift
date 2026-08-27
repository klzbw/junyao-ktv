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
    @State private var showQueue = false
    @State private var showQR = false

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
                .onChange(of: api.queue.first(where: { $0.isPlaying })?.id) { _ in
                    // Song changed, re-attach layer to ensure video shows
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        playerManager.attachLayerToCurrentHost()
                    }
                }

            if showControls && !showQueue && !showQR {
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

                        // 7 control buttons - standard tvOS focusable buttons
                        HStack(spacing: 20) {
                            FocusableControlButton(icon: "house", title: "主页", isDefaultFocus: false) { onClose() }
                            FocusableControlButton(icon: "gobackward", title: "重唱", isDefaultFocus: false) { playerManager.restart(); api.restartSong() }
                            FocusableControlButton(icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                                                   title: playerManager.isPlaying ? "暂停" : "播放",
                                                   isDefaultFocus: true) { playerManager.togglePlayPause() }
                            FocusableControlButton(icon: "mic.fill", title: voiceMode.label, isDefaultFocus: false) { toggleVoice() }
                            FocusableControlButton(icon: "forward.end.fill", title: "切歌", isDefaultFocus: false) { onNext() }
                            FocusableControlButton(icon: "list.bullet", title: "队列", isDefaultFocus: false) { showQueue = true }
                            FocusableControlButton(icon: "qrcode", title: "扫码", isDefaultFocus: false) { showQR = true }
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
                .onAppear {
                    // FocusableControlButton auto-focuses the play button
                }
            }

            // Transparent focusable area to receive select button when controls are hidden
            if !showControls && !showQueue && !showQR {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .focusable(true)
                    .focusEffectDisabled()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showControls = true
                        }
                        resetHideTimer()
                    }
                    .ignoresSafeArea()
            }

            // Queue panel overlay
            if showQueue {
                queuePanel
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }

            // QR code overlay
            if showQR {
                qrPanel
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .onChange(of: showControls) { showing in
            // Focus managed by FocusableControlButton internally
        }
        .onPlayPauseCommand {
            playerManager.togglePlayPause()
            showControls = true
            resetHideTimer()
        }
        .onExitCommand {
            if showQR {
                showQR = false
            } else if showQueue {
                showQueue = false
            } else if showControls {
                showControls = false
            } else {
                onClose()
            }
        }
    }

    private func setup() {
        showControls = true
        resetHideTimer()
        hasAutoExited = false
        voiceMode = playerManager.isOriginalVoice ? .original : .accompaniment
    }

    // MARK: - Queue Panel
    private var queuePanel: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .focusable(false)
                .onTapGesture { showQueue = false }
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    HStack {
                        Text("♪ 已点队列")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(WebColors.ac2)
                        Text("\(api.queue.count)首")
                            .font(.system(size: 14))
                            .foregroundColor(WebColors.sub)
                            .padding(.leading, 8)
                        Spacer()
                        FocusableCloseButton { showQueue = false }
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
                                    if !item.isPlaying {
                                        Button(action: { api.topSong(queueId: item.queue_id) }) {
                                            Image(systemName: "arrow.up.to.line")
                                                .font(.system(size: 14))
                                                .foregroundColor(WebColors.ac2)
                                                .frame(width: 32, height: 32)
                                        }.buttonStyle(.plain).focusEffectDisabled()
                                        Button(action: { api.removeFromQueue(queueId: item.queue_id) }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14))
                                                .foregroundColor(WebColors.pink)
                                                .frame(width: 32, height: 32)
                                        }.buttonStyle(.plain).focusEffectDisabled()
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(item.isPlaying ? WebColors.ac.opacity(0.15) : Color.clear)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .frame(width: 340)
                .background(WebColors.panelBg)
                .cornerRadius(16, corners: [.topLeft, .bottomLeft])
                .focusSection()
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - QR Panel
    private var qrPanel: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .focusable(false)
                .onTapGesture { showQR = false }
            VStack(spacing: 16) {
                Text("扫码点歌")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                if let qrImage = generateQRCode(from: "http://\(api.serverAddress)/m") {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                Text("手机扫码即可点歌")
                    .font(.system(size: 16))
                    .foregroundColor(WebColors.sub)
                FocusableTextButton(title: "关闭", color: WebColors.ac) { showQR = false }
            }
            .padding(30)
            .background(WebColors.panelBg)
            .cornerRadius(20)
            .focusSection()
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func cleanup() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func toggleVoice() {
        playerManager.toggleVoice()
        voiceMode = playerManager.isOriginalVoice ? .original : .accompaniment
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

// MARK: - Focusable Control Button (fullscreen player 7 keys)
struct FocusableControlButton: View {
    let icon: String
    let title: String
    let isDefaultFocus: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 95, height: 95)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(focused ? WebColors.ac.opacity(0.4) : Color.white.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(focused ? WebColors.ac.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .scaleEffect(focused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear {
            if isDefaultFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    focused = true
                }
            }
        }
    }
}

// MARK: - Focusable Text Button
struct FocusableTextButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(color.opacity(focused ? 1.0 : 0.8))
                .cornerRadius(999)
                .overlay(
                    Capsule().stroke(focused ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .scaleEffect(focused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
