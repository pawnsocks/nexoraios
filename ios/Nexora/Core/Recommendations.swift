import Foundation

@MainActor final class Recommendations {
    static let shared = Recommendations()
    private var metadata: [Int: Anime] = [:]

    func forYou(api: API, catalogue: HomeData, excluding: Int? = nil) async -> [Anime] {
        let token = api.token
        guard token != nil else { return [] }
        do {
            async let favorites: CollectionResponse<Anime> = api.request("/library/favorites")
            async let watching: CollectionResponse<Anime> = api.request("/library/continue")
            async let history: CollectionResponse<Anime> = api.request("/library/history")
            let (saved, active, watched) = try await (favorites, watching, history)
            try Task.checkCancellation()
            let excluded = Set((saved.items + active.items + watched.items).map(\.id))
            var seeds: [Int: (anime: Anime, weight: Double)] = [:]
            // Favourite status is an explicit preference. Progress is a weaker,
            // positive signal; briefly opening an episode does not imply liking it.
            for anime in saved.items.prefix(12) { seeds[anime.id] = (anime, 3) }
            for anime in (active.items + watched.items).prefix(24) {
                let fraction = min(1, max(0, (anime.position ?? 0) / max(1, anime.duration ?? 1)))
                let progress = min(2, Double(max(0, (anime.episode ?? 1) - 1)) / 3 + fraction)
                guard progress >= 0.1 else { continue }
                if let old = seeds[anime.id] { seeds[anime.id] = (old.anime, max(old.weight, 1 + progress)) }
                else { seeds[anime.id] = (anime, 1 + progress) }
            }
            var profile: [String: Double] = [:]
            let strongest = seeds.values.sorted { $0.weight == $1.weight ? $0.anime.id < $1.anime.id : $0.weight > $1.weight }.prefix(16)
            for seed in strongest {
                try Task.checkCancellation()
                guard api.token == token else { return [] }
                var anime = metadata[seed.anime.id] ?? seed.anime
                if anime.genres == nil {
                    guard let detail: Anime = try? await api.request("/anime/\(anime.id)") else { continue }
                    anime = detail
                    if metadata.count >= 100 { metadata.removeAll(keepingCapacity: true) }
                    metadata[anime.id] = detail
                }
                let genres = Set(anime.genres ?? [])
                for genre in genres { profile[genre, default: 0] += seed.weight / Double(max(1, genres.count)) }
            }
            guard api.token == token, !profile.isEmpty else { return [] }
            var seen = Set<Int>()
            var ranked = (catalogue.popular + catalogue.airing).filter {
                $0.id != excluding && !excluded.contains($0.id) && seen.insert($0.id).inserted
            }.map { anime -> (anime: Anime, score: Double) in
                let genres = Set(anime.genres ?? [])
                let score = genres.reduce(0.0) { $0 + (profile[$1] ?? 0) } / sqrt(Double(max(1, genres.count)))
                return (anime, score)
            }.filter { $0.score > 0 }
            var selected: [Anime] = []
            var usedGenres: [String: Int] = [:]
            while !ranked.isEmpty && selected.count < 10 {
                // Mild diversity penalty avoids ten near-identical recommendations.
                func adjusted(_ item: (anime: Anime, score: Double)) -> Double {
                    let repeats = (item.anime.genres ?? []).reduce(0) { $0 + (usedGenres[$1] ?? 0) }
                    return item.score / (1 + Double(repeats) * 0.12)
                }
                ranked.sort { adjusted($0) == adjusted($1) ? $0.anime.id < $1.anime.id : adjusted($0) > adjusted($1) }
                let pick = ranked.removeFirst().anime
                selected.append(pick)
                for genre in pick.genres ?? [] { usedGenres[genre, default: 0] += 1 }
            }
            return selected
        } catch { return [] }
    }
}
