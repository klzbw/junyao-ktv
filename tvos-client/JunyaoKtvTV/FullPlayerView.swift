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
                            TVTightButton(action: { onClose() }) { focused in
                                controlContent(icon: "house", title: "主页", focused: focused)
                            }

                            TVTightButton(action: { playerManager.restart(); api.restartSong() }) { focused in
                                controlContent(icon: "gobackward", title: "重唱", focused: focused)
                            }

                            TVTightButton(action: {
                                playerManager.togglePlayPause()
                            }, autoFocus: true) { focused in
                                controlContent(
                                    icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                                    title: playerManager.isPlaying ? "暂停" : "播放",
                                    focused: focused
                                )
                            }

                            TVTightButton(action: { toggleVoice() }) { focused in
                                controlContent(icon: "mic.fill", title: voiceMode.label, focused: focused)
                            }

                            TVTightButton(action: { onNext() }) { focused in
                                controlContent(icon: "forward.end.fill", title: "切歌", focused: focused)
                            }

                            TVTightButton(action: { showQueue = true }) { focused in
                                controlContent(icon: "list.bullet", title: "队列", focused: focused)
                            }

                            TVTightButton(action: { showQR = true }) { focused in
                                controlContent(icon: "qrcode", title: "扫码", focused: focused)
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

    private func controlContent(icon: String, title: String, focused: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(focused ? Color(hex: 0x1a1a2e) : .white)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(focused ? Color(hex: 0x1a1a2e) : .white)
        }
        .frame(width: 95, height: 95)
        .background(focused ? Color.white : Color.white.opacity(0.15))
        .cornerRadius(16)
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
                        TVTightButton(action: { showQueue = false }) { focused in
                            Image(systemName: "xmark")
                                .foregroundColor(focused ? Color(hex: 0x1a1a2e) : .white)
                                .frame(width: 36, height: 36)
                                .background(focused ? Color.white : Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(WebColors.topbarBg)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(api.queue.enumerated()), id: \.element.id) { idx, item in
                                HStack(spacing: 12) {
                                    if item.isPlaying {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundColor(WebColors.ac2)
                                            .font(.system(size: 26))
                                    } else {
                                        Text("\(idx + 1)")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(WebColors.sub)
                                            .frame(width: 32)
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.displayTitle)
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(item.displayArtist)
                                            .font(.system(size: 19, weight: .medium))
                                            .foregroundColor(WebColors.sub)
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    if !item.isPlaying {
                                        TVTightButton(action: { api.topSong(queueId: item.queue_id) }) { focused in
                                            Image(systemName: "arrow.up.to.line")
                                                .font(.system(size: 24))
                                                .foregroundColor(focused ? Color(hex: 0x1a1a2e) : WebColors.ac2)
                                                .frame(width: 52, height: 52)
                                                .background(focused ? Color.white : Color.clear)
                                                .cornerRadius(8)
                                        }
                                        TVTightButton(action: { api.removeFromQueue(queueId: item.queue_id) }) { focused in
                                            Image(systemName: "trash")
                                                .font(.system(size: 24))
                                                .foregroundColor(focused ? Color(hex: 0x1a1a2e) : WebColors.pink)
                                                .frame(width: 52, height: 52)
                                                .background(focused ? Color.white : Color.clear)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 16)
                                .background(item.isPlaying ? WebColors.ac.opacity(0.15) : Color.clear)
                                .cornerRadius(10)
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
                TVTightButton(action: { showQR = false }, autoFocus: true) { focused in
                    Text("关闭")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(focused ? Color(hex: 0x1a1a2e) : .white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(focused ? Color.white : WebColors.ac)
                        .cornerRadius(999)
                }
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

