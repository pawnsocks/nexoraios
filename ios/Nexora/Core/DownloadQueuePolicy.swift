import Foundation

enum DownloadQueuePolicy {
    static func releasedCount(status: String?, total: Int?, aired: Int?) -> Int? {
        let value = status == "FINISHED" ? total : aired
        guard let value, (0...9999).contains(value) else { return nil }
        return value
    }
    static func reordered<T>(_ original: [T], from offsets: IndexSet, to destination: Int) -> [T]? {
        guard offsets.allSatisfy({ original.indices.contains($0) }), (0...original.count).contains(destination) else { return nil }
        var rows = original
        let moving = offsets.sorted().map { original[$0] }
        for index in offsets.sorted(by: >) { rows.remove(at: index) }
        rows.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        return rows
    }
}
