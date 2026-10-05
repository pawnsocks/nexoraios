import Foundation
@main struct MediaPolicyChecks {
 static func main() {
  precondition(PlaybackLanguages.order("English") == ["English","Eng-Sub","Deutsch","Ger-Sub","Original"])
  precondition(PlaybackLanguages.order("Deutsch").first == "Deutsch")
  precondition(Set(PlaybackLanguages.order("Ger-Sub")).count == 5)
  for status in [401,403,429] { precondition(!PlaybackLanguages.canRetry(status)) }
  for status in [404,502,503,504] { precondition(PlaybackLanguages.canRetry(status)) }
  precondition(DownloadFailure.retryable(domain: "network", code: -1001, status: nil))
  precondition(!DownloadFailure.retryable(domain: "network", code: -1009, status: nil))
  precondition(!DownloadFailure.retryable(domain: "network", code: -1011, status: 403))
  precondition(DownloadFailure.category("AVFoundationErrorDomain") == "media")
  print("14 language fallback and download failure checks passed")
 }
}
