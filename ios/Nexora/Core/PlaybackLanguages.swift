import Foundation

enum PlaybackLanguages {
    static func order(_ preferred: String) -> [String] {
        let rest = ["Deutsch", "Ger-Sub"].contains(preferred) ? ["Deutsch", "Ger-Sub", "English", "Eng-Sub", "Original"] : ["English", "Eng-Sub", "Deutsch", "Ger-Sub", "Original"]
        var seen = Set<String>()
        return ([preferred] + rest).filter { seen.insert($0).inserted }
    }
    static func canRetry(_ status: Int) -> Bool { [404,502,503,504].contains(status) }
    static func label(_ value: String) -> String {
        ["English":"English audio", "Deutsch":"German audio", "Eng-Sub":"English subtitles", "Ger-Sub":"German subtitles", "Original":"Original audio"][value] ?? value
    }
}
