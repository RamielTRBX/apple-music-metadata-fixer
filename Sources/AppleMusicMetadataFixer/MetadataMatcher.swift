import Foundation

struct MatchedGroup {
    let changes: [TrackUpdate]
    let resolvedPersistentIDs: Set<String>
    let displayChanges: [DisplayChange]
}

struct MetadataMatcher {
    let rules: CuratedRules
    let client: ITunesClient

    func match(_ tracks: [TrackSnapshot]) async -> MatchedGroup {
        guard let first = tracks.first else {
            return MatchedGroup(
                changes: [],
                resolvedPersistentIDs: [],
                displayChanges: []
            )
        }

        let curatedArtist = rules.artists[first.artist] ?? first.artist
        let curatedAlbum = rules.albums[first.album] ?? first.album
        let searchArtist = curatedArtist.isEmpty ? first.albumArtist : curatedArtist
        let searchAlbum = curatedAlbum.isEmpty ? first.album : curatedAlbum

        let results: [OnlineTrack]
        do {
            results = try await client.search(
                artist: searchArtist,
                album: searchAlbum
            )
        } catch {
            return directCuratedChanges(for: tracks, error: error.localizedDescription)
        }

        var candidate = bestCandidate(
            from: results,
            tracks: tracks,
            artist: searchArtist,
            album: searchAlbum
        )
        if candidate == nil {
            do {
                let titleResults = try await client.search(
                    artist: searchArtist,
                    album: first.name
                )
                candidate = bestCandidate(
                    from: titleResults,
                    tracks: tracks,
                    artist: searchArtist,
                    album: first.name
                )
            } catch {
                // The curated rules below are still applied if the fallback
                // network request fails.
            }
        }

        var updates: [TrackUpdate] = []
        var displays: [DisplayChange] = []
        var resolved = Set<String>()

        for track in tracks {
            let mappedArtist = rules.artists[track.artist] ?? track.artist
            let mappedAlbum = rules.albums[track.album] ?? track.album
            let mappedAlbumArtist: String
            if ["群星", "Various Artists"].contains(track.albumArtist) {
                mappedAlbumArtist = track.albumArtist
            } else if track.albumArtist.isEmpty {
                mappedAlbumArtist = mappedArtist
            } else {
                mappedAlbumArtist = rules.artists[track.albumArtist] ?? mappedArtist
            }
            let curatedTitle = rules.titles[
                titleAliasKey(artist: track.artist, title: track.name)
            ]

            var update = TrackUpdate(
                persistentID: track.persistentID,
                name: nil,
                sortName: nil,
                album: nil,
                sortAlbum: nil,
                artist: nil,
                sortArtist: nil,
                albumArtist: nil,
                sortAlbumArtist: nil
            )

            if let curatedTitle, curatedTitle != track.name {
                update.name = curatedTitle
                update.sortName = curatedTitle
            }

            if mappedAlbum != track.album {
                update.album = mappedAlbum
                update.sortAlbum = mappedAlbum
            }

            if mappedArtist != track.artist {
                update.artist = mappedArtist
                update.sortArtist = mappedArtist
            }

            if mappedAlbumArtist != track.albumArtist {
                update.albumArtist = mappedAlbumArtist
                update.sortAlbumArtist = mappedAlbumArtist
            }

            if let candidate {
                let onlineTrack = matchOnlineTrack(track, in: candidate.tracks)
                if let onlineTrack {
                    resolved.insert(track.persistentID)
                    if let title = onlineTrack.trackName,
                       shouldUseOnlineTitle(
                           current: update.name ?? track.name,
                           candidate: title,
                           hasCuratedTitle: curatedTitle != nil
                       ) {
                        update.name = title
                        update.sortName = title
                    }
                    if let album = onlineTrack.collectionName,
                       shouldUseOnlineAlbum(
                           current: update.album ?? track.album,
                           candidate: album,
                           hasCuratedAlbum: rules.albums[track.album] != nil
                       ) {
                        update.album = album
                        update.sortAlbum = album
                    }
                }
            }

            let finalTitle = update.name ?? track.name
            let finalAlbum = update.album ?? track.album
            if finalTitle != track.name || finalAlbum != track.album
                || update.artist != nil || update.albumArtist != nil {
                updates.append(update)
                displays.append(
                    DisplayChange(
                        persistentID: track.persistentID,
                        oldTitle: track.name,
                        newTitle: finalTitle,
                        oldAlbum: track.album,
                        newAlbum: finalAlbum,
                        oldArtist: track.artist,
                        newArtist: update.artist ?? track.artist
                    )
                )
            }
            if curatedTitle != nil || mappedAlbum != track.album
                || mappedArtist != track.artist {
                resolved.insert(track.persistentID)
            }
        }

        return MatchedGroup(
            changes: updates,
            resolvedPersistentIDs: resolved,
            displayChanges: displays
        )
    }

    private func directCuratedChanges(
        for tracks: [TrackSnapshot],
        error: String
    ) -> MatchedGroup {
        var changes: [TrackUpdate] = []
        var displays: [DisplayChange] = []
        var resolved = Set<String>()

        for track in tracks {
            let artist = rules.artists[track.artist] ?? track.artist
            let album = rules.albums[track.album] ?? track.album
            let albumArtist: String
            if ["群星", "Various Artists"].contains(track.albumArtist) {
                albumArtist = track.albumArtist
            } else if track.albumArtist.isEmpty {
                albumArtist = artist
            } else {
                albumArtist = rules.artists[track.albumArtist] ?? artist
            }
            let title = rules.titles[
                titleAliasKey(artist: track.artist, title: track.name)
            ] ?? track.name

            if title != track.name || album != track.album
                || artist != track.artist
                || albumArtist != track.albumArtist {
                changes.append(
                    TrackUpdate(
                        persistentID: track.persistentID,
                        name: title != track.name ? title : nil,
                        sortName: title != track.name ? title : nil,
                        album: album != track.album ? album : nil,
                        sortAlbum: album != track.album ? album : nil,
                        artist: artist != track.artist ? artist : nil,
                        sortArtist: artist != track.artist ? artist : nil,
                        albumArtist: albumArtist != track.albumArtist
                            ? albumArtist : nil,
                        sortAlbumArtist: albumArtist != track.albumArtist
                            ? albumArtist : nil
                    )
                )
                displays.append(
                    DisplayChange(
                        persistentID: track.persistentID,
                        oldTitle: track.name,
                        newTitle: title,
                        oldAlbum: track.album,
                        newAlbum: album,
                        oldArtist: track.artist,
                        newArtist: artist
                    )
                )
                resolved.insert(track.persistentID)
            }
        }

        _ = error
        return MatchedGroup(
            changes: changes,
            resolvedPersistentIDs: resolved,
            displayChanges: displays
        )
    }
}

private struct CandidateCollection {
    let id: Int
    let name: String
    let tracks: [OnlineTrack]
    let score: Double
}

private extension MetadataMatcher {
    func bestCandidate(
        from results: [OnlineTrack],
        tracks: [TrackSnapshot],
        artist: String,
        album: String
    ) -> CandidateCollection? {
        let grouped = Dictionary(
            grouping: results.filter {
                $0.collectionId != nil && $0.trackName != nil
            },
            by: { $0.collectionId! }
        )

        let ranked = grouped.compactMap { id, items -> CandidateCollection? in
            guard let name = items.first?.collectionName else { return nil }
            let candidateArtist = items.first?.artistName ?? ""
            var score = 0.0
            let albumMatch = normalized(name) == normalized(album)
            let mappedCandidateArtist = rules.artists[candidateArtist] ?? candidateArtist
            let artistMatch = normalized(mappedCandidateArtist) == normalized(artist)
            if albumMatch { score += 75 }
            if artistMatch { score += 45 }
            if !albumMatch,
               normalized(name).contains(normalized(album))
                    || normalized(album).contains(normalized(name)) {
                score += 30
            }
            if !artistMatch,
               normalized(mappedCandidateArtist).contains(normalized(artist))
                    || normalized(artist).contains(normalized(mappedCandidateArtist)) {
                score += 18
            }
            if containsJapanese(name) && !containsJapanese(album) {
                score += 12
            }

            let positions = Set(items.map { "\($0.discNumber ?? 1)-\($0.trackNumber ?? 0)" })
            let localPositions = tracks.map {
                "\($0.discNumber)-\($0.trackNumber)"
            }
            if localPositions.allSatisfy({ positions.contains($0) }) {
                score += 22
            }

            var durationMatches = 0
            for track in tracks {
                guard let online = matchOnlineTrack(track, in: items),
                      let millis = online.trackTimeMillis else { continue }
                let difference = abs(Double(millis) / 1000.0 - track.duration)
                if difference <= 3 { score += 8; durationMatches += 1 }
                else if difference <= 7 { score += 3; durationMatches += 1 }
            }
            if durationMatches == tracks.count { score += 10 }

            return CandidateCollection(
                id: id,
                name: name,
                tracks: items,
                score: score
            )
        }

        guard let best = ranked.sorted(by: { $0.score > $1.score }).first else {
            return nil
        }
        return best.score >= 72 ? best : nil
    }

    func matchOnlineTrack(
        _ local: TrackSnapshot,
        in candidates: [OnlineTrack]
    ) -> OnlineTrack? {
        let exactPosition = candidates.filter {
            ($0.discNumber ?? 1) == local.discNumber
                && ($0.trackNumber ?? 0) == local.trackNumber
        }
        if let exact = exactPosition.first,
           durationMatches(local, exact) {
            return exact
        }

        let titleMatches = candidates.filter {
            normalized($0.trackName ?? "") == normalized(local.name)
        }
        if let titleMatch = titleMatches.first(where: {
            durationMatches(local, $0)
        }) {
            return titleMatch
        }

        return candidates
            .filter { durationMatches(local, $0) }
            .min {
                durationDifference(local, $0) < durationDifference(local, $1)
            }
    }

    func durationMatches(_ local: TrackSnapshot, _ online: OnlineTrack) -> Bool {
        guard online.trackTimeMillis != nil else { return false }
        return durationDifference(local, online) <= 7
    }

    func durationDifference(_ local: TrackSnapshot, _ online: OnlineTrack) -> Double {
        guard let millis = online.trackTimeMillis else { return .infinity }
        return abs(Double(millis) / 1000.0 - local.duration)
    }

    func shouldUseOnlineTitle(
        current: String,
        candidate: String,
        hasCuratedTitle: Bool
    ) -> Bool {
        guard current != candidate else { return false }
        if normalized(current) == normalized(candidate) { return false }
        // Lyrics do not determine title language. If the current official
        // title is already Japanese or Chinese, never replace it with an
        // English alternative from another catalog edition.
        if containsJapanese(current) && !containsJapanese(candidate) {
            return false
        }
        if hasCuratedTitle { return true }
        if !containsJapanese(current) && !containsJapanese(candidate) {
            return true
        }
        return containsJapanese(candidate) && !containsJapanese(current)
    }

    func shouldUseOnlineAlbum(
        current: String,
        candidate: String,
        hasCuratedAlbum: Bool
    ) -> Bool {
        guard current != candidate else { return false }
        if normalized(current) == normalized(candidate) { return false }
        if containsJapanese(current) && !containsJapanese(candidate) {
            return false
        }
        if hasCuratedAlbum { return true }
        if !containsJapanese(current) && !containsJapanese(candidate) {
            return true
        }
        return containsJapanese(candidate) && !containsJapanese(current)
    }
}
