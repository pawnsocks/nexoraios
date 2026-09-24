import Foundation

/// Store container-relative locations, accepting equivalent filesystem aliases.
enum DownloadPath {
    private static func canonical(_ url: URL) -> URL {
        // The download package may not exist yet. Resolve its existing ancestor.
        var ancestor = url.standardizedFileURL
        var remaining: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path) && ancestor.path != "/" {
            remaining.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in remaining.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    static func relative(_ location: URL, home: URL) -> String? {
        guard location.scheme == nil || location.isFileURL else { return nil }
        let candidate: URL
        if location.baseURL != nil || location.path.hasPrefix("/") {
            candidate = location.absoluteURL
        } else {
            candidate = home.appendingPathComponent(location.relativePath)
        }
        let base = canonical(home).pathComponents
        let target = canonical(candidate).pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else { return nil }
        return target.dropFirst(base.count).joined(separator: "/")
    }
}
