import SwiftUI
import AVKit
import CoreImage

struct ContentView: View {
    @StateObject private var api: KTVAPIClient
    @AppStorage("serverAddress") private var serverAddress: String = ""
    @AppStorage("appTheme") private var appThemeRaw: Int = 1
    @State private var showingSetup = false
    @State private var showingPlayer = false
    @State private var activePanel: PanelType? = nil
    @State private var activePage: PageType? = nil
    @State private var selectedArtist: String = ""
    @State private var toast: String?
    @State private var currentTheme: AppTheme = .theme1
    @State private var isPlaying = false
    @State private var isOriginalVoice = true
    @State private var showSongIntro = false
    @State private var introSong: QueueItem?
    @State private var volume: Float = 0.7
    @State private var showQR = false
    @State private var shouldResumePlaying = true
    private let playerManager = PlayerManager.shared

    enum PanelType { case search, queue, settings, eq }
    enum PageType { case order, artists, artistSongs, charts, favorites, history, newest, category }

    init() {
        let addr = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        _api = StateObject(wrappedValue: KTVAPIClient(baseURL: addr.isEmpty ? "http://192.168.3.16:8083" : addr))
    }

    var body: some View {
        Group {
            if showingSetup || serverAddress.isEmpty {
                SetupView(serverAddress: $serverAddress, onSave: {
                    api.updateBaseURL(serverAddress)
                    showingSetup = false
                })
            } else if let page = activePage {
                pageView(page)
            } else {
                mainContent
            }
        }
        .onExitCommand {
            if activePage != nil {
                activePage = nil
            }
        }
        .onAppear {
            currentTheme = AppTheme(rawValue: appThemeRaw) ?? .theme1
            if !serverAddress.isEmpty {
                api.fetchAll()
                api.connectWebSocket()
                setupControlHandler()
            } else {
                showingSetup = true
            }
        }
        .onChange(of: showingPlayer) { isPresented in
            if isPresented {
                // Entering fullscreen: record state, shared player keeps playing
                shouldResumePlaying = playerManager.isPlaying
            } else {
                // Exiting fullscreen: shared player continues, just sync state
                isPlaying = playerManager.isPlaying
            }
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            if let playing = api.queue.first(where: { $0.isPlaying }) {
                FullPlayerView(
                    song: playing,
                    onNext: { api.nextSong() },
                    onClose: { showingPlayer = false },
                    api: api
                )
            }
        }
        .overlay(alignment: .top) {
            if let toast = toast {
                Text(toast)
                    .font(.system(size: 17))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color(red: 20/255, green: 20/255, blue: 50/255).opacity(0.96))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(WebColors.ac.opacity(0.4), lineWidth: 1))
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: toast)
    }

    // MARK: - Main Content (exact web layout)
    private var mainContent: some View {
        ZStack {
            // Theme-based background
            if appThemeRaw == 2 {
                // Theme 2: Dark Neon (simulates theme2-bg.jpg)
                AppTheme.neonBg.ignoresSafeArea()
                RadialGradient(colors: [WebColors.ac.opacity(0.25), .clear],
                               center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 500)
                    .ignoresSafeArea()
                RadialGradient(colors: [WebColors.pink.opacity(0.2), .clear],
                               center: UnitPoint(x: 0.8, y: 0.7), startRadius: 0, endRadius: 450)
                    .ignoresSafeArea()
                RadialGradient(colors: [WebColors.ac2.opacity(0.15), .clear],
                               center: UnitPoint(x: 0.5, y: 1.0), startRadius: 0, endRadius: 400)
                    .ignoresSafeArea()
            } else if appThemeRaw == 3 {
                // Theme 3: Carousel style
                Color(hex: 0x050a15).ignoresSafeArea()
                RadialGradient(colors: [AppTheme.s3Accent.opacity(0.15), .clear],
                               center: UnitPoint(x: 0.3, y: 0.4), startRadius: 0, endRadius: 500)
                    .ignoresSafeArea()
                RadialGradient(colors: [AppTheme.s3Accent2.opacity(0.12), .clear],
                               center: UnitPoint(x: 0.7, y: 0.6), startRadius: 0, endRadius: 450)
                    .ignoresSafeArea()
            } else {
                // Theme 1: Default (exact #bg)
                WebColors.bg.ignoresSafeArea()
                RadialGradient(colors: [WebColors.ac.opacity(0.12), .clear],
                               center: UnitPoint(x: 0.1, y: 0.5), startRadius: 0, endRadius: 400)
                    .ignoresSafeArea()
                RadialGradient(colors: [WebColors.ac2.opacity(0.12), .clear],
                               center: UnitPoint(x: 0.9, y: 0.2), startRadius: 0, endRadius: 400)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                nextUpBar
                mainGrid
            }
            .allowsHitTesting(activePanel == nil)

            if let panel = activePanel {
                panelView(panel)
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        .onExitCommand {
            if activePanel != nil {
                activePanel = nil
            }
        }
        .onPlayPauseCommand {
            if api.queue.contains(where: { $0.isPlaying }) {
                showingPlayer = true
            }
        }
    }

    // MARK: - Top Bar (exact #topbar)
    private var topBar: some View {
        HStack(spacing: 8) {
            // Logo
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 24))
                    .foregroundStyle(LinearGradient(colors: [WebColors.ac2, WebColors.ac, WebColors.pink],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("骏耀K歌")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.trailing, 4)

            NavButton(icon: "magnifyingglass", title: "搜索", badge: nil) { activePanel = .search }
            NavButton(icon: "list.bullet", title: "已点", badge: api.queue.count > 0 ? api.queue.count : nil) { activePanel = .queue }
            NavButton(icon: "gearshape", title: "设置", badge: nil) { activePanel = .settings }

            Spacer()

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(api.isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(api.isConnected ? "已连接" : "未连接")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(WebColors.sub)
            }
            .padding(.horizontal, 10)

            // Clock
            VStack(alignment: .trailing, spacing: 2) {
                Text(currentTime)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Text(currentDate)
                    .font(.system(size: 14))
                    .foregroundColor(WebColors.sub)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(WebColors.topbarBg)
        .overlay(Rectangle().fill(WebColors.topbarBorder).frame(height: 1), alignment: .bottom)
        .focusSection()
    }

    // MARK: - Next Up Bar (exact #next-up-bar)
    private var nextUpBar: some View {
        Group {
            if let next = api.queue.first(where: { !$0.isPlaying }) {
                HStack(spacing: 10) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .foregroundColor(WebColors.ac2)
                    Text("下一首:")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(WebColors.sub)
                    Text(next.displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text("- \(next.displayArtist)")
                        .font(.system(size: 17))
                        .foregroundColor(WebColors.sub)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(LinearGradient(colors: [WebColors.ac.opacity(0.32), WebColors.ac2.opacity(0.16)],
                                           startPoint: .leading, endPoint: .trailing))
                .overlay(Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1), alignment: .bottom)
            }
        }
    }

    // MARK: - Main Grid (4-column 5-row layout, video spans 2x3)
    private var mainGrid: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                // Left column: contains video + controls + quick cards
                VStack(spacing: 10) {
                    // Video panel - 3 rows (60% height)
                    nowPanel
                        .frame(height: geo.size.height * 0.58)

                    // Controls - 1 row (22% height)
                    mvCtrl
                        .frame(height: geo.size.height * 0.22)

                    // Quick cards - 1 row (20% height)
                    bottomQuickCards
                        .frame(height: geo.size.height * 0.20)
                }
                .frame(width: geo.size.width * 0.52)

                // Middle column: 4 vertical buttons
                midCards
                    .frame(width: geo.size.width * 0.28)

                // Right column: queue (narrow)
                rightQueue
                    .frame(width: geo.size.width * 0.20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .focusSection()
    }

    // MARK: - Bottom Quick Cards (hot charts, recent, favorites, newest)
    private var bottomQuickCards: some View {
        HStack(spacing: 8) {
            quickCard(title: "热歌排行", icon: "chart.line.uptrend.xyaxis", gradient: LinearGradient(colors: [Color(hex: 0xff4f9b), Color(hex: 0xff6b6b)], startPoint: .leading, endPoint: .trailing)) { activePage = .charts }
            quickCard(title: "最近唱过", icon: "clock.fill", gradient: LinearGradient(colors: [Color(hex: 0x8e44f7), Color(hex: 0xc736f7)], startPoint: .leading, endPoint: .trailing)) { activePage = .history }
            quickCard(title: "我的收藏", icon: "heart.fill", gradient: LinearGradient(colors: [Color(hex: 0xff8c42), Color(hex: 0xffb347)], startPoint: .leading, endPoint: .trailing)) { activePage = .favorites }
            quickCard(title: "最新入库", icon: "tray.full.fill", gradient: LinearGradient(colors: [Color(hex: 0x1a7bff), Color(hex: 0x36d9f7)], startPoint: .leading, endPoint: .trailing)) { activePage = .newest }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusSection()
    }

    private func quickCard(title: String, icon: String, gradient: LinearGradient, action: @escaping () -> Void) -> some View {
        @FocusState var focused: Bool
        return HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gradient.opacity(focused ? 1.0 : 0.35))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focused ? Color.white : Color.white.opacity(0.15), lineWidth: focused ? 3 : 1)
        )
        .shadow(color: focused ? Color.white.opacity(0.4) : .clear, radius: focused ? 12 : 0, x: 0, y: 0)
        .focusable(true)
        .focused($focused)
        .focusEffectDisabled()
        .scaleEffect(focused ? 1.08 : 0.96)
        .animation(Animation.easeOut(duration: 0.18), value: focused)
        .onTapGesture { action() }
    }

    // MARK: - QR Code View (exact #now-qr-code2)
    private var qrCodeView: some View {
        VStack(spacing: 6) {
            if let qrImage = generateQRCode(from: "http://\(api.serverAddress)/m") {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 60))
                    .frame(width: 96, height: 96)
            }
            Text("扫码点歌")
                .font(.system(size: 11))
                .foregroundColor(.black)
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

    // MARK: - Now Panel (exact #now-panel with video preview)
    private var nowPanel: some View {
        @FocusState var panelFocused: Bool
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black)

            if let playing = api.queue.first(where: { $0.isPlaying }),
               let hlsURL = api.hlsURL(songId: playing.song_id) {
                // Video preview using shared player
                // Use id to force rebuild when returning from fullscreen
                SharedVideoView(playerManager: playerManager)
                    .id("preview-\(showingPlayer ? "fs" : "normal")")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        playerManager.currentAudioTracks = playing.audio_tracks ?? 1
                        playerManager.setupPlayer(for: hlsURL)
                        playerManager.setVolume(volume)
                        // Re-attach layer after setup to ensure video shows
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            playerManager.attachLayerToCurrentHost()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            playerManager.attachLayerToCurrentHost()
                        }
                    }

                // Song intro animation (exact #song-intro)
                if showSongIntro, let intro = introSong {
                    songIntroView(song: intro)
                        .transition(.opacity)
                }

                // Bottom gradient info (exact #now-info)
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playing.displayTitle)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(playing.displayArtist)
                            .font(.system(size: 17))
                            .foregroundColor(WebColors.sub)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [Color.black.opacity(0.85), .clear],
                                               startPoint: .bottom, endPoint: .top))
                }
            } else {
                // Idle state (exact #now-idle)
                VStack(spacing: 10) {
                    Text("骏耀K歌")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [WebColors.ac2, WebColors.ac, WebColors.pink],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("扫码点歌 · 大屏沉浸演唱")
                        .font(.system(size: 14))
                        .foregroundColor(WebColors.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RadialGradient(colors: [WebColors.ac.opacity(0.2), .clear],
                                   center: UnitPoint(x: 0.3, y: 0.5), startRadius: 0, endRadius: 200)
                    .overlay(WebColors.navy)
                )
            }

            // QR Code corner (exact #now-qr-corner)
            if showQR {
                VStack {
                    HStack {
                        Spacer()
                        qrCodeView
                            .padding(10)
                            .background(Color.white.opacity(0.95))
                            .cornerRadius(10)
                            .padding(10)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(panelFocused ? WebColors.ac2 : Color.white.opacity(0.1), lineWidth: panelFocused ? 4 : 1)
        )
        .shadow(color: panelFocused ? WebColors.ac.opacity(0.8) : .clear, radius: panelFocused ? 20 : 0, x: 0, y: 0)
        .focusable(true)
        .focused($panelFocused)
        .focusEffectDisabled()
        .scaleEffect(panelFocused ? 1.03 : 0.98)
        .animation(.easeOut(duration: 0.18), value: panelFocused)
        .onTapGesture {
            if api.queue.contains(where: { $0.isPlaying }) {
                showingPlayer = true
            }
        }
        .onChange(of: api.queue.first(where: { $0.isPlaying })?.song_id) { newId in
            if let playing = api.queue.first(where: { $0.isPlaying }) {
                introSong = playing
                showSongIntro = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showSongIntro = false
                }
                // Setup new song in shared player
                if let url = api.hlsURL(songId: playing.song_id) {
                    playerManager.currentAudioTracks = playing.audio_tracks ?? 1
                    playerManager.setupPlayer(for: url)
                    playerManager.setVolume(volume)
                }
            } else {
                // No song playing
                playerManager.cleanup()
            }
            isPlaying = playerManager.isPlaying
            shouldResumePlaying = true
        }
        .focusSection()
    }

    private func setupControlHandler() {
        api.onControlMessage = { [weak api] action, payload in
            guard let api = api else { return }
            switch action {
            case "play_pause":
                playerManager.togglePlayPause()
                isPlaying = playerManager.isPlaying
            case "repeat":
                playerManager.restart()
            case "voice":
                playerManager.toggleVoice()
                showToast(playerManager.isOriginalVoice ? "原唱" : "伴唱")
            case "eq":
                if let name = payload["name"] as? String {
                    showToast("均衡器: \(name)")
                }
            case "volume":
                if let delta = payload["delta"] as? Float {
                    volume = max(0, min(1, volume + delta))
                    playerManager.setVolume(volume)
                    showToast("音量: \(Int(volume * 100))%")
                }
            case "next":
                api.nextSong()
            default:
                break
            }
        }
    }

    // MARK: - Song Intro View (exact #song-intro)
    private func songIntroView(song: QueueItem) -> some View {
        HStack(spacing: 22) {
            // Mic icon with pulse rings (exact .si-mic + .si-ring)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 76, height: 76)
                    .scaleEffect(1.3)
                    .opacity(0.0)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false), value: UUID())
                Circle()
                    .fill(LinearGradient(colors: [WebColors.ac, WebColors.pink],
                                         startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1)))
                    .frame(width: 76, height: 76)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }

            // Text (exact .si-text)
            VStack(alignment: .leading, spacing: 10) {
                Text(song.displayTitle)
                    .font(.system(size: 30, weight: .heavy))
                    .lineLimit(1)
                    .foregroundStyle(LinearGradient(colors: [.white, WebColors.ac2],
                                                    startPoint: .leading, endPoint: .trailing))
                Text(song.displayArtist)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 5)
                    .background(Color.white.opacity(0.14))
                    .cornerRadius(999)
                    .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [WebColors.ac.opacity(0.35), .clear],
                           center: UnitPoint(x: 0.22, y: 0.5), startRadius: 0, endRadius: 200)
            .overlay(LinearGradient(colors: [WebColors.navy, WebColors.bg],
                                    startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 1)))
        )
    }

    // MARK: - MV Ctrl (compact 7-button row, exact web style)
    private var mvCtrl: some View {
        HStack(spacing: 6) {
            MVButton(icon: "slider.horizontal.3", title: "均衡器") { activePanel = .eq }
            MVButton(icon: "mic", title: playerManager.isOriginalVoice ? "原唱" : "伴唱") {
                playerManager.toggleVoice()
                api.toggleVoice()
                showToast(playerManager.isOriginalVoice ? "原唱" : "伴唱")
            }
            MVButton(icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                    title: playerManager.isPlaying ? "暂停" : "播放", isCenter: true) {
                playerManager.togglePlayPause()
                isPlaying = playerManager.isPlaying
            }
            MVButton(icon: "speaker.minus", title: "音量-") {
                volume = max(0, volume - 0.1)
                playerManager.setVolume(volume)
                showToast("音量: \(Int(volume * 100))%")
            }
            MVButton(icon: "speaker.plus", title: "音量+") {
                volume = min(1, volume + 0.1)
                playerManager.setVolume(volume)
                showToast("音量: \(Int(volume * 100))%")
            }
            MVButton(icon: "forward.end.fill", title: "切歌") { api.nextSong() }
            MVButton(icon: "gobackward", title: "重唱") {
                playerManager.restart()
                api.restartSong()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .focusSection()
    }

    // MARK: - Mid Cards (vertical column, 4 buttons fill height)
    private var midCards: some View {
        VStack(spacing: 8) {
            bigRequestButton(title: "歌名点歌", icon: "music.note.list", gradient: LinearGradient(colors: [Color(hex: 0xff4f9b), Color(hex: 0xff6b6b)], startPoint: .leading, endPoint: .trailing)) { activePage = .order }
            bigRequestButton(title: "歌手点歌", icon: "mic.fill", gradient: LinearGradient(colors: [Color(hex: 0x8e44f7), Color(hex: 0xc736f7)], startPoint: .leading, endPoint: .trailing)) { activePage = .artists }
            bigRequestButton(title: "分类点歌", icon: "square.grid.2x2.fill", gradient: LinearGradient(colors: [Color(hex: 0xff8c42), Color(hex: 0xffb347)], startPoint: .leading, endPoint: .trailing)) { activePage = .category }
            bigRequestButton(title: "扫码点歌", icon: "qrcode", gradient: LinearGradient(colors: [Color(hex: 0x1a7bff), Color(hex: 0x36d9f7)], startPoint: .leading, endPoint: .trailing)) { showQR.toggle() }
        }
        .frame(maxHeight: .infinity)
        .focusSection()
    }

    private func bigRequestButton(title: String, icon: String, gradient: LinearGradient, action: @escaping () -> Void) -> some View {
        @FocusState var focused: Bool
        return HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gradient.opacity(focused ? 1.0 : 0.4))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(focused ? Color.white : Color.white.opacity(0.1), lineWidth: focused ? 4 : 1)
        )
        .shadow(color: focused ? WebColors.ac : .clear, radius: focused ? 16 : 0, x: 0, y: 0)
        .focusable(true)
        .focused($focused)
        .focusEffectDisabled()
        .scaleEffect(focused ? 1.06 : 0.97)
        .animation(Animation.easeOut(duration: 0.18), value: focused)
        .onTapGesture { action() }
    }

    private func queueRow(item: QueueItem, index: Int) -> some View {
        @FocusState var focused: Bool
        return HStack(spacing: 8) {
            if item.isPlaying {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(WebColors.ac2)
                    .font(.system(size: 16))
                    .frame(width: 20)
            } else {
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(focused ? .white : WebColors.sub)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(item.displayArtist)
                    .font(.system(size: 13))
                    .foregroundColor(focused ? .white.opacity(0.8) : WebColors.sub)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            item.isPlaying ? WebColors.ac.opacity(0.4) :
            focused ? WebColors.ac.opacity(0.45) : Color.white.opacity(0.03)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? WebColors.ac2 : (item.isPlaying ? WebColors.ac.opacity(0.5) : Color.clear), lineWidth: focused ? 3 : 1)
        )
        .shadow(color: focused ? WebColors.ac.opacity(0.6) : .clear, radius: focused ? 10 : 0, x: 0, y: 0)
        .focusable(true)
        .focused($focused)
        .focusEffectDisabled()
        .scaleEffect(focused ? 1.04 : 1.0)
        .animation(Animation.easeOut(duration: 0.15), value: focused)
        .onTapGesture {
            // Queue item tap - could play this song if API supports it
        }
    }

    // MARK: - Right Queue (exact #right-queue)
    private var rightQueue: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("♪ 已点队列")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(WebColors.ac2)
                Spacer()
                Text("\(api.queue.count)首")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(WebColors.sub)
            }

            if api.queue.isEmpty {
                Spacer()
                Text("暂无点歌")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(WebColors.sub)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(Array(api.queue.prefix(15).enumerated()), id: \.element.id) { idx, item in
                            queueRow(item: item, index: idx)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
        .background(
            Group {
                if appThemeRaw == 2 {
                    AppTheme.neonPanel
                } else if appThemeRaw == 3 {
                    Color(hex: 0x0a1525).opacity(0.6)
                } else {
                    LinearGradient(colors: [Color(hex: 0x0d0050), Color(hex: 0x1a0060), Color(hex: 0x2a0080)],
                                   startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
                }
            }
        )
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
            appThemeRaw == 2 ? WebColors.ac.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
        .focusSection()
    }

    // MARK: - Panel Views
    @ViewBuilder
    private func panelView(_ panel: PanelType) -> some View {
        switch panel {
        case .search:
            SearchPanel(api: api, onClose: { activePanel = nil })
        case .queue:
            QueuePanel(api: api, onClose: { activePanel = nil }, onPlay: { activePanel = nil; showingPlayer = true })
        case .settings:
            SettingsPanel(api: api, onClose: { activePanel = nil }, onThemeChange: { t in
                currentTheme = t
                appThemeRaw = t.rawValue
            })
        case .eq:
            EQPanel(onClose: { activePanel = nil })
        }
    }

    // MARK: - Page Views
    @ViewBuilder
    private func pageView(_ page: PageType) -> some View {
        switch page {
        case .order:
            OrderSongsPage(api: api, onBack: { activePage = nil },
                          onAdd: { song in api.addToQueue(songId: song.id); showToast("已点: \(song.displayTitle)") })
        case .artists:
            ArtistsPage(api: api, onBack: { activePage = nil }, onArtistSelect: { artist in
                selectedArtist = artist
                activePage = .artistSongs
            })
        case .artistSongs:
            ArtistSongsPage(api: api, artist: selectedArtist, onBack: { activePage = .artists })
        case .charts:
            ChartsPage(api: api, onBack: { activePage = nil })
        case .favorites:
            FavoritesPage(api: api, onBack: { activePage = nil })
        case .history:
            HistoryPage(api: api, onBack: { activePage = nil })
        case .newest:
            NewestPage(api: api, onBack: { activePage = nil })
        case .category:
            CategoryPage(api: api, onBack: { activePage = nil })
        }
    }

    // MARK: - Clock
    private var currentTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
    private var currentDate: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }

    // MARK: - Toast
    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}

// MARK: - Order Songs Page (歌名点歌 - left list + right alphabet panel)
struct OrderSongsPage: View {
    let api: KTVAPIClient
    let onBack: () -> Void
    let onAdd: (Song) -> Void
    @State private var currentPage = 0
    @State private var inputLetters = "" // Multi-letter pinyin initials input
    @State private var songPinyin: [Int: String] = [:] // Precomputed pinyin initials
    @State private var isCacheReady = false
    private let pageSize = 32
    private let letterRows: [[String]] = [
        ["A","B","C","D","E"],
        ["F","G","H","I","J"],
        ["K","L","M","N","O"],
        ["P","Q","R","S","T"],
        ["U","V","W","X","Y"],
        ["Z","DEL"]
    ]

    private func computePinyinInitials(_ text: String) -> String {
        var result = ""
        for char in text {
            if char.isLetter && char.isASCII {
                result.append(char.uppercased())
            } else if char.isLetter {
                result.append(pinyinFirstLetter(char))
            }
        }
        return result
    }

    private static var pinyinCharCache: [Character: String] = [:]
    private static let pinyinCacheLock = NSLock()

    private func pinyinFirstLetter(_ char: Character) -> String {
        OrderSongsPage.pinyinCacheLock.lock()
        if let cached = OrderSongsPage.pinyinCharCache[char] {
            OrderSongsPage.pinyinCacheLock.unlock()
            return cached
        }
        OrderSongsPage.pinyinCacheLock.unlock()

        let mutable = NSMutableString(string: String(char)) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let pinyin = mutable as String
        let result = pinyin.first.map { String($0).uppercased() } ?? "#"

        OrderSongsPage.pinyinCacheLock.lock()
        OrderSongsPage.pinyinCharCache[char] = result
        OrderSongsPage.pinyinCacheLock.unlock()

        return result
    }

    private func buildCache() {
        let songs = api.songs
        guard !songs.isEmpty else { return }
        isCacheReady = false
        DispatchQueue.global(qos: .userInitiated).async {
            var cache: [Int: String] = [:]
            for song in songs {
                cache[song.id] = computePinyinInitials(song.displayTitle)
            }
            DispatchQueue.main.async {
                self.songPinyin = cache
                self.isCacheReady = true
            }
        }
    }

    var filteredSongs: [Song] {
        if inputLetters.isEmpty { return api.songs }
        guard isCacheReady else { return [] }
        return api.songs.filter { song in
            guard let pinyin = songPinyin[song.id] else { return false }
            return pinyin.hasPrefix(inputLetters) || pinyin.contains(inputLetters)
        }
    }

    var pagedSongs: [Song] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, filteredSongs.count)
        return start < filteredSongs.count ? Array(filteredSongs[start..<end]) : []
    }

    var totalPages: Int { max(1, (filteredSongs.count + pageSize - 1) / pageSize) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundColor(WebColors.ac2)
                    Text("立即点歌")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(999)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(WebColors.topbarBg)

            // Main content: left song list + right alphabet panel
            HStack(spacing: 0) {
                // Left: song list (2 cols)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 10) {
                        ForEach(Array(pagedSongs.enumerated()), id: \.element.id) { idx, song in
                            songRow(song, index: currentPage * pageSize + idx)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)

                // Right: alphabet search panel
                VStack(spacing: 0) {
                    // Panel header with input display
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(WebColors.sub)
                        Text("歌名搜索")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        if inputLetters.isEmpty {
                            Text("全部")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(999)
                        } else {
                            Text(inputLetters)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                                .background(Color(hex: UInt32(0xb91c5c)).opacity(0.8))
                                .cornerRadius(999)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)

                    // Alphabet grid (5 cols)
                    VStack(spacing: 10) {
                        ForEach(letterRows, id: \.self) { row in
                            HStack(spacing: 10) {
                                ForEach(row, id: \.self) { letter in
                                    Button(action: {
                                        if letter == "DEL" {
                                            if !inputLetters.isEmpty {
                                                inputLetters.removeLast()
                                            }
                                        } else {
                                            inputLetters.append(letter)
                                        }
                                        currentPage = 0
                                    }) {
                                        if letter == "DEL" {
                                            HStack(spacing: 6) {
                                                Image(systemName: "delete.left")
                                                    .font(.system(size: 20, weight: .bold))
                                                Text("删除")
                                                    .font(.system(size: 20, weight: .bold))
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(Color(hex: 0x2a2a3a))
                                            .cornerRadius(10)
                                        } else {
                                            Text(letter)
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 56)
                                                .background(Color(hex: 0x2a2a3a))
                                                .cornerRadius(10)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Clear button
                    if !inputLetters.isEmpty {
                        Button(action: { inputLetters = ""; currentPage = 0 }) {
                            Text("清空")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }

                    Spacer()
                }
                .frame(width: 340)
                .background(Color(hex: 0x15151f))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Pagination footer
            HStack(spacing: 20) {
                Button(action: { if currentPage > 0 { currentPage -= 1 } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("上一页")
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .foregroundColor(currentPage > 0 ? .white : WebColors.sub)
                    .background(currentPage > 0 ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(999)
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)

                Text("第 \(currentPage + 1)/\(totalPages) (共\(filteredSongs.count)首)")
                    .font(.system(size: 18))
                    .foregroundColor(.white)

                Button(action: { if currentPage + 1 < totalPages { currentPage += 1 } }) {
                    HStack(spacing: 6) {
                        Text("下一页")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .foregroundColor(currentPage + 1 < totalPages ? .white : WebColors.sub)
                    .background(currentPage + 1 < totalPages ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(999)
                }
                .buttonStyle(.plain)
                .disabled(currentPage + 1 >= totalPages)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(WebColors.topbarBg)
        }
        .background(WebColors.bg.ignoresSafeArea())
        .onAppear {
            if api.songs.isEmpty {
                api.fetchSongs { buildCache() }
            } else {
                buildCache()
            }
        }
        .onChange(of: api.songs.count) { _ in buildCache() }
    }

    @ViewBuilder
    private func songRow(_ song: Song, index: Int) -> some View {
        HStack(spacing: 10) {
            // Number circle
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x9333ea), Color(hex: 0x6366f1)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(.system(size: 14))
                    .foregroundColor(WebColors.sub)
                    .lineLimit(1)
            }

            Spacer()

            // Favorite
            Button(action: { api.toggleFavorite(songId: song.id) }) {
                Image(systemName: api.favorites.contains { $0.id == song.id } ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundColor(api.favorites.contains { $0.id == song.id } ? WebColors.pink : Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            // Add button
            Button(action: { onAdd(song) }) {
                Text("点歌")
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(LinearGradient(colors: [Color(hex: 0x9333ea), Color(hex: 0x7c3aed)],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.card)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(hex: 0x1e1e2e))
        .cornerRadius(10)
    }
}

// MARK: - Video Preview (AVPlayerLayer without controls)
struct VideoPreview: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.playerLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var playerLayer: AVPlayerLayer?
    }
}
