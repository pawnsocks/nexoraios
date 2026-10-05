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
    var variants: [AnimeVariant]?
}
struct Season: Decodable, Identifiable { let id: Int; let title: String; let label: String }
struct Episode: Decodable, Identifiable { let id: Int; let title: String }
struct CollectionResponse<T: Decodable>: Decodable { let items: [T] }
struct EpisodesResponse: Decodable { let items: [Episode]; let has_next: Bool; let unknown: Bool }
struct CalendarEntry: Decodable, Identifiable { let id: Int; let episode: Int; let airing_at: Int; let anime: Anime }
struct HomeData: Decodable { let popular: [Anime]; let airing: [Anime]; let upcoming: [Anime]; let calendar: [CalendarEntry]; let calendar_note: String }
struct Account: Codable { let id: String; let username: String; var must_change_password: Bool?; var is_admin: Bool? }
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
    var source: MediaSource
    let has_prev: Bool
    let has_next: Bool
}
struct MediaSource: Decodable { let id: String?; var url: String; let content_type: String?; let language: String? }

struct EpisodeStatus: Decodable, Identifiable { let id: Int; let watched: Bool; let position: Double; let duration: Double? }

struct UndoResponse: Decodable { let ok: Bool; let undo_token: String? }

struct AnimeVariant: Codable, Hashable, Identifiable { let id: Int; let title: String; var cover: String? }
struct Announcement: Decodable, Identifiable { let id: String; let title: String; let body: String; let kind: String }
