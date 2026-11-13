import Foundation

actor ITunesClient {
    private var cache: [String: [OnlineTrack]] = [:]
    private var artworkCache: [String: UInt64?] = [:]

    func search(artist: String, album: String) async throws -> [OnlineTrack] {
        let term = "\(artist) \(album)"
        let key = normalized(term)
        if let cached = cache[key] {
            return cached
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: "jp"),
            URLQueryItem(name: "lang", value: "ja_jp"),
            URLQueryItem(name: "limit", value: "200")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue(
            "AppleMusicMetadataFixer/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("联网查询没有返回有效响应。")
        }
        if http.statusCode == 429 {
            throw AppError.message("在线曲库暂时限制了查询，请稍后再试。")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.message("在线曲库查询失败（HTTP \(http.statusCode)）。")
        }

        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        cache[key] = payload.results
        try await Task.sleep(nanoseconds: 220_000_000)
        return payload.results
    }

    func artworkHash(urlString: String) async -> UInt64? {
        if let cached = artworkCache[urlString] {
            return cached
        }
        let highResolution = urlString
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100-75", with: "600x600-75")
        guard let url = URL(string: highResolution) else {
            artworkCache[urlString] = nil
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "AppleMusicMetadataFixer/1.1",
            forHTTPHeaderField: "User-Agent"
        )
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            data.count <= 12_000_000
        else {
            artworkCache[urlString] = nil
            return nil
        }
        let hash = ArtworkHasher.hash(imageData: data)
        artworkCache[urlString] = hash
        return hash
    }
}
