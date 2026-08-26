import Foundation

/// Strip filename prefix like "N5c6d89ad::" that leaks into artist/title fields
private func cleanName(_ raw: String?) -> String? {
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return raw }
    // Remove prefix pattern: N + 8 hex chars + "::"
    if let range = s.range(of: #"^N[0-9a-fA-F]{8}::"#, options: .regularExpression) {
        s = String(s[range.upperBound...])
    }
    return s
}

struct Song: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let artist: String?
    let filename: String?
    let filepath: String?
    let cover: String?
    let duration: Int?
    let audio_tracks: Int?
    let play_count: Int?
    let category: String?
    let genre: String?
    let language: String?
    let source: String?

    var displayTitle: String { cleanName(title) ?? cleanName(filename) ?? "未知歌曲" }
    var displayArtist: String { cleanName(artist) ?? "未知歌手" }
    var hasMultiTrack: Bool { (audio_tracks ?? 1) >= 2 }
    var durationText: String {
        guard let d = duration else { return "" }
        return String(format: "%d:%02d", d / 60, d % 60)
    }
}

struct QueueItem: Codable, Identifiable, Hashable {
    let queue_id: Int
    let nickname: String?
    let is_top: Int?
    let status: String?
    let song_id: Int
    let title: String?
    let artist: String?
    let filename: String?
    let cover: String?
    let duration: Int?
    let audio_tracks: Int?

    var id: Int { queue_id }
    var displayTitle: String { cleanName(title) ?? cleanName(filename) ?? "未知歌曲" }
    var displayArtist: String { cleanName(artist) ?? "未知歌手" }
    var isPlaying: Bool { status == "playing" }
    var isTop: Bool { (is_top ?? 0) == 1 }
    var hasMultiTrack: Bool { (audio_tracks ?? 1) >= 2 }
}

struct Artist: Codable, Identifiable, Hashable {
    let artist: String
    let count: Int
    var id: String { artist }
    var displayName: String { cleanName(artist) ?? "未知歌手" }
}

struct Category: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let type: CategoryType
}

enum CategoryType: String {
    case newest, charts, favorites, history, artists, category, order
}

struct Stats: Codable {
    let songCount: Int?
    let queueCount: Int?
    let totalPlays: Int?
    let appVersion: String?
}

struct AutoplaySettings: Codable {
    var enabled: Bool
    var localOnly: Bool
}
