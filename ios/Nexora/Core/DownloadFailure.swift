import Foundation

enum DownloadFailure {
    static func category(_ domain: String) -> String {
        if domain == NSURLErrorDomain { return "network" }
        if domain == NSCocoaErrorDomain { return "storage" }
        if domain == "AVFoundationErrorDomain" || domain == "CoreMediaErrorDomain" { return "media" }
        return "other"
    }
    static func retryable(domain: String, code: Int, status: Int?) -> Bool {
        if let status, [401,403,429].contains(status) { return false }
        return domain == "media" || (domain == "network" && [-1001,-1005,-1011].contains(code)) || [502,503,504].contains(status ?? 0)
    }
    static func message(domain: String, code: Int, status: Int?) -> String {
        let reference = " (\(domain) \(code)" + (status.map { ", HTTP \($0)" } ?? "") + ")."
        if status == 401 || status == 403 { return "Media access was denied or expired. Sign in again and tap Retry" + reference }
        if domain == "storage" { return "iOS could not save the video. Check available storage and tap Retry" + reference }
        if domain == "network" && code == -1009 { return "iOS reports no permitted connection. Check the selected download network" + reference }
        if domain == "network" && code == -1001 { return "The video source timed out. Tap Retry to request a fresh source" + reference }
        return "The source could not finish this download. Tap Retry; you do not need to delete the episode" + reference
    }
}
