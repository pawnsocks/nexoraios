import Foundation

final class UnsupportedResponseTask: URLSessionTask, @unchecked Sendable {
    override var response: URLResponse? { fatalError("Unsupported response getter must never be called") }
}
final class FileResponseTask: URLSessionDownloadTask, @unchecked Sendable {
    override var response: URLResponse? {
        HTTPURLResponse(url: URL(string: "https://example.com/video.mp4")!, statusCode: 503, httpVersion: nil, headerFields: nil)
    }
}
@main struct Checks {
    static func main() {
        precondition(DownloadResponse.httpStatus(for: UnsupportedResponseTask()) == nil)
        precondition(DownloadResponse.httpStatus(for: FileResponseTask()) == 503)
        print("2 download response regression checks passed")
    }
}
