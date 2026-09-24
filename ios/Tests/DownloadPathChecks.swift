import Foundation

@main struct DownloadPathChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("container", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: alias, withDestinationURL: home)
        let asset = home.appendingPathComponent("Library/video.movpkg")
        precondition(DownloadPath.relative(asset, home: home) == "Library/video.movpkg")
        precondition(DownloadPath.relative(asset, home: alias) == "Library/video.movpkg")
        precondition(DownloadPath.relative(alias.appendingPathComponent("Library/video.movpkg"), home: home) == "Library/video.movpkg")
        precondition(DownloadPath.relative(URL(string: "Library/video.movpkg")!, home: home) == "Library/video.movpkg")
        precondition(DownloadPath.relative(home, home: home) == nil)
        precondition(DownloadPath.relative(root.appendingPathComponent("container-other/video"), home: home) == nil)
        precondition(DownloadPath.relative(URL(string: "../outside.movpkg")!, home: home) == nil)
        precondition(DownloadPath.relative(URL(string: "https://example.com/video")!, home: home) == nil)
        try fm.createSymbolicLink(at: home.appendingPathComponent("escape"), withDestinationURL: root)
        precondition(DownloadPath.relative(home.appendingPathComponent("escape/outside"), home: home) == nil)
        print("9 download destination checks passed")
    }
}
