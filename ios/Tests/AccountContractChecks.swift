import Foundation

@main struct AccountContractChecks {
    static func main() throws {
        let decoder = JSONDecoder()
        let first = try decoder.decode(Account.self, from: Data(#"{"id":"mobile:test","username":"test","must_change_password":true,"is_admin":false}"#.utf8))
        precondition(first.must_change_password == true)
        let existing = try decoder.decode(Account.self, from: Data(#"{"id":"mobile:test","username":"test"}"#.utf8))
        precondition(existing.must_change_password == nil)
        let grouped = try decoder.decode(Anime.self, from: Data(#"{"id":21,"title":"Example","variants":[{"id":-7,"title":"Example"}]}"#.utf8))
        precondition(grouped.variants?.first?.id == -7)
        let direct = try decoder.decode(EpisodesResponse.self, from: Data(#"{"items":[{"id":1099,"title":"Episode 1099"},{"id":1180,"title":"Episode 1180"}],"has_next":false,"unknown":false}"#.utf8))
        precondition(direct.items.map(\.id) == [1099, 1180])
        print("Account and catalogue contract checks passed")
    }
}
