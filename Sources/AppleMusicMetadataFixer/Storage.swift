import Foundation

final class AppStorage {
    let rootURL: URL
    private let fileManager = FileManager.default

    init() {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        rootURL = support.appendingPathComponent(
            "AppleMusicMetadataFixer",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: backupsURL,
            withIntermediateDirectories: true
        )
    }

    var stateURL: URL {
        rootURL.appendingPathComponent("state.json")
    }

    var backupsURL: URL {
        rootURL.appendingPathComponent("backups", isDirectory: true)
    }

    var temporaryURL: URL {
        let url = rootURL.appendingPathComponent("tmp", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func loadState() -> AppState {
        guard
            let data = try? Data(contentsOf: stateURL),
            let state = try? Self.decoder.decode(AppState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    func saveState(_ state: AppState) throws {
        let data = try Self.encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    func saveBackup(
        previousState: AppState,
        tracks: [TrackSnapshot]
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = RunBackup(
            createdAt: Date(),
            previousState: previousState,
            entries: tracks.map {
                BackupEntry(
                    persistentID: $0.persistentID,
                    name: $0.name,
                    album: $0.album,
                    artist: $0.artist,
                    albumArtist: $0.albumArtist,
                    sortName: $0.name,
                    sortAlbum: $0.album,
                    sortArtist: $0.artist,
                    sortAlbumArtist: $0.albumArtist
                )
            }
        )
        let url = backupsURL.appendingPathComponent(
            "\(formatter.string(from: Date())).json"
        )
        try Self.encoder.encode(backup).write(to: url, options: .atomic)
        return url
    }

    func loadLatestBackup() -> (URL, RunBackup)? {
        let files = (try? fileManager.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: nil
        )) ?? []
        let latest = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
        guard
            let latest,
            let data = try? Data(contentsOf: latest),
            let backup = try? Self.decoder.decode(RunBackup.self, from: data)
        else {
            return nil
        }
        return (latest, backup)
    }

    func writeTemporary<T: Encodable>(_ value: T, name: String) throws -> URL {
        let url = temporaryURL.appendingPathComponent(name)
        try Self.encoder.encode(value).write(to: url, options: .atomic)
        return url
    }

    func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = temporaryURL.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
