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
        let systemAsset = root.appendingPathComponent("System Assets/episode.movpkg")
        precondition(DownloadPath.stored(systemAsset, home: home) == nil)
        let stored = DownloadPath.stored(systemAsset, home: home, systemManaged: true)!
        precondition(stored == systemAsset.absoluteString)
        precondition(DownloadPath.restored(stored, home: home) == systemAsset)
        precondition(DownloadPath.stored(URL(string: "https://example.com/video")!, home: home, systemManaged: true) == nil)
        precondition(DownloadPath.stored(asset, home: home, systemManaged: true) == "Library/video.movpkg")
        precondition(DownloadPath.restored("Library/video.movpkg", home: home) == asset)
        precondition(DownloadPath.stored(URL(string: "file://remotehost/path/video")!, home: home, systemManaged: true) == nil)
        print("16 download destination checks passed")
    }
}
