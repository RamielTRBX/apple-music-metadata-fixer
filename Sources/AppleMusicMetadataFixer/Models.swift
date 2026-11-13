import Foundation

struct TrackSnapshot: Codable, Identifiable, Hashable {
    let persistentID: String
    let databaseID: Int
    let name: String
    let artist: String
    let albumArtist: String
    let album: String
    let genre: String
    let discNumber: Int
    let discCount: Int
    let trackNumber: Int
    let trackCount: Int
    let duration: Double
    let dateAdded: Double
    let artworkHexPath: String?
    var artworkHash: UInt64?

    var id: String { persistentID }
    var position: String {
        if discCount > 1 {
            return "Disc \(discNumber) · 曲 \(trackNumber)"
        }
        return "曲 \(trackNumber)"
    }

    var isPlaceholder: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        return trackNumber == 0
            && !cleanName.isEmpty
            && !cleanAlbum.isEmpty
            && cleanName.allSatisfy(\.isNumber)
            && cleanAlbum.allSatisfy(\.isNumber)
    }
}

struct ReadRequest: Codable {
    let since: Double
    let pendingPersistentIDs: [String]
    let artworkDirectory: String
}

struct TrackUpdate: Codable, Identifiable {
    var persistentID: String
    var name: String?
    var sortName: String?
    var album: String?
    var sortAlbum: String?
    var artist: String?
    var sortArtist: String?
    var albumArtist: String?
    var sortAlbumArtist: String?

    var id: String { persistentID }
}

struct ApplyRequest: Codable {
    let updates: [TrackUpdate]
}

struct ApplyResult: Codable {
    let updated: Int
    let missing: [String]
}

struct BackupEntry: Codable {
    let persistentID: String
    let name: String
    let album: String
    let artist: String
    let albumArtist: String
    let sortName: String
    let sortAlbum: String
    let sortArtist: String
    let sortAlbumArtist: String
}

struct AppState: Codable {
    var lastSuccessfulRun: Date?
    var pendingPersistentIDs: [String]
    var lastBackupPath: String?

    static let empty = AppState(
        lastSuccessfulRun: nil,
        pendingPersistentIDs: [],
        lastBackupPath: nil
    )
}

struct RunBackup: Codable {
    let createdAt: Date
    let previousState: AppState
    let entries: [BackupEntry]
}

struct CuratedRules: Codable {
    var artists: [String: String]
    var albums: [String: String]
    var titles: [String: String]

    static let empty = CuratedRules(artists: [:], albums: [:], titles: [:])
}

struct SearchResponse: Decodable {
    let resultCount: Int
    let results: [OnlineTrack]
}

struct OnlineTrack: Decodable {
    let artistName: String?
    let collectionId: Int?
    let collectionName: String?
    let trackName: String?
    let trackNumber: Int?
    let discNumber: Int?
    let trackCount: Int?
    let releaseDate: String?
    let trackTimeMillis: Int?
    let artworkUrl100: String?
}

struct DisplayChange: Identifiable, Codable {
    let persistentID: String
    let oldTitle: String
    let newTitle: String
    let oldAlbum: String
    let newAlbum: String
    let oldArtist: String
    let newArtist: String

    var id: String { persistentID }
}

struct RunOutcome {
    let checked: Int
    let changed: Int
    let skipped: Int
    let changes: [DisplayChange]
    let message: String?
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}

func normalized(_ value: String) -> String {
    let comparable = value.applyingTransform(
        StringTransform("Hant-Hans"),
        reverse: false
    ) ?? value
    let folded = comparable
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "ja_JP")
        )
        .lowercased()
    let kept = folded.unicodeScalars.filter { scalar in
        CharacterSet.alphanumerics.contains(scalar)
    }
    return String(String.UnicodeScalarView(kept))
}

func containsJapanese(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

func containsKana(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        (0x3040...0x30FF).contains(scalar.value)
    }
}

func containsHan(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        (0x3400...0x9FFF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }
}

func likelyNeedsJapaneseMetadata(_ track: TrackSnapshot) -> Bool {
    let japaneseGenres = [
        "J-Pop",
        "Kayokyoku",
        "Anime",
        "Video Game",
        "TV Soundtrack"
    ]
    if japaneseGenres.contains(track.genre) {
        return true
    }
    if containsKana(track.name) || containsKana(track.album) {
        return true
    }
    if containsHan(track.name) || containsHan(track.album) {
        return !["Mandopop", "Cantopop/HK-Pop"].contains(track.genre)
    }
    return false
}

func titleAliasKey(artist: String, title: String) -> String {
    "\(normalized(artist))|\(normalized(title))"
}
