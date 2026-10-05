import Foundation

@main struct DownloadQueueChecks {
    static func main() {
        precondition(DownloadQueuePolicy.releasedCount(status: "RELEASING", total: 24, aired: 7) == 7)
        precondition(DownloadQueuePolicy.releasedCount(status: "RELEASING", total: 24, aired: nil) == nil)
        precondition(DownloadQueuePolicy.releasedCount(status: "NOT_YET_RELEASED", total: 12, aired: 0) == 0)
        precondition(DownloadQueuePolicy.releasedCount(status: "FINISHED", total: 220, aired: nil) == 220)
        precondition(DownloadQueuePolicy.releasedCount(status: "FINISHED", total: -1, aired: nil) == nil)
        precondition(DownloadQueuePolicy.reordered([1,2,3,4], from: IndexSet(integer: 0), to: 4) == [2,3,4,1])
        precondition(DownloadQueuePolicy.reordered([1,2,3,4], from: IndexSet([1,3]), to: 0) == [2,4,1,3])
        precondition(DownloadQueuePolicy.reordered([1,2], from: IndexSet(integer: 5), to: 0) == nil)
        precondition(DownloadQueuePolicy.accepts(animeID: -7, episode: 1180))
        precondition(DownloadQueuePolicy.accepts(animeID: 21, episode: 1))
        precondition(!DownloadQueuePolicy.accepts(animeID: 0, episode: 1))
        precondition(!DownloadQueuePolicy.accepts(animeID: 21, episode: 0))
        print("12 download queue checks passed")
    }
}
