import SwiftUI

// MARK: - Full Page Container (exact .pd-full / .pf-head / .pf-body / .pf-foot)
struct FullPageContainer<Content: View>: View {
    let title: String
    let onBack: () -> Void
    let showPagination: Bool
    let currentPage: Int
    let totalPages: Int
    let onPageChange: (Int) -> Void
    @ViewBuilder let content: Content
    @FocusState private var backFocused: Bool

    init(title: String, onBack: @escaping () -> Void,
         showPagination: Bool = false, currentPage: Int = 1, totalPages: Int = 1,
         onPageChange: @escaping (Int) -> Void = { _ in },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.onBack = onBack
        self.showPagination = showPagination
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.onPageChange = onPageChange
        self.content = content()
    }

    var body: some View {
        ZStack {
            WebColors.bg.ignoresSafeArea()
            RadialGradient(colors: [WebColors.ac.opacity(0.1), .clear],
                           center: UnitPoint(x: 0.1, y: 0.3), startRadius: 0, endRadius: 400)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (exact .pf-head)
                HStack {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .font(.system(size: 17))
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .foregroundColor(backFocused ? WebColors.ac : .white)
                        .cornerRadius(999)
                        .overlay(RoundedRectangle(cornerRadius: 999)
                            .stroke(backFocused ? WebColors.ac : Color.white.opacity(0.25), lineWidth: 1))
                        .scaleEffect(backFocused ? 1.08 : 1.0)
                        .animation(.easeOut(duration: 0.2), value: backFocused)
                    }
                    .buttonStyle(.plain)
                    .focused($backFocused)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(WebColors.topbarBg)
                .overlay(Rectangle().fill(WebColors.topbarBorder).frame(height: 1), alignment: .bottom)

                // Body (exact .pf-body)
                content

                // Pagination footer (exact .pf-foot)
                if showPagination {
                    HStack(spacing: 16) {
                        Button(action: { if currentPage > 1 { onPageChange(currentPage - 1) } }) {
                            Image(systemName: "chevron.left.circle")
                                .font(.system(size: 28))
                                .foregroundColor(currentPage > 1 ? WebColors.ac : WebColors.sub)
                        }
                        .buttonStyle(.plain).disabled(currentPage <= 1)

                        Text("第 \(currentPage) / \(max(1, totalPages)) 页")
                            .font(.system(size: 15)).foregroundColor(WebColors.sub)

                        Button(action: { if currentPage < totalPages { onPageChange(currentPage + 1) } }) {
                            Image(systemName: "chevron.right.circle")
                                .font(.system(size: 28))
                                .foregroundColor(currentPage < totalPages ? WebColors.ac : WebColors.sub)
                        }
                        .buttonStyle(.plain).disabled(currentPage >= totalPages)
                    }
                    .padding(.vertical, 10).frame(maxWidth: .infinity)
                    .background(WebColors.topbarBg)
                    .overlay(Rectangle().fill(WebColors.topbarBorder).frame(height: 1), alignment: .top)
                }
            }
        }
        .onExitCommand { onBack() }
    }
}

// MARK: - Song List Row (exact .song-list-2col row)
struct WebSongRow: View {
    let song: Song
    let index: Int
    let showRank: Bool
    let onAdd: () -> Void
    let isFavorite: Bool
    let onToggleFav: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showRank {
                Text("\(index + 1)")
                    .font(.system(size: index < 3 ? 24 : 18, weight: index < 3 ? .bold : .medium))
                    .foregroundColor(index < 3 ? WebColors.ac : WebColors.sub)
                    .frame(width: 36)
            } else {
                Text("\(index + 1)").font(.system(size: 18, weight: .medium)).foregroundColor(WebColors.sub).frame(width: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(song.displayTitle).font(.system(size: 22, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    if song.hasMultiTrack {
                        Text("伴唱").font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(WebColors.ac2.opacity(0.3)).foregroundColor(WebColors.ac2).cornerRadius(5)
                    }
                }
                Text(song.displayArtist).font(.system(size: 18)).foregroundColor(WebColors.sub).lineLimit(1)
            }
            Spacer()

            Button(action: onToggleFav) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundColor(isFavorite ? WebColors.pink : .white)
                    .frame(width: 44, height: 44)
                    .background(isFavorite ? WebColors.pink.opacity(0.3) : WebColors.cardBg)
                    .cornerRadius(9)
            }.buttonStyle(.plain)

            Button(action: onAdd) {
                Text("点歌").font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(LinearGradient.g6).foregroundColor(.white).cornerRadius(10)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(focused ? WebColors.ac.opacity(0.15) : WebColors.cardBg)
        .cornerRadius(12)
        .scaleEffect(focused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
    }
}

// MARK: - Two Column Song List
struct TwoColSongList: View {
    let songs: [Song]
    let startIndex: Int
    let showRank: Bool
    let onAdd: (Song) -> Void
    let favorites: [Song]
    let onToggleFav: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                  spacing: 10) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                WebSongRow(song: song, index: startIndex + idx, showRank: showRank,
                           onAdd: { onAdd(song) },
                           isFavorite: favorites.contains { $0.id == song.id },
                           onToggleFav: { onToggleFav(song.id) })
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Artists Page (exact #pf-artists)
struct ArtistsPage: View {
    @ObservedObject var api: KTVAPIClient
    let onBack: () -> Void
    let onArtistSelect: (String) -> Void
    @State private var currentPage = 1
    @State private var inputLetters = ""
    @State private var artistPinyin: [String: String] = [:] // key: artist name, value: pinyin initials
    @State private var isCacheReady = false
    @State private var isLoading = true
    private let pageSize = 18
    private let letterRows: [[String]] = [
        ["A","B","C","D","E"],
        ["F","G","H","I","J"],
        ["K","L","M","N","O"],
        ["P","Q","R","S","T"],
        ["U","V","W","X","Y"],
        ["Z","DEL"]
    ]

    private static var pinyinCharCache: [Character: String] = [:]
    private static let pinyinCacheLock = NSLock()

    private func pinyinFirstLetter(_ char: Character) -> String {
        ArtistsPage.pinyinCacheLock.lock()
        if let cached = ArtistsPage.pinyinCharCache[char] {
            ArtistsPage.pinyinCacheLock.unlock()
            return cached
        }
        ArtistsPage.pinyinCacheLock.unlock()

        let mutable = NSMutableString(string: String(char)) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let pinyin = mutable as String
        let result = pinyin.first.map { String($0).uppercased() } ?? "#"

        ArtistsPage.pinyinCacheLock.lock()
        ArtistsPage.pinyinCharCache[char] = result
        ArtistsPage.pinyinCacheLock.unlock()

        return result
    }

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

    private func buildCache() {
        let artists = api.artists
        guard !artists.isEmpty else { return }
        isCacheReady = false
        DispatchQueue.global(qos: .userInitiated).async {
            var cache: [String: String] = [:]
            for artist in artists {
                cache[artist.artist] = computePinyinInitials(artist.displayName)
            }
            DispatchQueue.main.async {
                self.artistPinyin = cache
                self.isCacheReady = true
                self.isLoading = false
            }
        }
    }

    var filteredArtists: [Artist] {
        if inputLetters.isEmpty { return api.artists }
        guard isCacheReady else { return [] }
        return api.artists.filter { artist in
            guard let pinyin = artistPinyin[artist.artist] else { return false }
            return pinyin.hasPrefix(inputLetters) || pinyin.contains(inputLetters) ||
                   artist.displayName.localizedCaseInsensitiveContains(inputLetters)
        }
    }

    var pagedArtists: [Artist] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, filteredArtists.count)
        return start < filteredArtists.count ? Array(filteredArtists[start..<end]) : []
    }

    var totalPages: Int { max(1, (filteredArtists.count + pageSize - 1) / pageSize) }

    // Gradient colors for artist avatars (cycle through)
    private let avatarGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(hex: 0xf97316), Color(hex: 0xea580c)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0xa855f7), Color(hex: 0x7c3aed)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0x06b6d4), Color(hex: 0x0891b2)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0xec4899), Color(hex: 0xdb2777)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0x22c55e), Color(hex: 0x16a34a)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0xf59e0b), Color(hex: 0xd97706)], startPoint: .top, endPoint: .bottom)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 24))
                        .foregroundColor(WebColors.ac2)
                    Text("歌星")
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

            // Main: left artist grid + right alphabet panel
            HStack(spacing: 0) {
                // Left: artist grid (6 cols)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 6),
                              spacing: 20) {
                        ForEach(Array(pagedArtists.enumerated()), id: \.element.artist) { idx, artist in
                            Button(action: { onArtistSelect(artist.artist) }) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(avatarGradients[idx % avatarGradients.count])
                                            .frame(width: 90, height: 90)
                                        Text(String(artist.displayName.prefix(1)))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    Text(artist.displayName)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                    Text("\(artist.count)首")
                                        .font(.system(size: 14))
                                        .foregroundColor(WebColors.sub)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity)

                // Right: alphabet search panel
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(WebColors.sub)
                        Text("歌星搜索")
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

                    // Alphabet grid
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
                                        currentPage = 1
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
                                    if letter == "Z" {
                                        Spacer().frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Clear button
                    if !inputLetters.isEmpty {
                        Button(action: { inputLetters = ""; currentPage = 1 }) {
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
                Button(action: { if currentPage > 1 { currentPage -= 1 } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("上一页")
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .foregroundColor(currentPage > 1 ? .white : WebColors.sub)
                    .background(currentPage > 1 ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(999)
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 1)

                Text("第 \(currentPage)/\(totalPages) (共\(filteredArtists.count)位)")
                    .font(.system(size: 18))
                    .foregroundColor(.white)

                Button(action: { if currentPage < totalPages { currentPage += 1 } }) {
                    HStack(spacing: 6) {
                        Text("下一页")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .foregroundColor(currentPage < totalPages ? .white : WebColors.sub)
                    .background(currentPage < totalPages ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(999)
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(WebColors.topbarBg)
        }
        .background(WebColors.bg.ignoresSafeArea())
        .onAppear {
            isLoading = true
            api.fetchArtists {
                buildCache()
            }
        }
        .onChange(of: api.artists.count) { _ in
            if api.artists.count > 0 && !isCacheReady {
                buildCache()
            }
        }
    }
}

// MARK: - Alpha Keyboard (exact .alpha-panel)
struct AlphaKeyboard: View {
    @Binding var input: String
    @State private var isNumMode = false
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let numbers = Array("0123456789")

    var body: some View {
        VStack(spacing: 10) {
            // Display (exact .alpha-disp)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(WebColors.sub)
                Text(input.isEmpty ? "歌星搜索" : input)
                    .font(.system(size: 16)).foregroundColor(.white).lineLimit(1)
                Spacer()
                Button(action: { isNumMode.toggle() }) {
                    Text(isNumMode ? "ABC" : "123")
                        .font(.system(size: 14)).foregroundColor(WebColors.ac2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(WebColors.cardBg).cornerRadius(6)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(WebColors.cardBg).cornerRadius(8)

            // Keys (exact .alpha-keys)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible())], spacing: 6) {
                    let keys = isNumMode ? numbers : letters
                    ForEach(keys, id: \.self) { ch in
                        Button(action: { input.append(ch) }) {
                            Text(String(ch))
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(WebColors.cardBg)
                                .cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                    Button(action: { if !input.isEmpty { input.removeLast() } }) {
                        Text("删除")
                            .font(.system(size: 14))
                            .foregroundColor(WebColors.pink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(WebColors.pink.opacity(0.15))
                            .cornerRadius(6)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Artist Songs Page (exact #pf-artist-songs)
struct ArtistSongsPage: View {
    @ObservedObject var api: KTVAPIClient
    let artist: String
    let onBack: () -> Void
    @State private var currentPage = 1
    private let pageSize = 50

    var pagedSongs: [Song] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, api.songs.count)
        return start < api.songs.count ? Array(api.songs[start..<end]) : []
    }

    var body: some View {
        FullPageContainer(title: artist, onBack: onBack,
                         showPagination: true, currentPage: currentPage,
                         totalPages: max(1, (api.songs.count + pageSize - 1) / pageSize),
                         onPageChange: { currentPage = $0 }) {
            ScrollView {
                TwoColSongList(songs: pagedSongs, startIndex: (currentPage - 1) * pageSize,
                              showRank: false, onAdd: { api.addToQueue(songId: $0.id) },
                              favorites: api.favorites, onToggleFav: { api.toggleFavorite(songId: $0) })
            }
        }
        .onAppear { api.fetchSongs(artist: artist) }
    }
}

// MARK: - Charts Page (exact #pf-charts)
struct ChartsPage: View {
    @ObservedObject var api: KTVAPIClient
    let onBack: () -> Void

    var body: some View {
        FullPageContainer(title: "🏆 热歌榜单", onBack: onBack) {
            ScrollView {
                TwoColSongList(songs: api.charts, startIndex: 0, showRank: true,
                              onAdd: { api.addToQueue(songId: $0.id) },
                              favorites: api.favorites, onToggleFav: { api.toggleFavorite(songId: $0) })
            }
        }
        .onAppear { api.fetchCharts() }
    }
}

// MARK: - Favorites Page (exact #pf-favorites)
struct FavoritesPage: View {
    @ObservedObject var api: KTVAPIClient
    let onBack: () -> Void
    @State private var currentPage = 1
    private let pageSize = 50

    var pagedSongs: [Song] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, api.favorites.count)
        return start < api.favorites.count ? Array(api.favorites[start..<end]) : []
    }

    var body: some View {
        FullPageContainer(title: "❤️ 我的收藏", onBack: onBack,
                         showPagination: true, currentPage: currentPage,
                         totalPages: max(1, (api.favorites.count + pageSize - 1) / pageSize),
                         onPageChange: { currentPage = $0 }) {
            if api.favorites.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "heart").font(.system(size: 48)).foregroundColor(WebColors.sub)
                    Text("暂无收藏歌曲").font(.system(size: 16)).foregroundColor(WebColors.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            } else {
                ScrollView {
                    TwoColSongList(songs: pagedSongs, startIndex: (currentPage - 1) * pageSize,
                                  showRank: false, onAdd: { api.addToQueue(songId: $0.id) },
                                  favorites: api.favorites, onToggleFav: { api.toggleFavorite(songId: $0) })
                }
            }
        }
        .onAppear { api.fetchFavorites() }
    }
}

// MARK: - History Page (exact #pf-history)
struct HistoryPage: View {
    @ObservedObject var api: KTVAPIClient
    let onBack: () -> Void
    @State private var currentPage = 1
    private let pageSize = 50

    var pagedSongs: [Song] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, api.history.count)
        return start < api.history.count ? Array(api.history[start..<end]) : []
    }

    var body: some View {
        FullPageContainer(title: "⭐ 常唱", onBack: onBack,
                         showPagination: true, currentPage: currentPage,
                         totalPages: max(1, (api.history.count + pageSize - 1) / pageSize),
                         onPageChange: { currentPage = $0 }) {
            if api.history.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 48)).foregroundColor(WebColors.sub)
                    Text("暂无演唱记录").font(.system(size: 16)).foregroundColor(WebColors.sub)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            } else {
                ScrollView {
                    TwoColSongList(songs: pagedSongs, startIndex: (currentPage - 1) * pageSize,
                                  showRank: false, onAdd: { api.addToQueue(songId: $0.id) },
                                  favorites: api.favorites, onToggleFav: { api.toggleFavorite(songId: $0) })
                }
            }
        }
        .onAppear { api.fetchHistory() }
    }
}

// MARK: - Newest Page (exact #pf-newest)
struct NewestPage: View {
    @ObservedObject var api: KTVAPIClient
    let onBack: () -> Void
    @State private var currentPage = 1
    private let pageSize = 18

    var pagedSongs: [Song] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, api.newest.count)
        return start < api.newest.count ? Array(api.newest[start..<end]) : []
    }

    var body: some View {
        FullPageContainer(title: "🆕 最新入库", onBack: onBack,
                         showPagination: true, currentPage: currentPage,
                         totalPages: max(1, (api.newest.count + pageSize - 1) / pageSize),
                         onPageChange: { currentPage = $0 }) {
            ScrollView {
                TwoColSongList(songs: pagedSongs, startIndex: (currentPage - 1) * pageSize,
                              showRank: false, onAdd: { api.addToQueue(songId: $0.id) },
                              favorites: api.favorites, onToggleFav: { api.toggleFavorite(songId: $0) })
            }
        }
        .onAppear { api.fetchNewest() }
    }
}

// MARK: - Category Page (exact #pf-category)
struct CategoryPage: View {
    @ObservedObject var api: KTVAPIClient
    let onBack: () -> Void
    @State private var selectedLang: String? = nil
    @State private var selectedGenre: String? = nil
    @State private var currentPage = 1
    private let pageSize = 50

    let languages = ["国语", "粤语", "英语", "日语", "韩语", "其他"]
    let genres = ["流行", "摇滚", "民谣", "电子", "古典", "爵士", "乡村", "R&B", "其他"]

    var filteredSongs: [Song] {
        api.songs.filter { song in
            if let lang = selectedLang, song.language != lang { return false }
            if let genre = selectedGenre, song.category != genre { return false }
            return true
        }
    }

    var pagedSongs: [Song] {
        let start = (currentPage - 1) * pageSize
        let end = min(start + pageSize, filteredSongs.count)
        return start < filteredSongs.count ? Array(filteredSongs[start..<end]) : []
    }

    var body: some View {
        FullPageContainer(title: "🗂 分类点歌", onBack: onBack,
                         showPagination: true, currentPage: currentPage,
                         totalPages: max(1, (filteredSongs.count + pageSize - 1) / pageSize),
                         onPageChange: { currentPage = $0 }) {
            HStack(spacing: 0) {
                // Category panel (exact .cat-panel)
                VStack(alignment: .leading, spacing: 12) {
                    Text("语种").font(.system(size: 15, weight: .bold)).foregroundColor(WebColors.ac2)
                    WrapView(items: languages) { lang in
                        categoryChip(lang, isSelected: selectedLang == lang) {
                            selectedLang = selectedLang == lang ? nil : lang
                            currentPage = 1
                        }
                    }

                    Text("风格").font(.system(size: 15, weight: .bold)).foregroundColor(WebColors.ac2)
                        .padding(.top, 8)
                    WrapView(items: genres) { genre in
                        categoryChip(genre, isSelected: selectedGenre == genre) {
                            selectedGenre = selectedGenre == genre ? nil : genre
                            currentPage = 1
                        }
                    }
                }
                .frame(width: 280)
                .padding(16)
                .background(Color.black.opacity(0.3))

                // Song list (exact .song-list-2col)
                ScrollView {
                    TwoColSongList(songs: pagedSongs, startIndex: (currentPage - 1) * pageSize,
                                  showRank: false, onAdd: { api.addToQueue(songId: $0.id) },
                                  favorites: api.favorites, onToggleFav: { api.toggleFavorite(songId: $0) })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func categoryChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : WebColors.sub)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background {
                    if isSelected {
                        LinearGradient.g6
                    } else {
                        WebColors.cardBg
                    }
                }
                .cornerRadius(999)
                .overlay(RoundedRectangle(cornerRadius: 999)
                    .stroke(isSelected ? .clear : Color.white.opacity(0.12), lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
}

// MARK: - Wrap View (for category chips)
struct WrapView<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
