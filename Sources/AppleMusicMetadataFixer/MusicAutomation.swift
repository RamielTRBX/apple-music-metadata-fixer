import Foundation

struct MusicAutomation {
    private let storage: AppStorage

    init(storage: AppStorage) {
        self.storage = storage
    }

    func readTracks(
        since: Date,
        pendingPersistentIDs: [String]
    ) async throws -> [TrackSnapshot] {
        let request = ReadRequest(
            since: since.timeIntervalSince1970 * 1000,
            pendingPersistentIDs: pendingPersistentIDs
        )
        let data = try await executeScript(
            resource: "music_read",
            request: request
        )
        return try JSONDecoder().decode([TrackSnapshot].self, from: data)
    }

    func applyUpdates(_ updates: [TrackUpdate]) async throws -> ApplyResult {
        guard !updates.isEmpty else {
            return ApplyResult(updated: 0, missing: [])
        }
        let data = try await executeScript(
            resource: "music_apply",
            request: ApplyRequest(updates: updates)
        )
        return try JSONDecoder().decode(ApplyResult.self, from: data)
    }

    private func executeScript<T: Encodable>(
        resource: String,
        request: T
    ) async throws -> Data {
        let token = UUID().uuidString
        let requestURL = try storage.writeTemporary(
            request,
            name: "\(resource)-request-\(token).json"
        )
        let responseURL = storage.temporaryURL
            .appendingPathComponent("\(resource)-response-\(token).json")
        let scriptURL = try scriptURL(named: resource)

        defer {
            try? FileManager.default.removeItem(at: requestURL)
            try? FileManager.default.removeItem(at: responseURL)
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-l",
                "JavaScript",
                scriptURL.path,
                requestURL.path,
                responseURL.path
            ]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()

            do {
                try process.run()
            } catch {
                throw AppError.message("无法启动 Apple Music 自动化：\(error.localizedDescription)")
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw AppError.message(
                    detail?.isEmpty == false
                        ? detail!
                        : "Apple Music 没有响应。请在首次运行时允许自动化权限。"
                )
            }
            guard let data = try? Data(contentsOf: responseURL) else {
                throw AppError.message("Apple Music 返回了空结果。")
            }
            return data
        }.value
    }

    private func scriptURL(named name: String) throws -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            return url
        }
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let fallback = sourceDirectory.appendingPathComponent("\(name).js")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw AppError.message("缺少内部脚本：\(name).js")
        }
        return fallback
    }
}
