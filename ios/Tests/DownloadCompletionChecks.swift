import Foundation

@main struct Checks {
    @MainActor static func main() async {
        let queue = DownloadEvents()
        var output: [Int] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                queue.enqueue {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    output.append(1) // saved location
                }
                queue.enqueue { output.append(2) } // completion sees location
                queue.enqueue { output.append(3); done.resume() } // background completion last
            }
        }
        precondition(output == [1, 2, 3], "Delegate events reordered")
        func action(_ active: Bool = false, _ queued: Bool = false, _ completed: Bool = false,
                    _ failed: Bool = false, _ exists: Bool = false, _ mp4: Bool = false) -> DownloadRecovery.Action {
            DownloadRecovery.action(active: active, queued: queued, completed: completed, failed: failed,
                                    savedFileExists: exists, finalizedMP4: mp4)
        }
        precondition(action() == .interrupt)
        precondition(action(false,false,false,false,true,false) == .interrupt, "Partial HLS must not be marked complete")
        precondition(action(false,false,false,false,true,true) == .finish)
        precondition(action(false,false,false,false,false,true) == .interrupt)
        precondition(action(true) == .keep)
        precondition(action(false,true) == .keep)
        precondition(action(false,false,true) == .keep)
        precondition(action(false,false,false,true) == .keep)
        print("9 download completion/recovery checks passed")
    }
}
