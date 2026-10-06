import Foundation

enum DownloadResponse {
    static func httpStatus(for task: URLSessionTask) -> Int? {
        // AVAssetDownloadTask.response raises an Objective-C exception on iOS.
        // Only ordinary file download tasks expose a usable HTTP response here.
        guard let download = task as? URLSessionDownloadTask else { return nil }
        return (download.response as? HTTPURLResponse)?.statusCode
    }
}
