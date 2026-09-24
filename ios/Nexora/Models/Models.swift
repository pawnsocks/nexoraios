import Foundation

struct Anime: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    var cover: String?
    var banner: String?
    var description: String?
    var year: Int?
    var format: String?
    var status: String?
    var episodes: Int?
    var aired_episodes: Int?
    var genres: [String]?
    var episode: Int?
    var position: Double?
    var duration: Double?
}
struct Season: Decodable, Identifiable { let id: Int; let title: String; let label: String }
struct Episode: Decodable, Identifiable { let id: Int; let title: String }
struct CollectionResponse<T: Decodable>: Decodable { let items: [T] }
struct EpisodesResponse: Decodable { let items: [Episode]; let has_next: Bool; let unknown: Bool }
struct CalendarEntry: Decodable, Identifiable { let id: Int; let episode: Int; let airing_at: Int; let anime: Anime }
struct HomeData: Decodable { let popular: [Anime]; let airing: [Anime]; let upcoming: [Anime]; let calendar: [CalendarEntry]; let calendar_note: String }
struct Account: Codable { let id: String; let username: String }
struct LoginResponse: Decodable { let token: String; let account: Account }
struct OK: Decodable { let ok: Bool }
struct ReleaseInfo: Decodable { let api_version: Int; let latest: String; let minimum: String; let url: String?; let notes: String }
struct Playback: Decodable, Identifiable {
    var id: String { session_id }
    let session_id: String
    let anime_id: Int
    let anime_title: String
    let episode_number: Int
    let resume_seconds: Double?
    let source: MediaSource
    let has_prev: Bool
    let has_next: Bool
}
struct MediaSource: Decodable { let url: String; let content_type: String?; let language: String? }
