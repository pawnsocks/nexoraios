import Foundation
import Combine
import AVFoundation
import UIKit
import Network

struct OfflineEpisode: Codable, Identifiable {
    var id: String
    let title: String
    let owner: String
    let episode: Int
    let language: String
    var queued: Bool?
    var animeID: Int?
    var wifiOnly: Bool?
    var location: String?
    var progress: Double = 0
    var error: String?
}

@MainActor final class DownloadStore: NSObject, ObservableObject, AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    static let shared = DownloadStore()
    var backgroundCompletions: [String: () -> Void] = [:]
    @Published var items: [OfflineEpisode] = []
    @Published var message: String?
    @Published var usedBytes: Int64 = 0
    @Published var queuePaused = UserDefaults.standard.bool(forKey: "downloadQueuePaused")
    private weak var api: API?
    private var ready = false
    private var pumping = false
    @Published var preparingID: String?
    private var queueWatch: Task<Void, Never>?
    private var online = false
    private var onWiFi = false
    private let monitor = NWPathMonitor()
    private var transferred: [String: Int64] = [:]
    private var lastQuotaCheck = Date.distantPast
    var autoDelete: Bool { UserDefaults.standard.object(forKey: "downloadAutoDelete") as? Bool ?? true }
    var limitBytes: Int64 { Int64(max(1, UserDefaults.standard.integer(forKey: "downloadLimitGB") == 0 ? 5 : UserDefaults.standard.integer(forKey: "downloadLimitGB"))) * 1_000_000_000 }
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Offline", isDirectory: true)
    private var manifest: URL { directory.appendingPathComponent("episodes.json") }
    private lazy var hls: AVAssetDownloadURLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "org.nexora.offline.hls")
        config.isDiscretionary = false
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.httpMaximumConnectionsPerHost = 2
        return AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }()
    private lazy var files: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "org.nexora.offline.files")
        config.isDiscretionary = false
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    private lazy var cellularHLS: AVAssetDownloadURLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "org.nexora.offline.hls.cellular")
        config.allowsCellularAccess = true
        return AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }()
    private lazy var cellularFiles: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "org.nexora.offline.files.cellular")
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    private var sessions: [URLSession] { [hls, files, cellularHLS, cellularFiles] }
    func bind(_ api: API) {
        self.api = api
        Task { await pump() }
    }
    func setQueuePaused(_ value: Bool) {
        queuePaused = value
        UserDefaults.standard.set(value, forKey: "downloadQueuePaused")
        if !value { Task { await pump() } }
    }
    func enqueue(_ requests: [DownloadRequest], owner: String?, allowCellular: Bool) -> Bool {
        guard let owner, owner == api?.offlineOwner else { message = "Please log in before downloading."; return false }
        var ids = Set(items.map(\.id))
        var added: [OfflineEpisode] = []
        for request in requests where request.animeID > 0 && (1...9999).contains(request.episode) {
            let id = "\(owner)-\(request.animeID)-\(request.episode)-\(request.language)"
            guard !items.contains(where: { $0.owner == owner && $0.animeID == request.animeID && $0.episode == request.episode && $0.language == request.language }), ids.insert(id).inserted else { continue }
            added.append(OfflineEpisode(id: id, title: request.title, owner: owner, episode: request.episode,
                language: request.language, queued: true, animeID: request.animeID, wifiOnly: !allowCellular))
        }
        guard items.count + added.count <= 20_000 else { message = "Queue is full. Remove entries before adding more."; return false }
        items.append(contentsOf: added); persist()
        message = added.isEmpty ? "These episodes are already in Downloads." : "Added \(added.count) episodes to the queue."
        Task { await pump() }
        return true
    }
    func moveQueued(from offsets: IndexSet, to destination: Int, owner: String?) {
        let slots = items.indices.filter { items[$0].owner == owner && items[$0].queued == true && items[$0].id != preparingID }
        guard let rows = DownloadQueuePolicy.reordered(slots.map { items[$0] }, from: offsets, to: destination) else { return }
        for (index, row) in zip(slots, rows) { items[index] = row }
        persist()
    }
    func retry(_ item: OfflineEpisode) {
        guard item.owner == api?.offlineOwner, item.error != nil, item.animeID != nil,
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        for session in sessions {
            session.getAllTasks { tasks in tasks.filter { $0.taskDescription == item.id }.forEach { $0.cancel() } }
        }
        if let location = items[index].location { try? FileManager.default.removeItem(at: localURL(location)) }
        // A fresh identity prevents late callbacks from the old task corrupting this attempt.
        items[index].id = UUID().uuidString
        items[index].location = nil
        transferred.removeValue(forKey: item.id)
        items[index].error = nil; items[index].queued = true; items[index].progress = 0
        persist(); setQueuePaused(false); Task { await pump() }
    }
    private func pump() async {
        guard ready, !pumping, !queuePaused, online, let api, let owner = api.offlineOwner else { return }
        pumping = true; defer { pumping = false; preparingID = nil }
        // Include cancelling and restored background tasks so only one transfer runs.
        for session in sessions {
            let tasks = (await session.allTasks).filter { $0.state != .completed }
            for task in tasks {
                if let index = items.firstIndex(where: { $0.id == task.taskDescription }), items[index].error == nil {
                    if items[index].queued == true { items[index].queued = false; persist() }
                    message = "Downloading episode \(items[index].episode)…"
                } else {
                    task.cancel()
                    message = "Stopping the previous transfer…"
                }
            }
            if !tasks.isEmpty { return }
        }
        guard let next = items.first(where: { $0.owner == owner && $0.queued == true }), let animeID = next.animeID else { return }
        guard next.wifiOnly != true || onWiFi else { message = "Waiting for Wi-Fi. Reorder the queue to download another episode first."; return }
        refreshUsage()
        let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 1_000_000_000, usedBytes + 256_000_000 <= limitBytes else {
            message = "Queue waiting for storage. Free space or increase the download limit."; return
        }
        let token = api.token
        preparingID = next.id
        do {
            // Resolve only when the episode reaches the front; signed URLs must stay fresh.
            let playback: Playback = try await api.request("/play", method: "POST", body: ["anime_id": animeID, "episode": next.episode, "language": next.language])
            guard api.token == token, api.offlineOwner == owner, !queuePaused,
                  items.contains(where: { $0.id == next.id && $0.queued == true }) else { return }
            guard playback.anime_id == animeID, playback.episode_number == next.episode,
                  playback.source.language == next.language else { throw APIError.message("The source does not match this episode and language.") }
            startTransfer(playback, queuedID: next.id, allowCellular: next.wifiOnly == false)
        } catch {
            guard api.token == token, let index = items.firstIndex(where: { $0.id == next.id }) else { return }
            items[index].queued = false; items[index].error = error.localizedDescription; persist()
            message = "An episode could not be prepared. Tap Retry, or resume the queue to skip it."
            // Stop after an error instead of firing hundreds of failing provider requests.
            setQueuePaused(true)
        }
    }
    func refreshUsage() {
        usedBytes = items.reduce(Int64(0)) { sum, item in
            guard let path = item.location else { return sum }
            return sum + fileBytes(localURL(path))
        }
    }
    private func fileBytes(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true { return Int64(values.fileSize ?? 0) }
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    func applyPolicy() {
        refreshUsage()
        if usedBytes > limitBytes { message = "Downloads exceed your new limit. Remove some files before downloading more." }
        Task { await pump() }
    }
    private func checkQuota(_ task: URLSessionTask, received: Int64 = 0, expected: Int64 = 0) {
        guard let id = task.taskDescription, items.contains(where: { $0.id == id && $0.error == nil }) else { return }
        transferred[id] = max(transferred[id] ?? 0, received)
        guard Date().timeIntervalSince(lastQuotaCheck) > 1 else { return }
        lastQuotaCheck = Date(); refreshUsage()
        let inFlight = items.reduce(Int64(0)) { sum, item in
            sum + (item.location == nil ? (transferred[item.id] ?? 0) : 0)
        }
        let additional = max(0, expected - received)
        if usedBytes + inFlight + additional > limitBytes {
            task.cancel(); fail(id, message: "Storage limit reached. Increase the limit or delete a download.")
        }
    }
    func removeWatched(anime: Int, episode: Int, owner: String?) {
        guard autoDelete, let owner else { return }
        for item in items.filter({ $0.owner == owner && ($0.animeID == anime || $0.id.hasPrefix("\(owner)-\(anime)-\(episode)-")) && $0.episode == episode }) { remove(item) }
    }
    func removeWatched(identity: String) {
        guard autoDelete, let item = items.first(where: { $0.id == identity }) else { return }
        remove(item)
    }
    override init() {
        super.init()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.online = path.status == .satisfied
                self.onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                await self.pump()
            }
        }
        monitor.start(queue: DispatchQueue(label: "nexora.download-network"))
        queueWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if UIApplication.shared.applicationState == .active { await self.pump() }
            }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        if let data = try? Data(contentsOf: manifest), let saved = try? JSONDecoder().decode([OfflineEpisode].self, from: data) { items = saved }
        for index in items.indices {
            if let location = items[index].location, !FileManager.default.fileExists(atPath: localURL(location).path) {
                items[index].location = nil; items[index].error = "File was removed. Download this episode again."
            }
        }
        _ = hls; _ = files
        Task {
            let hlsTasks = await hls.allTasks
            let fileTasks = await files.allTasks
            let cellHLSTasks = await cellularHLS.allTasks
            let cellFileTasks = await cellularFiles.allTasks
            let active = Set((hlsTasks + fileTasks + cellHLSTasks + cellFileTasks).compactMap(\.taskDescription))
            for index in items.indices where items[index].progress < 1 && items[index].error == nil && !active.contains(items[index].id) {
                if items[index].animeID != nil && items[index].wifiOnly != nil {
                    // A task may have completed while the app was terminated; retry from a fresh source.
                    if let location = items[index].location { try? FileManager.default.removeItem(at: localURL(location)) }
                    items[index].location = nil; items[index].progress = 0; items[index].queued = true
                } else { items[index].error = "Download interrupted. Remove it and try again." }
            }
            for task in hlsTasks + fileTasks + cellHLSTasks + cellFileTasks {
                if let id = task.taskDescription, let item = items.first(where: { $0.id == id }), item.wifiOnly == nil {
                    task.cancel(); fail(id, message: "Choose a download network and start this download again.")
                }
            }
            ready = true; persist(); applyPolicy()
        }
    }
    func localURL(_ location: String) -> URL {
        DownloadPath.restored(location, home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: manifest, options: .atomic) }
    }
    func add(_ playback: Playback, owner: String?, allowCellular: Bool) {
        let request = DownloadRequest(animeID: playback.anime_id, title: playback.anime_title,
            episode: playback.episode_number, language: playback.source.language ?? "Deutsch")
        _ = enqueue([request], owner: owner, allowCellular: allowCellular)
    }
    private func startTransfer(_ playback: Playback, queuedID id: String, allowCellular: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard let url = URL(string: playback.source.url, relativeTo: API.base)?.absoluteURL, url.scheme == "https" else { fail(id, message: "Download source unavailable."); setQueuePaused(true); return }
        let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 1_000_000_000 else { message = "Free at least 1 GB before downloading."; return }
        refreshUsage()
        guard usedBytes + 256_000_000 <= limitBytes else { message = "Queue waiting for storage."; return }
        let contentType = playback.source.content_type?.lowercased() ?? ""
        let task: URLSessionTask
        if contentType.contains("mpegurl") || url.pathExtension == "m3u8" {
            let config = AVAssetDownloadConfiguration(asset: AVURLAsset(url: url), title: "\(playback.anime_title) • Episode \(playback.episode_number)")
            task = (allowCellular ? cellularHLS : hls).makeAssetDownloadTask(downloadConfiguration: config)
        } else if contentType.contains("mp4") || url.pathExtension == "mp4" {
            task = (allowCellular ? cellularFiles : files).downloadTask(with: url)
        } else { fail(id, message: "This source does not support offline downloads."); setQueuePaused(true); return }
        task.taskDescription = id
        items[index].queued = false; items[index].error = nil
        persist(); task.resume(); message = "Download requested. Waiting for video data…"
    }
    func remove(_ item: OfflineEpisode) {
        for session in sessions {
            session.getAllTasks { tasks in tasks.filter { $0.taskDescription == item.id }.forEach { $0.cancel() } }
        }
        if let path = item.location, FileManager.default.fileExists(atPath: localURL(path).path) {
            do { try FileManager.default.removeItem(at: localURL(path)) }
            catch { message = "Could not delete the file. Try again after closing playback."; return }
        }
        items.removeAll { $0.id == item.id }; transferred.removeValue(forKey: item.id); persist(); refreshUsage(); Task { await pump() }
    }
    private func record(_ id: String?, location: URL, systemManaged: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.error == nil }) else {
            if let relative = DownloadPath.stored(location, home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true), systemManaged: systemManaged) {
                try? FileManager.default.removeItem(at: localURL(relative))
            }
            return
        }
        guard let relative = DownloadPath.stored(location, home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true), systemManaged: systemManaged) else {
            fail(id, message: "The download service returned an unsupported storage URL.")
            setQueuePaused(true)
            return
        }
        items[index].queued = false
        items[index].location = relative
        persist(); refreshUsage()
        if usedBytes > limitBytes { fail(id, message: "File exceeds your storage limit.") }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        MainActor.assumeIsolated { self.record(assetDownloadTask.taskDescription, location: location, systemManaged: true) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        let id = assetDownloadTask.taskDescription
        MainActor.assumeIsolated { self.record(id, location: location, systemManaged: true) }
    }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        let total = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        let id = assetDownloadTask.taskDescription
        Task { @MainActor in
            self.checkQuota(assetDownloadTask, received: assetDownloadTask.countOfBytesReceived)
            if total.isFinite, total > 0, let index = self.items.firstIndex(where: { $0.id == id }) { self.items[index].progress = min(0.99, max(0, loaded / total)) }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskDescription
        Task { @MainActor in
            self.checkQuota(downloadTask, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
            if totalBytesExpectedToWrite > 0, let index = self.items.firstIndex(where: { $0.id == id }) { self.items[index].progress = min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskDescription
        let response = downloadTask.response as? HTTPURLResponse
        guard response?.statusCode == 200, response?.mimeType?.hasPrefix("video/") == true else {
            Task { @MainActor in self.fail(id, message: "The server did not return a video. Try downloading again.") }; return
        }
        // The temporary URL expires as soon as this delegate returns.
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Offline")
        let destination = folder.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            MainActor.assumeIsolated { self.record(id, location: destination) }
        } catch {
            Task { @MainActor in self.fail(id, message: "Could not save the video. Check available storage.") }
        }
    }
    private func fail(_ id: String?, message: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let path = items[index].location { try? FileManager.default.removeItem(at: localURL(path)) }
        items[index].queued = false; items[index].location = nil; items[index].error = message; transferred.removeValue(forKey: items[index].id); persist(); refreshUsage()
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier
        Task { @MainActor in
            guard let identifier else { return }
            self.backgroundCompletions.removeValue(forKey: identifier)?()
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskDescription
        let failed = error != nil
        Task { @MainActor in
            if self.items.contains(where: { $0.id == id && (failed || $0.error != nil) }) { self.setQueuePaused(true) }
            if failed && self.items.first(where: { $0.id == id })?.error == nil { self.fail(id, message: "Download failed. Remove it and try again while online.") }
            else if !failed, let index = self.items.firstIndex(where: { $0.id == id && $0.error == nil }), self.items[index].location != nil {
                self.items[index].queued = false; self.items[index].progress = 1; self.transferred.removeValue(forKey: self.items[index].id); self.persist(); self.refreshUsage()
            }
            Task { await self.pump() }
        }
    }
}

@MainActor final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadStore.shared.backgroundCompletions[identifier] = completionHandler
    }
}
