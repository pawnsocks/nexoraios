import Foundation

/// Store container-relative locations, accepting equivalent filesystem aliases.
enum DownloadPath {
    static func relative(_ location: URL, home: URL) -> String? {
        guard location.scheme == nil || location.isFileURL else { return nil }
        let candidate: URL
        if location.baseURL != nil || location.path.hasPrefix("/") {
            candidate = location.absoluteURL
        } else {
            candidate = home.appendingPathComponent(location.relativePath)
        }
        let base = home.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let target = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else { return nil }
        return target.dropFirst(base.count).joined(separator: "/")
    }
}
