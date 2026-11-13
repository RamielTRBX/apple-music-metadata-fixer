import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var isRunning = false
    @Published var status = "准备检查新增歌曲…"
    @Published var progress = 0.0
    @Published var checkedCount = 0
    @Published var changedCount = 0
    @Published var skippedCount = 0
    @Published var changes: [DisplayChange] = []
    @Published var unresolvedTracks: [TrackSnapshot] = []
    @Published var attentionTracks: [TrackSnapshot] = []
    @Published var likelyCorrectTracks: [TrackSnapshot] = []
    @Published var errorMessage: String?
    @Published var canUndo = false

    private let storage = AppStorage()
    private lazy var music = MusicAutomation(storage: storage)
    private let client = ITunesClient()
    private let isDryRun = ProcessInfo.processInfo.arguments.contains("--dry-run")
    private var hasStarted = false

    init() {
        refreshUndoAvailability()
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        await run()
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        changes = []
        unresolvedTracks = []
        attentionTracks = []
        likelyCorrectTracks = []
        errorMessage = nil
        checkedCount = 0
        changedCount = 0
        skippedCount = 0

        do {
            let runStart = Date()
            var state = storage.loadState()
            let defaultStart = Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: runStart
            ) ?? runStart
            let cutoff = state.lastSuccessfulRun ?? defaultStart

            status = "正在读取 Apple Music 新增歌曲…"
            let tracks = try await music.readTracks(
                since: cutoff,
                pendingPersistentIDs: state.pendingPersistentIDs
            ).filter { !$0.isPlaceholder }
            checkedCount = tracks.count

            guard !tracks.isEmpty else {
                if !isDryRun {
                    state.lastSuccessfulRun = runStart
                    state.pendingPersistentIDs = []
                    try storage.saveState(state)
                }
                status = "没有发现需要检查的新增歌曲"
                progress = 1
                isRunning = false
                refreshUndoAvailability()
                return
            }

            let grouped = Dictionary(grouping: tracks) {
                "\(normalized($0.artist))|\(normalized($0.album))"
            }
            let sortedGroups = grouped.values.sorted {
                ($0.first?.artist ?? "") < ($1.first?.artist ?? "")
            }
            let matcher = MetadataMatcher(
                rules: try loadRules(),
                client: client
            )

            var allUpdates: [TrackUpdate] = []
            var allDisplays: [DisplayChange] = []
            var resolved = Set<String>()

            for (index, group) in sortedGroups.enumerated() {
                let artist = group.first?.artist ?? "未知艺人"
                let album = group.first?.album ?? "未知专辑"
                status = "正在核对：\(artist) — \(album)"
                let matched = await matcher.match(group)
                allUpdates.append(contentsOf: matched.changes)
                allDisplays.append(contentsOf: matched.displayChanges)
                resolved.formUnion(matched.resolvedPersistentIDs)
                progress = 0.15 + 0.65 * Double(index + 1) / Double(sortedGroups.count)
            }

            if allUpdates.isEmpty {
                unresolvedTracks = tracks.filter {
                    !resolved.contains($0.persistentID)
                }
                classifyUnresolved()
                skippedCount = unresolvedTracks.count
                if !isDryRun {
                    state.lastSuccessfulRun = runStart
                    state.pendingPersistentIDs = tracks
                        .map(\.persistentID)
                        .filter { !resolved.contains($0) }
                    try storage.saveState(state)
                }
                changes = []
                status = skippedCount == 0
                    ? "检查完成，新增歌曲的名称已经正确"
                    : "检查完成，\(skippedCount) 首无法可靠匹配"
                progress = 1
                isRunning = false
                refreshUndoAvailability()
                return
            }

            if isDryRun {
                changes = allDisplays
                let changedIDs = Set(allUpdates.map(\.persistentID))
                unresolvedTracks = tracks.filter {
                    !resolved.contains($0.persistentID)
                        && !changedIDs.contains($0.persistentID)
                }
                classifyUnresolved()
                changedCount = allUpdates.count
                skippedCount = unresolvedTracks.count
                let previewURL = storage.rootURL
                    .appendingPathComponent("last-preview.json")
                try? JSONEncoder()
                    .encode(allUpdates)
                    .write(to: previewURL, options: .atomic)
                status = "预览完成：将修正 \(changedCount) 首歌曲"
                progress = 1
                isRunning = false
                refreshUndoAvailability()
                return
            }

            let changedIDs = Set(allUpdates.map(\.persistentID))
            let changedTracks = tracks.filter {
                changedIDs.contains($0.persistentID)
            }
            let backupURL = try storage.saveBackup(
                previousState: state,
                tracks: changedTracks
            )

            status = "正在写入 Apple Music…"
            let result = try await music.applyUpdates(allUpdates)
            if !result.missing.isEmpty {
                throw AppError.message(
                    "有 \(result.missing.count) 首歌在写入前已不在资料库中。"
                )
            }

            state.lastSuccessfulRun = runStart
            state.lastBackupPath = backupURL.path
            state.pendingPersistentIDs = tracks
                .map(\.persistentID)
                .filter { !resolved.contains($0) && !changedIDs.contains($0) }
            try storage.saveState(state)

            changes = allDisplays
            unresolvedTracks = tracks.filter {
                !resolved.contains($0.persistentID)
                    && !changedIDs.contains($0.persistentID)
            }
            classifyUnresolved()
            changedCount = allDisplays.count
            skippedCount = unresolvedTracks.count
            progress = 1
            status = changedCount > 0
                ? "完成：已修正 \(changedCount) 首歌曲"
                : "检查完成，歌曲名称已经正确"
            isRunning = false
            refreshUndoAvailability()
        } catch {
            errorMessage = error.localizedDescription
            unresolvedTracks = []
            attentionTracks = []
            likelyCorrectTracks = []
            status = "处理未完成"
            progress = 0
            isRunning = false
            refreshUndoAvailability()
        }
    }

    func undoLastRun() async {
        guard !isRunning else { return }
        guard let (url, backup) = storage.loadLatestBackup() else {
            errorMessage = "没有可撤销的修改。"
            canUndo = false
            return
        }

        isRunning = true
        errorMessage = nil
        status = "正在撤销上次修改…"
        progress = 0.35
        let updates = backup.entries.map {
            TrackUpdate(
                persistentID: $0.persistentID,
                name: $0.name,
                sortName: $0.sortName,
                album: $0.album,
                sortAlbum: $0.sortAlbum,
                artist: $0.artist,
                sortArtist: $0.sortArtist,
                albumArtist: $0.albumArtist,
                sortAlbumArtist: $0.sortAlbumArtist
            )
        }

        do {
            _ = try await music.applyUpdates(updates)
            var restored = backup.previousState
            restored.lastBackupPath = nil
            try storage.saveState(restored)
            try? FileManager.default.removeItem(at: url)
            status = "已撤销 \(updates.count) 首歌曲的名称修改"
            progress = 1
            isRunning = false
            refreshUndoAvailability()
        } catch {
            errorMessage = error.localizedDescription
            status = "撤销失败"
            isRunning = false
        }
    }

    private func refreshUndoAvailability() {
        canUndo = storage.loadLatestBackup() != nil
    }

    private func classifyUnresolved() {
        attentionTracks = unresolvedTracks.filter(likelyNeedsJapaneseMetadata)
        likelyCorrectTracks = unresolvedTracks.filter {
            !likelyNeedsJapaneseMetadata($0)
        }
    }

    private func loadRules() throws -> CuratedRules {
        if let url = Bundle.main.url(
            forResource: "curated_rules",
            withExtension: "json"
        ) {
            return try JSONDecoder().decode(
                CuratedRules.self,
                from: Data(contentsOf: url)
            )
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("curated_rules.json")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            return .empty
        }
        return try JSONDecoder().decode(
            CuratedRules.self,
            from: Data(contentsOf: fallback)
        )
    }
}
